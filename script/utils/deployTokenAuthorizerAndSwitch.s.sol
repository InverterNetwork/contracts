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

    address moduleFactoryAddress = 0x349D52589aF62Ba1b35DB871F54FA2c5aFcA6B5B;
    address orchestratorAddress = 0x94846d78aC3E35D4C6119000003CA81d362042d0;
    address receiptTokenAddress = 0xe86b937e3901d715d5B4162B6A29758D1BD1Afd6;

    ModuleFactory moduleFactory = ModuleFactory(moduleFactoryAddress);
    Orchestrator orchestrator = Orchestrator(orchestratorAddress);

    IModule.Metadata authorizerMetadata = IModule.Metadata(
        1, 1, "https://github.com/inverter/tokenAuthorizer", "TokenAuthorizer"
    );

    address bountyManagerAddress = 0x7560b724B90eD62bF1ab3D374CdaD6d14EAF09BB;
    BountyManager bountyManager = BountyManager(bountyManagerAddress);

    address authorizer = 0x05E8B4d1F715B1a1D2BE4b6a91569dAaE1fC2F2A;
    address authorizerBeacon = 0x3594aAd2f1301888B2E40f50Dc8140a8c723D813;

    function run() public {
        /*
        //call deployment script
        address authorizer = deployTokenRoleAuthorizer.run();
        // register at beacon / module factory
        address authorizerBeacon = deployAndSetUpBeacon.run(
            authorizer, address(moduleFactory), authorizerMetadata
        );
        */

        // correct mistake from before
        // orchestrator.removeModule(0xC0f1842627Eeda938911A9A8368407ec241AC1dd);

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

        /*vm.prank(orchestratorOwner);
        uint bountyId =
            bountyManager.addBounty(100e18, 250e18, "0x0");

        console2.log("\t -Bounty Created. Id: ", bountyId);
        /*
        console2.log(
            "=================================================================================="
        );
        console2.log("Claim added with id: ", claimId);
        console2.log(
            "=================================================================================="
        ); */
    }
}
