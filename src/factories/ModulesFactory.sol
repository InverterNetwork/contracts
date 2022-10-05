// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Dependencies
import {Clones} from "@oz/proxy/Clones.sol";
import {Context} from "@oz/utils/Context.sol";
import {Ownable2Step} from "@oz/access/Ownable2Step.sol";

// Internal Interfaces
import {IProposal} from "src/interfaces/IProposal.sol";
import {IModule} from "src/interfaces/IModule.sol";

// @todo Needs owner
contract ModulesFactory is Ownable2Step {
    mapping(bytes32 => address) private targetPerModuleId;

    constructor() {
        // NO-OP
    }

    function createModule(
        bytes32 moduleId,
        IProposal proposal,
        IModule.Metadata memory metadata,
        bytes memory configdata
    ) public returns (IModule) {
        address target = targetPerModuleId[moduleId];

        if (target == address(0)) {
            revert("Invalid moduleId");
        }

        address clone = Clones.clone(target);
        IModule(clone).init(proposal, metadata, configdata);

        return IModule(clone);
    }

    //--------------------------------------------------------------------------
    // onlyOwner Functions

    function commitModuleId(bytes32 moduleId, address module)
        external
        onlyOwner
    {
        if (address(module) == address(0)) {
            revert("Invalid module address");
        }

        if (IModule(module).identifier() != moduleId) {
            revert("Module identifier mismatch");
        }

        address got = targetPerModuleId[moduleId];
        if (got != address(0) && got != module) {
            revert("ModuleId already registered with different module address");
        }

        targetPerModuleId[moduleId] = module;
        // @todo mp: Emit event.
    }
}
