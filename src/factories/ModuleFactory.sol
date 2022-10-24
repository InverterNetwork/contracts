// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Dependencies
import {Context} from "@oz/utils/Context.sol";
import {Ownable2Step} from "@oz/access/Ownable2Step.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";
import {ERC165Checker} from "@oz/utils/introspection/ERC165Checker.sol";
import {Address} from "@oz/utils/Address.sol";

// External Interfaces
import {IBeacon} from "@oz/proxy/beacon/IBeacon.sol";

// Internal Dependencies
import {BeaconProxy} from "src/factories/beacon/BeaconProxy.sol";

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
    ///         beacon.
    modifier validBeacon(address beacon) {
        // Revert if beacon is not a contract.
        if (!Address.isContract(beacon)) {
            revert ModuleFactory__InvalidTarget();
        }

        // Revert if beacon does not implement {IBeacon} interface.
        // Checked via ERC-165.
        bool isIBeacon =
            ERC165Checker.supportsInterface(beacon, type(IBeacon).interfaceId);
        if (!isIBeacon) {
            revert ModuleFactory__InvalidTarget();
        }

        // Revert if beacon's implementation is zero address.
        if (IBeacon(beacon).implementation() == address(0)) {
            revert ModuleFactory__InvalidTarget();
        }

        // Otherwise valid beacon.
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

        address target;
        (target, /*id*/ ) = getTargetAndId(metadata);

        if (target == address(0)) {
            revert ModuleFactory__UnregisteredMetadata();
        }

        // @todo mp: This is not cool... Check needs to be there because
        //           contract can change after registration, but the error
        //           should be more "exceptional".
        //           This should _really_ NOT happen!
        // Update:   It indicates the module is broken and should NOT be
        //           trusted. Better to burn all gas and make sure nothing
        //           can happen in this tx anymore (?)
        assert(IBeacon(target).implementation() != address(0));
        //if (IBeacon(target).implementation() == address(0)) {
        //    revert ModuleFactory__InvalidBeaconImplementation();
        //}

        address implementation = address(new BeaconProxy(IBeacon(target)));

        IModule(implementation).init(proposal, metadata, configdata);

        return implementation;
    }

    //--------------------------------------------------------------------------
    // Public View Functions

    /// @inheritdoc IModuleFactory
    function getTargetAndId(IModule.Metadata memory metadata)
        public
        view
        returns (address, bytes32)
    {
        bytes32 id = LibMetadata.identifier(metadata);

        return (_targets[id], id);
    }

    //--------------------------------------------------------------------------
    // onlyOwner Functions

    /// @inheritdoc IModuleFactory
    function registerMetadata(IModule.Metadata memory metadata, address target)
        external
        onlyOwner
        validMetadata(metadata)
        validBeacon(target) // @todo mp: Just expect interface IBeacon.
    {
        address oldTarget;
        bytes32 id;
        (oldTarget, id) = getTargetAndId(metadata);

        // Revert if metadata already registered for different target.
        if (oldTarget != address(0)) {
            revert ModuleFactory__MetadataAlreadyRegistered();
        }

        // Register Metadata for target.
        _targets[id] = target;
        emit MetadataRegistered(metadata, target);
    }
}
