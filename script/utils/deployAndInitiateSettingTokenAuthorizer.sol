// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {
    AUT_TokenGated_Roles_v1,
    IAUT_TokenGated_Roles_v1,
    IAuthorizer_v1
} from "@aut/role/AUT_TokenGated_Roles_v1.sol";
import {DeployAUT_TokenGated_Role_v1} from
    "script/modules/authorizer/DeployAUT_TokenGated_Role_v1.s.sol";
import {ModuleFactory_v1} from "src/factories/ModuleFactory_v1.sol";
import {
    Orchestrator_v1,
    IOrchestrator_v1
} from "src/orchestrator/Orchestrator_v1.sol";
import {IModule_v1} from "src/modules/base/IModule_v1.sol";
import {IOrchestratorFactory_v1} from "src/factories/OrchestratorFactory_v1.sol";

import {DeployAndSetUpInverterBeacon_v1} from
    "script/proxies/DeployAndSetUpInverterBeacon_v1.s.sol";
import {ScriptConstants} from "../script-constants.sol";

contract deployAndSwitchTokenAuthorizer is Script {
    DeployAndSetUpInverterBeacon_v1 deployAndSetupInverterBeacon_v1 =
        new DeployAndSetUpInverterBeacon_v1();
    ScriptConstants scriptConstants = new ScriptConstants();

    uint orchestratorAdminPrivateKey =
        vm.envUint("ORCHESTRATOR_ADMIN_PRIVATE_KEY");
    address orchestratorAdmin = vm.addr(orchestratorAdminPrivateKey);

    DeployAUT_TokenGated_Role_v1 deployTokenRoleAuthorizer =
        new DeployAUT_TokenGated_Role_v1();

    // ===============================================================================================================
    // Introduce addresses of the deployed Orchestrator_v1 here
    // ===============================================================================================================
    address moduleFactoryAddress = scriptConstants.moduleFactoryAddress();
    address orchestratorAddress = scriptConstants.orchestratorAddress();

    // ===============================================================================================================
    // Set the Module Metadata.
    // ===============================================================================================================
    IModule_v1.Metadata authorizerMetadata = IModule_v1.Metadata(
        1, 0, 0, "https://github.com/InverterNetwork", "TokenAuthorizer"
    );

    // Decide on the workflowConfig
    IOrchestratorFactory_v1.WorkflowConfig workflowConfig =
    IOrchestratorFactory_v1.WorkflowConfig({
        independentUpdates: false,
        independentUpdateAdmin: address(0)
    });

    ModuleFactory_v1 moduleFactory = ModuleFactory_v1(moduleFactoryAddress);
    Orchestrator_v1 orchestrator = Orchestrator_v1(orchestratorAddress);

    function run() public {
        /*
        // In case the module Beacon hasn't been deployed yet, deploy it and register it in the ModuleFactory_v1   

        address authorizerImpl = deployTokenRoleAuthorizer.run();

        address authorizerBeacon = deployAndSetupInverterBeacon_v1.run(
            authorizerImpl, address(moduleFactory), authorizerMetadata
        ); 
        */

        // Authorizer: Metadata, initial authorized addresses
        IOrchestratorFactory_v1.ModuleConfig memory authorizerFactoryConfig =
        IOrchestratorFactory_v1.ModuleConfig(
            authorizerMetadata, abi.encode(orchestratorAdmin, orchestratorAdmin)
        );

        vm.startBroadcast(orchestratorAdminPrivateKey);

        // moduleFactory -> create Module
        address deployedAuthorizerAddress = moduleFactory.createModule(
            authorizerMetadata,
            IOrchestrator_v1(orchestrator),
            authorizerFactoryConfig.configData,
            workflowConfig
        );
        AUT_TokenGated_Roles_v1 deployedAuthorizer =
            AUT_TokenGated_Roles_v1(deployedAuthorizerAddress);

        console.log(
            "Deployed Token Authorizer at address: ", deployedAuthorizerAddress
        );

        // initiate add module to orchestrator
        orchestrator.initiateSetAuthorizerWithTimelock(deployedAuthorizer);

        console.log(
            "Initiated updating authorizer in Orchestrator with address: ",
            address(orchestrator),
            " Timelock until (unix time) : ",
            orchestrator.MODULE_UPDATE_TIMELOCK()
        );

        vm.stopBroadcast();
    }
}
