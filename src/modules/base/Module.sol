// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

// External Dependencies
import {
    PausableUpgradeable,
    ContextUpgradeable
} from "@oz-up/security/PausableUpgradeable.sol";

// Internal Libraries
import {LibMetadata} from "src/modules/lib/LibMetadata.sol";

// Internal Interfaces
import {IModule, IProposal} from "src/modules/base/IModule.sol";
import {IAuthorizer} from "src/modules/IAuthorizer.sol";

/**
 * @title Module
 *
 * @dev The base contract for modules.
 *
 *      This contract provides a framework for triggering and receiving proposal
 *      callbacks (via `call`) and a modifier to authenticate
 *      callers via the module's proposal.
 *
 *      Each module is identified via a unique identifier based on its major
 *      version, title, and url given in the metadata.
 *
 *      Using proxy contracts, e.g. beacons, enables globally updating module
 *      instances when its minor version changes, but supports differentiating
 *      otherwise equal modules with different major versions.
 *
 * @author byterocket
 */
abstract contract Module is IModule, PausableUpgradeable {
    //--------------------------------------------------------------------------
    // Storage
    //
    // Variables are prefixed with `__Module_`.

    /// @dev The module's proposal instance.
    ///
    /// @custom:invariant Not mutated after initialization.
    IProposal internal __Module_proposal;

    /// @dev The module's metadata.
    ///
    /// @custom:invariant Not mutated after initialization.
    Metadata internal __Module_metadata;

    //--------------------------------------------------------------------------
    // Modifiers
    //
    // Note that the modifiers declared here are available in dowstream
    // contracts too. To not make unnecessary modifiers available, this contract
    // inlines argument validations not needed in downstream contracts.

    /// @notice Modifier to guarantee function is only callable by addresses
    ///         authorized via Proposal.
    modifier onlyAuthorized() {
        IAuthorizer authorizer = __Module_proposal.authorizer();
        if (!authorizer.isAuthorized(_msgSender())) {
            revert Module__CallerNotAuthorized();
        }
        _;
    }

    /// @notice Modifier to guarantee function is only callable by either
    ///         addresses authorized via Proposal or the Proposal's owner.
    modifier onlyAuthorizedOrOwner() {
        IAuthorizer authorizer = __Module_proposal.authorizer();
        if (
            !authorizer.isAuthorized(_msgSender())
                && __Module_proposal.owner() != _msgSender()
        ) {
            revert Module__CallerNotAuthorized();
        }
        _;
    }

    /// @notice Modifier to guarantee function is only callable by the proposal.
    /// @dev onlyProposal functions MUST only access the module's storage, i.e.
    ///      `__Module_` variables.
    /// @dev Note to use function prefix `__Module_`.
    modifier onlyProposal() {
        if (_msgSender() != address(__Module_proposal)) {
            revert Module__OnlyCallableByProposal();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Initialization

    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc IModule
    function init(
        IProposal proposal_,
        Metadata memory metadata,
        bytes memory /*configdata*/
    ) external virtual initializer {
        __Module_init(proposal_, metadata);
    }

    /// @dev The initialization function MUST be called by the upstream
    ///      contract in their overriden `init()` function.
    /// @param proposal_ The module's proposal.
    function __Module_init(IProposal proposal_, Metadata memory metadata)
        internal
        onlyInitializing
    {
        __Pausable_init();

        // Write proposal to storage.
        if (address(proposal_) == address(0)) {
            revert Module__InvalidProposalAddress();
        }
        __Module_proposal = proposal_;

        // Write metadata to storage.
        if (!LibMetadata.isValid(metadata)) {
            revert Module__InvalidMetadata();
        }
        __Module_metadata = metadata;
    }

    //--------------------------------------------------------------------------
    // onlyAuthorized Functions
    //
    // API functions for authenticated users.

    /// @inheritdoc IModule
    function pause() external override(IModule) onlyAuthorizedOrOwner {
        _pause();
    }

    /// @inheritdoc IModule
    function unpause() external override(IModule) onlyAuthorizedOrOwner {
        _unpause();
    }

    //--------------------------------------------------------------------------
    // Public View Functions

    /// @inheritdoc IModule
    function identifier() public view returns (bytes32) {
        return LibMetadata.identifier(__Module_metadata);
    }

    /// @inheritdoc IModule
    function version() public view returns (uint, uint) {
        return (__Module_metadata.majorVersion, __Module_metadata.minorVersion);
    }

    /// @inheritdoc IModule
    function url() public view returns (string memory) {
        return __Module_metadata.url;
    }

    /// @inheritdoc IModule
    function title() public view returns (string memory) {
        return __Module_metadata.title;
    }

    /// @inheritdoc IModule
    function proposal() public view returns (IProposal) {
        return __Module_proposal;
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    /// @dev Internal function to trigger a callback from the proposal.
    /// @param data The call data for the proposal to call.
    /// @return Whether the callback succeeded.
    /// @return The return data of the callback.
    function _triggerProposalCallback(bytes memory data)
        internal
        returns (bool, bytes memory)
    {
        bool ok;
        bytes memory returnData;
        (ok, returnData) =
            __Module_proposal.executeTxFromModule(address(this), data);

        // Note that there is no check whether the proposal callback succeeded.
        // This responsibility is delegated to the caller, i.e. downstream
        // module implementation.
        // However, the {IModule} interface defines a generic error type for
        // failed proposal callbacks that can be used to prevent different
        // custom error types in each implementation.
        return (ok, returnData);
    }
}
