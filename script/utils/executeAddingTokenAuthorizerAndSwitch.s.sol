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
import {LM_PC_Bounties_v1} from "@lm/LM_PC_Bounties_v1.sol";
import {IOrchestratorFactory_v1} from "src/factories/OrchestratorFactory_v1.sol";

import {DeployAndSetUpInverterBeacon_v1} from
    "script/proxies/DeployAndSetUpInverterBeacon_v1.s.sol";
import {ScriptConstants} from "../script-constants.sol";

contract deployAndSwitchTokenAuthorizer is Script {
    DeployAndSetUpInverterBeacon_v1 deployAndSetupInverterBeacon_v1 =
        new DeployAndSetUpInverterBeacon_v1();
    ScriptConstants scriptConstants = new ScriptConstants();

    uint orchestratorOwnerPrivateKey =
        vm.envUint("ORCHESTRATOR_OWNER_PRIVATE_KEY");
    address orchestratorOwner = vm.addr(orchestratorOwnerPrivateKey);

    DeployAUT_TokenGated_Role_v1 deployTokenRoleAuthorizer =
        new DeployAUT_TokenGated_Role_v1();

    // ===============================================================================================================
    // Introduce addresses of the deployed Orchestrator_v1 here
    // ===============================================================================================================
    address moduleFactoryAddress = scriptConstants.moduleFactoryAddress();
    address orchestratorAddress = scriptConstants.orchestratorAddress();
    address receiptTokenAddress = scriptConstants.receiptTokenAddress();
    address bountyManagerAddress = scriptConstants.bountyManagerAddress();

    // ===============================================================================================================
    // Set the Module Metadata.
    // ===============================================================================================================

    ModuleFactory_v1 moduleFactory = ModuleFactory_v1(moduleFactoryAddress);
    Orchestrator_v1 orchestrator = Orchestrator_v1(orchestratorAddress);

    LM_PC_Bounties_v1 bountyManager = LM_PC_Bounties_v1(bountyManagerAddress);

    function run() public {
        vm.startBroadcast(orchestratorOwnerPrivateKey);

        // Get deployed and setting initiated authorizer from .env
        address deployedAuthorizerAddress =
            vm.envAddress("INITIATED_AUTHORIZER");

        AUT_TokenGated_Roles_v1 deployedAuthorizer =
            AUT_TokenGated_Roles_v1(deployedAuthorizerAddress);

        console.log(
            "Deployed Token Authorizer at address: ", deployedAuthorizerAddress
        );

        // execute add module to orchestrator
        orchestrator.executeSetAuthorizer(deployedAuthorizer);

        // grant default admin role to orchestratorOwner
        deployedAuthorizer.grantRole(
            deployedAuthorizer.DEFAULT_ADMIN_ROLE(), orchestratorOwner
        );

        // make all LM_PC_Bounties_v1 roles tokenGated
        bytes32 claimRoleId = deployedAuthorizer.generateRoleId(
            bountyManagerAddress, bountyManager.CLAIMANT_ROLE()
        );
        bytes32 bountyRoleId = deployedAuthorizer.generateRoleId(
            bountyManagerAddress, bountyManager.BOUNTY_ISSUER_ROLE()
        );
        bytes32 verifyRoleId = deployedAuthorizer.generateRoleId(
            bountyManagerAddress, bountyManager.VERIFIER_ROLE()
        );

        // manually set tokenGated, token and threshold for all roles
        deployedAuthorizer.setTokenGated(claimRoleId, true);
        deployedAuthorizer.grantRole(claimRoleId, receiptTokenAddress);
        deployedAuthorizer.setThreshold(claimRoleId, receiptTokenAddress, 1);

        deployedAuthorizer.setTokenGated(bountyRoleId, true);
        deployedAuthorizer.grantRole(bountyRoleId, receiptTokenAddress);
        deployedAuthorizer.setThreshold(bountyRoleId, receiptTokenAddress, 1);

        deployedAuthorizer.setTokenGated(verifyRoleId, true);
        deployedAuthorizer.grantRole(verifyRoleId, receiptTokenAddress);
        deployedAuthorizer.setThreshold(verifyRoleId, receiptTokenAddress, 1);

        vm.stopBroadcast();
    }
}
