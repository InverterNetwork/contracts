// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

//Modules
import {
    IAuthorizer,
    ListAuthorizer
} from "src/modules/governance/ListAuthorizer.sol";

import {
    IPaymentProcessor,
    PaymentProcessor
} from "src/modules/PaymentProcessor.sol";

import {
    IMilestoneManager,
    MilestoneManager
} from "src/modules/MilestoneManager.sol";

//Beacon
import {IBeacon, Beacon} from "src/factories/beacon/Beacon.sol";

//IModule
import {IModule} from "src/modules/base/IModule.sol";

//Module Factory
import {IModuleFactory, ModuleFactory} from "src/factories/ModuleFactory.sol";

//Proposal Factory
import {
    IProposalFactory,
    ProposalFactory
} from "src/factories/ProposalFactory.sol";

//Token import
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

//Proposal
import {IProposal, Proposal} from "src/proposal/Proposal.sol";

/**
 * e2e PoC test to show how to create a new proposal via the {ProposalFactory}.
 */
contract ProposalCreation is Test {
    //Module Templates
    IAuthorizer authorizerTemplate; //This is just the template thats referenced in the Factory later
    IPaymentProcessor paymentProcessorTemplate; //Just a template
    IMilestoneManager milestoneManagerTemplate; //Just a template

    //Module Beacons
    Beacon authorizerBeacon;
    Beacon paymentProcessorBeacon;
    Beacon milestoneManagerBeacon;

    //Metadata for Modules
    IModule.Metadata authorizerMetadata;
    IModule.Metadata paymentProcessorMetadata;
    IModule.Metadata milestoneManagerMetadata;

    //Module Factory
    IModuleFactory moduleFactory;

    //Proposal Template
    IProposal proposalTemplate; //Just a template

    //Proposal Factory
    IProposalFactory proposalFactory;

    // This function sets up all necessary components needed for the creation of a proposal.
    // Components are:
    // -Authorizer: A Module that declares who can access the main functionalities of the proposal
    // -PaymentProcessor: A Module that enables Token distribution
    // -MilestoneManager: A Module that enables Declaration of Milestones and upon fullfillment, uses the Payment Processor for salary distributions
    // -Beacons: A Proxy Contract structure that enables to update all proxy contracts at the same time (EIP-1967)
    // -ModuleFactory: A factory that creates Modules. Modules have to be registered with Metadata and the intended beacon, which contains the module template, for it to be used
    // -ProposalFactory: A Factory that creates Proposals. Needs to have a Proposal Template and a module factory as a reference.

    function setUp() public {
        //Create Module Templates
        authorizerTemplate = new ListAuthorizer();
        paymentProcessorTemplate = new PaymentProcessor();
        milestoneManagerTemplate = new MilestoneManager();

        //Create Beacons for every Module
        authorizerBeacon = new Beacon();
        paymentProcessorBeacon = new Beacon();
        milestoneManagerBeacon = new Beacon();

        //Upgrade Beacons to correct implementation
        authorizerBeacon.upgradeTo(address(authorizerTemplate));
        paymentProcessorBeacon.upgradeTo(address(paymentProcessorTemplate));
        milestoneManagerBeacon.upgradeTo(address(milestoneManagerTemplate));

        //Create Metadata for the Modules
        authorizerMetadata = IModule.Metadata(
            1, 1, "https://github.com/inverter/authorizer", "Authorizer"
        );
        paymentProcessorMetadata = IModule.Metadata(
            1,
            1,
            "https://github.com/inverter/payment-processor",
            "PaymentProcessor"
        );
        milestoneManagerMetadata = IModule.Metadata(
            1,
            1,
            "https://github.com/inverter/milestone-manager",
            "MilestoneManager"
        );

        //Create Module Factory
        moduleFactory = new ModuleFactory();

        //Register Module Metadata in ModuleFactory
        moduleFactory.registerMetadata(
            authorizerMetadata, IBeacon(authorizerBeacon)
        );
        moduleFactory.registerMetadata(
            paymentProcessorMetadata, IBeacon(paymentProcessorBeacon)
        );
        moduleFactory.registerMetadata(
            milestoneManagerMetadata, IBeacon(milestoneManagerBeacon)
        );

        //Create proposal template
        proposalTemplate = new Proposal();

        //Create ProposalFactory
        proposalFactory = new ProposalFactory(
            address(proposalTemplate),
            address(moduleFactory)
        );
    }

    // This function creates a new Proposal
    // For this we create a few config files, that we'll later use in the Proposalfactory:
    // -proposalFactoryConfig: Contains the owner and paymentToken address
    // -authorizerFactoryConfig: Contains initially Authorized Addresses, that can use onlyAuthorized functions in the proposal
    //                           Notice that we have to decrypt the initialAuthorizedAddresses into a bytes format for correct
    //                           creation of the module in the ModuleFactory
    // -paymentProcessorFactoryConfig: Just signals the Factory, that we want to integrate the PaymentProcessor here
    // -optionalModules: This array would contain further moduleConfigs in the same styling like before to signal
    //                   the proposalFactory that we want to integrate the defined modules.
    function createNewProposal() public returns (IProposal) {
        //The Token used for Payment processes in the proposal
        // Could be WEI or USDC or other ERC20.
        IERC20 paymentToken = new ERC20Mock("Mock Token", "MOCK");

        // Create ProposalConfig instance.
        IProposalFactory.ProposalConfig memory proposalFactoryConfig =
        IProposalFactory.ProposalConfig({
            owner: address(this),
            token: paymentToken
        });

        //Create ModuleConfig for Authorizer
        address[] memory initialAuthorizedAddresses = new address[](1);
        initialAuthorizedAddresses[0] = address(this);

        IProposalFactory.ModuleConfig memory authorizerFactoryConfig =
        IProposalFactory.ModuleConfig(
            authorizerMetadata, abi.encode(initialAuthorizedAddresses)
        );

        //Create ModuleConfig for PaymentProcessor
        IProposalFactory.ModuleConfig memory paymentProcessorFactoryConfig =
            IProposalFactory.ModuleConfig(paymentProcessorMetadata, bytes(""));

        //Create optionalModule array
        //We keep it empty for now, because Authorizer and PaymentProcessor are the only necessary Modules
        //The ModuleConfig structure would follow the structure shown above
        IProposalFactory.ModuleConfig[] memory optionalModules =
            new IProposalFactory.ModuleConfig[](0);

        //Create proposal using the different needed configs
        IProposal proposal = proposalFactory.createProposal(
            proposalFactoryConfig,
            authorizerFactoryConfig,
            paymentProcessorFactoryConfig,
            optionalModules
        );

        return proposal;
    }

    //Just a formal test to see the use case of creating a new Proposal
    function testCreateNewProposal() public {
        //See createNewProposal()
        createNewProposal();
    }

    //We're adding and removing a Module during the lifetime of the proposal
    function testManageModulesLiveOnPorposal() public {
        //Create Proposal
        IProposal proposal = createNewProposal();

        //--------------------------------------------------------------------------------
        // Adding Module

        //Create milestoneManagerConfigdata
        //Note: This bytes array is used for transmitting data in a generalized way
        //      to the modules during they initilization via the modulefactory
        //      Some Modules might need additional Deployment/Configuration data
        bytes memory milestoneManagerConfigdata = bytes("");

        //Create the module via the moduleFactory
        address milestoneManager = moduleFactory.createModule(
            milestoneManagerMetadata, proposal, milestoneManagerConfigdata
        );

        //Add Module to the proposal
        proposal.addModule(milestoneManager);

        //--------------------------------------------------------------------------------
        // Removing Module

        //Note: This function is ideally called via the frontend, see the documentation of the getPreviousModule Function
        address previousModule = proposal.getPreviousModule(milestoneManager);

        proposal.removeModule(previousModule, milestoneManager);
    }

    //We're adding and removing a Contributor here
    function testManageContributors() public {
        //Create Proposal
        IProposal proposal = createNewProposal();

        //--------------------------------------------------------------------------------
        // Add Contributor

        //Set example Contributor
        address who = address(0xA);
        string memory name = "John Doe";
        string memory role = "Role";
        uint salary = 1 ether;

        //Add Contributor -> who
        proposal.addContributor(who, name, role, salary);

        //--------------------------------------------------------------------------------
        // Remove Contributor

        //Remove Contributor -> who

        //Note: This function is ideally called via the frontend, see the documentation of the getPreviousModule Function
        address previousContributor = proposal.getPreviousContributor(who);

        proposal.removeContributor(previousContributor, who);
    }
}
