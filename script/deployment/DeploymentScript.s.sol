// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

// Import interfaces:

import {IModule} from "src/modules/base/IModule.sol";
import {IBeacon} from "src/factories/beacon/Beacon.sol";
import {IModuleFactory} from "src/factories/ModuleFactory.sol";

// Import scripts:

import {DeployAndSetUpBeacon} from "script/proxies/DeployAndSetUpBeacon.s.sol";
import {DeployModuleFactory} from "script/factories/DeployModuleFactory.s.sol";
import {DeployOrchestratorFactory} from
    "script/factories/DeployOrchestratorFactory.s.sol";
import {DeployBountyManager} from "script/modules/DeployBountyManager.s.sol";
import {DeployOrchestrator} from "script/orchestrator/DeployOrchestrator.s.sol";
import {DeploySimplePaymentProcessor} from
    "script/modules/paymentProcessor/DeploySimplePaymentProcessor.s.sol";
import {DeployRebasingFundingManager} from
    "script/modules/fundingManager/DeployRebasingFundingManager.s.sol";
import {DeployRoleAuthorizer} from
    "script/modules/governance/DeployRoleAuthorizer.s.sol";

contract DeploymentScript is Script {
    // ------------------------------------------------------------------------
    // Instances of Deployer Contracts

    DeployModuleFactory deployModuleFactory = new DeployModuleFactory();
    DeployOrchestratorFactory deployOrchestratorFactory =
        new DeployOrchestratorFactory();

    DeployOrchestrator deployOrchestrator = new DeployOrchestrator();
    DeploySimplePaymentProcessor deploySimplePaymentProcessor =
        new DeploySimplePaymentProcessor();
    DeployRebasingFundingManager deployRebasingFundingManager =
        new DeployRebasingFundingManager();
    DeployRoleAuthorizer deployRoleAuthorizer = new DeployRoleAuthorizer();
    DeployBountyManager deployBountyManager = new DeployBountyManager();

    DeployAndSetUpBeacon deployAndSetUpBeacon = new DeployAndSetUpBeacon();

    // ------------------------------------------------------------------------
    // Deployed Contracts

    address orchestrator;
    address simplePaymentProcessor;
    address bountyManager;
    address fundingManager;
    address authorizer;

    address moduleFactory;
    address orchestratorFactory;

    address paymentProcessorBeacon;
    address bountyManagerBeacon;
    address fundingManagerBeacon;
    address authorizerBeacon;

    // ------------------------------------------------------------------------
    // Module Metadata
    IModule.Metadata paymentProcessorMetadata = IModule.Metadata(
        1,
        1,
        "https://github.com/inverter/payment-processor",
        "SimplePaymentProcessor"
    );

    IModule.Metadata fundingManagerMetadata = IModule.Metadata(
        1, 1, "https://github.com/inverter/funding-manager", "FundingManager"
    );

    IModule.Metadata authorizerMetadata = IModule.Metadata(
        1, 1, "https://github.com/inverter/RoleAuthorizer", "RoleAuthorizer"
    );

    IModule.Metadata bountyManagerMetadata = IModule.Metadata(
        1, 1, "https://github.com/inverter/bounty-manager", "BountyManager"
    );

    /// @notice Deploys all necessary factories, beacons and iplementations
    /// @return factory The addresses of the fully deployed orchestrator factory. All other addresses should be accessible from this.
    function run() public virtual returns (address factory) {
        // Deploy implementation contracts.
        orchestrator = deployOrchestrator.run();
        simplePaymentProcessor = deploySimplePaymentProcessor.run();
        fundingManager = deployRebasingFundingManager.run();
        authorizer = deployRoleAuthorizer.run();

        moduleFactory = deployModuleFactory.run();
        orchestratorFactory =
            deployOrchestratorFactory.run(orchestrator, moduleFactory);

        bountyManager = deployBountyManager.run();

        // Create beacons, set implementations and set metadata.
        paymentProcessorBeacon = deployAndSetUpBeacon.run(
            simplePaymentProcessor, moduleFactory, paymentProcessorMetadata
        );
        fundingManagerBeacon = deployAndSetUpBeacon.run(
            fundingManager, moduleFactory, fundingManagerMetadata
        );
        authorizerBeacon = deployAndSetUpBeacon.run(
            authorizer, moduleFactory, authorizerMetadata
        );
        bountyManagerBeacon = deployAndSetUpBeacon.run(
            bountyManager, moduleFactory, bountyManagerMetadata
        );

        return (orchestratorFactory);
    }
}
