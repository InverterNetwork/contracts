// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

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
import {ScriptConstants} from "../script-constants.sol";

contract deployAndSwitchTokenAuthorizer is Script {
    DeployAndSetUpBeacon deployAndSetUpBeacon = new DeployAndSetUpBeacon();
    ScriptConstants scriptConstants = new ScriptConstants();

    bool hasDependency;
    string[] dependencies = new string[](0);

    uint orchestratorOwnerPrivateKey =
        vm.envUint("ORCHESTRATOR_OWNER_PRIVATE_KEY");
    address orchestratorOwner = vm.addr(orchestratorOwnerPrivateKey);

    DeployTokenGatedRoleAuthorizer deployTokenRoleAuthorizer =
        new DeployTokenGatedRoleAuthorizer();

    // ===============================================================================================================
    // Introduce addresses of the deployed Orchestrator here
    // ===============================================================================================================
    address moduleFactoryAddress = scriptConstants.moduleFactoryAddress();
    address orchestratorAddress = scriptConstants.orchestratorAddress();
    address receiptTokenAddress = scriptConstants.receiptTokenAddress();
    address bountyManagerAddress = scriptConstants.bountyManagerAddress();

    // ===============================================================================================================
    // Set the Module Metadata.
    // ===============================================================================================================
    IModule.Metadata authorizerMetadata = IModule.Metadata(
        1, 1, "https://github.com/inverter/tokenAuthorizer", "TokenAuthorizer"
    );

    ModuleFactory moduleFactory = ModuleFactory(moduleFactoryAddress);
    Orchestrator orchestrator = Orchestrator(orchestratorAddress);

    BountyManager bountyManager = BountyManager(bountyManagerAddress);

    function run() public {
        /*   

        // In case the module Beacon hasn't been deployed yet, deploy it and register it in the ModuleFactory   

        address authorizerImpl = deployTokenRoleAuthorizer.run();

        address authorizerBeacon = deployAndSetUpBeacon.run(
            authorizerImpl, address(moduleFactory), authorizerMetadata
        ); */

        // Authorizer: Metadata, initial authorized addresses
        IOrchestratorFactory.ModuleConfig memory authorizerFactoryConfig =
        IOrchestratorFactory.ModuleConfig(
            authorizerMetadata,
            abi.encode(orchestratorOwner, orchestratorOwner),
            abi.encode(hasDependency, dependencies)
        );

        vm.startBroadcast(orchestratorOwnerPrivateKey);

        // moduleFactory -> create Module
        address deployedAuthorizerAddress = moduleFactory.createModule(
            authorizerMetadata,
            IOrchestrator(orchestrator),
            authorizerFactoryConfig.configData
        );
        TokenGatedRoleAuthorizer deployedAuthorizer =
            TokenGatedRoleAuthorizer(deployedAuthorizerAddress);

        console.log(
            "Deployed Authorizer at address: ", deployedAuthorizerAddress
        );

        // add module to orchestrator
        orchestrator.setAuthorizer(deployedAuthorizer);

        //grant default admin role to orchestratorOwner
        deployedAuthorizer.grantRole(
            deployedAuthorizer.DEFAULT_ADMIN_ROLE(), orchestratorOwner
        );

        // make all BountyManager roles tokenGated
        bytes32 claimRoleId = deployedAuthorizer.generateRoleId(
            bountyManagerAddress, bountyManager.CLAIM_ADMIN_ROLE()
        );
        bytes32 bountyRoleId = deployedAuthorizer.generateRoleId(
            bountyManagerAddress, bountyManager.BOUNTY_ADMIN_ROLE()
        );
        bytes32 verifyRoleId = deployedAuthorizer.generateRoleId(
            bountyManagerAddress, bountyManager.VERIFY_ADMIN_ROLE()
        );

        //manually set tokenGated, token and threshold for all roles
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
