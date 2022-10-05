// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Interfaces
import {IProposal} from "src/interfaces/IProposal.sol";
import {IModule} from "src/interfaces/IModule.sol";

interface IModulesFactory {
    function createModule(
        bytes32 moduleId,
        IProposal proposal,
        IModule.Metadata memory metadata,
        bytes memory configdata
    ) external returns (address);
}
