// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Dependencies
// @todo mp: Would like to have 2 step owner.
import {OwnableUpgradeable} from "@oz-up/access/OwnableUpgradeable.sol";
import {Initializable} from "@oz-up/proxy/utils/Initializable.sol";
import {PausableUpgradeable} from "@oz-up/security/PausableUpgradeable.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Internal Dependencies
import {Types} from "src/common/Types.sol";
import {ModuleManager} from "src/proposal/base/ModuleManager.sol";
import {ContributorManager} from "src/proposal/base/ContributorManager.sol";

// Internal Interfaces
import {
    IProposal,
    IPaymentProcessor,
    IAuthorizer
} from "src/proposal/IProposal.sol";

contract Proposal is
    IProposal,
    ModuleManager,
    ContributorManager,
    OwnableUpgradeable,
    PausableUpgradeable
{
    //--------------------------------------------------------------------------
    // Modifiers

    /// @notice Modifier to guarantee function is only callable by authorized
    ///         address.
    modifier onlyOwnerOrAuthorized() {
        if (!_isOwnerOrAuthorized(msg.sender)) {
            revert Proposal__CallerNotAuthorized();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Storage

    /// @dev The list of funders.
    address[] private _funders;

    /// @inheritdoc IProposal
    uint public override (IProposal) proposalId;

    /// @inheritdoc IProposal
    IERC20 public override (IProposal) token;

    /// @inheritdoc IProposal
    IAuthorizer public override (IProposal) authorizer;

    /// @inheritdoc IProposal
    IPaymentProcessor public override (IProposal) paymentProcessor;

    //--------------------------------------------------------------------------
    // Initializer

    // @todo mp: Check that `_disableInitializers()` is used correctly.
    //           Makes testing setup harder too.
    //constructor() {
    //    _disableInitializers();
    //}

    /// @inheritdoc IProposal
    function init(
        uint proposalId_,
        IERC20 token_,
        address[] calldata funders,
        address[] calldata modules,
        IAuthorizer authorizer_,
        IPaymentProcessor paymentProcessor_
    ) external override (IProposal) initializer {
        // Set storage variables.
        _funders = funders;
        proposalId = proposalId_;
        token = token_;
        authorizer = authorizer_;
        paymentProcessor = paymentProcessor_;

        // Initialize upstream contracts.
        __Pausable_init();
        __Ownable_init();
        __ModuleManager_init(modules);
        __ContributorManager_init();

        // Add necessary modules.
        addModule(address(authorizer_));
        addModule(address(paymentProcessor_));
    }

    //--------------------------------------------------------------------------
    // Upstream Function Implementations

    function __ModuleManager_isAuthorized(address who)
        internal
        view
        override (ModuleManager)
        returns (bool)
    {
        return _isOwnerOrAuthorized(who);
    }

    function __ContributorManager_isAuthorized(address who)
        internal
        view
        override (ContributorManager)
        returns (bool)
    {
        return _isOwnerOrAuthorized(who);
    }

    //--------------------------------------------------------------------------
    // Public Functions

    /// @inheritdoc IProposal
    function executeTx(address target, bytes memory data)
        external
        onlyOwnerOrAuthorized
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

    //--------------------------------------------------------------------------
    // Internal Functions

    function _isOwnerOrAuthorized(address who) private view returns (bool) {
        return authorizer.isAuthorized(who) || owner() == who;
    }
}
