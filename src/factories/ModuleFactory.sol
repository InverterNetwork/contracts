// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// External Dependencies
import {Context} from "@oz/utils/Context.sol";
import {Ownable2Step} from "@oz/access/Ownable2Step.sol";
import {Ownable} from "@oz/access/Ownable.sol";

// External Interfaces
import {ERC165} from "@oz/utils/introspection/ERC165.sol";

// Internal Dependencies
import {InverterBeaconProxy} from "src/factories/beacon/InverterBeaconProxy.sol";

import {IInverterBeacon} from "src/factories/beacon/IInverterBeacon.sol";

// Internal Libraries
import {LibMetadata} from "src/modules/lib/LibMetadata.sol";

// Internal Interfaces
import {
    IModuleFactory,
    IOrchestrator,
    IModule
} from "src/factories/IModuleFactory.sol";

/**
 * @title Module Factory
 *
 * @dev An owned factory for deploying modules.
 *
 *      The owner can register module metadata's to an {IInverterBeacon}
 *      implementations. Note that a metadata's registered {IInverterBeacon}
 *      implementation can not be changed after registration!
 *
 * @author Inverter Network
 */
contract ModuleFactory is IModuleFactory, Ownable2Step, ERC165 {
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC165)
        returns (bool)
    {
        return interfaceId == type(IModuleFactory).interfaceId
            || super.supportsInterface(interfaceId);
    }
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
    ///         {IInverterBeacon} instance.
    modifier validBeacon(IInverterBeacon beacon) {
        // Revert if beacon's implementation is zero address.
        if (beacon.implementation() == address(0)) {
            revert ModuleFactory__InvalidInverterBeacon();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Storage

    /// @dev Mapping of metadata identifier to {IInverterBeacon} instance.
    /// @dev MetadataLib.identifier(metadata) => {IInverterBeacon}
    mapping(bytes32 => IInverterBeacon) private _beacons;

    //--------------------------------------------------------------------------
    // Constructor

    constructor() Ownable(_msgSender()) {
        // NO-OP
    }

    //--------------------------------------------------------------------------
    // Public Mutating Functions

    /// @inheritdoc IModuleFactory
    function createModule(
        IModule.Metadata memory metadata,
        IOrchestrator orchestrator,
        bytes memory configData
    ) external returns (address) {
        // Note that the metadata's validity is not checked because the
        // module's `init()` function does it anyway.

        IInverterBeacon beacon;
        (beacon, /*id*/ ) = getBeaconAndId(metadata);

        if (address(beacon) == address(0)) {
            revert ModuleFactory__UnregisteredMetadata();
        }

        // Note that a beacon's implementation address can not be the zero
        // address when the beacon is registered. The beacon must have been
        // updated since then.
        // As a zero address implementation indicates an unrecoverable state
        // and faulty update from the beacon's owner, the beacon should be
        // considered dangerous. We therefore make sure that nothing else can
        // happen in this tx and burn all remaining gas.
        // Note that while the inverter's beacon implementation forbids an
        // implementation update to non-contract addresses, we can not ensure
        // a module does not use a different beacon implementation.
        assert(beacon.implementation() != address(0));

        address implementation = address(new InverterBeaconProxy(beacon));

        IModule(implementation).init(orchestrator, metadata, configData);

        emit ModuleCreated(
            address(orchestrator),
            implementation,
            LibMetadata.identifier(metadata)
        );

        return implementation;
    }

    //--------------------------------------------------------------------------
    // Public View Functions

    /// @inheritdoc IModuleFactory
    function getBeaconAndId(IModule.Metadata memory metadata)
        public
        view
        returns (IInverterBeacon, bytes32)
    {
        bytes32 id = LibMetadata.identifier(metadata);

        return (_beacons[id], id);
    }

    //--------------------------------------------------------------------------
    // onlyOwner Functions

    /// @inheritdoc IModuleFactory
    function registerMetadata(
        IModule.Metadata memory metadata,
        IInverterBeacon beacon
    ) external onlyOwner validMetadata(metadata) validBeacon(beacon) {
        IInverterBeacon oldBeacon;
        bytes32 id;
        (oldBeacon, id) = getBeaconAndId(metadata);

        // Revert if metadata already registered for different beacon.
        if (address(oldBeacon) != address(0)) {
            revert ModuleFactory__MetadataAlreadyRegistered();
        }

        // Register Metadata for beacon.
        _beacons[id] = beacon;
        emit MetadataRegistered(metadata, beacon);
    }
}
