// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {IModule} from "src/modules/base/IModule.sol";
import {Proposal} from "src/proposal/Proposal.sol";
import {StreamingPaymentProcessor} from "src/modules/paymentProcessor/StreamingPaymentProcessor.sol";

import {RebasingFundingManager} from
    "src/modules/fundingManager/RebasingFundingManager.sol";

import {MilestoneManager} from "src/modules/logicModule/MilestoneManager.sol";
import {ListAuthorizer} from "src/modules/authorizer/ListAuthorizer.sol";

import {ModuleFactory} from "src/factories/ModuleFactory.sol";
import {
    ProposalFactory,
    IProposalFactory
} from "src/factories/ProposalFactory.sol";

import {Beacon, IBeacon} from "src/factories/beacon/Beacon.sol";

contract DeploymentScript is Script {
    address deployer = vm.envAddress("PROPOSAL_OWNER_ADDRESS");
    address paymentProcessorBeaconOwner = vm.envAddress("PPBO_ADDRESS");
    address milestoneManagerBeaconOwner = vm.envAddress("MMBO_ADDRESS");
    address authorizerBeaconOwner = vm.envAddress("ABO_ADDRESS");

    address[] authorizerAddresses=[address(0xBEEF)];

    address deploymentScript = address(this);

    Proposal proposal;
    StreamingPaymentProcessor streamingPaymentProcessor;
    MilestoneManager milestoneManager;
    RebasingFundingManager fundingManager;
    ListAuthorizer authorizer;

    ModuleFactory moduleFactory;
    ProposalFactory proposalFactory;

    Beacon paymentProcessorBeacon;
    Beacon milestoneManagerBeacon;
    Beacon fundingManagerBeacon;
    Beacon authorizerBeacon;

    IModule.Metadata paymentProcessorMetadata = IModule.Metadata( 1, 1, "https://github.com/inverter/payment-processor", "StreamingPaymentProcessor");
    IProposalFactory.ModuleConfig paymentProcessorFactoryConfig = IProposalFactory.ModuleConfig(paymentProcessorMetadata, bytes(""));

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

    uint256 deployerPrivateKey = vm.envUint("PROPOSAL_OWNER_PRIVATE_KEY");
    uint256 paymentProcessorBeaconOwnerPrivateKey = vm.envUint("PPBO_PRIVATE_KEY");
    uint256 milestoneManagerBeaconOwnerPrivateKey = vm.envUint("MMBO_PRIVATE_KEY");
    uint256 authorizerBeaconOwnerPrivateKey = vm.envUint("ABO_PRIVATE_KEY");
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
            streamingPaymentProcessor = new StreamingPaymentProcessor();
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
            paymentProcessorBeacon.upgradeTo(address(streamingPaymentProcessor));
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
        vm.startBroadcast(deployer);
        moduleFactory.registerMetadata(paymentProcessorMetadata, IBeacon(paymentProcessorBeacon));
        moduleFactory.registerMetadata(milestoneManagerMetadata, IBeacon(milestoneManagerBeacon));
        moduleFactory.registerMetadata(authorizerMetadata, IBeacon(authorizerBeacon));
        moduleFactory.registerMetadata(
            fundingManagerMetadata, IBeacon(fundingManagerBeacon)
        );
        vm.stopBroadcast();
        // Logging the deployed addresses
        console2.log("Proposal Implementatio Contract Deployed at: ", address(proposal));
        console2.log(
            "Streaming Payment Processor Implementation Contract Deployed at: ",
            address(streamingPaymentProcessor)
        );
        console2.log(
            "Milestone Manager Implementation Contract Deployed at: ",
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
        console2.log("Proposal Factory Deployed at: ", address(proposalFactory));
        console2.log("Module Factory Deployed at: ", address(moduleFactory));
    }
}
