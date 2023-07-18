// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

// External Dependencies
import {OwnableUpgradeable} from "@oz-up/access/OwnableUpgradeable.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Internal Dependencies
import {ModuleManager} from "src/proposal/base/ModuleManager.sol";

// Internal Interfaces
import {
    IProposal,
    IFundingManager,
    IPaymentProcessor,
    IAuthorizer
} from "src/proposal/IProposal.sol";

/**
 * @title Proposal
 *
 * @dev A new funding primitive to enable multiple actors within a decentralized
 *      network to collaborate on proposals.
 *
 *      A proposal is composed of a [funding mechanism](./base/FundingVault) *      and a set of [modules](./base/ModuleManager).
 *
 *      The token being accepted for funding is non-changeable and set during
 *      initialization. Authorization is performed via calling a non-changeable
 *      {IAuthorizer} instance. Payments, initiated by modules, are processed
 *      via a non-changeable {IPaymentProcessor} instance.
 *
 *      Each proposal has a unique id set during initialization.
 *
 * @author Inverter Network
 */
contract Proposal is IProposal, OwnableUpgradeable, ModuleManager {
    //--------------------------------------------------------------------------
    // Modifiers

    /// @notice Modifier to guarantee function is only callable by authorized
    ///         address.
    modifier onlyAuthorized() {
        if (!authorizer.isAuthorized(_msgSender())) {
            revert Proposal__CallerNotAuthorized();
        }
        _;
    }

    // Once we merge the RoleAuthoirzer We can completely remove Ownable
    // as import and rely on IAuthorizer to validate owners.

    /// @notice Modifier to guarantee function is only callable by authorized
    ///         address or manager.
    modifier onlyAuthorizedOrManager() {
        if (!authorizer.isAuthorized(_msgSender()) && _msgSender() != manager())
        {
            revert Proposal__CallerNotAuthorized();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Storage

    IERC20 private _token;

    /// @inheritdoc IProposal
    uint public override(IProposal) proposalId;

    /// @inheritdoc IProposal
    IFundingManager public override(IProposal) fundingManager;

    /// @inheritdoc IProposal
    IAuthorizer public override(IProposal) authorizer;

    /// @inheritdoc IProposal
    IPaymentProcessor public override(IProposal) paymentProcessor;

    //--------------------------------------------------------------------------
    // Initializer

    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc IProposal
    function init(
        uint proposalId_,
        address owner_,
        IERC20 token_,
        address[] calldata modules,
        IFundingManager fundingManager_,
        IAuthorizer authorizer_,
        IPaymentProcessor paymentProcessor_
    ) external override(IProposal) initializer {
        // Initialize upstream contracts.
        __Ownable_init();
        __ModuleManager_init(modules);

        // Set storage variables.
        proposalId = proposalId_;

        _token = token_;

        fundingManager = fundingManager_;
        authorizer = authorizer_;
        paymentProcessor = paymentProcessor_;

        // Transfer ownerhsip of proposal to owner argument.
        _transferOwnership(owner_);

        // Add necessary modules.
        // Note to not use the public addModule function as the factory
        // is (most probably) not authorized.
        __ModuleManager_addModule(address(fundingManager_));
        __ModuleManager_addModule(address(authorizer_));
        __ModuleManager_addModule(address(paymentProcessor_));
    }

    //--------------------------------------------------------------------------
    // Upstream Function Implementations

    /// @dev Only addresses authorized via the {IAuthorizer} instance can manage
    ///      modules.
    function __ModuleManager_isAuthorized(address who)
        internal
        view
        override(ModuleManager)
        returns (bool)
    {
        return authorizer.isAuthorized(who);
    }

    //--------------------------------------------------------------------------
    // onlyAuthorized Functions

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

    //--------------------------------------------------------------------------
    // View Functions

    /// @inheritdoc IProposal
    function token() public view override(IProposal) returns (IERC20) {
        return _token;
    }

    /// @inheritdoc IProposal
    function version() external pure returns (string memory) {
        return "1";
    }

    function owner()
        public
        view
        override(OwnableUpgradeable, IProposal)
        returns (address)
    {
        return super.owner();
    }

    function manager() public view returns (address) {
        return owner();
    }
}
