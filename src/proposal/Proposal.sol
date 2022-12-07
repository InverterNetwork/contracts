// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

// External Dependencies
import {OwnableUpgradeable} from "@oz-up/access/OwnableUpgradeable.sol";
import {Initializable} from "@oz-up/proxy/utils/Initializable.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IERC20MetadataUpgradeable} from
    "@oz-up/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

// Internal Dependencies
import {Types} from "src/common/Types.sol";
import {ModuleManager} from "src/proposal/base/ModuleManager.sol";
import {ContributorManager} from "src/proposal/base/ContributorManager.sol";
import {FundingManager} from "src/proposal/base/FundingManager.sol";

// Internal Interfaces
import {
    IProposal,
    IPaymentProcessor,
    IAuthorizer
} from "src/proposal/IProposal.sol";

/**
 * @title Proposal
 *
 * @dev A new funding primitive to enable multiple actors within a decentralized
 *      network to collaborate on proposals.
 *
 *      A proposal is composed of a [funding mechanism](./base/FundingVault),
 *      a set of [contributors](./base/ContributorManager), and a set of
 *      [modules](./base/ModuleManager).
 *
 *      The token being accepted for funding is non-changeable and set during
 *      initialization. Authorization is performed via calling a non-changeable
 *      {IAuthorizer} instance. Payments, initiated by modules, are processed
 *      via a non-changeable {IPaymentProcessor} instance.
 *
 *      Each proposal has a unique id set during initialization.
 *
 * @author byterocket
 */
contract Proposal is
    IProposal,
    OwnableUpgradeable,
    ModuleManager,
    ContributorManager,
    FundingManager
{
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

    /// @notice Modifier to guarantee function is only callable by authorized
    ///         address or owner.
    modifier onlyAuthorizedOrOwner() {
        if (!authorizer.isAuthorized(_msgSender()) && _msgSender() != owner()) {
            revert Proposal__CallerNotAuthorized();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Storage

    IERC20 private _token;

    /// @inheritdoc IProposal
    uint public override (IProposal) proposalId;

    /// @inheritdoc IProposal
    IAuthorizer public override (IProposal) authorizer;

    /// @inheritdoc IProposal
    IPaymentProcessor public override (IProposal) paymentProcessor;

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
        IAuthorizer authorizer_,
        IPaymentProcessor paymentProcessor_
    ) external override (IProposal) initializer {
        // Initialize upstream contracts.
        __Ownable_init();
        __ModuleManager_init(modules);
        __ContributorManager_init();

        // Set storage variables.
        proposalId = proposalId_;
        _token = token_;
        authorizer = authorizer_;
        paymentProcessor = paymentProcessor_;

        // Transfer ownerhsip of proposal to owner argument.
        _transferOwnership(owner_);

        // Add necessary modules.
        // Note to not use the public addModule function as the factory
        // is (most probably) not authorized.
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
        override (ModuleManager)
        returns (bool)
    {
        return authorizer.isAuthorized(who);
    }

    /// @dev Addresses authorized via the {IAuthorizer} instance and the
    ///      proposal's owner can manage contributors.
    function __ContributorManager_isAuthorized(address who)
        internal
        view
        override (ContributorManager)
        returns (bool)
    {
        return authorizer.isAuthorized(who) || who == owner();
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

    function token()
        public
        view
        override (IProposal, FundingManager)
        returns (IERC20)
    {
        return _token;
    }

    /// @inheritdoc IProposal
    function version() external pure returns (string memory) {
        return "1";
    }

    function owner()
        public
        view
        override (OwnableUpgradeable, IProposal)
        returns (address)
    {
        return super.owner();
    }
}
