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
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

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
    function getRoundGenericParameters(uint64 _roundId)
        external
        view
        returns (
            uint roundStart,
            uint roundEnd,
            uint roundCap,
            address hookContract,
            bytes memory hookFunction,
            bool closureMechanism,
            bool globalAccumulativeCaps
        )
    {
        Round storage round = rounds[_roundId];
        return (
            round.roundStart,
            round.roundEnd,
            round.roundCap,
            round.hookContract,
            round.hookFunction,
            round.closureMechanism,
            round.globalAccumulativeCaps
        );
    }

    function getRoundAccessCriteria(uint64 _roundId, uint64 _id)
        external
        view
        returns (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        )
    {
        Round storage round = rounds[_roundId];
        AccessCriteria storage accessCriteria = round.accessCriterias[_id];
        return (
            accessCriteria.nftContract,
            accessCriteria.merkleRoot,
            accessCriteria.allowedAddresses
        );
    }

    /// @inheritdoc ILM_PC_FundingPot_v1
    function getRoundCount() external view returns (uint64) {
        return nextRoundId;
    }

    // -------------------------------------------------------------------------
    // Public - Mutating

    /// @inheritdoc ILM_PC_FundingPot_v1
    function createRound(
        uint _roundStart,
        uint _roundEnd,
        uint _roundCap,
        address _hookContract,
        bytes memory _hookFunction,
        bool _closureMechanism,
        bool _globalAccumulativeCaps
    ) external onlyModuleRole(FUNDING_POT_ADMIN_ROLE) returns (uint64) {
        nextRoundId++;

        uint64 roundId = nextRoundId;

        Round storage round = rounds[roundId];
        round.roundStart = _roundStart;
        round.roundEnd = _roundEnd;
        round.roundCap = _roundCap;
        round.hookContract = _hookContract;
        round.hookFunction = _hookFunction;
        round.closureMechanism = _closureMechanism;
        round.globalAccumulativeCaps = _globalAccumulativeCaps;

        _validateRoundParameters(round);

        emit RoundCreated(
            roundId,
            _roundStart,
            _roundEnd,
            _roundCap,
            _hookContract,
            _closureMechanism,
            _globalAccumulativeCaps
        );

        return roundId;
    }

    /// @inheritdoc ILM_PC_FundingPot_v1
    function editRound(
        uint64 _roundId,
        uint _roundStart,
        uint _roundEnd,
        uint _roundCap,
        address _hookContract,
        bytes memory _hookFunction,
        bool _closureMechanism,
        bool _globalAccumulativeCaps
    ) external onlyModuleRole(FUNDING_POT_ADMIN_ROLE) returns (bool) {
        Round storage round = rounds[_roundId];

        if (round.roundEnd == 0 && round.roundCap == 0) {
            revert Module__LM_PC_FundingPot__RoundNotCreated();
        }

        if (block.timestamp > round.roundStart) {
            revert Module__LM_PC_FundingPot__RoundAlreadyStarted();
        }

        round.roundStart = _roundStart;
        round.roundEnd = _roundEnd;
        round.roundCap = _roundCap;
        round.hookContract = _hookContract;
        round.hookFunction = _hookFunction;
        round.closureMechanism = _closureMechanism;
        round.globalAccumulativeCaps = _globalAccumulativeCaps;

        _validateRoundParameters(round);

        emit RoundEdited(
            _roundId,
            _roundStart,
            _roundEnd,
            _roundCap,
            _hookContract,
            _closureMechanism,
            _globalAccumulativeCaps
        );

        return true;
    }

    function setAccessCriteriaForRound(
        uint64 _roundId,
        uint8 _accessId,
        AccessCriteria memory _accessCriteria
    ) external onlyModuleRole(FUNDING_POT_ADMIN_ROLE) {
        Round storage round = rounds[_roundId];

        if (round.roundEnd == 0 && round.roundCap == 0) {
            revert Module__LM_PC_FundingPot__RoundNotCreated();
        }

        if (block.timestamp > round.roundStart) {
            revert Module__LM_PC_FundingPot__RoundAlreadyStarted();
        }

        if (
            (
                _accessCriteria.accessCriteriaId == AccessCriteriaId.NFT
                    && _accessCriteria.nftContract == address(0)
            )
                || (
                    _accessCriteria.accessCriteriaId == AccessCriteriaId.MERKLE
                        && _accessCriteria.merkleRoot == bytes32("")
                )
                || (
                    _accessCriteria.accessCriteriaId == AccessCriteriaId.LIST
                        && _accessCriteria.allowedAddresses.length == 0
                )
        ) {
            revert Module__LM_PC_FundingPot__IncorrectAccessCriteria();
        }

        round.accessCriterias[_accessId] = _accessCriteria;
        emit AccessCriteriaSet(_roundId, _accessId, _accessCriteria);
    }
    // -------------------------------------------------------------------------
    // Internal

    /// @notice Validates the round parameters.
    /// @param  round The round to validate.
    /// @dev    Reverts if the round parameters are invalid.
    function _validateRoundParameters(Round storage round) internal view {
        // Validate round start time is in the future
        // @note: The below condition wont allow _roundStart == block.timestamp
        if (round.roundStart <= block.timestamp) {
            revert Module__LM_PC_FundingPot__RoundStartMustBeInFuture();
        }

        // Validate that either end time or cap is set
        if (round.roundEnd == 0 && round.roundCap == 0) {
            revert Module__LM_PC_FundingPot__RoundMustHaveEndTimeOrCap();
        }

        // If end time is set, validate it's after start time
        if (round.roundEnd > 0 && round.roundEnd <= round.roundStart) {
            revert Module__LM_PC_FundingPot__RoundEndMustBeAfterStart();
        }

        // Validate hook contract and function consistency
        if (round.hookContract != address(0) && round.hookFunction.length == 0)
        {
            revert
                Module__LM_PC_FundingPot__HookFunctionRequiredWithHookContract();
        }

        if (round.hookContract == address(0) && round.hookFunction.length > 0) {
            revert
                Module__LM_PC_FundingPot__HookContractRequiredWithHookFunction();
        }
    }
}
