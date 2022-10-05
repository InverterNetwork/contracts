// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Dependencies
import {Clones} from "@oz/proxy/Clones.sol";
import {Context} from "@oz/utils/Context.sol";

// Internal Interfaces
import {IAuthorizer} from "src/interfaces/IAuthorizer.sol";
import {IProposal} from "src/interfaces/IProposal.sol";
import {IModule} from "src/interfaces/IModule.sol";
import {IModulesFactory} from "src/interfaces/IModulesFactory.sol";

contract ProposalFactory {
    address public immutable target;
    address public immutable modulesFactory;

    uint private _proposalIdCounter;

    constructor(address target_, address modulesFactory_) {
        target = target_;
        modulesFactory = modulesFactory_;
    }

    function createProposal(
        address[] calldata funders,
        bytes32 authorizerModuleId,
        IModule.Metadata memory authorizerMetadata,
        bytes memory authorizerConfigdata,
        bytes32[] memory moduleIds,
        IModule.Metadata[] memory moduleMetadatas,
        bytes[] memory moduleConfigdatas
    ) external returns (address) {
        address proposal = Clones.clone(target);

        // @todo mp: Check that array length all match.

        // Deploy and cache authorizer modules.
        address authorizer = IModulesFactory(modulesFactory).createModule(
            authorizerModuleId,
            IProposal(proposal),
            authorizerMetadata,
            authorizerConfigdata
        );

        // Deploy and cache optional modules.
        address[] memory modules = new address[](moduleIds.length);
        for (uint i; i < moduleIds.length; i++) {
            modules[i] = IModulesFactory(modulesFactory).createModule(
                moduleIds[i],
                IProposal(proposal),
                moduleMetadatas[i],
                moduleConfigdatas[i]
            );
        }

        // Initialize proposal.
        IProposal(proposal).init(
            _proposalIdCounter++, funders, modules, IAuthorizer(authorizer)
        );

        return proposal;
    }
}
