// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

// External Dependencies
import {Context} from "@oz/utils/Context.sol";
import {Ownable2Step} from "@oz/access/Ownable2Step.sol";

// External Interfaces
import {IBeacon} from "@oz/proxy/beacon/IBeacon.sol";

// Internal Dependencies
import {BeaconProxy} from "src/factories/beacon/BeaconProxy.sol";

// Internal Libraries
import {LibMetadata} from "src/modules/lib/LibMetadata.sol";

// Internal Interfaces
import {
    IModuleFactory,
    IProposal,
    IModule
} from "src/factories/IModuleFactory.sol";

/**
 * @title Module Factory
 *
 * @dev An owned factory for deploying modules.
 *
 *      The owner can register module metadata's to an {IBeacon}
 *      implementations. Note that a metadata's registered {IBeacon}
 *      implementation can not be changed after registration!
 *
 * @author Inverter Network
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
    ///         {IBeacon} instance.
    modifier validBeacon(IBeacon beacon) {
        // Revert if beacon's implementation is zero address.
        if (beacon.implementation() == address(0)) {
            revert ModuleFactory__InvalidBeacon();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Storage

    /// @dev Mapping of metadata identifier to {IBeacon} instance.
    /// @dev MetadataLib.identifier(metadata) => {IBeacon}
    mapping(bytes32 => IBeacon) private _beacons;

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

        IBeacon beacon;
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

        address implementation = address(new BeaconProxy(beacon));

        IModule(implementation).init(proposal, metadata, configdata);

        emit ModuleCreated(address(proposal), implementation, metadata.title);

        return implementation;
    }
 
    //--------------------------------------------------------------------------
    // Public View Functions

    /// @inheritdoc IModuleFactory
    function getBeaconAndId(IModule.Metadata memory metadata)
        public
        view
        returns (IBeacon, bytes32)
    {
        bytes32 id = LibMetadata.identifier(metadata);

        return (_beacons[id], id);
    }

    //--------------------------------------------------------------------------
    // onlyOwner Functions

    /// @inheritdoc IModuleFactory
    function registerMetadata(IModule.Metadata memory metadata, IBeacon beacon)
        external
        onlyOwner
        validMetadata(metadata)
        validBeacon(beacon)
    {
        IBeacon oldBeacon;
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
