// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Dependencies
import {Clones} from "@oz/proxy/Clones.sol";
import {Context} from "@oz/utils/Context.sol";
import {Ownable2Step} from "@oz/access/Ownable2Step.sol";

// Internal Libraries
import {MetadataLib} from "src/modules/lib/MetadataLib.sol";

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
    mapping(bytes32 => address) private _targetPerMetadata;

    constructor() {
        // NO-OP
    }

    modifier validMetadata(IModule.Metadata memory data) {
        if (!MetadataLib.isValid(data)) {
            revert("Invalid Metadata");
        }
        _;
    }

    // @todo mp: Modules need to use beacon pattern and support
    //           "bulk updates".
    // @todo mp: ModuleFactory needs to know/manage minorVersion.
    //           Module does not have knowledge about this anymore!

    /// @inheritdoc IModuleFactory
    function createModule(
        IModule.Metadata memory metadata,
        IProposal proposal,
        bytes memory configdata
    ) external validMetadata(metadata) returns (address) {
        bytes32 id = MetadataLib.identifier(metadata);

        address target = _targetPerMetadata[id];

        if (target == address(0)) {
            revert ModulesFactory__UnregisteredMetadata();
        }

        address clone = Clones.clone(target);
        IModule(clone).init(proposal, metadata, configdata);

        return clone;
    }

    //--------------------------------------------------------------------------
    // onlyOwner Functions

    /// @inheritdoc IModuleFactory
    function registerMetadata(IModule.Metadata memory metadata, address target)
        external
        onlyOwner
        validMetadata(metadata)
    {
        bytes32 id = MetadataLib.identifier(metadata);

        address got = _targetPerMetadata[id];

        // Revert if metadata already registered for different target.
        if (got != address(0)) {
            revert ModulesFactory__MetataAlreadyRegistered();
        }

        if (got != target) {
            // Register Metadata for target.
            _targetPerMetadata[id] = target;
            emit MetadataRegistered(metadata, target);
        }
    }
}
