// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Interfaces
import {IModule, IOrchestrator} from "src/modules/base/IModule.sol";
import {IInverterBeacon} from "src/factories/beacon/IInverterBeacon.sol";

interface IModuleFactory {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Given metadata invalid.
    error ModuleFactory__InvalidMetadata();

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
        IModule.Metadata indexed metadata, IInverterBeacon indexed beacon
    );

    /// @notice Event emitted when new module created for a orchestrator.
    /// @param orchestrator The corresponding orchestrator.
    /// @param module The created module instance.
    /// @param identifier The module's identifier.
    event ModuleCreated(
        address indexed orchestrator, address indexed module, bytes32 identifier
    );

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Returns the governor contract address
    /// @return The address of the governor contract
    function governor() external view returns (address);

    /// @notice Creates a module instance identified by given metadata.
    /// @param metadata The module's metadata.
    /// @param orchestrator The orchestrator's instance of the module.
    /// @param configData The configData of the module
    function createModule(
        IModule.Metadata memory metadata,
        IOrchestrator orchestrator,
        bytes memory configData
    ) external returns (address);

    /// @notice Returns the {IInverterBeacon} instance registered and the id for given
    ///         metadata.
    /// @param metadata The module's metadata.
    /// @return The module's {IInverterBeacon} instance registered.
    /// @return The metadata's id.
    function getBeaconAndId(IModule.Metadata memory metadata)
        external
        view
        returns (IInverterBeacon, bytes32);

    /// @notice Returns the address of the orchestrator a proxy was registered for.
    /// @param proxy The address of the module proxy.
    /// @return The address of the corresponding orchestrator.
    function getOrchestratorOfProxy(address proxy)
        external
        view
        returns (address);

    /// @notice Registers metadata `metadata` with {IInverterBeacon} implementation
    ///         `beacon`.
    /// @dev Only callable by owner.
    /// @param metadata The module's metadata.
    /// @param beacon The module's {IInverterBeacon} instance.
    function registerMetadata(
        IModule.Metadata memory metadata,
        IInverterBeacon beacon
    ) external;
}
