// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Dependencies
import {Clones} from "@oz/proxy/Clones.sol";
import {Context} from "@oz/utils/Context.sol";
import {Ownable2Step} from "@oz/access/Ownable2Step.sol";

import {IBeacon} from "@oz/proxy/beacon/IBeacon.sol";
import {BeaconProxy} from "src/factories/beacon-fundamentals/BeaconProxy.sol";

// External Libraries
import {ERC165Checker} from "@oz/utils/introspection/ERC165Checker.sol";
import {Address} from "@oz/utils/Address.sol";

// Internal Libraries
import {LibMetadata} from "src/modules/lib/LibMetadata.sol";

// Internal Interfaces
import {IProposal} from "src/interfaces/IProposal.sol";
import {IModule} from "src/interfaces/IModule.sol";
import {IModuleFactory} from "src/interfaces/IModuleFactory.sol";

/**
 * @title Module Factory
 *
 * @dev Factory for modules.
 *
 *      Has owner that can register module metadata's to target
 *      implementations.
 *
 * @author byterocket
 */
contract ModuleFactory is IModuleFactory, Ownable2Step {
    //--------------------------------------------------------------------------
    // Modifiers

    /// @notice Modifier to guarantee function is only callable with valid
    ///         metadata.
    modifier validMetadata(IModule.Metadata memory data) {
        if (!LibMetadata.isValid(data)) {
            revert ModuleFactory__InvalidMetadata();
        }
        _;
    }

    /// @notice Modifier to guarantee function is only callable with valid
    ///         target.
    modifier validTarget(address target_) {
        if (target_ == address(this) || target_ == address(0)) {
            revert ModuleFactory__InvalidTarget();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Storage

    // @todo mp: ModuleFactory needs to know/manage minorVersion.
    //           Module does not have knowledge about this anymore!

    /// @dev Mapping of metadata identifier to target contract address.
    /// @dev MetadataLib.identifier(metadata) => address
    mapping(bytes32 => address) private _targets;

    //--------------------------------------------------------------------------
    // Constructor

    constructor() {
        // NO-OP
    }

    //--------------------------------------------------------------------------
    // Public Mutating Functions

    /// @inheritdoc IModuleFactory
    function createModule(
        IModule.Metadata memory metadata,
        IProposal proposal,
        bytes memory configdata
    ) external returns (address) {
        // Note that the metadata's validity is not checked because the
        // module's `init()` function does it anyway.
        // @todo mp: Add comment to function doc?!

        bytes32 id = LibMetadata.identifier(metadata);

        address target_ = _targets[id];

        if (target_ == address(0)) {
            revert ModuleFactory__UnregisteredMetadata();
        }

        if (IBeacon(target_).implementation() == address(0)) {
            revert ModuleFactory__BeaconNoValidImplementation();
        }

        address implementation = address(new BeaconProxy(IBeacon(target_)));

        IModule(implementation).init(proposal, metadata, configdata);

        return implementation;
    }

    //--------------------------------------------------------------------------
    // Public View Functions

    /// @inheritdoc IModuleFactory
    function target(IModule.Metadata memory metadata)
        external
        view
        returns (address)
    {
        bytes32 id = LibMetadata.identifier(metadata);

        return _targets[id];
    }

    //--------------------------------------------------------------------------
    // onlyOwner Functions

    /// @inheritdoc IModuleFactory
    function registerMetadata(IModule.Metadata memory metadata, address target_)
        external
        onlyOwner
        validMetadata(metadata)
        validTarget(target_)
    {
        bytes32 id = LibMetadata.identifier(metadata);

        address got = _targets[id];

        // Revert if metadata already registered for different target.
        if (got != address(0)) {
            revert ModuleFactory__MetadataAlreadyRegistered();
        }

        if (!Address.isContract(target_)) {
            revert ModuleFactory__BeaconNoValidImplementation();
        }

        if (
            !ERC165Checker.supportsInterface(target_, type(IBeacon).interfaceId)
        ) {
            revert ModuleFactory__BeaconNoValidImplementation();
        }

        if (IBeacon(target_).implementation() == address(0)) {
            revert ModuleFactory__BeaconNoValidImplementation();
        }

        // Register Metadata for target.
        _targets[id] = target_;
        emit MetadataRegistered(metadata, target_);
    }
}
