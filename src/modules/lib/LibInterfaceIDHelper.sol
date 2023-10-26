// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IModule} from "src/modules/base/IModule.sol";
import {IModuleFactory} from "src/factories/IModuleFactory.sol";
import {IOrchestratorFactory} from "src/factories/IOrchestratorFactory.sol";
import {IModuleManager} from "src/orchestrator/base/IModuleManager.sol";
import {IOrchestrator} from "src/orchestrator/IOrchestrator.sol";


library LibInterfaceIDHelper {

    function getInterfaceId_IOrchestrator() external pure returns(bytes4) {
        return type(IOrchestrator).interfaceId;
    }

    function getInterfaceId_IModuleManager() external pure returns(bytes4) {
        return type(IModuleManager).interfaceId;
    }

}
