// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Interfaces
import {IModule_v1, IOrchestrator_v1} from "src/modules/base/IModule_v1.sol";
import {IOrchestratorFactory_v1} from
    "src/factories/interfaces/IOrchestratorFactory_v1.sol";
import {IInverterBeacon_v1} from "src/proxies/interfaces/IInverterBeacon_v1.sol";

interface IModuleFactory_v1 {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Given metadata invalid.
    error ModuleFactory__InvalidMetadata();

    /// @notice Given metadata invalid.
    error ModuleFactory__InvalidInitialRegistrationData();

    /// @notice Given beacon invalid.
    error ModuleFactory__InvalidInverterBeacon();

    /// @notice Given metadata unregistered.
    error ModuleFactory__UnregisteredMetadata();

    /// @notice Given metadata already registered.
    error ModuleFactory__MetadataAlreadyRegistered();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when new beacon registered for metadata.
    /// @param metadata The registered Metadata
    /// @param beacon The registered Beacon
    event MetadataRegistered(
        IModule_v1.Metadata indexed metadata, IInverterBeacon_v1 indexed beacon
    );

    /// @notice Event emitted when new module created for a orchestrator_v1.
    /// @param orchestrator The corresponding orchestrator.
    /// @param module The created module instance.
    /// @param identifier The module's identifier.
    event ModuleCreated(
        address indexed orchestrator, address indexed module, bytes32 identifier
    );

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Returns the governor_v1 contract address
    /// @return The address of the governor contract
    function governor() external view returns (address);

    /// @notice Creates a module instance identified by given metadata.
    /// @param metadata The module's metadata.
    /// @param orchestrator The orchestrator's instance of the module.
    /// @param configData The configData of the module
    /// @param workflowConfig The configData of the workflow
    /// @return Returns the address of the created module proxy
    function createModule(
        IModule_v1.Metadata memory metadata,
        IOrchestrator_v1 orchestrator,
        bytes memory configData,
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig
    ) external returns (address);

    /// @notice Returns the {IInverterBeacon_v1} instance registered and the id for given
    ///         metadata.
    /// @param metadata The module's metadata.
    /// @return The module's {IInverterBeacon_v1} instance registered.
    /// @return The metadata's id.
    function getBeaconAndId(IModule_v1.Metadata memory metadata)
        external
        view
        returns (IInverterBeacon_v1, bytes32);

    /// @notice Returns the orchestrator address of a beacon proxy.
    /// @param proxy The beacon proxy address.
    /// @return The corresponding orchestrator address for the provided proxy.
    function getOrchestratorOfProxy(address proxy)
        external
        view
        returns (address);

    /// @notice Registers metadata `metadata` with {IInverterBeacon_v1} implementation
    ///         `beacon`.
    /// @dev Only callable by owner.
    /// @param metadata The module's metadata.
    /// @param beacon The module's {IInverterBeacon_v1} instance.
    function registerMetadata(
        IModule_v1.Metadata memory metadata,
        IInverterBeacon_v1 beacon
    ) external;
}
