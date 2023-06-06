// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

// Import interfaces:

import {IModule} from "src/modules/base/IModule.sol";
import {IBeacon} from "src/factories/beacon/Beacon.sol";
import {IModuleFactory} from "src/factories/ModuleFactory.sol";

// Import scripts:

import {DeployAndSetUpBeacon} from "script/proxies/DeployAndSetUpBeacon.s.sol";
import {DeployModuleFactory} from "script/factories/DeployModuleFactory.s.sol";
import {DeployProposalFactory} from
    "script/factories/DeployProposalFactory.s.sol";

import {DeployProposal} from "script/proposal/DeployProposal.s.sol";
import {DeployStreamingPaymentProcessor} from
    "script/modules/paymentProcessor/DeployStreamingPaymentProcessor.s.sol";
import {DeployMilestoneManager} from
    "script/modules/DeployMilestoneManager.s.sol";
import {DeployRebasingFundingManager} from
    "script/modules/DeployRebasingFundingManager.sol";
import {DeployListAuthorizer} from
    "script/modules/governance/DeployListAuthorizer.s.sol";

contract DeploymentScript is Script {
    // ------------------------------------------------------------------------
    // Instances of Deployer Contracts

    DeployModuleFactory deployModuleFactory = new DeployModuleFactory();
    DeployProposalFactory deployProposalFactory = new DeployProposalFactory();

    DeployProposal deployProposal = new DeployProposal();
    DeployStreamingPaymentProcessor deployStreamingPaymentProcessor =
        new DeployStreamingPaymentProcessor();
    DeployMilestoneManager deployMilestoneManager = new DeployMilestoneManager();
    DeployRebasingFundingManager deployRebasingFundingManager =
        new DeployRebasingFundingManager();
    DeployListAuthorizer deployListAuthorizer = new DeployListAuthorizer();

    DeployAndSetUpBeacon deployAndSetUpBeacon = new DeployAndSetUpBeacon();

    // ------------------------------------------------------------------------
    // Deployed Contracts

    address proposal;
    address streamingPaymentProcessor;
    address milestoneManager;
    address fundingManager;
    address authorizer;

    address moduleFactory;
    address proposalFactory;

    address paymentProcessorBeacon;
    address milestoneManagerBeacon;
    address fundingManagerBeacon;
    address authorizerBeacon;

    // ------------------------------------------------------------------------
    // Module Metadata
    IModule.Metadata paymentProcessorMetadata = IModule.Metadata(
        1,
        1,
        "https://github.com/inverter/payment-processor",
        "StreamingPaymentProcessor"
    );

    IModule.Metadata milestoneManagerMetadata = IModule.Metadata(
        1,
        1,
        "https://github.com/inverter/milestone-manager",
        "MilestoneManager"
    );

    IModule.Metadata fundingManagerMetadata = IModule.Metadata(
        1, 1, "https://github.com/inverter/funding-manager", "FundingManager"
    );

    IModule.Metadata authorizerMetadata = IModule.Metadata(
        1, 1, "https://github.com/inverter/authorizer", "Authorizer"
    );

    function run() public virtual {

        // Deploy implementation contracts.
        proposal = deployProposal.run();
        streamingPaymentProcessor = deployStreamingPaymentProcessor.run();
        fundingManager = deployRebasingFundingManager.run();
        authorizer = deployListAuthorizer.run();
        milestoneManager = deployMilestoneManager.run();

        moduleFactory = deployModuleFactory.run();
        proposalFactory = deployProposalFactory.run(proposal, moduleFactory);

        // Create beacons, set implementations and set metadata.
        paymentProcessorBeacon = deployAndSetUpBeacon.run(
            streamingPaymentProcessor, moduleFactory, paymentProcessorMetadata
        );
        fundingManagerBeacon = deployAndSetUpBeacon.run(
            fundingManager, moduleFactory, fundingManagerMetadata
        );
        authorizerBeacon = deployAndSetUpBeacon.run(
            authorizer, moduleFactory, authorizerMetadata
        );
        milestoneManagerBeacon = deployAndSetUpBeacon.run(
            milestoneManager, moduleFactory, milestoneManagerMetadata
        );
    }
}
