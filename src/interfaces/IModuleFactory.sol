// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Interfaces
import {IProposal} from "src/interfaces/IProposal.sol";
import {IModule} from "src/interfaces/IModule.sol";

interface IModuleFactory {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Given metadata invalid.
    error ModuleFactory__InvalidMetadata();

    /// @notice Given target invalid.
    error ModuleFactory__InvalidTarget();

    /// @notice Given metadata unregistered.
    error ModuleFactory__UnregisteredMetadata();

    /// @notice Given metadata already registered.
    error ModuleFactory__MetadataAlreadyRegistered();

    /// @notice Given beacon has no Implmentation.
    error ModuleFactory__BeaconNoValidImplementation();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when new target registered for metadata.
    event MetadataRegistered(
        IModule.Metadata indexed metadata, address indexed target
    );

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Creates a module instance identified by given metadata.
    /// @param metadata The module's metadata.
    /// @param proposal The proposal's instance of the module.
    /// @param configdata The configdata of the module.
    function createModule(
        IModule.Metadata memory metadata,
        IProposal proposal,
        bytes memory configdata
    ) external returns (address);

    /// @notice Returns the target address to clone for given metadata.
    /// @param metadata The module's metadata.
    /// @return The target address to clone.
    function target(IModule.Metadata memory metadata)
        external
        view
        returns (address);

    /// @notice Registers metadata `metadata` with module's implementation `target`.
    /// @dev Only callable by owner.
    /// @dev Has to guarantee that
    /// @param metadata The module's metadata.
    /// @param target The module's implementation.
    function registerMetadata(IModule.Metadata memory metadata, address target)
        external;
}
