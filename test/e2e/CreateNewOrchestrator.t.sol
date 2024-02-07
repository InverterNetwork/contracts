// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

//Modules
import {
    IFundingManager,
    RebasingFundingManager
} from "src/modules/fundingManager/RebasingFundingManager.sol";

import {
    IAuthorizer,
    RoleAuthorizer
} from "src/modules/authorizer/RoleAuthorizer.sol";

import {
    IPaymentProcessor,
    SimplePaymentProcessor
} from "src/modules/paymentProcessor/SimplePaymentProcessor.sol";

import {
    IMetadataManager,
    MetadataManager
} from "src/modules/utils/MetadataManager.sol";

//Beacon
import {IBeacon, Beacon} from "src/factories/beacon/Beacon.sol";

//IModule
import {IModule} from "src/modules/base/IModule.sol";

//Module Factory
import {IModuleFactory, ModuleFactory} from "src/factories/ModuleFactory.sol";

//Orchestrator Factory
import {
    IOrchestratorFactory,
    OrchestratorFactory
} from "src/factories/OrchestratorFactory.sol";

//Token import
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

//Orchestrator
import {IOrchestrator, Orchestrator} from "src/orchestrator/Orchestrator.sol";

//Base Modules
import {IPaymentProcessor} from
    "src/modules/paymentProcessor/IPaymentProcessor.sol";
import {IFundingManager} from "src/modules/fundingManager/IFundingManager.sol";
import {IAuthorizer} from "src/modules/authorizer/IAuthorizer.sol";
import {
    IBountyManager,
    BountyManager
} from "src/modules/logicModule/BountyManager.sol";

/**
 * e2e PoC test to show how to create a new orchestrator via the {OrchestratorFactory}.
 */
contract OrchestratorCreation is Test {
    //Module Templates
    IFundingManager fundingManagerTemplate; //This is just the template thats referenced in the Factory later
    IAuthorizer authorizerTemplate; //Just a template
    IPaymentProcessor paymentProcessorTemplate; //Just a template
    IBountyManager bountyManagerTemplate; //Just a template
    IMetadataManager metadataManagerTemplate; //Just a template

    //Module Beacons
    Beacon fundingManagerBeacon;
    Beacon authorizerBeacon;
    Beacon paymentProcessorBeacon;
    Beacon bountyManagerBeacon;
    Beacon metadataManagerBeacon;

    //Metadata for Modules
    IModule.Metadata fundingManagerMetadata;
    IModule.Metadata authorizerMetadata;
    IModule.Metadata paymentProcessorMetadata;
    IModule.Metadata bountyManagerMetadata;
    IModule.Metadata metadataManagerMetadata;

    //Orchestrator Metadata
    IMetadataManager.ManagerMetadata ownerMetadata;
    IMetadataManager.OrchestratorMetadata orchestratorMetadata;
    IMetadataManager.MemberMetadata[] teamMetadata;

    //Module Factory
    IModuleFactory moduleFactory;

    //Orchestrator Template
    IOrchestrator orchestratorTemplate; //Just a template

    //Orchestrator Factory
    IOrchestratorFactory orchestratorFactory;

    // This function sets up all necessary components needed for the creation of a orchestrator.
    // Components are:
    // -Authorizer: A Module that declares who can access the main functionalities of the orchestrator
    // -SimplePaymentProcessor: A Module that enables Token distribution
    // -MetadataManager: A Module contains metadata for the orchestrator
    // -Beacons: A Proxy Contract structure that enables to update all proxy contracts at the same time (EIP-1967)
    // -ModuleFactory: A factory that creates Modules. Modules have to be registered with Metadata and the intended beacon, which contains the module template, for it to be used
    // -OrchestratorFactory: A Factory that creates Orchestrators. Needs to have a Orchestrator Template and a module factory as a reference.

    function setUp() public {
        //==========================================
        //Create Beacons

        //Create Module Templates
        fundingManagerTemplate = new RebasingFundingManager();
        authorizerTemplate = new RoleAuthorizer();
        paymentProcessorTemplate = new SimplePaymentProcessor();
        bountyManagerTemplate = new BountyManager();
        metadataManagerTemplate = new MetadataManager();

        //Create Beacons for every Module
        fundingManagerBeacon = new Beacon();
        authorizerBeacon = new Beacon();
        paymentProcessorBeacon = new Beacon();
        bountyManagerBeacon = new Beacon();
        metadataManagerBeacon = new Beacon();

        //Upgrade Beacons to correct implementation
        fundingManagerBeacon.upgradeTo(address(fundingManagerTemplate));
        authorizerBeacon.upgradeTo(address(authorizerTemplate));
        paymentProcessorBeacon.upgradeTo(address(paymentProcessorTemplate));
        bountyManagerBeacon.upgradeTo(address(bountyManagerTemplate));
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

        metadataManagerMetadata = IModule.Metadata(
            1,
            1,
            "https://github.com/inverter/metadata-manager",
            "MetadataManager"
        );

        bountyManagerMetadata = IModule.Metadata(
            1, 1, "https://github.com/inverter/bounty-manager", "BountyManager"
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
            bountyManagerMetadata, IBeacon(bountyManagerBeacon)
        );
        moduleFactory.registerMetadata(
            metadataManagerMetadata, IBeacon(metadataManagerBeacon)
        );

        //==========================================
        //Set up Orchestrator Metadata

        ownerMetadata = IMetadataManager.ManagerMetadata(
            "Name", address(0xBEEF), "TwitterHandle"
        );

        orchestratorMetadata = IMetadataManager.OrchestratorMetadata(
            "Title",
            "DescriptionShort",
            "DescriptionLong",
            new string[](0),
            new string[](0)
        );

        orchestratorMetadata.externalMedias.push("externalMedia1");
        orchestratorMetadata.externalMedias.push("externalMedia2");
        orchestratorMetadata.externalMedias.push("externalMedia3");

        orchestratorMetadata.categories.push("category1");
        orchestratorMetadata.categories.push("category2");
        orchestratorMetadata.categories.push("category3");

        teamMetadata.push(
            IMetadataManager.MemberMetadata(
                "Name", address(0xBEEF), "Something"
            )
        );

        //==========================================
        //Set up Orchestrator Factory

        //Create orchestrator template
        orchestratorTemplate = new Orchestrator();

        //Create OrchestratorFactory
        orchestratorFactory = new OrchestratorFactory(
            address(orchestratorTemplate), address(moduleFactory)
        );
    }

    // This function creates a new Orchestrator
    // For this we create a few config files, that we'll later use in the Orchestratorfactory:
    // -orchestratorFactoryConfig: Contains the owner and paymentToken address
    // -authorizerFactoryConfig: Contains initially Authorized Addresses, that can use onlyAuthorized functions in the orchestrator
    //                           Notice that we have to decrypt the initialAuthorizedAddresses into a bytes format for correct
    //                           creation of the module in the ModuleFactory
    // -paymentProcessorFactoryConfig: Just signals the Factory, that we want to integrate the SimplePaymentProcessor here
    // -optionalModules: This array contains further moduleConfigs in the same styling like before to signal
    //                   the orchestratorFactory that we want to integrate the defined modules.
    function createNewOrchestrator() public returns (IOrchestrator) {
        //The Token used for Payment processes in the orchestrator
        // Could be WEI or USDC or other ERC20.
        IERC20 paymentToken = new ERC20Mock("Mock Token", "MOCK");

        // Create OrchestratorConfig instance.
        IOrchestratorFactory.OrchestratorConfig memory orchestratorFactoryConfig =
        IOrchestratorFactory.OrchestratorConfig({
            owner: address(this),
            token: paymentToken
        });

        bool hasDependency;
        string[] memory dependencies = new string[](0);

        IOrchestratorFactory.ModuleConfig memory fundingManagerFactoryConfig =
        IOrchestratorFactory.ModuleConfig(
            fundingManagerMetadata,
            abi.encode(address(paymentToken)),
            abi.encode(hasDependency, dependencies)
        );

        IOrchestratorFactory.ModuleConfig memory authorizerFactoryConfig =
        IOrchestratorFactory.ModuleConfig(
            authorizerMetadata,
            abi.encode(address(this), address(this)),
            abi.encode(hasDependency, dependencies)
        );

        //Create ModuleConfig for SimplePaymentProcessor
        IOrchestratorFactory.ModuleConfig memory paymentProcessorFactoryConfig =
        IOrchestratorFactory.ModuleConfig(
            paymentProcessorMetadata,
            bytes(""),
            abi.encode(hasDependency, dependencies)
        );

        //Create optionalModule array

        //Technically Authorizer and SimplePaymentProcessor are the only necessary Modules, but we'll inlcude the metadata manager as an example

        //Note: Its possible to submit a zero size array too
        IOrchestratorFactory.ModuleConfig[] memory optionalModules =
            new IOrchestratorFactory.ModuleConfig[](1);

        //Add MetadataManager as a optional Module
        optionalModules[0] = IOrchestratorFactory.ModuleConfig(
            metadataManagerMetadata,
            abi.encode(ownerMetadata, orchestratorMetadata, teamMetadata),
            abi.encode(hasDependency, dependencies)
        );

        //Create orchestrator using the different needed configs
        IOrchestrator orchestrator = orchestratorFactory.createOrchestrator(
            orchestratorFactoryConfig,
            fundingManagerFactoryConfig,
            authorizerFactoryConfig,
            paymentProcessorFactoryConfig,
            optionalModules
        );

        return orchestrator;
    }

    //Just a formal test to see the use case of creating a new Orchestrator
    function testCreateNewOrchestrator() public {
        //See createNewOrchestrator()
        createNewOrchestrator();
    }

    //We're adding and removing a Module during the lifetime of the orchestrator
    function testManageModulesLiveOnPorposal() public {
        //Create Orchestrator
        IOrchestrator orchestrator = createNewOrchestrator();

        //--------------------------------------------------------------------------------
        // Adding Module

        //Create bountyManagerConfigData
        //Note: This bytes array is used for transmitting data in a generalized way
        //      to the modules during they initilization via the modulefactory
        //      Some Modules might need additional Deployment/Configuration data

        //Create the module via the moduleFactory
        address bountyManager = moduleFactory.createModule(
            bountyManagerMetadata, orchestrator, bytes("")
        );

        //Add Module to the orchestrator
        orchestrator.addModule(bountyManager);

        //--------------------------------------------------------------------------------
        // Removing Module
        orchestrator.removeModule(bountyManager);

        //In case there is a need to replace the  paymentProcessor / fundingManager / authorizer

        //Create the modules via the moduleFactory
        address newPaymentProcessor = moduleFactory.createModule(
            paymentProcessorMetadata, orchestrator, bytes("")
        );
        address newFundingManager = moduleFactory.createModule(
            fundingManagerMetadata,
            orchestrator,
            abi.encode(address(orchestrator.fundingManager().token()))
        );

        address[] memory initialAuthorizedAddresses = new address[](1);
        initialAuthorizedAddresses[0] = address(this);

        address newAuthorizer = moduleFactory.createModule(
            authorizerMetadata,
            orchestrator,
            abi.encode(initialAuthorizedAddresses)
        );

        //Replace the old modules with the new ones
        orchestrator.setPaymentProcessor(IPaymentProcessor(newPaymentProcessor));
        orchestrator.setFundingManager(IFundingManager(newFundingManager));
        orchestrator.setAuthorizer(IAuthorizer(newAuthorizer));
    }
}
