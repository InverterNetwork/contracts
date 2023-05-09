// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {IModule} from "src/modules/base/IModule.sol";
import {Proposal} from "src/proposal/Proposal.sol";
import {SimplePaymentProcessor} from "src/modules/SimplePaymentProcessor.sol";
import {MilestoneManager} from "src/modules/MilestoneManager.sol";
import {ListAuthorizer} from "src/modules/governance/ListAuthorizer.sol";

import {ModuleFactory} from "src/factories/ModuleFactory.sol";
import {
    ProposalFactory,
    IProposalFactory
} from "src/factories/ProposalFactory.sol";

import {Beacon, IBeacon} from "src/factories/beacon/Beacon.sol";

contract DeploymentScript is Script {
    address deployer = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address paymentProcessorBeaconOwner =
        0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    address milestoneManagerBeaconOwner =
        0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
    address authorizerBeaconOwner = 0x90F79bf6EB2c4f870365E785982E1f101E93b906;

    address[] authorizerAddresses = [address(0xBEEF)];

    address deploymentScript = address(this);

    Proposal proposal;
    SimplePaymentProcessor simplePaymentProcessor;
    MilestoneManager milestoneManager;
    ModuleFactory moduleFactory;
    ProposalFactory proposalFactory;

    ListAuthorizer authorizer;

    Beacon paymentProcessorBeacon;
    Beacon milestoneManagerBeacon;
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

    IModule.Metadata authorizerMetadata = IModule.Metadata(
        1, 1, "https://github.com/inverter/authorizer", "Authorizer"
    );
    IProposalFactory.ModuleConfig authorizerFactoryConfig = IProposalFactory
        .ModuleConfig(authorizerMetadata, abi.encode(authorizerAddresses));

    uint deployerPrivateKey = vm.envUint("ANVIL_PRIVATE_KEY");
    uint paymentProcessorBeaconOwnerPrivateKey = vm.envUint("PPBO_PRIVATE_KEY");
    uint milestoneManagerBeaconOwnerPrivateKey = vm.envUint("MMBO_PRIVATE_KEY");
    uint authorizerBeaconOwnerPrivateKey = vm.envUint("ABO_PRIVATE_KEY");

    function run() public virtual {
        vm.startBroadcast(deployerPrivateKey);
        {
            proposal = new Proposal();
            simplePaymentProcessor = new SimplePaymentProcessor();
            milestoneManager = new MilestoneManager();
            authorizer = new ListAuthorizer();
            moduleFactory = new ModuleFactory();
            proposalFactory =
                new ProposalFactory(address(proposal), address(moduleFactory));
        }
        vm.stopBroadcast();

        vm.startBroadcast(paymentProcessorBeaconOwnerPrivateKey);
        {
            paymentProcessorBeacon = new Beacon();
        }
        vm.stopBroadcast();

        vm.startBroadcast(milestoneManagerBeaconOwnerPrivateKey);
        {
            milestoneManagerBeacon = new Beacon();
        }
        vm.stopBroadcast();

        vm.startBroadcast(authorizerBeaconOwnerPrivateKey);
        {
            authorizerBeacon = new Beacon();
        }
        vm.stopBroadcast();

        // Let us set beacon's implementations.
        vm.prank(paymentProcessorBeaconOwner);
        paymentProcessorBeacon.upgradeTo(address(simplePaymentProcessor));

        vm.prank(milestoneManagerBeaconOwner);
        milestoneManagerBeacon.upgradeTo(address(milestoneManager));

        vm.prank(authorizerBeaconOwner);
        authorizerBeacon.upgradeTo(address(authorizer));

        // Register modules at moduleFactory.
        vm.startPrank(deployer);
        moduleFactory.registerMetadata(
            paymentProcessorMetadata, IBeacon(paymentProcessorBeacon)
        );
        moduleFactory.registerMetadata(
            milestoneManagerMetadata, IBeacon(milestoneManagerBeacon)
        );
        moduleFactory.registerMetadata(
            authorizerMetadata, IBeacon(authorizerBeacon)
        );
        vm.stopPrank();

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
            "List Authorizer Beacon Deployed at: ", address(authorizerBeacon)
        );
    }
}
