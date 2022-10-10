// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Interfaces
import {IProposal} from "src/interfaces/IProposal.sol";
import {IModule} from "src/interfaces/IModule.sol";

interface IModuleFactory {
    error ModuleFactory__InvalidMetadata();
    error ModuleFactory__InvalidTarget();

    error ModuleFactory__UnregisteredMetadata();
    error ModuleFactory__MetadataAlreadyRegistered();

    event MetadataRegistered(
        IModule.Metadata indexed metadata, address indexed target
    );

    /// @notice Creates a module instance identified by given metadata.
    /// @param metadata The metadata of the module.
    /// @param proposal The proposal's instance of the module.
    /// @param configdata The configdata of the module.
    function createModule(
        IModule.Metadata memory metadata,
        IProposal proposal,
        bytes memory configdata
    ) external returns (address);

    /// @notice Registers metadata `metadata` with module's implementation `target`.
    /// @dev Only callable by owner.
    /// @param metadata The module's metadata.
    /// @param target The module's implementation.
    function registerMetadata(IModule.Metadata memory metadata, address target)
        external;
}
