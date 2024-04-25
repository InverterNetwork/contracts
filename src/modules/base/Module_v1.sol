// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IModule_v1, IOrchestrator_v1} from "src/modules/base/IModule_v1.sol";
import {IAuthorizer_v1} from "@aut/IAuthorizer_v1.sol";
import {IAuthorizer_v1} from "@aut/IAuthorizer_v1.sol";

// External Dependencies
import {Initializable} from "@oz-up/proxy/utils/Initializable.sol";
import {
    ERC2771ContextUpgradeable,
    ContextUpgradeable
} from "@oz-up/metatx/ERC2771ContextUpgradeable.sol";
import {ERC165} from "@oz/utils/introspection/ERC165.sol";

// Internal Libraries
import {LibMetadata} from "src/modules/lib/LibMetadata.sol";

/**
 * @title   Module
 *
 * @dev     This Contract is the basic building block for all Modules in the Inverter Network.
 *          It contains references to other contracts, modifier for access restriction,
 *          metadata to identify the module type as well as utility functions for general
 *          module interactions.
 *
 *          This contract provides a framework for triggering and receiving orchestrator
 *          callbacks (via `call`) and a modifier to authenticate
 *          callers via the module's orchestrator.
 *
 *          Each module is identified via a unique identifier based on its major
 *          version, title, and url given in the metadata.
 *
 * @author  Inverter Network
 */
abstract contract Module_v1 is
    IModule_v1,
    Initializable,
    ERC2771ContextUpgradeable,
    ERC165
{
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC165)
        returns (bool)
    {
        return interfaceId == type(IModule_v1).interfaceId
            || super.supportsInterface(interfaceId);
    }

    //--------------------------------------------------------------------------
    // Storage
    //
    // Variables are prefixed with `__Module_`.

    /// @dev same thing as the initializer modifier but for the init2 function
    ///
    /// @custom:invariant Not mutated after the init2 call
    bool private __Module_initialization;

    /// @dev The module's orchestrator instance.
    ///
    /// @custom:invariant Not mutated after initialization.
    IOrchestrator_v1 internal __Module_orchestrator;

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
    ///         authorized via Orchestrator_v1.
    modifier onlyOrchestratorOwner() {
        IAuthorizer_v1 authorizer = __Module_orchestrator.authorizer();

        bytes32 ownerRole = authorizer.getOwnerRole();

        if (!authorizer.hasRole(ownerRole, _msgSender())) {
            revert Module__CallerNotAuthorized(ownerRole, _msgSender());
        }
        _;
    }

    /// @notice Modifier to guarantee function is only callable by either
    ///         addresses authorized via Orchestrator_v1 or the Orchestrator_v1's manager.
    modifier onlyOrchestratorOwnerOrManager() {
        IAuthorizer_v1 authorizer = __Module_orchestrator.authorizer();

        bytes32 ownerRole = authorizer.getOwnerRole();
        bytes32 managerRole = authorizer.getManagerRole();

        if (
            authorizer.hasRole(ownerRole, _msgSender())
                || authorizer.hasRole(managerRole, _msgSender())
        ) {
            _;
        } else {
            revert Module__CallerNotAuthorized(ownerRole, _msgSender());
        }
    }

    /// @notice Modifier to guarantee function is only callable by addresses that hold a specific module-assigned role.
    modifier onlyModuleRole(bytes32 role) {
        if (
            !__Module_orchestrator.authorizer().hasModuleRole(role, _msgSender())
        ) {
            revert Module__CallerNotAuthorized(
                __Module_orchestrator.authorizer().generateRoleId(
                    address(this), role
                ),
                _msgSender()
            );
        }
        _;
    }

    /// @notice Modifier to guarantee function is only callable by the orchestrator.
    /// @dev onlyOrchestrator functions MUST only access the module's storage, i.e.
    ///      `__Module_` variables.
    /// @dev Note to use function prefix `__Module_`.
    modifier onlyOrchestrator() {
        if (_msgSender() != address(__Module_orchestrator)) {
            revert Module__OnlyCallableByOrchestrator();
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

    modifier validDependencyData(bytes memory dependencyData) {
        if (!_dependencyInjectionRequired(dependencyData)) {
            revert Module__NoDependencyOrMalformedDependencyData();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Initialization

    constructor() ERC2771ContextUpgradeable(address(0)) {
        _disableInitializers();
    }

    /// @inheritdoc IModule_v1
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata,
        bytes memory /*configData*/
    ) external virtual initializer {
        __Module_init(orchestrator_, metadata);
    }

    /// @dev The initialization function MUST be called by the upstream
    ///      contract in their overriden `init()` function.
    /// @param orchestrator_ The module's orchestrator.
    function __Module_init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata
    ) internal onlyInitializing {
        // Write orchestrator to storage.
        if (address(orchestrator_) == address(0)) {
            revert Module__InvalidOrchestratorAddress();
        }
        __Module_orchestrator = orchestrator_;

        // Write metadata to storage.
        if (!LibMetadata.isValid(metadata)) {
            revert Module__InvalidMetadata();
        }
        __Module_metadata = metadata;

        emit ModuleInitialized(
            address(orchestrator_),
            metadata.title,
            metadata.majorVersion,
            metadata.minorVersion
        );
    }

    function init2(IOrchestrator_v1 orchestrator_, bytes memory dependencyData)
        external
        virtual
        initializer2
        validDependencyData(dependencyData)
    {}

    //--------------------------------------------------------------------------
    // Public View Functions

    /// @inheritdoc IModule_v1
    function identifier() public view returns (bytes32) {
        return LibMetadata.identifier(__Module_metadata);
    }

    /// @inheritdoc IModule_v1
    function version() public view returns (uint, uint) {
        return (__Module_metadata.majorVersion, __Module_metadata.minorVersion);
    }

    /// @inheritdoc IModule_v1
    function url() public view returns (string memory) {
        return __Module_metadata.url;
    }

    /// @inheritdoc IModule_v1
    function title() public view returns (string memory) {
        return __Module_metadata.title;
    }

    /// @inheritdoc IModule_v1
    function orchestrator() public view returns (IOrchestrator_v1) {
        return __Module_orchestrator;
    }

    //--------------------------------------------------------------------------
    // Role Management

    function grantModuleRole(bytes32 role, address addr)
        external
        onlyOrchestratorOwner
    {
        IAuthorizer_v1 roleAuthorizer = __Module_orchestrator.authorizer();
        roleAuthorizer.grantRoleFromModule(role, addr);
    }

    function revokeModuleRole(bytes32 role, address addr)
        external
        onlyOrchestratorOwner
    {
        IAuthorizer_v1 roleAuthorizer = __Module_orchestrator.authorizer();
        roleAuthorizer.revokeRoleFromModule(role, addr);
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    /// @dev Internal function to trigger a callback from the orchestrator.
    /// @param data The call data for the orchestrator to call.
    /// @return Whether the callback succeeded.
    /// @return The return data of the callback.
    function _triggerOrchestratorCallback(bytes memory data)
        internal
        returns (bool, bytes memory)
    {
        bool ok;
        bytes memory returnData;
        (ok, returnData) =
            __Module_orchestrator.executeTxFromModule(address(this), data);

        // Note that there is no check whether the orchestrator callback succeeded.
        // This responsibility is delegated to the caller, i.e. downstream
        // module implementation.
        // However, the {IModule_v1} interface defines a generic error type for
        // failed orchestrator callbacks that can be used to prevent different
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

    function _dependencyInjectionRequired(bytes memory dependencyData)
        internal
        view
        returns (bool)
    {
        try this.decoder(dependencyData) returns (bool) {
            return this.decoder(dependencyData);
        } catch {
            return false;
        }
    }

    //--------------------------------------------------------------------------
    // ERC2771 Context Upgradeable

    /// @notice Checks if the provided address is the trusted forwarder
    /// @param forwarder The contract address to be verified.
    /// @return bool Is the given address the trusted forwarder
    /// @dev We imitate here the EIP2771 Standard to enable metatransactions
    /// As it currently stands we dont want to feed the forwarder address to each module individually and we decided to move this to the orchestrator
    function isTrustedForwarder(address forwarder)
        public
        view
        virtual
        override(ERC2771ContextUpgradeable)
        returns (bool)
    {
        return __Module_orchestrator.isTrustedForwarder(forwarder);
    }

    /// @notice Returns the trusted forwarder
    /// @return address The trusted forwarder
    /// @dev We imitate here the EIP2771 Standard to enable metatransactions
    /// As it currently stands we dont want to feed the forwarder address to each module individually and we decided to move this to the orchestrator
    function trustedForwarder()
        public
        view
        virtual
        override(ERC2771ContextUpgradeable)
        returns (address)
    {
        return __Module_orchestrator.trustedForwarder();
    }
}
