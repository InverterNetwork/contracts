// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Dependencies
import {Clones} from "@oz/proxy/Clones.sol";
import {Context} from "@oz/utils/Context.sol";

// Internal Interfaces
import {IAuthorizer} from "src/interfaces/IAuthorizer.sol";
import {IProposal} from "src/interfaces/IProposal.sol";
import {IModule} from "src/interfaces/IModule.sol";
import {IModuleFactory} from "src/interfaces/IModuleFactory.sol";

/**
 * @title Proposal Factory
 *
 * @author byterocket
 */
contract ProposalFactory {
    address public immutable target;
    address public immutable moduleFactory;

    uint private _proposalIdCounter;

    constructor(address target_, address moduleFactory_) {
        target = target_;
        moduleFactory = moduleFactory_;
    }

    function createProposal(
        address[] calldata funders,
        IModule.Metadata memory authorizerMetadata,
        bytes memory authorizerConfigdata,
        IModule.Metadata[] memory moduleMetadatas,
        bytes[] memory moduleConfigdatas
    ) external returns (address) {
        address proposal = Clones.clone(target);

        // @todo mp: Check that array length all match.

        // Deploy and cache authorizer module.
        address authorizer = IModuleFactory(moduleFactory).createModule(
            authorizerMetadata, IProposal(proposal), authorizerConfigdata
        );

        // Deploy and cache optional modules.
        address[] memory modules = new address[](moduleMetadatas.length);
        for (uint i; i < moduleMetadatas.length; i++) {
            modules[i] = IModuleFactory(moduleFactory).createModule(
                moduleMetadatas[i], IProposal(proposal), moduleConfigdatas[i]
            );
        }

        // Initialize proposal.
        IProposal(proposal).init(
            _proposalIdCounter++, funders, modules, IAuthorizer(authorizer)
        );

        return proposal;
    }
}
