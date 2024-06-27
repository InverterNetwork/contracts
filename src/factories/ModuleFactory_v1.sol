// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {
    IModuleFactory_v1,
    IOrchestrator_v1,
    IModule_v1
} from "src/factories/interfaces/IModuleFactory_v1.sol";
import {IOrchestratorFactory_v1} from
    "src/factories/interfaces/IOrchestratorFactory_v1.sol";
import {IInverterBeacon_v1} from "src/proxies/interfaces/IInverterBeacon_v1.sol";

// Internal Dependencies
import {InverterBeaconProxy_v1} from "src/proxies/InverterBeaconProxy_v1.sol";
import {InverterTransparentUpgradeableProxy_v1} from
    "src/proxies/InverterTransparentUpgradeableProxy_v1.sol";
import {LibMetadata} from "src/modules/lib/LibMetadata.sol";

// External Interfaces
import {ERC165} from "@oz/utils/introspection/ERC165.sol";

// External Dependencies
import {
    ERC2771ContextUpgradeable,
    ContextUpgradeable
} from "@oz-up/metatx/ERC2771ContextUpgradeable.sol";
import {
    Ownable2StepUpgradeable,
    Initializable
} from "@oz-up/access/Ownable2StepUpgradeable.sol";

/**
 * @title   Module Factory
 *
 * @notice  Enables the creation and registration of Inverter Modules,
 *          facilitating the deployment of module instances linked to specific beacons.
 *          Allows for configuration of modules starting state via provided deployment data.
 *
 * @dev     An owned factory for deploying modules.
 *          The owner can register module metadata's to an {IInverterBeacon_v1}
 *          implementations. Note that a metadata's registered {IInverterBeacon_v1}
 *          implementation can not be changed after registration!
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
 *
 * @author  Inverter Network
 */
contract ModuleFactory_v1 is
    IModuleFactory_v1,
    ERC2771ContextUpgradeable,
    Ownable2StepUpgradeable,
    ERC165
{
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC165)
        returns (bool)
    {
        return interfaceId == type(IModuleFactory_v1).interfaceId
            || super.supportsInterface(interfaceId);
    }
    //--------------------------------------------------------------------------
    // Modifiers

    /// @notice Modifier to guarantee function is only callable with valid
    ///         metadata.
    modifier validMetadata(IModule_v1.Metadata memory data) {
        if (!LibMetadata.isValid(data)) {
            revert ModuleFactory__InvalidMetadata();
        }
        _;
    }

    /// @notice Modifier to guarantee function is only callable with valid
    ///         IInverterBeacon_v1 instance and if the owner of the beacon
    ///         is same as the governor of this contract.
    modifier validBeacon(IInverterBeacon_v1 beacon) {
        // Revert if beacon's implementation is zero address.
        if (
            beacon.implementation() == address(0)
                || Ownable2StepUpgradeable(address(beacon)).owner() != governor
        ) {
            revert ModuleFactory__InvalidInverterBeacon();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Storage

    /// @inheritdoc IModuleFactory_v1
    address public governor;

    /// @dev Mapping of metadata identifier to {IInverterBeacon_v1} instance.
    /// @dev MetadataLib.identifier(metadata) => {IInverterBeacon_v1}
    mapping(bytes32 => IInverterBeacon_v1) private _beacons;

    /// @dev Mapping of proxy address to orchestrator address.
    mapping(address => address) private _orchestratorOfProxy;

    // Storage gap for future upgrades
    uint[50] private __gap;

    //--------------------------------------------------------------------------
    // Constructor & Initializer

    constructor(address _trustedForwarder)
        ERC2771ContextUpgradeable(_trustedForwarder)
    {
        _disableInitializers();
    }

    /// @notice The factories initializer function.
    /// @param _governor The address of the governor contract.
    /// @param initialMetadataRegistration List of metadata that will be registered during the initialization.
    /// @param initialMetadataRegistration List of beacon addresses that will be registered during the initialization.
    function init(
        address _governor,
        IModule_v1.Metadata[] memory initialMetadataRegistration,
        IInverterBeacon_v1[] memory initialBeaconRegistration
    ) external initializer {
        __Ownable_init(_governor);
        governor = _governor;

        uint length = initialMetadataRegistration.length;
        if (length != initialBeaconRegistration.length) {
            revert ModuleFactory__InvalidInitialRegistrationData();
        }

        for (uint i = 0; i < length; i++) {
            _registerMetadata(
                initialMetadataRegistration[i], initialBeaconRegistration[i]
            );
        }
    }

    //--------------------------------------------------------------------------
    // Public Mutating Functions

    /// @inheritdoc IModuleFactory_v1
    function createModule(
        IModule_v1.Metadata memory metadata,
        IOrchestrator_v1 orchestrator,
        bytes memory configData,
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig
    ) external returns (address) {
        // Note that the metadata's validity is not checked because the
        // module's `init()` function does it anyway.

        IInverterBeacon_v1 beacon;
        (beacon, /*id*/ ) = getBeaconAndId(metadata);

        if (address(beacon) == address(0)) {
            revert ModuleFactory__UnregisteredMetadata();
        }

        address proxy;
        // If the workflow should fetch their updates themselves
        if (workflowConfig.independentUpdates) {
            // Use an InverterTransparentUpgradeableProxy as a proxy
            proxy = address(
                new InverterTransparentUpgradeableProxy_v1(
                    beacon, workflowConfig.independentUpdateAdmin, bytes("")
                )
            );
        }
        // If not then
        else {
            // Instead use the Beacon Structure Proxy
            proxy = address(new InverterBeaconProxy_v1(beacon));
        }

        IModule_v1(proxy).init(orchestrator, metadata, configData);

        _orchestratorOfProxy[proxy] = address(orchestrator);

        emit ModuleCreated(
            address(orchestrator), proxy, LibMetadata.identifier(metadata)
        );

        return proxy;
    }

    //--------------------------------------------------------------------------
    // Public View Functions

    /// @inheritdoc IModuleFactory_v1
    function getBeaconAndId(IModule_v1.Metadata memory metadata)
        public
        view
        returns (IInverterBeacon_v1, bytes32)
    {
        bytes32 id = LibMetadata.identifier(metadata);

        return (_beacons[id], id);
    }

    /// @inheritdoc IModuleFactory_v1
    function getOrchestratorOfProxy(address proxy)
        public
        view
        returns (address)
    {
        return _orchestratorOfProxy[proxy];
    }

    //--------------------------------------------------------------------------
    // onlyOwner Functions

    /// @inheritdoc IModuleFactory_v1
    function registerMetadata(
        IModule_v1.Metadata memory metadata,
        IInverterBeacon_v1 beacon
    ) external onlyOwner {
        _registerMetadata(metadata, beacon);
    }

    function _registerMetadata(
        IModule_v1.Metadata memory metadata,
        IInverterBeacon_v1 beacon
    ) internal validMetadata(metadata) validBeacon(beacon) {
        IInverterBeacon_v1 oldBeacon;
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
        override(ERC2771ContextUpgradeable, ContextUpgradeable)
        returns (address sender)
    {
        return ERC2771ContextUpgradeable._msgSender();
    }

    /// Needs to be overriden, because they are imported via the Ownable2Step as well
    function _msgData()
        internal
        view
        virtual
        override(ERC2771ContextUpgradeable, ContextUpgradeable)
        returns (bytes calldata)
    {
        return ERC2771ContextUpgradeable._msgData();
    }

    function _contextSuffixLength()
        internal
        view
        virtual
        override(ERC2771ContextUpgradeable, ContextUpgradeable)
        returns (uint)
    {
        return ERC2771ContextUpgradeable._contextSuffixLength();
    }
}
