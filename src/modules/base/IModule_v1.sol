// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Interfaces
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";

interface IModule_v1 {
    struct Metadata {
        uint majorVersion;
        uint minorVersion;
        string url;
        string title;
    }

    //--------------------------------------------------------------------------
    // Events

    /// @notice Module has been initialized.
    /// @param parentOrchestrator The address of the orchestrator the module is linked to.
    /// @param moduleTitle The title of the module.
    /// @param majorVersion The major version of the module.
    /// @param minorVersion The minor version of the module.
    event ModuleInitialized(
        address indexed parentOrchestrator,
        string indexed moduleTitle,
        uint majorVersion,
        uint minorVersion
    );

    //--------------------------------------------------------------------------
    // Errors

    /// @notice Function is only callable by authorized caller.
    error Module__CallerNotAuthorized(bytes32 role, address caller);

    /// @notice Function is only callable by the orchestrator.
    error Module__OnlyCallableByOrchestrator();

    /// @notice Given orchestrator address invalid.
    error Module__InvalidOrchestratorAddress();

    /// @notice Given metadata invalid.
    error Module__InvalidMetadata();

    /// @notice Orchestrator_v1 callback triggered failed.
    /// @param funcSig The signature of the function called.
    error Module_OrchestratorCallbackFailed(string funcSig);

    /// @notice init2 was called again for a module
    error Module__CannotCallInit2Again();

    /// @notice the dependency data passed to init2 was not in the correct format
    ///         or there was no dependency for the particular module
    error Module__NoDependencyOrMalformedDependencyData();

    //--------------------------------------------------------------------------
    // Functions

    /// @notice The module's initializer function.
    /// @dev CAN be overriden by downstream contract.
    /// @dev MUST call `__Module_init()`.
    /// @param orchestrator The module's orchestrator instance.
    /// @param metadata The module's metadata.
    /// @param configData Variable config data for specific module
    ///                   implementations.
    function init(
        IOrchestrator_v1 orchestrator,
        Metadata memory metadata,
        bytes memory configData
    ) external;

    /// @notice Second initialization function of the module to take care of dependencies.
    /// @param orchestrator The module's orchestrator instance.
    /// @param configData Variable config data for specific module
    ///                   implementations.
    function init2(IOrchestrator_v1 orchestrator, bytes memory configData)
        external;

    /// @notice Returns the module's identifier.
    /// @dev The identifier is defined as the keccak256 hash of the module's
    ///      abi packed encoded major version, url and title.
    /// @return The module's identifier.
    function identifier() external view returns (bytes32);

    /// @notice Returns the module's version.
    /// @return The module's major version.
    /// @return The module's minor version.
    function version() external view returns (uint, uint);

    /// @notice Returns the module's URL.
    /// @return The module's URL.
    function url() external view returns (string memory);

    /// @notice Returns the module's title.
    /// @return The module's title.
    function title() external view returns (string memory);

    /// @notice Returns the module's {IOrchestrator_v1} orchestrator instance.
    /// @return The module's orchestrator.
    function orchestrator() external view returns (IOrchestrator_v1);

    function grantModuleRole(bytes32 role, address target) external;

    function grantModuleRoleBatched(bytes32 role, address[] calldata targets)
        external;

    function revokeModuleRole(bytes32 role, address target) external;

    function revokeModuleRoleBatched(bytes32 role, address[] calldata targets)
        external;
}
