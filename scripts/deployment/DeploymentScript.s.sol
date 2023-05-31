// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {IModule} from "src/modules/base/IModule.sol";
import {Proposal} from "src/proposal/Proposal.sol";
import {SimplePaymentProcessor} from "src/modules/SimplePaymentProcessor.sol";
import {MilestoneManager} from "src/modules/MilestoneManager.sol";
import {ListAuthorizer} from "src/modules/governance/ListAuthorizer.sol";

import {ModuleFactory} from "src/factories/ModuleFactory.sol";
import {ProposalFactory, IProposalFactory} from "src/factories/ProposalFactory.sol";

import {Beacon, IBeacon} from "src/factories/beacon/Beacon.sol";

contract DeploymentScript is Script {
    address deployer = vm.envUint("PROPOSAL_OWNER_ADDRESS");
    address paymentProcessorBeaconOwner = vm.envUint("PPBO_ADDRESS");
    address milestoneManagerBeaconOwner = vm.envUint("MMBO_ADDRESS");
    address authorizerBeaconOwner = vm.envUint("ABO_ADDRESS");

    address[] authorizerAddresses=[address(0xBEEF)];

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

    IModule.Metadata paymentProcessorMetadata = IModule.Metadata( 1, 1, "https://github.com/inverter/payment-processor", "SimplePaymentProcessor");
    IProposalFactory.ModuleConfig paymentProcessorFactoryConfig = IProposalFactory.ModuleConfig(paymentProcessorMetadata, bytes(""));

    IModule.Metadata milestoneManagerMetadata = IModule.Metadata(1, 1, "https://github.com/inverter/milestone-manager", "MilestoneManager");
    IProposalFactory.ModuleConfig milestoneManagerFactoryConfig = IProposalFactory.ModuleConfig(milestoneManagerMetadata, abi.encode(100_000_000, 1_000_000, makeAddr("treasury")));
    
    IModule.Metadata authorizerMetadata = IModule.Metadata(1, 1, "https://github.com/inverter/authorizer", "Authorizer");
    IProposalFactory.ModuleConfig authorizerFactoryConfig = IProposalFactory.ModuleConfig(authorizerMetadata, abi.encode(authorizerAddresses));

    uint256 deployerPrivateKey = vm.envUint("PROPOSAL_OWNER_PRIVATE_KEY");
    uint256 paymentProcessorBeaconOwnerPrivateKey = vm.envUint("PPBO_PRIVATE_KEY");
    uint256 milestoneManagerBeaconOwnerPrivateKey = vm.envUint("MMBO_PRIVATE_KEY");
    uint256 authorizerBeaconOwnerPrivateKey = vm.envUint("ABO_PRIVATE_KEY");

    function run() public virtual {        
        vm.startBroadcast(deployerPrivateKey);
        {
            proposal = new Proposal();
            simplePaymentProcessor = new SimplePaymentProcessor();
            milestoneManager = new MilestoneManager();
            authorizer = new ListAuthorizer();
            moduleFactory = new ModuleFactory();
            proposalFactory = new ProposalFactory(address(proposal), address(moduleFactory));
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
        vm.startBroadcast(paymentProcessorBeaconOwner);
        paymentProcessorBeacon.upgradeTo(address(simplePaymentProcessor));
        vm.stopBroadcast();
        
        vm.startBroadcast(milestoneManagerBeaconOwner);
        milestoneManagerBeacon.upgradeTo(address(milestoneManager));
        vm.stopBroadcast();
        
        vm.startBroadcast(authorizerBeaconOwner);
        authorizerBeacon.upgradeTo(address(authorizer));
        vm.stopBroadcast();

        // Register modules at moduleFactory.
        vm.startBroadcast(deployer);
        moduleFactory.registerMetadata(paymentProcessorMetadata, IBeacon(paymentProcessorBeacon));
        moduleFactory.registerMetadata(milestoneManagerMetadata, IBeacon(milestoneManagerBeacon));
        moduleFactory.registerMetadata(authorizerMetadata, IBeacon(authorizerBeacon));
        vm.stopBroadcast();

        // Logging the deployed addresses
        console2.log("Proposal Implemntation Contract Deployed at: ", address(proposal));
        console2.log("Simple Payment Processor Implementation Contract Deployed at: ", address(simplePaymentProcessor));
        console2.log("Milestone Manager Implementation Contract Deployed at: ", address(milestoneManager));
        console2.log("List Authorizer Implementation Contract Deployed at: ", address(authorizer));
        console2.log("Payment Processor Beacon Deployed at: ", address(paymentProcessorBeacon));
        console2.log("Milestone Manager Beacon Deployed at: ", address(milestoneManagerBeacon));
        console2.log("List Authorizer Beacon Deployed at: ", address(authorizerBeacon));
        console2.log("Proposal Factory Deployed at: ", address(proposalFactory));
        console2.log("Module Factory Deployed at: ", address(moduleFactory));
    }
}
