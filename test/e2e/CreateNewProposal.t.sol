// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

//Modules
import {
    IFundingManager,
    RebasingFundingManager
} from "src/modules/fundingManager/RebasingFundingManager.sol";

import {
    IAuthorizer,
    ListAuthorizer
} from "src/modules/authorizer/ListAuthorizer.sol";

import {
    IPaymentProcessor,
    SimplePaymentProcessor
} from "src/modules/paymentProcessor/SimplePaymentProcessor.sol";

import {
    IMilestoneManager,
    MilestoneManager
} from "src/modules/logicModule/MilestoneManager.sol";

import {
    IMetadataManager, MetadataManager
} from "src/modules/MetadataManager.sol";

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
    IFundingManager fundingManagerTemplate; //This is just the template thats referenced in the Factory later
    IAuthorizer authorizerTemplate; //Just a template
    IPaymentProcessor paymentProcessorTemplate; //Just a template
    IMilestoneManager milestoneManagerTemplate; //Just a template
    IMetadataManager metadataManagerTemplate; //Just a template

    //Module Beacons
    Beacon fundingManagerBeacon;
    Beacon authorizerBeacon;
    Beacon paymentProcessorBeacon;
    Beacon milestoneManagerBeacon;
    Beacon metadataManagerBeacon;

    //Metadata for Modules
    IModule.Metadata fundingManagerMetadata;
    IModule.Metadata authorizerMetadata;
    IModule.Metadata paymentProcessorMetadata;
    IModule.Metadata milestoneManagerMetadata;
    IModule.Metadata metadataManagerMetadata;

    //Proposal Metadata
    IMetadataManager.ManagerMetadata ownerMetadata;
    IMetadataManager.ProposalMetadata proposalMetadata;
    IMetadataManager.MemberMetadata[] teamMetadata;

    //Module Factory
    IModuleFactory moduleFactory;

    //Proposal Template
    IProposal proposalTemplate; //Just a template

    //Proposal Factory
    IProposalFactory proposalFactory;

    // This function sets up all necessary components needed for the creation of a proposal.
    // Components are:
    // -Authorizer: A Module that declares who can access the main functionalities of the proposal
    // -SimplePaymentProcessor: A Module that enables Token distribution
    // -MilestoneManager: A Module that enables Declaration of Milestones and upon fullfillment, uses the Payment Processor for salary distributions
    // -MetadataManager: A Module contains metadata for the proposal
    // -Beacons: A Proxy Contract structure that enables to update all proxy contracts at the same time (EIP-1967)
    // -ModuleFactory: A factory that creates Modules. Modules have to be registered with Metadata and the intended beacon, which contains the module template, for it to be used
    // -ProposalFactory: A Factory that creates Proposals. Needs to have a Proposal Template and a module factory as a reference.

    function setUp() public {
        //==========================================
        //Create Beacons

        //Create Module Templates
        fundingManagerTemplate = new RebasingFundingManager();
        authorizerTemplate = new ListAuthorizer();
        paymentProcessorTemplate = new SimplePaymentProcessor();
        milestoneManagerTemplate = new MilestoneManager();
        metadataManagerTemplate = new MetadataManager();

        //Create Beacons for every Module
        fundingManagerBeacon = new Beacon();
        authorizerBeacon = new Beacon();
        paymentProcessorBeacon = new Beacon();
        milestoneManagerBeacon = new Beacon();
        metadataManagerBeacon = new Beacon();

        //Upgrade Beacons to correct implementation
        fundingManagerBeacon.upgradeTo(address(fundingManagerTemplate));
        authorizerBeacon.upgradeTo(address(authorizerTemplate));
        paymentProcessorBeacon.upgradeTo(address(paymentProcessorTemplate));
        milestoneManagerBeacon.upgradeTo(address(milestoneManagerTemplate));
        metadataManagerBeacon.upgradeTo(address(metadataManagerTemplate));

        //==========================================
        //Setup Factory

        //Create Metadata for the Modules
        fundingManagerMetadata = IModule.Metadata(
            1,
            1,
            "https://github.com/inverter/funding-manager",
            "FundingManager"
        );
        authorizerMetadata = IModule.Metadata(
            1, 1, "https://github.com/inverter/authorizer", "Authorizer"
        );
        paymentProcessorMetadata = IModule.Metadata(
            1,
            1,
            "https://github.com/inverter/payment-processor",
            "SimplePaymentProcessor"
        );
        milestoneManagerMetadata = IModule.Metadata(
            1,
            1,
            "https://github.com/inverter/milestone-manager",
            "MilestoneManager"
        );

        metadataManagerMetadata = IModule.Metadata(
            1,
            1,
            "https://github.com/inverter/metadata-manager",
            "MetadataManager"
        );

        //Create Module Factory
        moduleFactory = new ModuleFactory();

        //Register Module Metadata in ModuleFactory
        moduleFactory.registerMetadata(
            fundingManagerMetadata, IBeacon(fundingManagerBeacon)
        );
        moduleFactory.registerMetadata(
            authorizerMetadata, IBeacon(authorizerBeacon)
        );
        moduleFactory.registerMetadata(
            paymentProcessorMetadata, IBeacon(paymentProcessorBeacon)
        );
        moduleFactory.registerMetadata(
            milestoneManagerMetadata, IBeacon(milestoneManagerBeacon)
        );
        moduleFactory.registerMetadata(
            metadataManagerMetadata, IBeacon(metadataManagerBeacon)
        );

        //==========================================
        //Set up Proposal Metadata

        ownerMetadata = IMetadataManager.ManagerMetadata(
            "Name", address(0xBEEF), "TwitterHandle"
        );

        proposalMetadata = IMetadataManager.ProposalMetadata(
            "Title",
            "DescriptionShort",
            "DescriptionLong",
            new string[](0),
            new string[](0)
        );

        proposalMetadata.externalMedias.push("externalMedia1");
        proposalMetadata.externalMedias.push("externalMedia2");
        proposalMetadata.externalMedias.push("externalMedia3");

        proposalMetadata.categories.push("category1");
        proposalMetadata.categories.push("category2");
        proposalMetadata.categories.push("category3");

        teamMetadata.push(
            IMetadataManager.MemberMetadata(
                "Name", address(0xBEEF), "Something"
            )
        );

        //==========================================
        //Set up Proposal Factory

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
    // -paymentProcessorFactoryConfig: Just signals the Factory, that we want to integrate the SimplePaymentProcessor here
    // -optionalModules: This array contains further moduleConfigs in the same styling like before to signal
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

        IProposalFactory.ModuleConfig memory fundingManagerFactoryConfig =
        IProposalFactory.ModuleConfig(
            fundingManagerMetadata, abi.encode(address(paymentToken))
        );

        //Create ModuleConfig for Authorizer
        address[] memory initialAuthorizedAddresses = new address[](1);
        initialAuthorizedAddresses[0] = address(this);

        IProposalFactory.ModuleConfig memory authorizerFactoryConfig =
        IProposalFactory.ModuleConfig(
            authorizerMetadata, abi.encode(initialAuthorizedAddresses)
        );

        //Create ModuleConfig for SimplePaymentProcessor
        IProposalFactory.ModuleConfig memory paymentProcessorFactoryConfig =
            IProposalFactory.ModuleConfig(paymentProcessorMetadata, bytes(""));

        //Create optionalModule array

        //Technically Authorizer and SimplePaymentProcessor are the only necessary Modules, but we'll inlcude the metadata manager as an example

        //Note: Its possible to submit a zero size array too
        IProposalFactory.ModuleConfig[] memory optionalModules =
            new IProposalFactory.ModuleConfig[](1);

        //Add MetadataManager as a optional Module
        optionalModules[0] = IProposalFactory.ModuleConfig(
            metadataManagerMetadata,
            abi.encode(ownerMetadata, proposalMetadata, teamMetadata)
        );

        //Create proposal using the different needed configs
        IProposal proposal = proposalFactory.createProposal(
            proposalFactoryConfig,
            fundingManagerFactoryConfig,
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
        uint SALARY_PRECISION = 100_000_000;
        uint FEE_PERCENTAGE = 1_000_000; //1%
        address FEE_TREASURY = makeAddr("treasury");

        bytes memory milestoneManagerConfigdata =
            abi.encode(SALARY_PRECISION, FEE_PERCENTAGE, FEE_TREASURY);

        //Create the module via the moduleFactory
        address milestoneManager = moduleFactory.createModule(
            milestoneManagerMetadata, proposal, milestoneManagerConfigdata
        );

        //Add Module to the proposal
        proposal.addModule(milestoneManager);

        //--------------------------------------------------------------------------------
        // Removing Module
        proposal.removeModule(milestoneManager);
    }
}
