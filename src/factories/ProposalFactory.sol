// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Dependencies
import {Clones} from "@oz/proxy/Clones.sol";
import {Context} from "@oz/utils/Context.sol";

// Internal Interfaces
import {IAuthorizer} from "src/interfaces/IAuthorizer.sol";
import {IPayer} from "src/interfaces/IPayer.sol";
import {IProposal} from "src/interfaces/IProposal.sol";
import {IModule} from "src/interfaces/IModule.sol";
import {IModuleFactory} from "src/interfaces/IModuleFactory.sol";
import {IProposalFactory} from "src/interfaces/IProposalFactory.sol";

/**
 * @title Proposal Factory
 *
 * @author byterocket
 */
contract ProposalFactory is IProposalFactory {
    //--------------------------------------------------------------------------
    // Immutables

    /// @inheritdoc IProposalFactory
    address public immutable override target;

    /// @inheritdoc IProposalFactory
    address public immutable override moduleFactory;

    //--------------------------------------------------------------------------
    // Storage

    uint private _proposalIdCounter;

    //--------------------------------------------------------------------------
    // Constructor

    constructor(address target_, address moduleFactory_) {
        target = target_;
        moduleFactory = moduleFactory_;
    }

    //--------------------------------------------------------------------------
    // Public Mutating Functions

    /// @inheritdoc IProposalFactory
    function createProposal(
        address[] calldata funders,
        IModule.Metadata memory authorizerMetadata,
        bytes memory authorizerConfigdata, // @todo mp: Add payer arguments.
        IModule.Metadata[] memory moduleMetadatas,
        bytes[] memory moduleConfigdatas
    ) external returns (address) {
        address clone = Clones.clone(target);

        // Revert if data arrays' lengths mismatch.
        if (moduleMetadatas.length != moduleConfigdatas.length) {
            revert ProposalFactory__ModuleDataLengthMismatch();
        }

        // Deploy and cache authorizer module.
        address authorizer = IModuleFactory(moduleFactory).createModule(
            authorizerMetadata, IProposal(clone), authorizerConfigdata
        );

        // Deploy and cache optional modules.
        uint modulesLen = moduleMetadatas.length;
        address[] memory modules = new address[](modulesLen);
        for (uint i; i < modulesLen; i++) {
            modules[i] = IModuleFactory(moduleFactory).createModule(
                moduleMetadatas[i], IProposal(clone), moduleConfigdatas[i]
            );
        }

        // Initialize proposal.
        IProposal(clone).init(
            _proposalIdCounter++,
            funders,
            modules,
            IAuthorizer(authorizer),
            IPayer(address(0xBEEF)) // @todo mp: Adjust when arguments added.
        );

        return clone;
    }
}
