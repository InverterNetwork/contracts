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

    /// @notice Stores the access criteria ID for each round.
    mapping(uint64 => uint8) private roundIdtoAccessId;
    /// @notice Stores all access criteria privilages by their unique ID.
    mapping(
        uint64 roundId => mapping(uint8 accessId => AccessCriteriaPrivilages)
    ) private accessCriteriaPrivilages;

    /// @notice Maps round IDs to user addresses to contribution amounts
    mapping(uint64 => mapping(address => uint)) private userContributions;

    /// @notice Maps round IDs to total contributions
    mapping(uint64 => uint) private roundTotalContributions;

    /// @notice The next available round ID.
    uint64 private nextRoundId;

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

        isOpen = (accessCriteria.accessCriteriaType == AccessCriteriaType.OPEN);
        return (
            isOpen,
            accessCriteria.nftContract,
            accessCriteria.merkleRoot,
            accessCriteria.allowedAddresses
        );
    }

    /// @inheritdoc ILM_PC_FundingPot_v1
    function getRoundAccessCriteriaPrivilages(uint64 roundId_, uint8 accessId_)
        external
        view
        returns (
            bool isRoundOpen_,
            uint personalCap_,
            bool overrideCap_,
            uint start_,
            uint cliff_,
            uint end_
        )
    {
        Round storage round = rounds[roundId_];
        AccessCriteria storage accessCriteria = round.accessCriterias[accessId_];

        if (accessCriteria.accessCriteriaId == AccessCriteriaId.OPEN) {
            return (true, 0, false, 0, 0, 0);
        }

        // Store the privileges in a local variable to reduce stack usage.
        AccessCriteriaPrivilages storage privs =
            accessCriteriaPrivilages[roundId_][accessId_];

        return (
            false,
            privs.personalCap,
            privs.overrideCap,
            privs.start,
            privs.cliff,
            privs.end
        );
    }

    /// @inheritdoc ILM_PC_FundingPot_v1
    function getRoundCount() external view returns (uint64) {
        return nextRoundId;
    }

    /// @inheritdoc ILM_PC_FundingPot_v1
    function getRoundAccessCriteriaCount(uint64 roundId_)
        public
        view
        returns (uint8 accessCriteriaCount_)
    {
        return roundIdtoAccessId[roundId_];
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
        nextRoundId++;

        uint64 roundId = nextRoundId;

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
        uint8 accessCriteriaId = roundIdtoAccessId[roundId_];
        round.accessCriterias[accessCriteriaId] = accessCriteria_;

        emit AccessCriteriaSet(roundId_, accessCriteriaId, accessCriteria_);

        roundIdtoAccessId[roundId_] += 1;
    }

    /// @inheritdoc ILM_PC_FundingPot_v1
    function editAccessCriteriaForRound(
        uint64 roundId_,
        uint8 accessCriteriaId_,
        AccessCriteria memory accessCriteria_
    ) external onlyModuleRole(FUNDING_POT_ADMIN_ROLE) {
        if (accessCriteriaId_ >= roundIdtoAccessId[roundId_]) {
            revert Module__LM_PC_FundingPot__InvalidAccessCriteriaId();
        }
        Round storage round = rounds[roundId_];

        _validateEditRoundParameters(round);

        round.accessCriterias[accessCriteriaId_] = accessCriteria_;

        emit AccessCriteriaEdited(roundId_, accessCriteriaId_, accessCriteria_);
    }

    /// @inheritdoc ILM_PC_FundingPot_v1
    function setAccessCriteriaPrivilages(
        uint64 roundId_,
        uint8 accessId_,
        uint personalCap_,
        bool overrideCap_,
        uint _start,
        uint _cliff,
        uint _end
    ) external onlyModuleRole(FUNDING_POT_ADMIN_ROLE) {
        Round storage round = rounds[roundId_];

        _validateEditRoundParameters(round);

        if (
            round.accessCriterias[accessId_].accessCriteriaId
                == AccessCriteriaId.OPEN
        ) {
            revert
                Module__LM_PC_FundingPot__CannotSetPrivilagesForOpenAccessCriteria();
        }
        if (!_validTimes(_start, _cliff, _end)) {
            revert Module__LM_PC_FundingPot__InvalidTimes();
        }

        AccessCriteriaPrivilages storage accessCriteriaPrivilages =
            accessCriteriaPrivilages[roundId_][accessId_];

        accessCriteriaPrivilages.personalCap = personalCap_;
        accessCriteriaPrivilages.overrideCap = overrideCap_;
        accessCriteriaPrivilages.start = _start;
        accessCriteriaPrivilages.cliff = _cliff;
        accessCriteriaPrivilages.end = _end;

        emit AccessCriteriaPrivilagesSet(
            roundId_,
            accessId_,
            personalCap_,
            overrideCap_,
            _start,
            _cliff,
            _end
        );
    }

    /// @inheritdoc ILM_PC_FundingPot_v1
    function contributeToRound(
        uint64 roundId_,
        uint amount_,
        uint8 accessId_,
        address contributionToken_,
        bytes32[] calldata merkleProof_
    ) external {
        // Validate input amount.
        if (amount_ == 0) {
            revert Module__LM_PC_FundingPot__InvalidDepositAmount();
        }

        Round storage round = rounds[roundId_];

        // Validate round exists.
        if (round.roundEnd == 0 && round.roundCap == 0) {
            revert Module__LM_PC_FundingPot__RoundNotCreated();
        }

        // Validate round timing.
        uint currentTime = block.timestamp;
        if (currentTime < round.roundStart) {
            revert Module__LM_PC_FundingPot__RoundHasNotStarted();
        }
        if (round.roundEnd > 0 && currentTime > round.roundEnd) {
            revert Module__LM_PC_FundingPot__RoundHasEnded();
        }

        // Validate access criteria.
        _validateAccessCriteria(roundId_, accessId_, merkleProof_);

        // Retrieve user's previous contribution and calculate the personal cap.
        uint userPreviousContribution =
            _getUserContribution(roundId_, msg.sender);
        uint userPersonalCap = _getUserPersonalCap(roundId_, msg.sender);

        // Revert contribution if it would exceed the personal cap.
        uint userRemainingCap = userPersonalCap - userPreviousContribution;
        if (amount_ > userRemainingCap) {
            revert Module__LM_PC_FundingPot__PersonalCapReached();
        }

        uint totalRoundContribution = _getTotalRoundContribution(roundId_);
        if (
            round.roundCap > 0
                && totalRoundContribution + amount_ >= round.roundCap
        ) {
            revert Module__LM_PC_FundingPot__RoundCapReached();
        }

        // Transfer funds.
        IERC20(contributionToken_).safeTransferFrom(
            msg.sender, address(this), amount_
        );

        // Record the contribution.
        _recordContribution(roundId_, msg.sender, amount_);
        emit ContributionMade(roundId_, msg.sender, amount_);
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
    /// @param  _start uint to validate.
    /// @param  _cliff uint to validate.
    /// @param  _end uint to validate.
    /// @return True if uint is valid.
    function _validTimes(uint _start, uint _cliff, uint _end)
        internal
        pure
        returns (bool)
    {
        // _start + _cliff should be less or equal to _end
        // this already implies that _start is not greater than _end
        return _start + _cliff <= _end;
    }

    /// @notice Validates access criteria for a specific round and access type
    /// @dev    Checks if a user meets the access requirements based on the round's access criteria
    /// @param  roundId_ The ID of the round being validated
    /// @param  accessId_ The ID of the specific access criteria
    /// @param  merkleProof_ Merkle proof for Merkle tree-based access (optional)
    function _validateAccessCriteria(
        uint64 roundId_,
        uint8 accessId_,
        bytes32[] calldata merkleProof_
    ) internal view {
        Round storage round = rounds[roundId_];
        AccessCriteria storage accessCriteria = round.accessCriterias[accessId_];

        if (accessCriteria.accessCriteriaId == AccessCriteriaId.OPEN) {
            return;
        }

        bool accessGranted = false;
        if (accessCriteria.accessCriteriaId == AccessCriteriaId.NFT) {
            accessGranted =
                _checkNftOwnership(accessCriteria.nftContract, msg.sender);
        } else if (accessCriteria.accessCriteriaId == AccessCriteriaId.MERKLE) {
            accessGranted = _validateMerkleProof(
                accessCriteria.merkleRoot, msg.sender, merkleProof_
            );
        } else if (accessCriteria.accessCriteriaId == AccessCriteriaId.LIST) {
            accessGranted = _checkAllowedAddressList(
                accessCriteria.allowedAddresses, msg.sender
            );
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
    function _getUserContribution(uint64 roundId_, address user_)
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
    function _getUserPersonalCap(uint64 roundId_, address user_)
        internal
        view
        returns (uint)
    {
        uint basePersonalCap = 500;
        Round storage round = rounds[roundId_];

        if (round.globalAccumulativeCaps) {
            uint unusedCapacity =
                _getUnusedCapacityFromPreviousRounds(user_, roundId_);
            return basePersonalCap + unusedCapacity;
        }
        return basePersonalCap;
    }

    /// @notice Calculates unused contribution capacity from previous rounds
    /// @dev    Aggregates unused contribution caps from previous rounds with global accumulative caps
    /// @param  user_ The address of the user
    /// @param  currentRoundId_ The ID of the current round
    /// @return Total unused contribution capacity from previous rounds
    function _getUnusedCapacityFromPreviousRounds(
        address user_,
        uint64 currentRoundId_
    ) internal view returns (uint) {
        uint totalUnusedCapacity = 0;
        for (uint64 i = 1; i < currentRoundId_; i++) {
            Round storage prevRound = rounds[i];
            if (!prevRound.globalAccumulativeCaps) {
                continue;
            }
            uint personalCap = 1000 ether;
            uint userContribution = _getUserContribution(i, user_);
            if (userContribution < personalCap) {
                totalUnusedCapacity += (personalCap - userContribution);
            }
        }
        return totalUnusedCapacity;
    }

    /// @notice Records a contribution for a user in a specific round
    /// @dev    Updates the user's contribution and the total round contribution
    /// @param  roundId_ The ID of the round
    /// @param  user_ The address of the user making the contribution
    /// @param  amount_ The amount of the contribution
    function _recordContribution(uint64 roundId_, address user_, uint amount_)
        internal
    {
        userContributions[roundId_][user_] += amount_;
        roundTotalContributions[roundId_] += amount_;
    }

    ///@notice Checks if a sender is in a list of allowed addresses
    /// @dev    Performs a linear search to validate address inclusion
    /// @param  allowedAddresses Array of addresses permitted to participate
    /// @param  sender Address to check for permission
    /// @return Boolean indicating whether the sender is in the allowed list
    function _checkAllowedAddressList(
        address[] memory allowedAddresses,
        address sender
    ) internal pure returns (bool) {
        for (uint i = 0; i < allowedAddresses.length; i++) {
            if (allowedAddresses[i] == sender) {
                return true;
            }
        }
        revert Module__LM_PC_FundingPot__AccessCriteriaListFailed();
        return false;
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

    function _validateMerkleProof(
        bytes32 root_,
        address user_,
        bytes32[] calldata merkleProof_
    ) internal pure returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(user_));

        if (!MerkleProof.verify(merkleProof_, root_, leaf)) {
            revert Module__LM_PC_FundingPot__AccessCriteriaMerkleFailed();
        }
    }
}
