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
import {FM_BC_Bancor_Redeeming_VirtualSupply_v1} from
    "src/modules/fundingManager/bondingCurve/FM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";

// External
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IERC721} from "@oz/token/ERC721/IERC721.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

import "@oz/utils/cryptography/MerkleProof.sol";
import {EnumerableSet} from "@oz/utils/structs/EnumerableSet.sol";

/**
 * @title   Inverter Funding Pot Logic Module
 *
 * @notice  Manages contribution rounds for fundraising within the Inverter Network, enabling
 *          configurable access control, contribution limits, and automated distribution.
 *          Supports multiple concurrent access criteria per round with customizable privileges.
 *
 * @dev     Implements a sophisticated round-based funding system with features including:
 *          - Configurable round parameters (start/end times, caps, hooks)
 *          - Multiple access criteria types (NFT holding, allowlist, Merkle proof)
 *          - Customizable privileges per access criteria
 *          - Global accumulative caps across rounds
 *          - Automatic and manual round closure mechanisms
 *          - Hook system for post-round actions
 *
 *          DISCLAIMER: Known Limitations
 *          1. Storage Considerations:
 *             The contract stores significant data per round (access criteria, privileges,
 *             contributions). While this enables flexible round configuration, it may lead
 *             to higher gas costs as the number of rounds and contributors increases.
 *
 *          2. Round Management:
 *             Rounds cannot be modified once started. This is a security feature but
 *             requires careful initial configuration. Additionally, rounds must be created
 *             sequentially and cannot run concurrently.
 *
 *          3. Access Criteria:
 *             The contract supports multiple access criteria per round, but each address
 *             can only contribute under one access criteria type per round. This is to
 *             prevent double-counting of privileges and caps.
 *
 *          CAUTION: Administrators should carefully consider round configurations,
 *          particularly when using global accumulative caps and multiple access criteria,
 *          as these features interact in complex ways that affect contribution limits.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
 *
 * @custom:version  v1.0.0
 *
 * @custom:inverter-standard-version    v0.1.0
 *
 * @author  Inverter Network
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

    /// @notice Stores all funding rounds by their unique ID.
    mapping(uint64 => Round) private rounds;

    /// @notice Stores all access criteria privilages by their unique ID.
    mapping(
        uint64 roundId
            => mapping(uint8 accessCriteriaId_ => AccessCriteriaPrivileges)
    ) private roundItToAccessCriteriaIdToPrivileges;

    /// @notice Maps round IDs to user addresses to contribution amounts
    mapping(uint64 => mapping(address => uint)) private
        roundIdToUserToContribution;

    /// @notice Maps round IDs to total contributions
    mapping(uint64 => uint) private roundIdToTotalContributions;

    /// @notice Maps round IDs to closed status
    mapping(uint64 => bool) private roundIdToClosedStatus;

    /// @notice Maps round IDs to bonding curve tokens bought
    mapping(uint64 => uint) private roundTokensBought;

    /// @notice Maps round IDs to contributors recipients
    mapping(uint64 => EnumerableSet.AddressSet) private contributorsByRound;

    /// @notice Maps round IDs to user addresses to contribution amounts by access criteria
    mapping(uint64 => mapping(address => mapping(uint8 => uint))) private
        roundIdTouserContributionsByAccessCriteria;

    /// @notice Bancor Bonding Curve Funding Manager
    FM_BC_Bancor_Redeeming_VirtualSupply_v1 bancorFM;

    /// @notice The current round count.
    uint64 private roundCount;

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

        address bancorFMaddress = abi.decode(configData_, (address));
        bancorFM = FM_BC_Bancor_Redeeming_VirtualSupply_v1(bancorFMaddress);
    }

    // -------------------------------------------------------------------------
    // Public - Getters

    /// @inheritdoc ILM_PC_FundingPot_v1
    function getRoundGenericParameters(uint64 roundId_)
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
    function getRoundAccessCriteria(uint64 roundId_, uint8 accessCriteriaId_)
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
        uint64 roundId_,
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
    function getRoundCount() external view returns (uint64) {
        return roundCount;
    }

    /// @inheritdoc ILM_PC_FundingPot_v1
    function isRoundClosed(uint64 roundId_) external view returns (bool) {
        return roundIdToClosedStatus[roundId_];
    }

    /// @inheritdoc ILM_PC_FundingPot_v1
    function getUserEligibility(
        uint64 roundId_,
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
    ) external onlyModuleRole(FUNDING_POT_ADMIN_ROLE) returns (uint64) {
        roundCount++;

        uint64 roundId = roundCount;

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

        return roundId;
    }

    /// @inheritdoc ILM_PC_FundingPot_v1
    function editRound(
        uint64 roundId_,
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
        uint64 roundId_,
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
        uint64 roundId_,
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
        uint64 roundId_,
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
        uint64 roundId_,
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
    function contributeToRound(
        uint64 roundId_,
        uint amount_,
        uint8 accessCriteriaId_,
        bytes32[] calldata merkleProof_
    ) external {
        // Call the internal function with no additional unspent personal cap
        _contributeToRound(
            roundId_, amount_, accessCriteriaId_, merkleProof_, 0
        );
    }

    /// @inheritdoc ILM_PC_FundingPot_v1
    function contributeToRound(
        uint64 roundId_,
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
                roundCap.roundId,
                roundCap.accessCriteriaId,
                roundCap.merkleProof,
                _msgSender()
            );

            if (isEligible) {
                AccessCriteriaPrivileges storage privileges =
                roundItToAccessCriteriaIdToPrivileges[roundCap.roundId][roundCap
                    .accessCriteriaId];

                uint userContribution =
                    _getUserContributionToRound(roundCap.roundId, _msgSender());
                uint personalCap = privileges.personalCap;

                if (userContribution < personalCap) {
                    unspentPersonalCap += (personalCap - userContribution);
                }
            }
        }

        _contributeToRound(
            roundId_,
            amount_,
            accessCriteriaId_,
            merkleProof_,
            unspentPersonalCap
        );
    }

    /// @inheritdoc ILM_PC_FundingPot_v1
    function closeRound(uint64 roundId_)
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

            _createPaymentOrdersForContributors(roundId_);
        } else {
            revert Module__LM_PC_FundingPot__ClosureConditionsNotMet();
        }
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

    /// @notice Contributes to a round with unused capacity from previous rounds
    /// @param roundId_ The ID of the round to contribute to
    /// @param amount_ The amount to contribute
    /// @param accessCriteriaId_ The ID of the access criteria to use for this contribution
    /// @param merkleProof_ The Merkle proof for validation if needed
    /// @param unspentPersonalCap_ The amount of unused capacity from previous rounds
    function _contributeToRound(
        uint64 roundId_,
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
            roundId_, accessCriteriaId_, merkleProof_, _msgSender()
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
            roundId_,
            amount_,
            accessCriteriaId_,
            canOverrideContributionSpan,
            unspentPersonalCap_
        );

        roundIdToUserToContribution[roundId_][_msgSender()] += adjustedAmount;
        roundIdToTotalContributions[roundId_] += adjustedAmount;
        roundIdTouserContributionsByAccessCriteria[roundId_][_msgSender()][accessCriteriaId_]
        += adjustedAmount;

        __Module_orchestrator.fundingManager().token().safeTransferFrom(
            _msgSender(), address(this), adjustedAmount
        );

        EnumerableSet.add(contributorsByRound[roundId_], _msgSender());

        emit ContributionMade(roundId_, _msgSender(), adjustedAmount);

        // contribution triggers automatic closure
        if (!roundIdToClosedStatus[roundId_] && round.autoClosure) {
            bool readyToClose = _checkRoundClosureConditions(roundId_);
            if (readyToClose) {
                _closeRound(roundId_);

                _buyBondingCurveToken(roundId_);

                _createPaymentOrdersForContributors(roundId_);
            }
        }
    }

    /// @notice Validates access criteria for a specific round and access type
    /// @dev    Checks if a user meets the access requirements based on the round's access criteria
    /// @param  roundId_ The ID of the round being validated
    /// @param  accessCriteriaId_ The ID of the specific access criteria
    /// @param  merkleProof_ Merkle proof for Merkle tree-based access (optional)
    /// @param  user_ The address of the user to validate
    function _validateAccessCriteria(
        uint64 roundId_,
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

    /// @notice Validates and adjusts the contribution amount considering caps and unspent capacity
    /// @param roundId_ The ID of the round to contribute to
    /// @param amount_ The amount to contribute
    /// @param accessCriteriaId__ The ID of the access criteria to use for this contribution
    /// @param canOverrideContributionSpan_ Whether the contribution span can be overridden
    /// @param unspentPersonalCap_ The amount of unused capacity from previous rounds
    function _validateAndAdjustCapsWithUnspentCap(
        uint64 roundId_,
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
            _getUserContributionToRound(roundId_, _msgSender());

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

    /// @notice Checks if a user meets the access criteria for a specific round and access type
    /// @dev    Returns true if the user meets the access criteria, reverts otherwise
    /// @param  roundId_ The ID of the round being validated
    /// @param  accessCriteriaId_ The ID of the specific access criteria
    /// @param  merkleProof_ Merkle proof for Merkle tree-based access (optional)
    /// @param  user_ The address of the user to validate
    /// @return isEligible True if the user meets the access criteria, false otherwise
    function _checkAccessCriteriaEligibility(
        uint64 roundId_,
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

    /// @notice Calculates unused capacity from previous rounds
    /// @param roundId_ The ID of the current round
    /// @return unusedCapacityFromPrevious The total unused capacity from previous rounds
    function _calculateUnusedCapacityFromPreviousRounds(uint64 roundId_)
        internal
        view
        returns (uint unusedCapacityFromPrevious)
    {
        unusedCapacityFromPrevious = 0;
        // Iterate through all previous rounds (1 to roundId_-1)
        for (uint64 i = 1; i < roundId_; ++i) {
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

    /// @notice Retrieves the total contribution for a specific round
    /// @dev    Returns the accumulated contributions for the given round
    /// @param  roundId_ The ID of the round to check contributions for
    /// @return The total contributions for the specified round
    function _getTotalRoundContribution(uint64 roundId_)
        internal
        view
        returns (uint)
    {
        return roundIdToTotalContributions[roundId_];
    }

    /// @notice Retrieves the contribution amount for a specific user in a round
    /// @dev    Returns the individual user's contribution for the given round
    /// @param  roundId_ The ID of the round to check contributions for
    /// @param  user_ The address of the user
    /// @return The user's contribution amount for the specified round
    function _getUserContributionToRound(uint64 roundId_, address user_)
        internal
        view
        returns (uint)
    {
        return roundIdToUserToContribution[roundId_][user_];
    }

    /// @notice Verifies NFT ownership for access control
    /// @dev    Safely checks the NFT balance of a user using a try-catch block
    /// @param  nftContract_ Address of the NFT contract
    /// @param  user_ Address of the user to check for NFT ownership
    /// @return Boolean indicating whether the user owns an NFT
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

    /// @notice Verifies a Merkle p roof for access control
    /// @dev    Validates that the user's address is part of the Merkle tree
    /// @param  root_ The Merkle root to validate against
    /// @param  user_ The address of the user to check
    /// @param  roundId_ The ID of the round to check
    /// @param  merkleProof_ The Merkle proof to verify
    /// @return Boolean indicating whether the proof is valid
    function _validateMerkleProof(
        bytes32 root_,
        bytes32[] memory merkleProof_,
        address user_,
        uint64 roundId_
    ) internal pure returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(user_, roundId_));

        if (!MerkleProof.verify(merkleProof_, root_, leaf)) {
            return false;
        }

        return true;
    }

    /// @notice Handles round closure logic
    /// @dev    Updates round status and executes hook if needed
    /// @param  roundId_ The ID of the round to close
    function _closeRound(uint64 roundId_) internal {
        Round storage round = rounds[roundId_];

        roundIdToClosedStatus[roundId_] = true;

        if (round.hookContract != address(0) && round.hookFunction.length > 0) {
            (bool success,) = round.hookContract.call(round.hookFunction);
            if (!success) {
                revert Module__LM_PC_FundingPot__HookExecutionFailed();
            }
        }

        emit RoundClosed(
            roundId_, block.timestamp, roundIdToTotalContributions[roundId_]
        );
    }

    /// @notice Creates payment orders for all contributors in a round based on their access criteria
    /// @dev    Loops through all contributors and creates payment orders with appropriate vesting schedules
    /// @param  roundId_ The ID of the round to create payment orders for
    function _createPaymentOrdersForContributors(uint64 roundId_) internal {
        Round storage round = rounds[roundId_];
        uint totalContributions = roundIdToTotalContributions[roundId_];
        uint tokensBought = roundTokensBought[roundId_];

        if (totalContributions == 0 || tokensBought == 0) return;

        address[] memory contributors =
            EnumerableSet.values(contributorsByRound[roundId_]);

        // address issuanceToken = address(
        //     IBondingCurveBase_v1(
        //         address(__Module_orchestrator.fundingManager())
        //     ).getIssuanceToken()
        // );
        //@note: This is for testing purpose, the above snippet should be used to fetch the token address, talk to Fabi!
        address issuanceToken = bancorFM.getIssuanceToken();

        for (uint i = 0; i < contributors.length; i++) {
            address contributor = contributors[i];
            uint contributorTotal =
                roundIdToUserToContribution[roundId_][contributor];

            if (contributorTotal == 0) continue;

            // Calculate tokens for this contributor proportionally
            uint contributorTokens =
                (contributorTotal * tokensBought) / totalContributions;

            for (
                uint8 accessCriteriaId = 0;
                accessCriteriaId <= MAX_ACCESS_CRITERIA_ID;
                accessCriteriaId++
            ) {
                uint contributionByAccessCriteria =
                roundIdTouserContributionsByAccessCriteria[roundId_][contributor][accessCriteriaId];

                if (contributionByAccessCriteria == 0) continue;

                AccessCriteriaPrivileges storage privileges =
                roundItToAccessCriteriaIdToPrivileges[roundId_][accessCriteriaId];

                uint tokensForThisAccessCriteria = (
                    contributionByAccessCriteria * tokensBought
                ) / totalContributions;

                uint start = privileges.overrideContributionSpan
                    ? privileges.start
                    : round.roundStart;
                uint cliff =
                    privileges.overrideContributionSpan ? privileges.cliff : 0;
                uint end = privileges.overrideContributionSpan
                    ? privileges.end
                    : round.roundEnd;

                if (start == 0) start = block.timestamp;
                if (end == 0) end = block.timestamp;

                bytes32 flags = 0;
                bytes32[] memory data = new bytes32[](3); // For start, cliff, and end
                uint8 flagCount = 0;

                if (start > 0) {
                    flags |= bytes32(uint(1) << 1); // Flag 1 for start
                    data[flagCount] = bytes32(start);
                    flagCount++;
                }

                if (cliff > 0) {
                    flags |= bytes32(uint(1) << 2); // Flag 2 for cliff
                    data[flagCount] = bytes32(cliff);
                    flagCount++;
                }

                if (end > 0) {
                    flags |= bytes32(uint(1) << 3); // Flag 3 for end
                    data[flagCount] = bytes32(end);
                    flagCount++;
                }

                bytes32[] memory finalData = new bytes32[](flagCount);
                for (uint8 j = 0; j < flagCount; j++) {
                    finalData[j] = data[j];
                }

                IERC20PaymentClientBase_v2.PaymentOrder memory paymentOrder =
                IERC20PaymentClientBase_v2.PaymentOrder({
                    recipient: contributor,
                    paymentToken: issuanceToken,
                    amount: tokensForThisAccessCriteria,
                    originChainId: block.chainid,
                    targetChainId: block.chainid,
                    flags: flags,
                    data: finalData
                });

                _addPaymentOrder(paymentOrder);

                emit PaymentOrderCreated(
                    roundId_,
                    contributor,
                    accessCriteriaId,
                    tokensForThisAccessCriteria,
                    start,
                    cliff,
                    end
                );
            }
        }
    }

    function _buyBondingCurveToken(uint64 roundId_) internal {
        uint totalContributions = _getTotalRoundContribution(roundId_);

        // address issuanceToken = address(
        //     IBondingCurveBase_v1(
        //         address(__Module_orchestrator.fundingManager())
        //     ).getIssuanceToken()
        // );

        address issuanceToken = bancorFM.getIssuanceToken();

        uint balanceBefore = IERC20(issuanceToken).balanceOf(address(this));
        IBondingCurveBase_v1(issuanceToken).buyFor(
            address(this), totalContributions, 0
        );
        uint balanceAfter = IERC20(issuanceToken).balanceOf(address(this));

        uint tokensBought = balanceAfter - balanceBefore;
        roundTokensBought[roundId_] = tokensBought;
    }

    /// @notice Checks if a round has reached its cap or time limit
    /// @param  roundId_ The ID of the round to check
    /// @return Boolean indicating if the round has reached its cap or time limit
    function _checkRoundClosureConditions(uint64 roundId_)
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
