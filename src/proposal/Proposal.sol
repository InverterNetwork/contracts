// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Dependencies
import {Initializable} from "@oz-up/proxy/utils/Initializable.sol";
import {PausableUpgradeable} from "@oz-up/security/PausableUpgradeable.sol";

// Internal Dependencies
import {Types} from "src/common/Types.sol";
import {ModuleManager} from "src/proposal/base/ModuleManager.sol";

// Internal Interfaces
import {IProposal} from "src/interfaces/IProposal.sol";
import {IPaymentProcessor} from "src/interfaces/IPaymentProcessor.sol";
import {IAuthorizer} from "src/interfaces/IAuthorizer.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

contract Proposal is IProposal, ModuleManager, PausableUpgradeable {
    //--------------------------------------------------------------------------
    // Modifiers

    /// @notice Modifier to guarantee function is only callable by authorized
    ///         address.
    modifier onlyAuthorized() {
        if (!authorizer.isAuthorized(msg.sender)) {
            revert Proposal__CallerNotAuthorized();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Storage

    /// @dev The proposal's id.
    uint private _proposalId;

    /// @dev The list of funders.
    address[] private _funders;

    /// @inheritdoc IProposal
    IAuthorizer public override (IProposal) authorizer;

    /// @inheritdoc IProposal
    IPaymentProcessor public override (IProposal) paymentProcessor;

    IERC20 public paymentToken;

    //--------------------------------------------------------------------------
    // Initializer

    // @todo mp: Check that `_disableInitializers()` is used correctly.
    //           Makes testing setup harder too.
    //constructor() {
    //    _disableInitializers();
    //}

    function init(
        uint proposalId,
        address[] calldata funders,
        address[] calldata modules,
        IAuthorizer authorizer_,
        IPaymentProcessor paymentProcessor_,
        IERC20 paymentToken_
    ) external initializer {
        _proposalId = proposalId;
        _funders = funders;

        __Pausable_init();
        __ModuleManager_init(modules);

        // Ensure that authorizer_ is an enabled module.
        if (!isEnabledModule(address(authorizer_))) {
            revert Proposal__InvalidAuthorizer();
        }
        authorizer = authorizer_;

        // Ensure that paymentProcessor_ is an enabled module.
        if (!isEnabledModule(address(paymentProcessor_))) {
            revert Proposal__InvalidPaymentProcessor();
        }
        paymentProcessor = paymentProcessor_;

        if (address(paymentToken_) == address(0)) {
            revert Proposal__InvalidPaymentToken();
        }
        paymentToken = paymentToken_;
    }

    //--------------------------------------------------------------------------
    // Public Functions

    /// @inheritdoc IProposal
    function executeTx(address target, bytes memory data)
        external
        onlyAuthorized
        returns (bytes memory)
    {
        bool ok;
        bytes memory returnData;
        (ok, returnData) = target.call(data);

        if (ok) {
            return returnData;
        } else {
            revert Proposal__ExecuteTxFailed();
        }
    }

    /// @inheritdoc IProposal
    function version() external pure returns (string memory) {
        return "1";
    }
}
