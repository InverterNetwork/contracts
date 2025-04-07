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

// External
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IERC721} from "@oz/token/ERC721/IERC721.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

import "@oz/utils/cryptography/MerkleProof.sol";

/**
 * @title   Inverter Funding Pot Module
 *
 * @notice  The module allows project supporters to contribute during funding rounds.
 *
 * @dev     Extends {ERC20PaymentClientBase_v2} and implements {ILM_PC_FundingPot_v1}.
 *          This contract manages funding rounds with configurable parameters including
 *          start/end times, funding caps, and hook contracts for custom logic.
 *          Uses timestamps as flags for payment processing via FLAG_START, FLAG_CLIFF,
 *          and FLAG_END constants.
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

    // -------------------------------------------------------------------------
    // State

    /// @notice Stores all funding rounds by their unique ID.
    mapping(uint64 => Round) private rounds;

    /// @notice Stores all access criteria privilages by their unique ID.
    mapping(
        uint64 roundId => mapping(uint8 accessId => AccessCriteriaPrivileges)
    ) private accessCriteriaPrivileges;

    /// @notice Maps round IDs to user addresses to contribution amounts
    mapping(uint64 => mapping(address => uint)) private userContributions;

    /// @notice Maps round IDs to total contributions
    mapping(uint64 => uint) private roundTotalContributions;

    /// @notice Maps round IDs to closed status
    mapping(uint64 => bool) private roundClosed;

    /// @notice The current round count.
    uint64 private roundCount;

    /// @notice The token used for contributions.
    IERC20 private contributionToken;

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
        address fundingPotToken;
        (fundingPotToken) = abi.decode(configData_, (address));
        // Set the flags for the PaymentOrders (this module uses 3 flags).
        bytes32 flags;
        flags |= bytes32(1 << FLAG_START);
        flags |= bytes32(1 << FLAG_CLIFF);
        flags |= bytes32(1 << FLAG_END);

        __ERC20PaymentClientBase_v2_init(flags);

        contributionToken = IERC20(address(fundingPotToken));
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
    function getRoundAccessCriteria(uint64 roundId_, uint8 id_)
        external
        view
        returns (
            bool isRoundOpen_,
            address nftContract_,
            bytes32 merkleRoot_,
            address[] memory allowedAddresses_
        )
    {
        Round storage round = rounds[roundId_];
        AccessCriteria storage accessCriteria = round.accessCriterias[id_];

        if (accessCriteria.accessCriteriaType == AccessCriteriaType.OPEN) {
            return (
                true,
                accessCriteria.nftContract,
                accessCriteria.merkleRoot,
                accessCriteria.allowedAddresses
            );
        } else {
            return (
                false,
                accessCriteria.nftContract,
                accessCriteria.merkleRoot,
                accessCriteria.allowedAddresses
            );
        }
    }

    /// @inheritdoc ILM_PC_FundingPot_v1
    function getRoundAccessCriteriaPrivileges(uint64 roundId_, uint8 accessId_)
        external
        view
        returns (
            bool isRoundOpen_,
            uint personalCap_,
            bool overrideContributionSpan_,
            uint start_,
            uint cliff_,
            uint end_
        )
    {
        Round storage round = rounds[roundId_];
        AccessCriteria storage accessCriteria = round.accessCriterias[accessId_];

        if (accessCriteria.accessCriteriaType == AccessCriteriaType.OPEN) {
            return (true, 0, false, 0, 0, 0);
        }

        // Store the privileges in a local variable to reduce stack usage.
        AccessCriteriaPrivileges storage privs =
            accessCriteriaPrivileges[roundId_][accessId_];

        return (
            false,
            privs.personalCap,
            privs.overrideContributionSpan,
            privs.start,
            privs.cliff,
            privs.end
        );
    }

    /// @inheritdoc ILM_PC_FundingPot_v1
    function getRoundCount() external view returns (uint64) {
        return roundCount;
    }

    /// @inheritdoc ILM_PC_FundingPot_v1
    function isRoundClosed(uint64 roundId_) external view returns (bool) {
        return roundClosed[roundId_];
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
        AccessCriteria memory accessCriteria_
    ) external onlyModuleRole(FUNDING_POT_ADMIN_ROLE) {
        Round storage round = rounds[roundId_];

        _validateEditRoundParameters(round);

        if (
            (
                accessCriteria_.accessCriteriaType == AccessCriteriaType.NFT
                    && accessCriteria_.nftContract == address(0)
            )
                || (
                    accessCriteria_.accessCriteriaType == AccessCriteriaType.MERKLE
                        && accessCriteria_.merkleRoot == bytes32("")
                )
                || (
                    accessCriteria_.accessCriteriaType == AccessCriteriaType.LIST
                        && accessCriteria_.allowedAddresses.length == 0
                )
        ) {
            revert Module__LM_PC_FundingPot__MissingRequiredAccessCriteriaData();
        }
        uint8 accessID = uint8(accessCriteria_.accessCriteriaType);
        round.accessCriterias[accessID] = accessCriteria_;

        emit AccessCriteriaSet(roundId_, accessID, accessCriteria_);
    }

    /// @inheritdoc ILM_PC_FundingPot_v1
    function editAccessCriteriaForRound(
        uint64 roundId_,
        uint8 accessCriteriaId_,
        AccessCriteria memory accessCriteria_
    ) external onlyModuleRole(FUNDING_POT_ADMIN_ROLE) {
        Round storage round = rounds[roundId_];
        if (accessCriteriaId_ > 4) {
            revert Module__LM_PC_FundingPot__InvalidAccessCriteriaId();
        }

        _validateEditRoundParameters(round);

        round.accessCriterias[accessCriteriaId_] = accessCriteria_;

        emit AccessCriteriaEdited(roundId_, accessCriteriaId_, accessCriteria_);
    }

    /// @inheritdoc ILM_PC_FundingPot_v1
    function setAccessCriteriaPrivileges(
        uint64 roundId_,
        uint8 accessId_,
        uint personalCap_,
        uint capByNFT_,
        uint capByMerkle_,
        uint capByList_,
        bool overrideContributionSpan_,
        uint start_,
        uint cliff_,
        uint end_
    ) external onlyModuleRole(FUNDING_POT_ADMIN_ROLE) {
        Round storage round = rounds[roundId_];

        uint highestCap = 0;

        _validateEditRoundParameters(round);

        if (
            round.accessCriterias[accessId_].accessCriteriaType
                == AccessCriteriaType.OPEN
        ) {
            highestCap = personalCap_;
        }

        if (
            round.accessCriterias[accessId_].accessCriteriaType
                == AccessCriteriaType.NFT && capByNFT_ > 0
        ) {
            uint nftCap = personalCap_ + capByNFT_;
            if (nftCap > highestCap) {
                highestCap = nftCap;
            }
        }

        if (
            round.accessCriterias[accessId_].accessCriteriaType
                == AccessCriteriaType.MERKLE && capByMerkle_ > 0
        ) {
            uint merkleCap = personalCap_ + capByMerkle_;
            if (merkleCap > highestCap) {
                highestCap = merkleCap;
            }
        }

        if (
            round.accessCriterias[accessId_].accessCriteriaType
                == AccessCriteriaType.LIST && capByList_ > 0
        ) {
            uint listCap = personalCap_ + capByList_;
            if (listCap > highestCap) {
                highestCap = listCap;
            }
        }

        if (!_validTimes(start_, cliff_, end_)) {
            revert Module__LM_PC_FundingPot__InvalidTimes();
        }

        AccessCriteriaPrivileges storage accessCriteriaPrivileges =
            accessCriteriaPrivileges[roundId_][accessId_];

        accessCriteriaPrivileges.personalCap = personalCap_;
        accessCriteriaPrivileges.overrideContributionSpan =
            overrideContributionSpan_;
        accessCriteriaPrivileges.start = start_;
        accessCriteriaPrivileges.cliff = cliff_;
        accessCriteriaPrivileges.end = end_;

        emit AccessCriteriaPrivilegesSet(
            roundId_,
            accessId_,
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
        uint adjustedAmount = _validateRoundContribution(
            roundId_, accessCriteriaId_, merkleProof_, amount_, msg.sender
        );

        Round storage round = rounds[roundId_];

        //Record contribution
        userContributions[roundId_][msg.sender] += adjustedAmount;
        roundTotalContributions[roundId_] += adjustedAmount;

        IERC20(contributionToken).safeTransferFrom(
            msg.sender, address(this), adjustedAmount
        );

        emit ContributionMade(roundId_, msg.sender, adjustedAmount);

        // contribution triggers automatic closure
        if (!roundClosed[roundId_] && round.autoClosure) {
            bool readyToClose = _checkRoundClosureConditions(roundId_);
            if (readyToClose) {
                _closeRound(roundId_);
            } else {
                revert Module__LM_PC_FundingPot__ClosureConditionsNotMet();
            }
        }
    }

    /// @inheritdoc ILM_PC_FundingPot_v1
    function closeRound(uint64 roundId_) external {
        Round storage round = rounds[roundId_];

        // Validate round exists
        if (round.roundEnd == 0 && round.roundCap == 0) {
            revert Module__LM_PC_FundingPot__RoundNotCreated();
        }

        // Check if round is already closed
        if (roundClosed[roundId_]) {
            revert Module__LM_PC_FundingPot__RoundHasEnded();
        }

        bool readyToClose = _checkRoundClosureConditions(roundId_);
        if (readyToClose) {
            _closeRound(roundId_);
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
        // start_ + cliff_ should be less or equal to end_
        // this already implies that start_ is not greater than end_
        return start_ + cliff_ <= end_;
    }

    /// @notice Validates the round existence and access criteria
    /// @param roundId_ ID of the round to validate
    /// @param accessCriteriaId_ ID of the access criteria to check
    /// @param merkleProof_ Merkle proof for validation if needed
    /// @param amount_ The amount sent by the user
    /// @param user_ The address of the user
    /// @return adjustedAmount The potentially adjusted contribution amount based on personal and round caps
    function _validateRoundContribution(
        uint64 roundId_,
        uint8 accessCriteriaId_,
        bytes32[] calldata merkleProof_,
        uint amount_,
        address user_
    ) internal view returns (uint adjustedAmount) {
        Round storage round = rounds[roundId_];
        uint currentTime = block.timestamp;
        uint adjustedAmount = amount_;

        if (amount_ == 0) {
            revert Module__LM_PC_FundingPot__InvalidDepositAmount();
        }
        // Validate round exists.
        if (round.roundEnd == 0 && round.roundCap == 0) {
            revert Module__LM_PC_FundingPot__RoundNotCreated();
        }

        // Validate contribution timing
        if (currentTime < round.roundStart) {
            revert Module__LM_PC_FundingPot__RoundHasNotStarted();
        }

        _validateAccessCriteria(
            roundId_, accessCriteriaId_, merkleProof_, user_
        );

        AccessCriteriaPrivileges storage privileges =
            accessCriteriaPrivileges[roundId_][accessCriteriaId_];

        bool canOverrideContributionSpan = privileges.overrideContributionSpan;

        // Allow contributions after the round end if the user can override the contribution span
        if (
            round.roundEnd > 0 && currentTime > round.roundEnd
                && !canOverrideContributionSpan
        ) {
            revert Module__LM_PC_FundingPot__RoundHasEnded();
        }

        adjustedAmount = _validateAndAdjustCaps(
            roundId_, amount_, accessCriteriaId_, canOverrideContributionSpan
        );

        return adjustedAmount;
    }

    /// @notice Validates cap constraints and adjusts amount if needed
    /// @param roundId_ ID of the round
    /// @param amount_ Requested contribution amount
    /// @param canOverrideContributionSpan_ Whether the user can override cap constraints
    /// @return adjustedAmount The potentially adjusted contribution amount
    function _validateAndAdjustCaps(
        uint64 roundId_,
        uint amount_,
        uint8 accessId_,
        bool canOverrideContributionSpan_
    ) internal view returns (uint adjustedAmount) {
        adjustedAmount = amount_;

        Round storage round = rounds[roundId_];

        if (!canOverrideContributionSpan_ && round.roundCap > 0) {
            uint totalRoundContribution = _getTotalRoundContribution(roundId_);
            uint effectiveRoundCap = round.roundCap;

            // If global accumulative caps are enabled,
            // adjust the round cap to acommodate unused capacity from previous rounds
            if (round.globalAccumulativeCaps) {
                uint unusedCapacityFromPrevious = 0;
                for (uint64 i = 1; i < roundId_; ++i) {
                    Round storage prevRound = rounds[i];
                    if (!prevRound.globalAccumulativeCaps) continue;

                    uint prevRoundTotal = _getTotalRoundContribution(i);
                    if (prevRoundTotal < prevRound.roundCap) {
                        unusedCapacityFromPrevious +=
                            (prevRound.roundCap - prevRoundTotal);
                    }
                }
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
            _getUserContributionToRound(roundId_, msg.sender);
        uint userPersonalCap =
            _getUserPersonalCapForRound(roundId_, accessId_, msg.sender);

        if (userPreviousContribution + adjustedAmount > userPersonalCap) {
            if (userPreviousContribution < userPersonalCap) {
                adjustedAmount = userPersonalCap - userPreviousContribution;
            } else {
                revert Module__LM_PC_FundingPot__PersonalCapReached();
            }
        }

        return adjustedAmount;
    }

    /// @notice Validates access criteria for a specific round and access type
    /// @dev    Checks if a user meets the access requirements based on the round's access criteria
    /// @param  roundId_ The ID of the round being validated
    /// @param  accessCriteriaId_ The ID of the specific access criteria
    /// @param  merkleProof_ Merkle proof for Merkle tree-based access (optional)
    function _validateAccessCriteria(
        uint64 roundId_,
        uint8 accessCriteriaId_,
        bytes32[] calldata merkleProof_,
        address user_
    ) internal view {
        Round storage round = rounds[roundId_];
        AccessCriteria storage accessCriteria =
            round.accessCriterias[accessCriteriaId_];

        if (accessCriteriaId_ > 4) {
            revert Module__LM_PC_FundingPot__InvalidAccessCriteriaId();
        }

        bool accessGranted = false;
        if (accessCriteria.accessCriteriaType == AccessCriteriaType.NFT) {
            accessGranted =
                _checkNftOwnership(accessCriteria.nftContract, user_);
        } else if (
            accessCriteria.accessCriteriaType == AccessCriteriaType.MERKLE
        ) {
            accessGranted = _validateMerkleProof(
                accessCriteria.merkleRoot, merkleProof_, user_, roundId_
            );
        } else if (accessCriteria.accessCriteriaType == AccessCriteriaType.LIST)
        {
            accessGranted =
                _checkAllowedAddressList(accessCriteria.allowedAddresses, user_);
        }
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
        return roundTotalContributions[roundId_];
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
        return userContributions[roundId_][user_];
    }

    /// @notice Calculates the personal contribution cap for a user in a specific round
    /// @dev    Determines the maximum amount a user can contribute based on global or round-specific rules
    /// @param  roundId_ The ID of the current round
    /// @param  user_ The address of the user
    /// @return The personal contribution cap for the user
    function _getUserPersonalCapForRound(
        uint64 roundId_,
        uint8 accessId_,
        address user_
    ) internal view returns (uint) {
        AccessCriteriaPrivileges storage privileges =
            accessCriteriaPrivileges[roundId_][accessId_];

        uint personalCap = privileges.personalCap;

        Round storage round = rounds[roundId_];
        if (round.globalAccumulativeCaps) {
            uint unusedCapacity =
                _getUserUnusedCapacityFromPreviousRounds(user_, roundId_);
            return personalCap + unusedCapacity;
        }
        return personalCap;
    }

    /// @notice Calculates unused contribution capacity from previous rounds
    /// @dev    Aggregates unused contribution caps from previous rounds with global accumulative caps
    /// @param  user_ The address of the user
    /// @param  currentRoundId_ The ID of the current round
    /// @return Total unused contribution capacity from previous rounds
    function _getUserUnusedCapacityFromPreviousRounds(
        address user_,
        uint64 currentRoundId_
    ) internal view returns (uint) {
        uint totalUnusedCapacity = 0;

        for (uint64 i = 1; i < currentRoundId_; ++i) {
            Round storage prevRound = rounds[i];
            if (!prevRound.globalAccumulativeCaps) continue;

            uint personalCap = 0;

            for (uint8 j = 0; j < 4; ++j) {
                AccessCriteria storage accessCriteria =
                    prevRound.accessCriterias[j];

                AccessCriteriaPrivileges storage privileges =
                    accessCriteriaPrivileges[i][j];

                // return only the highest personal cap from the selected access criteria
                if (privileges.personalCap > personalCap) {
                    personalCap = privileges.personalCap;
                }
            }

            uint userContribution = _getUserContributionToRound(i, user_);
            if (userContribution < personalCap) {
                totalUnusedCapacity += (personalCap - userContribution);
            }
        }
        return totalUnusedCapacity;
    }

    ///@notice Checks if a sender is in a list of allowed addresses
    /// @dev    Performs a linear search to validate address inclusion
    /// @param  allowedAddresses_ Array of addresses permitted to participate
    /// @param  sender_ Address to check for permission
    /// @return Boolean indicating whether the sender is in the allowed list
    function _checkAllowedAddressList(
        address[] memory allowedAddresses_,
        address sender_
    ) internal pure returns (bool) {
        uint lengthOfAddresses = allowedAddresses_.length;
        for (uint i = 0; i < lengthOfAddresses; ++i) {
            if (allowedAddresses_[i] == sender_) {
                return true;
            }
        }
        revert Module__LM_PC_FundingPot__AccessCriteriaListFailed();
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
                revert Module__LM_PC_FundingPot__AccessCriteriaNftFailed();
            }
            return true;
        } catch {
            revert Module__LM_PC_FundingPot__AccessCriteriaNftFailed();
        }
    }

    /// @notice Verifies a Merkle proof for access control
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
            revert Module__LM_PC_FundingPot__AccessCriteriaMerkleFailed();
        }

        return true;
    }

    /// @notice Handles round closure logic
    /// @dev    Updates round status and executes hook if needed
    /// @param  roundId_ The ID of the round to close
    function _closeRound(uint64 roundId_) internal {
        Round storage round = rounds[roundId_];

        // Mark round as closed
        roundClosed[roundId_] = true;

        // Execute hook if configured
        if (round.hookContract != address(0) && round.hookFunction.length > 0) {
            (bool success,) = round.hookContract.call(round.hookFunction);
            if (!success) {
                revert Module__LM_PC_FundingPot__HookExecutionFailed();
            }
        }

        // Emit event for round closure
        emit RoundClosed(
            roundId_, block.timestamp, roundTotalContributions[roundId_]
        );
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
        uint totalContribution = roundTotalContributions[roundId_];
        bool capReached =
            round.roundCap > 0 && totalContribution == round.roundCap;
        bool timeEnded = round.roundEnd > 0 && block.timestamp >= round.roundEnd;
        return capReached || timeEnded;
    }
}
