// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {IModule} from "src/modules/base/IModule.sol";
import {Proposal} from "src/proposal/Proposal.sol";

import {RebasingFundingManager} from
    "src/modules/fundingManager/RebasingFundingManager.sol";

import {SimplePaymentProcessor} from
    "src/modules/paymentProcessor/SimplePaymentProcessor.sol";
import {MilestoneManager} from "src/modules/logicModule/MilestoneManager.sol";
import {ListAuthorizer} from "src/modules/authorizer/ListAuthorizer.sol";

import {ModuleFactory} from "src/factories/ModuleFactory.sol";
import {
    ProposalFactory,
    IProposalFactory
} from "src/factories/ProposalFactory.sol";

import {Beacon, IBeacon} from "src/factories/beacon/Beacon.sol";

contract DeploymentScript is Script {
    address[] authorizerAddresses = [address(0xBEEF)];

    address deploymentScript = address(this);

    Proposal proposal;
    SimplePaymentProcessor simplePaymentProcessor;
    MilestoneManager milestoneManager;
    RebasingFundingManager fundingManager;
    ListAuthorizer authorizer;

    ModuleFactory moduleFactory;
    ProposalFactory proposalFactory;

    Beacon paymentProcessorBeacon;
    Beacon milestoneManagerBeacon;
    Beacon fundingManagerBeacon;
    Beacon authorizerBeacon;

    IModule.Metadata paymentProcessorMetadata = IModule.Metadata(
        1,
        1,
        "https://github.com/inverter/payment-processor",
        "SimplePaymentProcessor"
    );
    IProposalFactory.ModuleConfig paymentProcessorFactoryConfig =
        IProposalFactory.ModuleConfig(paymentProcessorMetadata, bytes(""));

    IModule.Metadata milestoneManagerMetadata = IModule.Metadata(
        1,
        1,
        "https://github.com/inverter/milestone-manager",
        "MilestoneManager"
    );
    IProposalFactory.ModuleConfig milestoneManagerFactoryConfig =
    IProposalFactory.ModuleConfig(
        milestoneManagerMetadata,
        abi.encode(100_000_000, 1_000_000, makeAddr("treasury"))
    );

    IModule.Metadata fundingManagerMetadata = IModule.Metadata(
        1, 1, "https://github.com/inverter/funding-manager", "FundingManager"
    );

    IModule.Metadata authorizerMetadata = IModule.Metadata(
        1, 1, "https://github.com/inverter/authorizer", "Authorizer"
    );
    IProposalFactory.ModuleConfig authorizerFactoryConfig = IProposalFactory
        .ModuleConfig(authorizerMetadata, abi.encode(authorizerAddresses));

    uint deployerPrivateKey = vm.envUint("ANVIL_PRIVATE_KEY");
    uint paymentProcessorBeaconOwnerPrivateKey = vm.envUint("PPBO_PRIVATE_KEY");
    uint milestoneManagerBeaconOwnerPrivateKey = vm.envUint("MMBO_PRIVATE_KEY");
    uint fundingManagerBeaconOwnerPrivateKey = vm.envUint("FMBO_PRIVATE_KEY");
    uint authorizerBeaconOwnerPrivateKey = vm.envUint("ABO_PRIVATE_KEY");

    function run() public virtual {
        vm.startBroadcast(deployerPrivateKey);
        {
            proposal = new Proposal();
            simplePaymentProcessor = new SimplePaymentProcessor();
            milestoneManager = new MilestoneManager();
            fundingManager = new RebasingFundingManager();
            authorizer = new ListAuthorizer();
            moduleFactory = new ModuleFactory();
            proposalFactory =
                new ProposalFactory(address(proposal), address(moduleFactory));
        }
        vm.stopBroadcast();

        // Create beacon and set implementation.

        vm.startBroadcast(paymentProcessorBeaconOwnerPrivateKey);
        {
            paymentProcessorBeacon = new Beacon();
            paymentProcessorBeacon.upgradeTo(address(simplePaymentProcessor));
        }
        vm.stopBroadcast();

        vm.startBroadcast(milestoneManagerBeaconOwnerPrivateKey);
        {
            milestoneManagerBeacon = new Beacon();
            milestoneManagerBeacon.upgradeTo(address(milestoneManager));
        }
        vm.stopBroadcast();

        vm.startBroadcast(fundingManagerBeaconOwnerPrivateKey);
        {
            fundingManagerBeacon = new Beacon();
            fundingManagerBeacon.upgradeTo(address(fundingManager));
        }
        vm.stopBroadcast();

        vm.startBroadcast(authorizerBeaconOwnerPrivateKey);
        {
            authorizerBeacon = new Beacon();
            authorizerBeacon.upgradeTo(address(authorizer));
        }
        vm.stopBroadcast();

        // Register modules at moduleFactory.
        vm.startBroadcast(deployerPrivateKey);

        moduleFactory.registerMetadata(
            paymentProcessorMetadata, IBeacon(paymentProcessorBeacon)
        );
        moduleFactory.registerMetadata(
            milestoneManagerMetadata, IBeacon(milestoneManagerBeacon)
        );
        moduleFactory.registerMetadata(
            fundingManagerMetadata, IBeacon(fundingManagerBeacon)
        );
        moduleFactory.registerMetadata(
            authorizerMetadata, IBeacon(authorizerBeacon)
        );
        vm.stopBroadcast();

        // Logging the deployed addresses
        console2.log("Proposal Contract Deployed at: ", address(proposal));
        console2.log(
            "Simple Payment Processor Contract Deployed at: ",
            address(simplePaymentProcessor)
        );
        console2.log(
            "Milestone Manager Contract Deployed at: ",
            address(milestoneManager)
        );
        console2.log(
            "Payment Processor Beacon Deployed at: ",
            address(paymentProcessorBeacon)
        );
        console2.log(
            "Milestone Manager Beacon Deployed at: ",
            address(milestoneManagerBeacon)
        );
        console2.log(
            "Rebasing Funding Manager Beacon Deployed at: ",
            address(fundingManagerBeacon)
        );
        console2.log(
            "List Authorizer Beacon Deployed at: ", address(authorizerBeacon)
        );
    }
}
