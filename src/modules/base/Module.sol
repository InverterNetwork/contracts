// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Dependencies
import {Initializable} from "@oz-up/proxy/utils/Initializable.sol";
import {PausableUpgradeable} from "@oz-up/security/PausableUpgradeable.sol";

// Internal Dependencies
import {Types} from "src/common/Types.sol";
import {ProposalStorage} from "src/generated/ProposalStorage.sol";

// Interfaces
import {IModule} from "src/interfaces/IModule.sol";
import {IAuthorizer} from "src/interfaces/IAuthorizer.sol";
import {IProposal} from "src/interfaces/IProposal.sol";

/**
 * @title Module
 *
 * @dev Module is the base contract for modules.
 *
 *      This contract provides a framework for triggering and receiving proposal
 *      callbacks (via `call` or `delegatecall`) and a modifier to authenticate
 *      callers via the module's proposal.
 *
 *
 *      Proposal Callbacks
 *      ==================
 *
 *      A module can trigger a callback from its proposal via the internal
 *      `triggerProposalCallback(funcData, op)` function. The `op` argument
 *      specifies whether the callback is executed via `call` or `delegatecall`,
 *      i.e. whether the callback is executed in the module's or the proposal's
 *      context.
 *
 *      Callbacks executed in the Proposal's Context
 *      --------------------------------------------
 *
 *      In order to easily access the proposals storage in proposal callback
 *      functions executed via `delegatecall`, the contract inherits from the
 *      auto-generated {ProposalStorage} contract to mirror the proposal's
 *      storage layout. All variables inherited from the {ProposalStorage} are
 *      prefixed with `__Proposal_`.
 *
 *      In order to guarantee the callback is not executed in the module's
 *      context, the `wantProposalContext` modifier MUST be used!
 *
 *      Per convention, such `delegatecall`-callbacks SHOULD:
 *          - Prefix the function name with `__Proposal_`
 *          - Only access {ProposalStorage} variables.
 *
 *      Callbacks executed in the Module's Context
 *      ------------------------------------------
 *
 *      Proposal callbacks executed in the module's context MUST be
 *      authenticated via the `onlyProposal` modifier. They MUST NOT access
 *      `__Proposal_` variables.
 *
 *      Per convention, the function name SHOULD be prefixed with `__Module_`.
 *
 *
 *      Initialization
 *      ==============
 *
 *      The contract provides a `__Module_init(proposal)` function for
 *      initialization that MUST be called in order to correctly initialize the
 *      storage.
 *
 *
 *      User Authentication
 *      ===================
 *
 *      Users are authenticated using the proposal's {IAuthenticator} instance.
 *      This ensures that all access management is handled solely by the proposal.
 *
 *
 *      Versioning
 *      ==========
 *
 *      todo mp: Versioning
 *
 *
 * @dev Property-based Testing
 *
 *      todo mp: Add Scribble invariants and setup test infra.
 *
 * @author byterocket
 */
abstract contract Module is IModule, ProposalStorage, PausableUpgradeable {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Function is only callable by authorized addresses.
    error Module__OnlyCallableByAuthorized();

    /// @notice Function is only callable by the proposal.
    error Module__OnlyCallableByProposal();

    /// @notice Function is only callable inside the proposal's context.
    /// @dev Note that we can not guarantee the function is executed in the
    ///      proposals context. However, we guarantee the function is not
    ///      executed inside the module's own context.
    error Module__WantProposalContext();

    //--------------------------------------------------------------------------
    // Storage
    //
    // Variables are prefixed with `__Module_`.

    /// @dev The module's proposal instance.
    /// @dev Set during initialization and MUST NOT ever be mutated!
    IProposal internal __Module_proposal;

    //--------------------------------------------------------------------------
    // Modifiers

    /// @notice Modifier to guarantee function is only callable by addresses
    ///         authorized via Proposal.
    /// @dev onlyAuthorized functions SHOULD only be used to trigger callbacks
    ///      from the proposal via the `triggerProposalCallback()` function.
    modifier onlyAuthorized() {
        IAuthorizer authorizer = __Module_proposal.authorizer();
        if (!authorizer.isAuthorized(msg.sender)) {
            revert Module__OnlyCallableByAuthorized();
        }
        _;
    }

    /// @notice Modifier to guarantee function is only callable by the proposal.
    /// @dev onlyProposal functions MUST only access the module's storage, i.e.
    ///      `__Module_` variables.
    /// @dev Note to use function prefix `__Module_`.
    modifier onlyProposal() {
        if (msg.sender != address(__Module_proposal)) {
            revert Module__OnlyCallableByProposal();
        }
        _;
    }

    /// @notice Modifier to guarantee that the function is not executed in the
    ///         module's context.
    /// @dev Note that it's save to not authenticate the caller in these
    ///      functions. The module's storage only starts after the proposal's.
    ///      As long as these functions only access the proposal storage
    ///      variables (`__Proposal_`) inherited from {ProposalStorage}, the
    ///      module's own state is never mutated.
    /// @dev Note to use function prefix `__Proposal_`.
    modifier wantProposalContext() {
        // If we are in the proposal's context, the following storage access
        // MUST return the zero address. That's because the module's storage
        // starts after the proposal's storage due to inheriting from
        // {ProposalStorage}.
        if (address(__Module_proposal) != address(0)) {
            revert Module__WantProposalContext();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Initialization

    /// @dev The initialization function MUST be called by the upstream
    ///      contract in their `initialize()` function.
    /// @param proposal The module's proposal.
    function __Module_init(IProposal proposal) internal initializer {
        __Pausable_init();

        require(address(proposal) != address(0));
        __Module_proposal = proposal;
    }

    // @todo mp: Fallback implemented for testing.
    fallback() external {
        revert("Fallback called");
    }

    // @todo mp: Need version function

    //--------------------------------------------------------------------------
    // onlyProposal Functions
    //
    // Proposal callback functions executed via `call`.

    /// @notice Callback function to pause the module.
    /// @dev Only callable by the proposal.
    function __Module_pause() external onlyProposal {
        _pause();
    }

    /// @notice Callback function to unpause the module.
    /// @dev Only callable by the proposal.
    function __Module_unpause() external onlyProposal {
        _unpause();
    }

    //--------------------------------------------------------------------------
    // onlyAuthorized Functions
    //
    // API functions for authenticated users.

    /// @inheritdoc IModule
    function pause() external override (IModule) onlyAuthorized {
        _triggerProposalCallback(
            abi.encodeWithSignature("__Module_pause()"), Types.Operation.Call
        );
    }

    /// @inheritdoc IModule
    function unpause() external override (IModule) onlyAuthorized {
        _triggerProposalCallback(
            abi.encodeWithSignature("__Module_unpause()"), Types.Operation.Call
        );
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    /// @dev Internal function to trigger a callback from the proposal.
    /// @param funcData The encoded function signature and arguments the
    ///                 proposal should call back to.
    /// @param op Whether the callback should be a `call` or `delegatecall`.
    function _triggerProposalCallback(bytes memory funcData, Types.Operation op)
        internal
    {
        __Module_proposal.executeTxFromModule(address(this), funcData, op);
    }
}
