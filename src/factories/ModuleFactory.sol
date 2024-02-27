// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;
pragma solidity 0.8.23;

//External Dependencies
import {ERC2771Context} from "@oz/metatx/ERC2771Context.sol";
import {Ownable2Step} from "@oz/access/Ownable2Step.sol";
import {Context, Ownable} from "@oz/access/Ownable.sol";

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
contract ModuleFactory is
    IModuleFactory,
    ERC2771Context,
    Ownable2Step,
    ERC165
{
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
    ///         IInverterBeacon instance and if the owner of the beacon
    ///         is same as the governor of this contract.
    modifier validBeacon(IInverterBeacon beacon) {
        // Revert if beacon's implementation is zero address.
        if (
            beacon.implementation() == address(0)
                || Ownable(address(beacon)).owner() != governor
        ) {
            revert ModuleFactory__InvalidInverterBeacon();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Storage

    /// @inheritdoc IModuleFactory
    address public governor;

    /// @dev Mapping of metadata identifier to {IInverterBeacon} instance.
    /// @dev MetadataLib.identifier(metadata) => {IInverterBeacon}
    mapping(bytes32 => IInverterBeacon) private _beacons;

    //--------------------------------------------------------------------------
    // Constructor

    constructor(address _governor, address _trustedForwarder)
        ERC2771Context(_trustedForwarder)
        Ownable(_msgSender())
    {
        governor = _governor;
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

    //--------------------------------------------------------------------------
    // ERC2771 Context Upgradeable

    /// Needs to be overriden, because they are imported via the Ownable2Step as well
    function _msgSender()
        internal
        view
        virtual
        override(ERC2771Context, Context)
        returns (address sender)
    {
        return ERC2771Context._msgSender();
    }

    /// Needs to be overriden, because they are imported via the Ownable2Step as well
    function _msgData()
        internal
        view
        virtual
        override(ERC2771Context, Context)
        returns (bytes calldata)
    {
        return ERC2771Context._msgData();
    }

    function _contextSuffixLength()
        internal
        view
        virtual
        override(ERC2771Context, Context)
        returns (uint)
    {
        return ERC2771Context._contextSuffixLength();
    }
}
