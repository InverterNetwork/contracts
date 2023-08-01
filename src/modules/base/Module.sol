// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

// External Dependencies
import {Initializable} from "@oz-up/proxy/utils/Initializable.sol";
import {ContextUpgradeable} from "@oz-up/utils/ContextUpgradeable.sol";

// Internal Libraries
import {LibMetadata} from "src/modules/lib/LibMetadata.sol";

// Internal Interfaces
import {IModule, IProposal} from "src/modules/base/IModule.sol";
import {IAuthorizer} from "src/modules/authorizer/IAuthorizer.sol";
import {IAuthorizer} from "src/modules/authorizer/IAuthorizer.sol";

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
 * @author Inverter Network
 */
abstract contract Module is IModule, Initializable, ContextUpgradeable {
    //--------------------------------------------------------------------------
    // Storage
    //
    // Variables are prefixed with `__Module_`.

    /// @dev same thing as the initializer modifier but for the init2 function
    ///
    /// @custom:invariant Not mutated after the init2 call
    bool private __Module_initialization;

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
    modifier onlyProposalOwner() {
        IAuthorizer authorizer =
            IAuthorizer(address(__Module_proposal.authorizer()));

        bytes32 ownerRole = authorizer.getOwnerRole();

        if (!authorizer.hasRole(ownerRole, _msgSender())) {
            revert Module__CallerNotAuthorized();
        }
        _;
    }

    /// @notice Modifier to guarantee function is only callable by either
    ///         addresses authorized via Proposal or the Proposal's manager.
    modifier onlyProposalOwnerOrManager() {
        IAuthorizer authorizer =
            IAuthorizer(address(__Module_proposal.authorizer()));

        bytes32 ownerRole = authorizer.getOwnerRole();
        bytes32 managerRole = authorizer.getManagerRole();

        if (
            !authorizer.hasRole(ownerRole, _msgSender())
                && !authorizer.hasRole(managerRole, _msgSender())
        ) {
            revert Module__CallerNotAuthorized();
        }
        _;
    }

    //@todo Reminder that this will be moved into the Module Contract at a later point of time
    modifier onlyModuleRole(uint8 roleId) {
        if (
            !IAuthorizer(address(__Module_proposal.authorizer())).isAuthorized(
                roleId, _msgSender()
            )
        ) {
            //revert Module__BountyManager__OnlyRole(roleId, address(this));
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

    /// @dev same function as OZ initializer, but for the init2 function
    modifier initializer2() {
        if (__Module_initialization) {
            revert Module__CannotCallInit2Again();
        }
        __Module_initialization = true;
        _;
    }

    modifier validDependencyData(bytes memory dependencydata) {
        if (!_dependencyInjectionRequired(dependencydata)) {
            revert Module__NoDependencyOrMalformedDependencyData();
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

    function init2(IProposal proposal_, bytes memory dependencydata)
        external
        virtual
        initializer2
        validDependencyData(dependencydata)
    {}

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
    // Role Management

    function grantModuleRole(uint8 role, address addr)
        external
        onlyProposalOwner
    {
        IAuthorizer roleAuthorizer =
            IAuthorizer(address(__Module_proposal.authorizer()));
        roleAuthorizer.grantRoleFromModule(uint8(role), addr);
    }

    function revokeModuleRole(uint8 role, address addr)
        external
        onlyProposalOwner
    {
        IAuthorizer roleAuthorizer =
            IAuthorizer(address(__Module_proposal.authorizer()));
        roleAuthorizer.revokeRoleFromModule(uint8(role), addr);
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

    function decoder(bytes memory data)
        public
        pure
        returns (bool requirement)
    {
        (requirement,) = abi.decode(data, (bool, string[]));
    }

    function _dependencyInjectionRequired(bytes memory dependencydata)
        internal
        view
        returns (bool)
    {
        try this.decoder(dependencydata) returns (bool) {
            return this.decoder(dependencydata);
        } catch {
            return false;
        }
    }
}
