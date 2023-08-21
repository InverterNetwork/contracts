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

contract deployAndSwitchTokenAuthorizer is Script {
    DeployAndSetUpBeacon deployAndSetUpBeacon = new DeployAndSetUpBeacon();

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
    address moduleFactoryAddress = 0x349D52589aF62Ba1b35DB871F54FA2c5aFcA6B5B;
    address orchestratorAddress = 0x0A7c8C0EB1afAb6CBaD4bb2d4c738acFF047814A;
    address receiptTokenAddress = 0xC0f1842627Eeda938911A9A8368407ec241AC1dd;
    address bountyManagerAddress = 0x4FB5adc63fB08c7E7864Ce3f77714af6B8B50D9f;

    // ===============================================================================================================
    // In case the Beacon of the Module is already deployed, introduce its address here
    // ===============================================================================================================
    //address authorizerBeacon = 0x3594aAd2f1301888B2E40f50Dc8140a8c723D813;

    ModuleFactory moduleFactory = ModuleFactory(moduleFactoryAddress);
    Orchestrator orchestrator = Orchestrator(orchestratorAddress);

    IModule.Metadata authorizerMetadata = IModule.Metadata(
        1, 1, "https://github.com/inverter/tokenAuthorizer", "TokenAuthorizer"
    );

    BountyManager bountyManager = BountyManager(bountyManagerAddress);

    function run() public {
        //Deploy Implementation and set up Beacon
        address authorizerImpl = deployTokenRoleAuthorizer.run();

        address authorizerBeacon = deployAndSetUpBeacon.run(
            authorizerImpl, address(moduleFactory), authorizerMetadata
        );

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
