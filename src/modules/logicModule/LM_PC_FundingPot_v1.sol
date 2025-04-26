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

// External
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IERC721} from "@oz/token/ERC721/IERC721.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

import "@oz/utils/cryptography/MerkleProof.sol";
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
    uint8 internal constant MAX_ACCESS_CRITERIA_ID = 4;

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
    ) private roundItToAccessCriteriaIdToPrivileges;

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
    /// @param  configData_ The config data of the module, comprised of:
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata_,
        bytes memory configData_
    ) external override(Module_v1) initializer {
        __Module_init(orchestrator_, metadata_);
        // Set the flags for the PaymentOrders (this module uses 3 flags).
        bytes32 flags;
        flags |= bytes32(1 << FLAG_START);
        flags |= bytes32(1 << FLAG_CLIFF);
        flags |= bytes32(1 << FLAG_END);

        __ERC20PaymentClientBase_v2_init(flags);
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
            bool globalAccumulativeCaps
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
            round.globalAccumulativeCaps
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
        Round storage round = rounds[roundId_];
        AccessCriteria storage accessCriteria =
            round.accessCriterias[accessCriteriaId_];

        if (accessCriteria.accessCriteriaType == AccessCriteriaType.OPEN) {
            return (
                true,
                accessCriteria.nftContract,
                accessCriteria.merkleRoot,
                true
            );
        } else if (accessCriteria.accessCriteriaType == AccessCriteriaType.LIST)
        {
            return (
                false,
                accessCriteria.nftContract,
                accessCriteria.merkleRoot,
                true
            );
        } else {
            return (
                false,
                accessCriteria.nftContract,
                accessCriteria.merkleRoot,
                false
            );
        }
    }

    /// @inheritdoc ILM_PC_FundingPot_v1
    function getRoundAccessCriteriaPrivileges(
        uint32 roundId_,
        uint8 accessCriteriaId__
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
            round.accessCriterias[accessCriteriaId__];

        if (accessCriteria.accessCriteriaType == AccessCriteriaType.UNSET) {
            return (0, false, 0, 0, 0);
        }

        // Store the privileges in a local variable to reduce stack usage.
        AccessCriteriaPrivileges storage privileges =
            roundItToAccessCriteriaIdToPrivileges[roundId_][accessCriteriaId__];

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
        if (accessCriteriaId_ > MAX_ACCESS_CRITERIA_ID) {
            revert Module__LM_PC_FundingPot__InvalidAccessCriteriaId();
        }

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
            roundItToAccessCriteriaIdToPrivileges[roundId_][accessCriteriaId_];
            uint userPersonalCap = privileges.personalCap;
            uint userContribution = _getUserContributionToRound(roundId_, user_);

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
        bool globalAccumulativeCaps_
    ) external onlyModuleRole(FUNDING_POT_ADMIN_ROLE) returns (uint32) {
        roundCount++;

        uint32 roundId = roundCount;

        Round storage round = rounds[roundId];
        round.roundStart = roundStart_;
        round.roundEnd = roundEnd_;
        round.roundCap = roundCap_;
        round.hookContract = hookContract_;
        round.hookFunction = hookFunction_;
        round.autoClosure = autoClosure_;
        round.globalAccumulativeCaps = globalAccumulativeCaps_;

        _validateRoundParameters(round);

        emit RoundCreated(
            roundId,
            roundStart_,
            roundEnd_,
            roundCap_,
            hookContract_,
            hookFunction_,
            autoClosure_,
            globalAccumulativeCaps_
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
        bool globalAccumulativeCaps_
    ) external onlyModuleRole(FUNDING_POT_ADMIN_ROLE) {
        Round storage round = rounds[roundId_];

        _validateEditRoundParameters(round);

        round.roundStart = roundStart_;
        round.roundEnd = roundEnd_;
        round.roundCap = roundCap_;
        round.hookContract = hookContract_;
        round.hookFunction = hookFunction_;
        round.autoClosure = autoClosure_;
        round.globalAccumulativeCaps = globalAccumulativeCaps_;

        _validateRoundParameters(round);

        emit RoundEdited(
            roundId_,
            roundStart_,
            roundEnd_,
            roundCap_,
            hookContract_,
            hookFunction_,
            autoClosure_,
            globalAccumulativeCaps_
        );
    }

    /// @inheritdoc ILM_PC_FundingPot_v1
    function setAccessCriteriaForRound(
        uint32 roundId_,
        uint8 accessCriteriaId_,
        address nftContract_,
        bytes32 merkleRoot_,
        address[] calldata allowedAddresses_
    ) external onlyModuleRole(FUNDING_POT_ADMIN_ROLE) {
        Round storage round = rounds[roundId_];

        _validateEditRoundParameters(round);

        if (
            (
                accessCriteriaId_ == uint8(AccessCriteriaType.NFT)
                    && nftContract_ == address(0)
            )
                || (
                    accessCriteriaId_ == uint8(AccessCriteriaType.MERKLE)
                        && merkleRoot_ == bytes32("")
                )
                || (
                    accessCriteriaId_ == uint8(AccessCriteriaType.LIST)
                        && allowedAddresses_.length == 0
                )
        ) {
            revert Module__LM_PC_FundingPot__MissingRequiredAccessCriteriaData();
        }

        AccessCriteriaType accessCriteriaType =
            AccessCriteriaType(accessCriteriaId_);
        round.accessCriterias[accessCriteriaId_].accessCriteriaType =
            accessCriteriaType;
        round.accessCriterias[accessCriteriaId_].nftContract = nftContract_;
        round.accessCriterias[accessCriteriaId_].merkleRoot = merkleRoot_;

        for (uint i = 0; i < allowedAddresses_.length; i++) {
            round.accessCriterias[accessCriteriaId_].allowedAddresses[allowedAddresses_[i]]
            = true;
        }

        emit AccessCriteriaSet(roundId_, accessCriteriaId_);
    }

    /// @inheritdoc ILM_PC_FundingPot_v1
    function editAccessCriteriaForRound(
        uint32 roundId_,
        uint8 accessCriteriaId_,
        address nftContract_,
        bytes32 merkleRoot_,
        address[] calldata allowedAddresses_
    ) external onlyModuleRole(FUNDING_POT_ADMIN_ROLE) {
        Round storage round = rounds[roundId_];
        if (accessCriteriaId_ > MAX_ACCESS_CRITERIA_ID) {
            revert Module__LM_PC_FundingPot__InvalidAccessCriteriaId();
        }

        _validateEditRoundParameters(round);

        AccessCriteriaType accessCriteriaType =
            AccessCriteriaType(accessCriteriaId_);
        round.accessCriterias[accessCriteriaId_].accessCriteriaType =
            accessCriteriaType;
        round.accessCriterias[accessCriteriaId_].nftContract = nftContract_;
        round.accessCriterias[accessCriteriaId_].merkleRoot = merkleRoot_;

        for (uint i = 0; i < allowedAddresses_.length; i++) {
            round.accessCriterias[accessCriteriaId_].allowedAddresses[allowedAddresses_[i]]
            = true;
        }

        emit AccessCriteriaEdited(roundId_, accessCriteriaId_);
    }

    function removeAllowlistedAddresses(
        uint32 roundId_,
        uint8 accessCriteriaId_,
        address[] calldata addressesToRemove_
    ) external onlyModuleRole(FUNDING_POT_ADMIN_ROLE) {
        Round storage round = rounds[roundId_];
        if (accessCriteriaId_ > MAX_ACCESS_CRITERIA_ID) {
            revert Module__LM_PC_FundingPot__InvalidAccessCriteriaId();
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
            roundItToAccessCriteriaIdToPrivileges[roundId_][accessCriteriaId_];

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
        bytes32[] calldata merkleProof_
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
        uint unspentPersonalCap;

        // Process each previous round cap that the user wants to carry over
        for (uint i = 0; i < unspentPersonalRoundCaps_.length; i++) {
            UnspentPersonalRoundCap memory roundCap =
                unspentPersonalRoundCaps_[i];

            Round storage prevRound = rounds[roundCap.roundId];
            if (!prevRound.globalAccumulativeCaps) continue;

            // Verify the user was eligible for this access criteria in the previous round
            bool isEligible = _checkAccessCriteriaEligibility(
                uint32(roundCap.roundId),
                roundCap.accessCriteriaId,
                roundCap.merkleProof,
                user_
            );

            if (isEligible) {
                AccessCriteriaPrivileges storage privileges =
                roundItToAccessCriteriaIdToPrivileges[roundCap.roundId][roundCap
                    .accessCriteriaId];

                uint userContribution =
                    _getUserContributionToRound(uint32(roundCap.roundId), user_);
                uint personalCap = privileges.personalCap;

                if (userContribution < personalCap) {
                    unspentPersonalCap += (personalCap - userContribution);
                }
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
        if (batchSize_ == 0 || batchSize_ > contributorCount) {
            revert Module__LM_PC_FundingPot__InvalidBatchParameters();
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

    // -------------------------------------------------------------------------
    // Internal

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

        if (accessCriteriaId_ > MAX_ACCESS_CRITERIA_ID) {
            revert Module__LM_PC_FundingPot__InvalidAccessCriteriaId();
        }

        _validateAccessCriteria(
            roundId_, accessCriteriaId_, merkleProof_, user_
        );

        AccessCriteriaPrivileges storage privileges =
            roundItToAccessCriteriaIdToPrivileges[roundId_][accessCriteriaId_];
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
    /// @param accessCriteriaId__ The ID of the access criteria to use for this contribution.
    /// @param canOverrideContributionSpan_ Whether the contribution span can be overridden.
    /// @param unspentPersonalCap_ The amount of unused capacity from previous rounds.
    function _validateAndAdjustCapsWithUnspentCap(
        address user_,
        uint32 roundId_,
        uint amount_,
        uint8 accessCriteriaId__,
        bool canOverrideContributionSpan_,
        uint unspentPersonalCap_
    ) internal view returns (uint adjustedAmount) {
        adjustedAmount = amount_;

        Round storage round = rounds[roundId_];

        if (!canOverrideContributionSpan_ && round.roundCap > 0) {
            uint totalRoundContribution = _getTotalRoundContribution(roundId_);
            uint effectiveRoundCap = round.roundCap;

            // If global accumulative caps are enabled,
            // adjust the round cap to acommodate unused capacity from previous rounds
            if (round.globalAccumulativeCaps) {
                uint unusedCapacityFromPrevious =
                    _calculateUnusedCapacityFromPreviousRounds(roundId_);
                effectiveRoundCap += unusedCapacityFromPrevious;
            }

            if (totalRoundContribution >= effectiveRoundCap) {
                revert Module__LM_PC_FundingPot__RoundCapReached();
            }

            // Allow the user to contribute up to the remaining round cap
            uint remainingRoundCap = effectiveRoundCap - totalRoundContribution;
            if (adjustedAmount > remainingRoundCap) {
                adjustedAmount = remainingRoundCap;
            }
        }

        // Check and adjust for personal cap
        uint userPreviousContribution =
            _getUserContributionToRound(roundId_, user_);

        // Get the base personal cap for this round and criteria
        AccessCriteriaPrivileges storage privileges =
            roundItToAccessCriteriaIdToPrivileges[roundId_][accessCriteriaId__];
        uint userPersonalCap = privileges.personalCap;

        // Add unspent capacity if global accumulative caps are enabled
        if (round.globalAccumulativeCaps) {
            userPersonalCap += unspentPersonalCap_;
        }

        if (userPreviousContribution + adjustedAmount > userPersonalCap) {
            if (userPreviousContribution < userPersonalCap) {
                adjustedAmount = userPersonalCap - userPreviousContribution;
            } else {
                revert Module__LM_PC_FundingPot__PersonalCapReached();
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
        unusedCapacityFromPrevious = 0;
        // Iterate through all previous rounds (1 to roundId_-1)
        for (uint32 i = 1; i < roundId_; ++i) {
            Round storage prevRound = rounds[i];
            if (!prevRound.globalAccumulativeCaps) continue;

            uint prevRoundTotal = _getTotalRoundContribution(i);
            if (prevRoundTotal < prevRound.roundCap) {
                unusedCapacityFromPrevious +=
                    (prevRound.roundCap - prevRoundTotal);
            }
        }
        return unusedCapacityFromPrevious;
    }

    /// @notice Retrieves the total contribution for a specific round.
    /// @dev    Returns the accumulated contributions for the given round.
    /// @param  roundId_ The ID of the round to check contributions for.
    /// @return The total contributions for the specified round.
    function _getTotalRoundContribution(uint32 roundId_)
        internal
        view
        returns (uint)
    {
        return roundIdToTotalContributions[roundId_];
    }

    /// @notice Retrieves the contribution amount for a specific user in a round.
    /// @dev    Returns the individual user's contribution for the given round.
    /// @param  roundId_ The ID of the round to check contributions for.
    /// @param  user_ The address of the user.
    /// @return The user's contribution amount for the specified round.
    function _getUserContributionToRound(uint32 roundId_, address user_)
        internal
        view
        returns (uint)
    {
        return roundIdToUserToContribution[roundId_][user_];
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
            if (balance == 0) {
                return false;
            }
            return true;
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

        if (!MerkleProof.verify(merkleProof_, root_, leaf)) {
            return false;
        }

        return true;
    }

    /// @notice Handles round closure logic.
    /// @dev    Updates round status and executes hook if needed.
    /// @param  roundId_ The ID of the round to close.
    function _closeRound(uint32 roundId_) internal {
        Round storage round = rounds[roundId_];

        roundIdToClosedStatus[roundId_] = true;

        if (round.hookContract != address(0) && round.hookFunction.length > 0) {
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
                uint8 accessCriteriaId = 0;
                accessCriteriaId <= MAX_ACCESS_CRITERIA_ID;
                accessCriteriaId++
            ) {
                uint contributionByAccessCriteria =
                roundIdTouserContributionsByAccessCriteria[roundId_][contributor][accessCriteriaId];

                if (contributionByAccessCriteria == 0) continue;

                uint tokensForThisAccessCriteria = (
                    contributionByAccessCriteria * tokensBought
                ) / totalContributions;

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
        if (end_ == 0) end_ = block.timestamp;

        flags = 0;
        bytes32[] memory data = new bytes32[](3); // For start, cliff, and end
        uint8 flagCount = 0;

        if (start_ > 0) {
            flags |= bytes32(uint(1) << 1);
            data[flagCount] = bytes32(start_);
            flagCount++;
        }

        if (cliff_ > 0) {
            flags |= bytes32(uint(1) << 2);
            data[flagCount] = bytes32(cliff_);
            flagCount++;
        }

        if (end_ > 0) {
            flags |= bytes32(uint(1) << 3);
            data[flagCount] = bytes32(end_);
            flagCount++;
        }

        finalData = new bytes32[](flagCount);
        for (uint8 j = 0; j < flagCount; j++) {
            finalData[j] = data[j];
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
            roundItToAccessCriteriaIdToPrivileges[roundId_][accessCriteriaId_];

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
        uint totalContributions = _getTotalRoundContribution(roundId_);
        if (totalContributions == 0) {
            revert Module__LM_PC_FundingPot__NoContributions();
        }
        // approve the fundingManager to spend the contribution token
        IERC20(__Module_orchestrator.fundingManager().token()).approve(
            address(__Module_orchestrator.fundingManager()), totalContributions
        );
        uint minAmountOut = IBondingCurveBase_v1(
            address(__Module_orchestrator.fundingManager())
        ).calculatePurchaseReturn(totalContributions);
        IBondingCurveBase_v1(address(__Module_orchestrator.fundingManager()))
            .buyFor(address(this), totalContributions, minAmountOut);

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
            round.roundCap > 0 && totalContribution == round.roundCap;
        bool timeEnded = round.roundEnd > 0 && block.timestamp >= round.roundEnd;
        return capReached || timeEnded;
    }
}
