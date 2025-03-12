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

    /// @notice Payment token.
    IERC20 internal _paymentToken;

    /// @notice Stores all funding rounds by their unique ID.
    mapping(uint64 => Round) public rounds;

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
    ) external returns (uint64) {
        if (_roundStart <= block.timestamp) {
            revert Module__LM_PC_FundingPot__RoundStartMustBeInFuture();
        }

        if (_roundEnd <= _roundStart && _roundCap == 0) {
            revert Module__LM_PC_FundingPot__RoundMustHaveEndTimeOrCap();
        }

        if (_roundEnd > 0 && _roundEnd <= _roundStart) {
            revert Module__LM_PC_FundingPot__RoundEndMustBeAfterStart();
        }

        uint64 roundId = nextRoundId;
        rounds[roundId] = Round({
            roundStart: _roundStart,
            roundEnd: _roundEnd,
            roundCap: _roundCap,
            hookContract: _hookContract,
            hookFunction: _hookFunction,
            closureMechanism: _closureMechanism,
            globalAccumulativeCaps: _globalAccumulativeCaps,
            isActive: true
        });

        nextRoundId++;

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
    ) external returns (bool) {
        Round storage round = rounds[_roundId];

        if (round.roundStart == 0) {
            revert Module__LM_PC_FundingPot__RoundDoesNotExist();
        }

        if (block.timestamp >= round.roundStart) {
            revert Module__LM_PC_FundingPot__RoundAlreadyStarted();
        }

        if (_roundStart <= block.timestamp) {
            revert Module__LM_PC_FundingPot__RoundStartMustBeInFuture();
        }

        if (_roundEnd <= _roundStart && _roundCap == 0) {
            revert Module__LM_PC_FundingPot__RoundMustHaveEndTimeOrCap();
        }

        if (_roundEnd > 0 && _roundEnd <= _roundStart) {
            revert Module__LM_PC_FundingPot__RoundEndMustBeAfterStart();
        }

        round.roundStart = _roundStart;
        round.roundEnd = _roundEnd;
        round.roundCap = _roundCap;
        round.hookContract = _hookContract;
        round.hookFunction = _hookFunction;
        round.closureMechanism = _closureMechanism;
        round.globalAccumulativeCaps = _globalAccumulativeCaps;

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
    // -------------------------------------------------------------------------
    // Internal
}
