// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {ILM_PC_FundingPot_v1} from
    "src/modules/logicModule/interfaces/ILM_PC_FundingPot_v1.sol";
import {
    IERC20PaymentClientBase_v2,
    IPaymentProcessor_v2
} from "@lm/abstracts/ERC20PaymentClientBase_v2.sol";
import {
    ERC20PaymentClientBase_v2,
    Module_v1
} from "@lm/abstracts/ERC20PaymentClientBase_v2.sol";
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";

// External
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IERC721} from "@oz/token/ERC721/IERC721.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

import {MerkleProof} from "@oz/utils/cryptography/MerkleProof.sol";
import {EnumerableSet} from "@oz/utils/structs/EnumerableSet.sol";

/**
 * @title   Inverter Funding Pot Logic Module.
 *
 * @notice  A sophisticated funding management system that enables configurable fundraising rounds
 *          with multiple access criteria, contribution limits, and automated distribution.
 *          This module provides a flexible framework for managing token sales and fundraising
 *          campaigns with granular access control and contribution management.
 *
 * @dev     Implements a comprehensive funding system with the following features:
 *          - Round Configuration.
 *            Supports configurable start/end times, caps, and post-round hooks.
 *
 *          - Access Control.
 *            Multiple access criteria types:
 *            - Allowlist-based access.
 *            - NFT ownership verification.
 *            - Merkle proof validation.
 *            - Open access.
 *
 *          - Contribution Management.
 *            - Personal contribution caps.
 *            - Round-level caps.
 *            - Global accumulative caps across rounds.
 *            - Configurable contribution time windows.
 *
 *          - Automated Processing.
 *            - Automatic round closure based on time or cap.
 *            - Post-round hook execution.
 *            - Payment order creation for contributors.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to
 *                          our Security Policy at security.inverter.network or
 *                          email us directly!
 *
 * @custom:version  v1.0.0.
 *
 * @custom:inverter-standard-version v0.1.0.
 *
 * @author  33Audits.
 */
contract LM_PC_FundingPot_v1 is
    ILM_PC_FundingPot_v1,
    ERC20PaymentClientBase_v2
{
    // -------------------------------------------------------------------------
    // Libraries

    using SafeERC20 for IERC20;

    // -------------------------------------------------------------------------
    // ERC165

    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId_)
        public
        view
        virtual
        override(ERC20PaymentClientBase_v2)
        returns (bool)
    {
        return interfaceId_ == type(ILM_PC_FundingPot_v1).interfaceId
            || super.supportsInterface(interfaceId_);
    }

    // --------------------------------------------------------------------------
    // Constants

    /// @notice The role that allows creating funding rounds.
    bytes32 public constant FUNDING_POT_ADMIN_ROLE = "FUNDING_POT_ADMIN";

    /// @notice The payment processor flag for the start timestamp.
    uint8 internal constant FLAG_START = 1;

    /// @notice The payment processor flag for the cliff timestamp.
    uint8 internal constant FLAG_CLIFF = 2;

    /// @notice The payment processor flag for the end timestamp.
    uint8 internal constant FLAG_END = 3;

    /// @notice The maximum valid access criteria ID.
    uint8 internal constant MAX_ACCESS_CRITERIA_TYPE = 4;

    // -------------------------------------------------------------------------
    // State

    /// @notice The current round count.
    uint32 private roundCount;

    /// @notice Stores all funding rounds by their unique ID.
    mapping(uint32 => Round) private rounds;

    /// @notice Stores all access criteria privilages by their unique ID.
    mapping(
        uint32 roundId
            => mapping(uint8 accessCriteriaId_ => AccessCriteriaPrivileges)
    ) private roundIdToAccessCriteriaIdToPrivileges;

    /// @notice Maps round IDs to user addresses to contribution amounts.
    mapping(uint32 => mapping(address => uint)) private
        roundIdToUserToContribution;

    /// @notice Maps round IDs to total contributions.
    mapping(uint32 => uint) private roundIdToTotalContributions;

    /// @notice Maps round IDs to closed status.
    mapping(uint32 => bool) private roundIdToClosedStatus;

    /// @notice Maps round IDs to bonding curve tokens bought.
    mapping(uint32 => uint) private roundTokensBought;

    /// @notice Maps round IDs to contributors recipients.
    mapping(uint32 => EnumerableSet.AddressSet) private contributorsByRound;

    /// @notice Maps round IDs to user addresses to contribution amounts by access criteria.
    mapping(uint32 => mapping(address => mapping(uint8 => uint))) private
        roundIdTouserContributionsByAccessCriteria;

    /// @notice Add a mapping to track the next unprocessed index for each round.
    mapping(uint32 => uint) private roundIdToNextUnprocessedIndex;

    /// @notice The next available access criteria ID for each round
    mapping(uint32 => uint8) private roundIdToNextAccessCriteriaId;

    /// @notice The minimum round ID (inclusive, >= 1) to consider for accumulation calculations.
    /// @dev    Defaults to 1. If a target round's mode allows accumulation,
    ///         only previous rounds with roundId >= globalAccumulationStartRoundId will be included.
    uint32 internal globalAccumulationStartRoundId;

    /// @notice Maps user addresses to a mapping of round IDs to a mapping of access criteria IDs to whether their unspent cap has been used
    mapping(address => mapping(uint32 => mapping(uint8 => bool))) public
        usedUnspentCaps;

    /// @notice Storage gap for future upgrades.
    uint[50] private __gap;

    // -------------------------------------------------------------------------
    // Modifiers

    // -------------------------------------------------------------------------
    // Initialization

    /// @notice The module's initializer function.
    /// @dev    CAN be overridden by downstream contract.
    /// @dev    MUST call `__Module_init()`.
    /// @param  orchestrator_ The orchestrator contract.
    /// @param  metadata_ The metadata of the module.
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata_,
        bytes memory
    ) external override(Module_v1) initializer {
        __Module_init(orchestrator_, metadata_);
        // Set the flags for the PaymentOrders (this module uses 3 flags).
        bytes32 flags;
        flags |= bytes32(1 << FLAG_START);
        flags |= bytes32(1 << FLAG_CLIFF);
        flags |= bytes32(1 << FLAG_END);

        __ERC20PaymentClientBase_v2_init(flags);
        // Explicitly initialize the global start round ID
        globalAccumulationStartRoundId = 1;
    }

    // -------------------------------------------------------------------------
    // Public - Getters

    /// @inheritdoc ILM_PC_FundingPot_v1
    function getRoundGenericParameters(uint32 roundId_)
        external
        view
        returns (
            uint roundStart,
            uint roundEnd,
            uint roundCap,
            address hookContract,
            bytes memory hookFunction,
            bool autoClosure,
            AccumulationMode accumulationMode
        )
    {
        Round storage round = rounds[roundId_];
        return (
            round.roundStart,
            round.roundEnd,
            round.roundCap,
            round.hookContract,
            round.hookFunction,
            round.autoClosure,
            round.accumulationMode
        );
    }

    /// @inheritdoc ILM_PC_FundingPot_v1
    function getRoundAccessCriteria(uint32 roundId_, uint8 accessCriteriaId_)
        external
        view
        returns (
            bool isRoundOpen_,
            address nftContract_,
            bytes32 merkleRoot_,
            bool isList_
        )
    {
        AccessCriteria storage accessCriteria =
            rounds[roundId_].accessCriterias[accessCriteriaId_];
        ILM_PC_FundingPot_v1.AccessCriteriaType acType =
            accessCriteria.accessCriteriaType;

        bool isRoundOpen =
            (acType == ILM_PC_FundingPot_v1.AccessCriteriaType.OPEN);
        bool isList = (
            acType == ILM_PC_FundingPot_v1.AccessCriteriaType.OPEN
                || acType == ILM_PC_FundingPot_v1.AccessCriteriaType.LIST
        );

        return (
            isRoundOpen,
            accessCriteria.nftContract,
            accessCriteria.merkleRoot,
            isList
        );
    }

    /// @inheritdoc ILM_PC_FundingPot_v1
    function getRoundAccessCriteriaPrivileges(
        uint32 roundId_,
        uint8 accessCriteriaId_
    )
        external
        view
        returns (
            uint personalCap_,
            bool overrideContributionSpan_,
            uint start_,
            uint cliff_,
            uint end_
        )
    {
        Round storage round = rounds[roundId_];
        AccessCriteria storage accessCriteria =
            round.accessCriterias[accessCriteriaId_];

        if (accessCriteria.accessCriteriaType == AccessCriteriaType.UNSET) {
            return (0, false, 0, 0, 0);
        }

        // Store the privileges in a local variable to reduce stack usage.
        AccessCriteriaPrivileges storage privileges =
            roundIdToAccessCriteriaIdToPrivileges[roundId_][accessCriteriaId_];

        return (
            privileges.personalCap,
            privileges.overrideContributionSpan,
            privileges.start,
            privileges.cliff,
            privileges.end
        );
    }

    /// @inheritdoc ILM_PC_FundingPot_v1
    function getRoundCount() external view returns (uint32) {
        return roundCount;
    }

    /// @inheritdoc ILM_PC_FundingPot_v1
    function isRoundClosed(uint32 roundId_) external view returns (bool) {
        return roundIdToClosedStatus[roundId_];
    }

    /// @inheritdoc ILM_PC_FundingPot_v1
    function getUserEligibility(
        uint32 roundId_,
        uint8 accessCriteriaId_,
        bytes32[] memory merkleProof_,
        address user_
    )
        external
        view
        returns (bool isEligible, uint remainingAmountAllowedToContribute)
    {
        Round storage round = rounds[roundId_];

        if (round.roundEnd == 0 && round.roundCap == 0) {
            revert Module__LM_PC_FundingPot__RoundNotCreated();
        }

        AccessCriteria storage accessCriteria =
            round.accessCriterias[accessCriteriaId_];

        if (accessCriteria.accessCriteriaType == AccessCriteriaType.UNSET) {
            return (false, 0);
        }

        isEligible = _checkAccessCriteriaEligibility(
            roundId_, accessCriteriaId_, merkleProof_, user_
        );

        if (isEligible) {
            AccessCriteriaPrivileges storage privileges =
            roundIdToAccessCriteriaIdToPrivileges[roundId_][accessCriteriaId_];
            uint userPersonalCap = privileges.personalCap;
            uint userContribution = roundIdToUserToContribution[roundId_][user_];

            uint personalCapRemaining = userPersonalCap > userContribution
                ? userPersonalCap - userContribution
                : 0;

            uint totalContributions = roundIdToTotalContributions[roundId_];
            uint roundCapRemaining = round.roundCap > totalContributions
                ? round.roundCap - totalContributions
                : 0;

            remainingAmountAllowedToContribute = personalCapRemaining
                < roundCapRemaining ? personalCapRemaining : roundCapRemaining;

            return (true, remainingAmountAllowedToContribute);
        } else {
            return (false, 0);
        }
    }

    /// @inheritdoc ILM_PC_FundingPot_v1
    function getTotalRoundContribution(uint32 roundId_)
        external
        view
        returns (uint)
    {
        return roundIdToTotalContributions[roundId_];
    }

    /// @inheritdoc ILM_PC_FundingPot_v1
    function getUserContributionToRound(uint32 roundId_, address user_)
        external
        view
        returns (uint)
    {
        return roundIdToUserToContribution[roundId_][user_];
    }

    /// @inheritdoc ILM_PC_FundingPot_v1
    function getGlobalAccumulationStartRoundId()
        external
        view
        returns (uint32)
    {
        return globalAccumulationStartRoundId;
    }

    // -------------------------------------------------------------------------
    // Public - Mutating

    /// @inheritdoc ILM_PC_FundingPot_v1
    function createRound(
        uint roundStart_,
        uint roundEnd_,
        uint roundCap_,
        address hookContract_,
        bytes memory hookFunction_,
        bool autoClosure_,
        AccumulationMode accumulationMode_
    ) external onlyModuleRole(FUNDING_POT_ADMIN_ROLE) returns (uint32) {
        unchecked {
            roundCount++;
        }

        uint32 roundId = roundCount;

        Round storage round = rounds[roundId];
        _setAndValidateRoundParameters(
            round,
            roundStart_,
            roundEnd_,
            roundCap_,
            hookContract_,
            hookFunction_,
            autoClosure_,
            accumulationMode_
        );

        emit RoundCreated(
            roundId,
            roundStart_,
            roundEnd_,
            roundCap_,
            hookContract_,
            hookFunction_,
            autoClosure_,
            accumulationMode_
        );

        return uint32(roundId);
    }

    /// @inheritdoc ILM_PC_FundingPot_v1
    function editRound(
        uint32 roundId_,
        uint roundStart_,
        uint roundEnd_,
        uint roundCap_,
        address hookContract_,
        bytes memory hookFunction_,
        bool autoClosure_,
        AccumulationMode accumulationMode_
    ) external onlyModuleRole(FUNDING_POT_ADMIN_ROLE) {
        Round storage round = rounds[roundId_];

        _validateEditRoundParameters(round);

        _setAndValidateRoundParameters(
            round,
            roundStart_,
            roundEnd_,
            roundCap_,
            hookContract_,
            hookFunction_,
            autoClosure_,
            accumulationMode_
        );

        emit RoundEdited(
            roundId_,
            roundStart_,
            roundEnd_,
            roundCap_,
            hookContract_,
            hookFunction_,
            autoClosure_,
            accumulationMode_
        );
    }

    /// @inheritdoc ILM_PC_FundingPot_v1
    function setAccessCriteria(
        uint32 roundId_,
        uint8 accessCriteriaType_,
        uint8 accessCriteriaId_, // Optional: 0 for new, non-zero for edit
        address nftContract_,
        bytes32 merkleRoot_,
        address[] calldata allowedAddresses_,
        address[] calldata removedAddresses_
    ) external onlyModuleRole(FUNDING_POT_ADMIN_ROLE) {
        Round storage round = rounds[roundId_];

        if (accessCriteriaType_ > MAX_ACCESS_CRITERIA_TYPE) {
            revert Module__LM_PC_FundingPot__InvalidAccessCriteriaType();
        }

        _validateEditRoundParameters(round);

        uint8 criteriaId;
        bool isEdit = false;

        // If accessCriteriaId_ is 0, create a new access criteria
        // Otherwise, edit the existing one
        if (accessCriteriaId_ == 0) {
            unchecked {
                criteriaId = ++roundIdToNextAccessCriteriaId[roundId_];
            }
        } else {
            criteriaId = accessCriteriaId_;
            isEdit = true;

            if (
                round.accessCriterias[criteriaId].accessCriteriaType
                    == AccessCriteriaType.UNSET
            ) {
                revert Module__LM_PC_FundingPot__InvalidAccessCriteriaType();
            }
        }

        // Validate required data based on access criteria type
        AccessCriteriaType accessCriteriaType =
            AccessCriteriaType(accessCriteriaType_);
        if (accessCriteriaType == AccessCriteriaType.NFT) {
            if (nftContract_ == address(0)) {
                revert
                    Module__LM_PC_FundingPot__MissingRequiredAccessCriteriaData();
            }
        } else if (accessCriteriaType == AccessCriteriaType.MERKLE) {
            if (merkleRoot_ == bytes32(0)) {
                revert
                    Module__LM_PC_FundingPot__MissingRequiredAccessCriteriaData();
            }
        } else if (accessCriteriaType == AccessCriteriaType.LIST) {
            if (allowedAddresses_.length == 0) {
                revert
                    Module__LM_PC_FundingPot__MissingRequiredAccessCriteriaData();
            }
        }

        // Clear all existing data to prevent stale data
        round.accessCriterias[criteriaId].nftContract = address(0);
        round.accessCriterias[criteriaId].merkleRoot = bytes32(0);
        // @note: When changing allowlists, call removeAllowlistedAddresses first to clear previous entries

        // Set the access criteria type
        round.accessCriterias[criteriaId].accessCriteriaType =
            accessCriteriaType;

        // Set only the relevant data based on the access criteria type
        if (accessCriteriaType == AccessCriteriaType.NFT) {
            round.accessCriterias[criteriaId].nftContract = nftContract_;
        } else if (accessCriteriaType == AccessCriteriaType.MERKLE) {
            round.accessCriterias[criteriaId].merkleRoot = merkleRoot_;
        } else if (accessCriteriaType == AccessCriteriaType.LIST) {
            // Remove the addresses from the allowed list if any
            if (removedAddresses_.length > 0) {
                for (uint i = 0; i < removedAddresses_.length; i++) {
                    round.accessCriterias[criteriaId].allowedAddresses[removedAddresses_[i]]
                    = false;
                }
            }
            // For LIST type, update the allowed addresses
            for (uint i = 0; i < allowedAddresses_.length; i++) {
                round.accessCriterias[criteriaId].allowedAddresses[allowedAddresses_[i]]
                = true;
            }
        }

        // Emit the appropriate event based on whether this is a new setting or an edit
        if (isEdit) {
            emit AccessCriteriaEdited(roundId_, criteriaId);
        } else {
            emit AccessCriteriaSet(roundId_, criteriaId);
        }
    }

    // Update removeAllowlistedAddresses to match the new approach
    /// @inheritdoc ILM_PC_FundingPot_v1
    function removeAllowlistedAddresses(
        uint32 roundId_,
        uint8 accessCriteriaId_,
        address[] calldata addressesToRemove_
    ) external onlyModuleRole(FUNDING_POT_ADMIN_ROLE) {
        Round storage round = rounds[roundId_];

        // Verify the access criteria exists
        if (
            round.accessCriterias[accessCriteriaId_].accessCriteriaType
                == AccessCriteriaType.UNSET
        ) {
            revert Module__LM_PC_FundingPot__InvalidAccessCriteriaType();
        }

        _validateEditRoundParameters(round);

        for (uint i = 0; i < addressesToRemove_.length; i++) {
            round.accessCriterias[accessCriteriaId_].allowedAddresses[addressesToRemove_[i]]
            = false;
        }

        emit AllowlistedAddressesRemoved(
            roundId_, accessCriteriaId_, addressesToRemove_
        );
    }

    /// @inheritdoc ILM_PC_FundingPot_v1
    function setAccessCriteriaPrivileges(
        uint32 roundId_,
        uint8 accessCriteriaId_,
        uint personalCap_,
        bool overrideContributionSpan_,
        uint start_,
        uint cliff_,
        uint end_
    ) external onlyModuleRole(FUNDING_POT_ADMIN_ROLE) {
        Round storage round = rounds[roundId_];

        _validateEditRoundParameters(round);

        if (!_validTimes(start_, cliff_, end_)) {
            revert Module__LM_PC_FundingPot__InvalidTimes();
        }

        AccessCriteriaPrivileges storage accessCriteriaPrivileges =
            roundIdToAccessCriteriaIdToPrivileges[roundId_][accessCriteriaId_];

        accessCriteriaPrivileges.personalCap = personalCap_;
        accessCriteriaPrivileges.overrideContributionSpan =
            overrideContributionSpan_;
        accessCriteriaPrivileges.start = start_;
        accessCriteriaPrivileges.cliff = cliff_;
        accessCriteriaPrivileges.end = end_;

        emit AccessCriteriaPrivilegesSet(
            roundId_,
            accessCriteriaId_,
            personalCap_,
            overrideContributionSpan_,
            start_,
            cliff_,
            end_
        );
    }

    /// @inheritdoc ILM_PC_FundingPot_v1
    function contributeToRoundFor(
        address user_,
        uint32 roundId_,
        uint amount_,
        uint8 accessCriteriaId_,
        bytes32[] memory merkleProof_
    ) external {
        // Call the internal function with no additional unspent personal cap
        _contributeToRoundFor(
            user_, roundId_, amount_, accessCriteriaId_, merkleProof_, 0
        );
    }

    /// @inheritdoc ILM_PC_FundingPot_v1
    function contributeToRoundFor(
        address user_,
        uint32 roundId_,
        uint amount_,
        uint8 accessCriteriaId_,
        bytes32[] memory merkleProof_,
        UnspentPersonalRoundCap[] calldata unspentPersonalRoundCaps_
    ) external {
        uint unspentPersonalCap = _calculateUnspentPersonalCap(
            user_, roundId_, unspentPersonalRoundCaps_
        );

        if (unspentPersonalCap > 0) {
            // Mark the specific caps that were used in this contribution
            for (uint i = 0; i < unspentPersonalRoundCaps_.length; i++) {
                UnspentPersonalRoundCap memory roundCapInfo =
                    unspentPersonalRoundCaps_[i];
                usedUnspentCaps[user_][roundCapInfo.roundId][roundCapInfo
                    .accessCriteriaId] = true;
            }
        }

        _contributeToRoundFor(
            user_,
            roundId_,
            amount_,
            accessCriteriaId_,
            merkleProof_,
            unspentPersonalCap
        );
    }

    /// @inheritdoc ILM_PC_FundingPot_v1
    function closeRound(uint32 roundId_)
        external
        onlyModuleRole(FUNDING_POT_ADMIN_ROLE)
    {
        Round storage round = rounds[roundId_];

        if (round.roundEnd == 0 && round.roundCap == 0) {
            revert Module__LM_PC_FundingPot__RoundNotCreated();
        }

        if (roundIdToClosedStatus[roundId_]) {
            revert Module__LM_PC_FundingPot__RoundHasEnded();
        }

        bool readyToClose = _checkRoundClosureConditions(roundId_);
        if (readyToClose) {
            _closeRound(roundId_);

            _buyBondingCurveToken(roundId_);

            // Payment orders will be created separately via createPaymentOrdersForContributorsBatch
        } else {
            revert Module__LM_PC_FundingPot__ClosureConditionsNotMet();
        }
    }

    /// @inheritdoc ILM_PC_FundingPot_v1
    function createPaymentOrdersForContributorsBatch(
        uint32 roundId_,
        uint batchSize_
    ) external {
        Round storage round = rounds[roundId_];

        // Check if round exists
        if (round.roundEnd == 0 && round.roundCap == 0) {
            revert Module__LM_PC_FundingPot__RoundNotCreated();
        }

        // Check if round is closed
        if (!roundIdToClosedStatus[roundId_]) {
            revert Module__LM_PC_FundingPot__RoundNotClosed();
        }

        address[] memory contributors =
            EnumerableSet.values(contributorsByRound[roundId_]);
        uint contributorCount = contributors.length;

        // Check batch size is not zero
        if (batchSize_ == 0) {
            revert Module__LM_PC_FundingPot__InvalidBatchParameters();
        }
        // If batch size is greater than contributor count, set batch size to contributor count
        if (batchSize_ > contributorCount) {
            batchSize_ = contributorCount;
        }

        // If autoClosure is false, only admin can process contributors
        if (!round.autoClosure) {
            _checkRoleModifier(
                __Module_orchestrator.authorizer().generateRoleId(
                    address(this), FUNDING_POT_ADMIN_ROLE
                ),
                _msgSender()
            );
        }

        uint startIndex = roundIdToNextUnprocessedIndex[roundId_];
        _createPaymentOrdersForContributors(roundId_, startIndex, batchSize_);

        // Update the next unprocessed index
        uint endIndex = startIndex + batchSize_;
        if (endIndex > contributorCount) {
            endIndex = contributorCount;
        }

        roundIdToNextUnprocessedIndex[roundId_] = endIndex;
    }

    /// @inheritdoc ILM_PC_FundingPot_v1
    function setGlobalAccumulationStart(uint32 startRoundId_)
        external
        onlyModuleRole(FUNDING_POT_ADMIN_ROLE)
    {
        if (startRoundId_ == 0) {
            revert Module__LM_PC_FundingPot__StartRoundCannotBeZero();
        }
        if (startRoundId_ > roundCount) {
            revert Module__LM_PC_FundingPot__StartRoundGreaterThanRoundCount(
                startRoundId_, roundCount
            );
        }

        globalAccumulationStartRoundId = startRoundId_;

        emit GlobalAccumulationStartSet(startRoundId_);
    }

    // -------------------------------------------------------------------------
    // Internal

    /// @notice Calculates the unspent personal capacity from previous rounds.
    /// @param user_ The user address to calculate unspent capacity for.
    /// @param roundId_ The current round ID.
    /// @param unspentPersonalRoundCaps_ Array of previous rounds and access criteria to calculate unused capacity from.
    /// @return unspentPersonalCap The amount of unspent personal capacity that can be used.
    function _calculateUnspentPersonalCap(
        address user_,
        uint32 roundId_,
        UnspentPersonalRoundCap[] calldata unspentPersonalRoundCaps_
    ) internal view returns (uint unspentPersonalCap) {
        if (unspentPersonalRoundCaps_.length == 0) {
            return 0;
        }

        uint totalAggregatedPersonalCap = 0;
        uint totalSpentInPastRounds = 0;
        uint32 firstRoundId = unspentPersonalRoundCaps_[0].roundId;
        uint32 lastSeenRoundId = 0;
        // Enforcement: All rounds from the start of the array to the end must be contiguous.
        for (uint i = 0; i < unspentPersonalRoundCaps_.length; i++) {
            UnspentPersonalRoundCap memory roundCapInfo =
                unspentPersonalRoundCaps_[i];
            uint32 currentProcessingRoundId = roundCapInfo.roundId;

            // Check for strictly increasing first (order matters)
            if (currentProcessingRoundId <= lastSeenRoundId) {
                revert
                    Module__LM_PC_FundingPot__UnspentCapsRoundIdsNotStrictlyIncreasing(
                );
            }
            lastSeenRoundId = currentProcessingRoundId;

            // Check for contiguity (consecutive sequence)
            if (currentProcessingRoundId != firstRoundId + i) {
                revert
                    Module__LM_PC_FundingPot__UnspentCapsRoundIdsNotContiguous();
            }

            // Enforcement: Round IDs must be strictly before the current roundId_
            if (currentProcessingRoundId >= roundId_) {
                revert
                    Module__LM_PC_FundingPot__UnspentCapsMustBeFromPreviousRounds();
            }

            // For PERSONAL cap rollover, the PREVIOUS round must have allowed it (Personal or All).
            if (
                rounds[currentProcessingRoundId].accumulationMode
                    != AccumulationMode.Personal
                    && rounds[currentProcessingRoundId].accumulationMode
                        != AccumulationMode.All
            ) {
                continue;
            }

            if (
                usedUnspentCaps[user_][currentProcessingRoundId][roundCapInfo
                    .accessCriteriaId]
            ) {
                continue;
            }

            // Skip if this round is before the global accumulation start round
            if (currentProcessingRoundId < globalAccumulationStartRoundId) {
                continue;
            }

            // Only count spent amounts from rounds that meet the accumulation criteria
            totalSpentInPastRounds +=
                roundIdToUserToContribution[currentProcessingRoundId][user_];

            // Check eligibility for the past round
            if (
                _checkAccessCriteriaEligibility(
                    currentProcessingRoundId,
                    roundCapInfo.accessCriteriaId,
                    roundCapInfo.merkleProof,
                    user_
                )
            ) {
                AccessCriteriaPrivileges storage privileges =
                roundIdToAccessCriteriaIdToPrivileges[currentProcessingRoundId][roundCapInfo
                    .accessCriteriaId];

                totalAggregatedPersonalCap += privileges.personalCap;
            }
        }

        if (totalAggregatedPersonalCap > totalSpentInPastRounds) {
            unspentPersonalCap =
                totalAggregatedPersonalCap - totalSpentInPastRounds;
        }

        return unspentPersonalCap;
    }

    /// @notice Validates the round parameters.
    /// @param  round_ The round to validate.
    /// @dev    Reverts if the round parameters are invalid.
    function _validateRoundParameters(Round storage round_) internal view {
        // Validate round start time is in the future
        // @note: The below condition wont allow _roundStart == block.timestamp
        if (round_.roundStart <= block.timestamp) {
            revert Module__LM_PC_FundingPot__RoundStartMustBeInFuture();
        }

        // Validate that either end time or cap is set
        if (round_.roundEnd == 0 && round_.roundCap == 0) {
            revert Module__LM_PC_FundingPot__RoundMustHaveEndTimeOrCap();
        }

        // If end time is set, validate it's after start time
        if (round_.roundEnd > 0 && round_.roundEnd < round_.roundStart) {
            revert Module__LM_PC_FundingPot__RoundEndMustBeAfterStart();
        }

        // Validate hook contract and function consistency
        if (
            round_.hookContract != address(0) && round_.hookFunction.length == 0
        ) {
            revert
                Module__LM_PC_FundingPot__HookFunctionRequiredWithHookContract();
        }

        if (round_.hookContract == address(0) && round_.hookFunction.length > 0)
        {
            revert
                Module__LM_PC_FundingPot__HookContractRequiredWithHookFunction();
        }
    }

    /// @notice Validates the round parameters before editing.
    /// @param  round_ The round to validate.
    /// @dev    Reverts if the round parameters are invalid.
    function _validateEditRoundParameters(Round storage round_) internal view {
        if (round_.roundEnd == 0 && round_.roundCap == 0) {
            revert Module__LM_PC_FundingPot__RoundNotCreated();
        }

        if (block.timestamp > round_.roundStart) {
            revert Module__LM_PC_FundingPot__RoundAlreadyStarted();
        }
    }

    /// @dev    Validate uint start input.
    /// @param  start_ uint to validate.
    /// @param  cliff_ uint to validate.
    /// @param  end_ uint to validate.
    /// @return True if uint is valid.
    function _validTimes(uint start_, uint cliff_, uint end_)
        internal
        pure
        returns (bool)
    {
        return start_ + cliff_ <= end_;
    }

    /// @notice Contributes to a round with unused capacity from previous rounds.
    /// @param roundId_ The ID of the round to contribute to.
    /// @param user_ The address of the user to contribute for.
    /// @param amount_ The amount to contribute.
    /// @param accessCriteriaId_ The ID of the access criteria to use for this contribution.
    /// @param merkleProof_ The Merkle proof for validation if needed.
    /// @param unspentPersonalCap_ The amount of unused capacity from previous rounds.
    function _contributeToRoundFor(
        address user_,
        uint32 roundId_,
        uint amount_,
        uint8 accessCriteriaId_,
        bytes32[] memory merkleProof_,
        uint unspentPersonalCap_
    ) internal {
        if (amount_ == 0) {
            revert Module__LM_PC_FundingPot__InvalidDepositAmount();
        }

        Round storage round = rounds[roundId_];
        uint currentTime = block.timestamp;

        if (round.roundEnd == 0 && round.roundCap == 0) {
            revert Module__LM_PC_FundingPot__RoundNotCreated();
        }

        if (currentTime < round.roundStart) {
            revert Module__LM_PC_FundingPot__RoundHasNotStarted();
        }

        if (accessCriteriaId_ > MAX_ACCESS_CRITERIA_TYPE) {
            revert Module__LM_PC_FundingPot__InvalidAccessCriteriaType();
        }

        _validateAccessCriteria(
            roundId_, accessCriteriaId_, merkleProof_, user_
        );

        AccessCriteriaPrivileges storage privileges =
            roundIdToAccessCriteriaIdToPrivileges[roundId_][accessCriteriaId_];
        bool canOverrideContributionSpan = privileges.overrideContributionSpan;

        if (
            round.roundEnd > 0 && currentTime > round.roundEnd
                && !canOverrideContributionSpan
        ) {
            revert Module__LM_PC_FundingPot__RoundHasEnded();
        }

        // Calculate the adjusted amount considering caps
        uint adjustedAmount = _validateAndAdjustCapsWithUnspentCap(
            user_,
            roundId_,
            amount_,
            accessCriteriaId_,
            canOverrideContributionSpan,
            unspentPersonalCap_
        );

        roundIdToUserToContribution[roundId_][user_] += adjustedAmount;
        roundIdToTotalContributions[roundId_] += adjustedAmount;
        roundIdTouserContributionsByAccessCriteria[roundId_][user_][accessCriteriaId_]
        += adjustedAmount;

        __Module_orchestrator.fundingManager().token().safeTransferFrom(
            _msgSender(), address(this), adjustedAmount
        );

        EnumerableSet.add(contributorsByRound[roundId_], user_);

        emit ContributionMade(roundId_, user_, adjustedAmount);

        // contribution triggers automatic closure
        if (!roundIdToClosedStatus[roundId_] && round.autoClosure) {
            bool readyToClose = _checkRoundClosureConditions(roundId_);
            if (readyToClose) {
                _closeRound(roundId_);

                _buyBondingCurveToken(roundId_);
            }
        }
    }

    /// @notice Validates access criteria for a specific round and access type.
    /// @dev    Checks if a user meets the access requirements based on the round's access criteria.
    /// @param  roundId_ The ID of the round being validated.
    /// @param  accessCriteriaId_ The ID of the specific access criteria.
    /// @param  merkleProof_ Merkle proof for Merkle tree-based access (optional).
    /// @param  user_ The address of the user to validate.
    function _validateAccessCriteria(
        uint32 roundId_,
        uint8 accessCriteriaId_,
        bytes32[] memory merkleProof_,
        address user_
    ) internal view {
        Round storage round = rounds[roundId_];
        AccessCriteria storage accessCriteria =
            round.accessCriterias[accessCriteriaId_];

        bool isEligible = _checkAccessCriteriaEligibility(
            roundId_, accessCriteriaId_, merkleProof_, user_
        );

        if (!isEligible) {
            if (accessCriteria.accessCriteriaType == AccessCriteriaType.NFT) {
                revert Module__LM_PC_FundingPot__AccessCriteriaNftFailed();
            }
            if (accessCriteria.accessCriteriaType == AccessCriteriaType.MERKLE)
            {
                revert Module__LM_PC_FundingPot__AccessCriteriaMerkleFailed();
            }

            if (accessCriteria.accessCriteriaType == AccessCriteriaType.LIST) {
                revert Module__LM_PC_FundingPot__AccessCriteriaListFailed();
            }
        }
    }

    /// @notice Validates and adjusts the contribution amount considering caps and unspent capacity.
    /// @param user_ The address of the user to contribute for.
    /// @param roundId_ The ID of the round to contribute to.
    /// @param amount_ The amount to contribute.
    /// @param accessCriteriaId_ The ID of the access criteria to use for this contribution.
    /// @param canOverrideContributionSpan_ Whether the contribution span can be overridden.
    /// @param unspentPersonalCap_ The amount of unused capacity from previous rounds.
    function _validateAndAdjustCapsWithUnspentCap(
        address user_,
        uint32 roundId_,
        uint amount_,
        uint8 accessCriteriaId_,
        bool canOverrideContributionSpan_,
        uint unspentPersonalCap_
    ) internal view returns (uint adjustedAmount) {
        adjustedAmount = amount_;

        Round storage round = rounds[roundId_];

        // --- Round Cap Check ---
        if (!canOverrideContributionSpan_ && round.roundCap > 0) {
            uint totalRoundContribution = roundIdToTotalContributions[roundId_];
            uint effectiveRoundCap = round.roundCap;

            // If total accumulative caps are enabled for this round,
            // adjust the effective round cap to accommodate unused capacity from previous rounds
            if (
                round.accumulationMode == AccumulationMode.Total
                    || round.accumulationMode == AccumulationMode.All
            ) {
                uint unusedCapacityFromPrevious =
                    _calculateUnusedCapacityFromPreviousRounds(roundId_);
                effectiveRoundCap += unusedCapacityFromPrevious;
            }

            if (totalRoundContribution >= effectiveRoundCap) {
                // If round cap is reached, revert (we know amount_ > 0 from parent function)
                revert Module__LM_PC_FundingPot__RoundCapReached();
            } else {
                // Cap is not full, calculate remaining and clamp if necessary
                uint remainingRoundCap =
                    effectiveRoundCap - totalRoundContribution;
                if (adjustedAmount > remainingRoundCap) {
                    adjustedAmount = remainingRoundCap;
                }
            }
        }

        // --- Personal Cap Check ---
        {
            uint userPreviousContribution =
                roundIdToUserToContribution[roundId_][user_];

            AccessCriteriaPrivileges storage privileges =
            roundIdToAccessCriteriaIdToPrivileges[roundId_][accessCriteriaId_];
            uint userPersonalCap = privileges.personalCap;

            // Add unspent personal capacity if personal accumulation is enabled for this round
            if (
                round.accumulationMode == AccumulationMode.Personal
                    || round.accumulationMode == AccumulationMode.All
            ) {
                userPersonalCap += unspentPersonalCap_;
            }

            // If user already reached their cap, revert
            if (userPreviousContribution >= userPersonalCap) {
                revert Module__LM_PC_FundingPot__PersonalCapReached();
            }

            // Calculate remaining personal cap and take minimum
            uint remainingPersonalCap =
                userPersonalCap - userPreviousContribution;
            if (remainingPersonalCap < adjustedAmount) {
                adjustedAmount = remainingPersonalCap;
            }
        }

        return adjustedAmount;
    }

    /// @notice Checks if a user meets the access criteria for a specific round and access type.
    /// @dev    Returns true if the user meets the access criteria, reverts otherwise.
    /// @param  roundId_ The ID of the round being validated.
    /// @param  accessCriteriaId_ The ID of the specific access criteria.
    /// @param  merkleProof_ Merkle proof for Merkle tree-based access (optional).
    /// @param  user_ The address of the user to validate.
    /// @return isEligible True if the user meets the access criteria, false otherwise.
    function _checkAccessCriteriaEligibility(
        uint32 roundId_,
        uint8 accessCriteriaId_,
        bytes32[] memory merkleProof_,
        address user_
    ) internal view returns (bool isEligible) {
        Round storage round = rounds[roundId_];
        AccessCriteria storage accessCriteria =
            round.accessCriterias[accessCriteriaId_];

        if (accessCriteria.accessCriteriaType == AccessCriteriaType.OPEN) {
            isEligible = true;
        }
        if (accessCriteria.accessCriteriaType == AccessCriteriaType.NFT) {
            isEligible = _checkNftOwnership(accessCriteria.nftContract, user_);
        } else if (
            accessCriteria.accessCriteriaType == AccessCriteriaType.MERKLE
        ) {
            isEligible = _validateMerkleProof(
                accessCriteria.merkleRoot, merkleProof_, user_, roundId_
            );
        } else if (accessCriteria.accessCriteriaType == AccessCriteriaType.LIST)
        {
            isEligible = accessCriteria.allowedAddresses[user_];
        }

        return isEligible;
    }

    /// @notice Calculates unused capacity from previous rounds.
    /// @param roundId_ The ID of the current round.
    /// @return unusedCapacityFromPrevious The total unused capacity from previous rounds.
    function _calculateUnusedCapacityFromPreviousRounds(uint32 roundId_)
        internal
        view
        returns (uint unusedCapacityFromPrevious)
    {
        uint32 startAccumulationFrom = globalAccumulationStartRoundId;

        if (startAccumulationFrom >= roundId_) {
            return 0; // No rounds to consider for accumulation
        }

        // Iterate through previous rounds starting from the globalAccumulationStartRoundId
        for (uint32 i = startAccumulationFrom; i < roundId_; ++i) {
            Round storage prevRound = rounds[i];
            // Only consider previous rounds that allowed total accumulation
            if (
                prevRound.accumulationMode != AccumulationMode.Total
                    && prevRound.accumulationMode != AccumulationMode.All
            ) {
                continue;
            }

            uint prevRoundTotal = roundIdToTotalContributions[i];
            if (prevRoundTotal < prevRound.roundCap) {
                unusedCapacityFromPrevious +=
                    (prevRound.roundCap - prevRoundTotal);
            }
        }
        return unusedCapacityFromPrevious;
    }

    /// @notice Verifies NFT ownership for access control.
    /// @dev    Safely checks the NFT balance of a user using a try-catch block.
    /// @param  nftContract_ Address of the NFT contract.
    /// @param  user_ Address of the user to check for NFT ownership.
    /// @return Boolean indicating whether the user owns an NFT.
    function _checkNftOwnership(address nftContract_, address user_)
        internal
        view
        returns (bool)
    {
        if (nftContract_ == address(0) || user_ == address(0)) {
            return false;
        }

        try IERC721(nftContract_).balanceOf(user_) returns (uint balance) {
            return balance > 0;
        } catch {
            return false;
        }
    }

    /// @notice Verifies a Merkle p roof for access control.
    /// @dev    Validates that the user's address is part of the Merkle tree.
    /// @param  root_ The Merkle root to validate against.
    /// @param  user_ The address of the user to check.
    /// @param  roundId_ The ID of the round to check.
    /// @param  merkleProof_ The Merkle proof to verify.
    /// @return Boolean indicating whether the proof is valid.
    function _validateMerkleProof(
        bytes32 root_,
        bytes32[] memory merkleProof_,
        address user_,
        uint32 roundId_
    ) internal pure returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(user_, roundId_));

        return MerkleProof.verify(merkleProof_, root_, leaf);
    }

    /// @notice Handles round closure logic.
    /// @dev    Updates round status and executes hook if needed.
    /// @param  roundId_ The ID of the round to close.
    function _closeRound(uint32 roundId_) internal {
        Round storage round = rounds[roundId_];

        roundIdToClosedStatus[roundId_] = true;

        if (round.hookContract != address(0)) {
            (bool success,) = round.hookContract.call(round.hookFunction);
            if (!success) {
                revert Module__LM_PC_FundingPot__HookExecutionFailed();
            }
        }

        emit RoundClosed(roundId_, roundIdToTotalContributions[roundId_]);
    }

    /// @notice Creates payment orders for contributors in a round based on their access criteria.
    /// @dev    Processes a batch of contributors to handle gas limit concerns.
    /// @param  roundId_ The ID of the round to create payment orders for.
    /// @param  startIndex_ The starting index in the contributors array.
    /// @param  batchSize_ The number of contributors to process in this batch.
    function _createPaymentOrdersForContributors(
        uint32 roundId_,
        uint startIndex_,
        uint batchSize_
    ) internal {
        uint totalContributions = roundIdToTotalContributions[roundId_];
        uint tokensBought = roundTokensBought[roundId_];

        if (totalContributions == 0 || tokensBought == 0) return;

        address[] memory contributors =
            EnumerableSet.values(contributorsByRound[roundId_]);
        uint contributorCount = contributors.length;

        if (startIndex_ >= contributorCount) {
            revert Module__LM_PC_FundingPot__InvalidStartIndex();
        }

        // Calculate the end index (don't exceed array bounds)
        uint endIndex = startIndex_ + batchSize_;
        if (endIndex > contributorCount) {
            endIndex = contributorCount;
        }

        address issuanceToken = address(
            IBondingCurveBase_v1(
                address(__Module_orchestrator.fundingManager())
            ).getIssuanceToken()
        );

        for (uint i = startIndex_; i < endIndex; i++) {
            address contributor = contributors[i];
            uint contributorTotal =
                roundIdToUserToContribution[roundId_][contributor];

            if (contributorTotal == 0) continue;

            for (
                uint8 accessCriteriaId = 1;
                accessCriteriaId <= MAX_ACCESS_CRITERIA_TYPE;
                accessCriteriaId++
            ) {
                uint contributionByAccessCriteria =
                roundIdTouserContributionsByAccessCriteria[roundId_][contributor][accessCriteriaId];

                if (contributionByAccessCriteria == 0) continue;

                uint tokensForThisAccessCriteria;
                unchecked {
                    tokensForThisAccessCriteria = (
                        contributionByAccessCriteria * tokensBought
                    ) / totalContributions;
                }

                _createAndAddPaymentOrder(
                    roundId_,
                    contributor,
                    accessCriteriaId,
                    tokensForThisAccessCriteria,
                    issuanceToken
                );
            }
        }

        emit ContributorBatchProcessed(roundId_, startIndex_, endIndex);
    }

    /// @notice Creates time parameter data for a payment order.
    /// @dev    Sets default values for start, cliff, and end if they are zero.
    /// @param  start_ The start time of the payment order.
    /// @param  cliff_ The cliff time of the payment order.
    /// @param  end_ The end time of the payment order.
    /// @return flags The flags for the payment order.
    /// @return finalData The final data for the payment order.
    function _createTimeParameterData(uint start_, uint cliff_, uint end_)
        internal
        view
        returns (bytes32 flags, bytes32[] memory finalData)
    {
        if (start_ == 0) start_ = block.timestamp;
        if (end_ == 0) end_ = block.timestamp; // Note: cliff_ is not defaulted here.

        flags = 0;
        uint8 flagCount = 0;
        bytes32[3] memory tempData; // Fixed-size array on stack for intermediate values

        // Start time
        flags |= bytes32(uint(1) << FLAG_START);
        tempData[flagCount] = bytes32(start_);
        unchecked {
            flagCount++;
        }

        if (cliff_ > 0) {
            flags |= bytes32(uint(1) << FLAG_CLIFF);
            tempData[flagCount] = bytes32(cliff_);
            unchecked {
                flagCount++;
            }
        }

        // End time
        flags |= bytes32(uint(1) << FLAG_END);
        tempData[flagCount] = bytes32(end_);
        unchecked {
            flagCount++;
        }

        finalData = new bytes32[](flagCount);
        for (uint8 j = 0; j < flagCount; ++j) {
            unchecked {
                finalData[j] = tempData[j];
            }
        }

        return (flags, finalData);
    }

    /// @notice Creates and adds a payment order for a contributor.
    /// @dev    Sets default values for start, cliff, and end if they are zero.
    /// @param  roundId_ The ID of the round to create the payment order for.
    /// @param  recipient_ The address of the recipient of the payment order.
    /// @param  accessCriteriaId_  The ID of the specific access criteria.
    /// @param  tokensAmount_ The amount of tokens for the payment order.
    /// @param  issuanceToken_ The issuance token for the payment order.
    function _createAndAddPaymentOrder(
        uint32 roundId_,
        address recipient_,
        uint8 accessCriteriaId_,
        uint tokensAmount_,
        address issuanceToken_
    ) internal {
        AccessCriteriaPrivileges storage privileges =
            roundIdToAccessCriteriaIdToPrivileges[roundId_][accessCriteriaId_];

        uint start = privileges.start;
        uint cliff = privileges.cliff;
        uint end = privileges.end;

        (bytes32 flags, bytes32[] memory finalData) =
            _createTimeParameterData(start, cliff, end);

        IERC20PaymentClientBase_v2.PaymentOrder memory paymentOrder =
        IERC20PaymentClientBase_v2.PaymentOrder({
            recipient: recipient_,
            paymentToken: issuanceToken_,
            amount: tokensAmount_,
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: flags,
            data: finalData
        });

        _addPaymentOrder(paymentOrder);

        emit PaymentOrderCreated(
            roundId_,
            recipient_,
            accessCriteriaId_,
            tokensAmount_,
            start,
            cliff,
            end
        );
    }

    function _buyBondingCurveToken(uint32 roundId_) internal {
        uint totalContributions = roundIdToTotalContributions[roundId_];
        if (totalContributions == 0) {
            revert Module__LM_PC_FundingPot__NoContributions();
        }

        // Cache the funding manager instance and its address
        IFundingManager_v1 fundingManager =
            __Module_orchestrator.fundingManager();

        // Get the contribution token from the cached funding manager instance and approve it
        IERC20 contributionToken = fundingManager.token();
        contributionToken.approve(address(fundingManager), totalContributions);

        // Cast the cached funding manager address to the bonding curve interface
        IBondingCurveBase_v1 bondingCurve =
            IBondingCurveBase_v1(address(fundingManager));

        uint minAmountOut =
            bondingCurve.calculatePurchaseReturn(totalContributions);
        bondingCurve.buyFor(address(this), totalContributions, minAmountOut);

        roundTokensBought[roundId_] = minAmountOut;
    }

    /// @notice Checks if a round has reached its cap or time limit.
    /// @param  roundId_ The ID of the round to check.
    /// @return Boolean indicating if the round has reached its cap or time limit.
    function _checkRoundClosureConditions(uint32 roundId_)
        internal
        view
        returns (bool)
    {
        Round storage round = rounds[roundId_];
        uint totalContribution = roundIdToTotalContributions[roundId_];
        bool capReached =
            round.roundCap > 0 && totalContribution >= round.roundCap;
        bool timeEnded = round.roundEnd > 0 && block.timestamp >= round.roundEnd;
        return capReached || timeEnded;
    }

    /// @notice Sets and validates the round parameters.
    /// @param  roundToSet_ The round storage object to set parameters for.
    /// @param  roundStart_ Start timestamp for the round.
    /// @param  roundEnd_ End timestamp for the round.
    /// @param  roundCap_ Maximum contribution cap.
    /// @param  hookContract_ Address of contract to call after round closure.
    /// @param  hookFunction_ Encoded function call for the hook.
    /// @param  autoClosure_ Whether hook closure coincides with contribution span end.
    /// @param  accumulationMode_ Defines how caps accumulate.
    function _setAndValidateRoundParameters(
        Round storage roundToSet_,
        uint roundStart_,
        uint roundEnd_,
        uint roundCap_,
        address hookContract_,
        bytes memory hookFunction_,
        bool autoClosure_,
        AccumulationMode accumulationMode_
    ) internal {
        roundToSet_.roundStart = roundStart_;
        roundToSet_.roundEnd = roundEnd_;
        roundToSet_.roundCap = roundCap_;
        roundToSet_.hookContract = hookContract_;
        roundToSet_.hookFunction = hookFunction_;
        roundToSet_.autoClosure = autoClosure_;
        roundToSet_.accumulationMode = accumulationMode_;

        _validateRoundParameters(roundToSet_);
    }
}
