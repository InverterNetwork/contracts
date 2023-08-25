// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {
    TokenGatedRoleAuthorizer,
    ITokenGatedRoleAuthorizer,
    IAuthorizer
} from "src/modules/authorizer/TokenGatedRoleAuthorizer.sol";
import {DeployTokenGatedRoleAuthorizer} from
    "script/modules/governance/DeployTokenGatedRoleAuthorizer.s.sol";
import {ModuleFactory} from "src/factories/ModuleFactory.sol";
import {Orchestrator, IOrchestrator} from "src/orchestrator/Orchestrator.sol";
import {IModule} from "src/modules/base/IModule.sol";
import {BountyManager} from "src/modules/logicModule/BountyManager.sol";
import {IOrchestratorFactory} from "src/factories/OrchestratorFactory.sol";

import {DeployAndSetUpBeacon} from "script/proxies/DeployAndSetUpBeacon.s.sol";

contract deployAndSwitchTokenAuthorizer is Script {
    // ===============================================================================================================
    // NOTE: This script has to be executed by the Orchestrator owner address.
    // IT IS STRONGLY RECOMMENDED TO STORE THE PRIVATE KEY TO THAT ADDRESS IN A SEPARATE .ENV FILE
    // ===============================================================================================================
    uint orchestratorOwnerPrivateKey =
        vm.envUint("ORCHESTRATOR_OWNER_PRIVATE_KEY");
    address orchestratorOwner = vm.addr(orchestratorOwnerPrivateKey);

    function run() public {
        // ===============================================================================================================
        // Introduce addresses of the deployed Orchestrator, BountyManager and Authorizer
        // ===============================================================================================================

        address orchestratorAddress = 0x0A7c8C0EB1afAb6CBaD4bb2d4c738acFF047814A;
        Orchestrator orchestrator = Orchestrator(orchestratorAddress);

        // The address of the deployed TokenGatedRoleAuthorizer.
        address authorizerAddress = address(orchestrator.authorizer());
        TokenGatedRoleAuthorizer deployedAuthorizer =
            TokenGatedRoleAuthorizer(authorizerAddress);

        // This script assumes we want to set the Role in the BountyManager. Change if appropriate.
        address bountyManagerAddress =
            0x4FB5adc63fB08c7E7864Ce3f77714af6B8B50D9f;
        BountyManager bountyManager = BountyManager(bountyManagerAddress);

        // ===============================================================================================================
        // Introduce authentication conditions here:
        //      - Address of the token to be used
        //      - Minimum amount of tokens needed by the caller
        // ===============================================================================================================

        address gatingTokenAddress = 0xC0f1842627Eeda938911A9A8368407ec241AC1dd;
        uint thresholdAmount = 1;

        // ===============================================================================================================
        // Setup
        // ===============================================================================================================

        vm.startBroadcast(orchestratorOwner);

        //Give the Orchestrator owner the power to change module roles
        deployedAuthorizer.grantRole(
            deployedAuthorizer.DEFAULT_ADMIN_ROLE(), orchestratorOwner
        );

        // ===============================================================================================================
        // Make the Role Token-Gated
        // ===============================================================================================================

        // Choose the role to be modified. In this example we will use the CLAIM_ADMIN_ROLE
        bytes32 roleId = deployedAuthorizer.generateRoleId(
            bountyManagerAddress, bountyManager.CLAIM_ADMIN_ROLE()
        );

        //First, we mark the Role as Token-Gated
        deployedAuthorizer.setTokenGated(roleId, true);
        // Second, we set the token to be used for the Role as the gating token
        deployedAuthorizer.grantRole(roleId, gatingTokenAddress);
        // Third, we set the minimum amount of tokens needed to be able to execute the Role
        deployedAuthorizer.setThreshold(
            roleId, gatingTokenAddress, thresholdAmount
        );

        vm.stopBroadcast();

        console.log(
            "=================================================================================="
        );
        console.log(
            "Execution succesful: Token-gating set up by the token %s with a threshold of %s",
            gatingTokenAddress,
            thresholdAmount
        );
    }
}
