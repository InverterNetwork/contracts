// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

//Internal Dependencies
import {
    E2ETest,
    IOrchestratorFactory,
    IOrchestrator,
    ModuleFactory
} from "test/e2e/E2ETest.sol";

//SuT
import {IOrchestrator, Orchestrator} from "src/orchestrator/Orchestrator.sol";

// Modules that are used in this E2E test
import {IPaymentProcessor} from
    "src/modules/paymentProcessor/IPaymentProcessor.sol";
import {IFundingManager} from "src/modules/fundingManager/IFundingManager.sol";
import {IAuthorizer} from "src/modules/authorizer/IAuthorizer.sol";
import {
    IBountyManager,
    BountyManager
} from "src/modules/logicModule/BountyManager.sol";
import {
    IMetadataManager,
    MetadataManager
} from "src/modules/utils/MetadataManager.sol";

//Beacon
import {Beacon} from "src/factories/beacon/Beacon.sol";

/**
 * e2e PoC test to show how to create a new orchestrator via the {OrchestratorFactory}.
 */
contract OrchestratorE2E is E2ETest {
    // Module Configurations for the current E2E test. Should be filled during setUp() call.
    IOrchestratorFactory.ModuleConfig[] moduleConfigurations;

    //Orchestrator Metadata
    IMetadataManager.ManagerMetadata ownerMetadata;
    IMetadataManager.OrchestratorMetadata orchestratorMetadata;
    IMetadataManager.MemberMetadata[] teamMetadata;

    function setUp() public override {
        // Setup common E2E framework
        super.setUp();

        // Set Up individual Modules the E2E test is going to use and store their configurations:
        // NOTE: It's important to store the module configurations in order, since _create_E2E_Orchestrator() will copy from the array.
        // The order should be:
        //      moduleConfigurations[0]  => FundingManager
        //      moduleConfigurations[1]  => Authorizer
        //      moduleConfigurations[2]  => PaymentProcessor
        //      moduleConfigurations[3:] => Additional Logic Modules

        // FundingManager
        setUpRebasingFundingManager();
        moduleConfigurations.push(
            IOrchestratorFactory.ModuleConfig(
                rebasingFundingManagerMetadata,
                abi.encode(address(token)),
                abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
            )
        );

        // Authorizer
        setUpRoleAuthorizer();
        moduleConfigurations.push(
            IOrchestratorFactory.ModuleConfig(
                roleAuthorizerMetadata,
                abi.encode(address(this), address(this)),
                abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
            )
        );

        // PaymentProcessor
        setUpSimplePaymentProcessor();
        moduleConfigurations.push(
            IOrchestratorFactory.ModuleConfig(
                simplePaymentProcessorMetadata,
                bytes(""),
                abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
            )
        );

        // We also set up the BountyManager, even though we'll add it later
        setUpBountyManager();

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
    }

    //We're adding and removing a Module during the lifetime of the orchestrator
    function testManageModulesLiveOnPorposal() public {
        // address(this) creates a new orchestrator.
        IOrchestratorFactory.OrchestratorConfig memory orchestratorConfig =
        IOrchestratorFactory.OrchestratorConfig({
            owner: address(this),
            token: token
        });

        //Create Orchestrator
        IOrchestrator orchestrator =
            _create_E2E_Orchestrator(orchestratorConfig, moduleConfigurations);

        //------------------------------------------------------------------------------------------------
        // Adding Module

        uint modulesBefore = orchestrator.modulesSize(); // We store the number of modules the orchestrator has

        //Create the module via the moduleFactory
        address bountyManager = moduleFactory.createModule(
            bountyManagerMetadata, orchestrator, bytes("")
        );

        //Add Module to the orchestrator
        orchestrator.addModule(bountyManager);

        assertEq((modulesBefore + 1), orchestrator.modulesSize()); // The orchestrator now has one more module

        //------------------------------------------------------------------------------------------------
        // Removing Module
        orchestrator.removeModule(bountyManager);

        assertEq(modulesBefore, orchestrator.modulesSize()); // The orchestrator is back to the original number of modules

        //------------------------------------------------------------------------------------------------
        //In case there is a need to replace the  paymentProcessor / fundingManager / authorizer

        //Create the new modules via the moduleFactory
        address newPaymentProcessor = moduleFactory.createModule(
            simplePaymentProcessorMetadata, orchestrator, bytes("")
        );

        address newFundingManager = moduleFactory.createModule(
            rebasingFundingManagerMetadata,
            orchestrator,
            abi.encode(address(orchestrator.fundingManager().token()))
        );

        address[] memory initialAuthorizedAddresses = new address[](1);
        initialAuthorizedAddresses[0] = address(this);

        address newAuthorizer = moduleFactory.createModule(
            roleAuthorizerMetadata,
            orchestrator,
            abi.encode(initialAuthorizedAddresses)
        );

        modulesBefore = orchestrator.modulesSize(); // We store the number of modules the orchestrator has

        //We store the original module addresses
        address originalPaymentProcessor =
            address(orchestrator.paymentProcessor());
        address originalFundingManager = address(orchestrator.fundingManager());
        address originalAuthorizer = address(orchestrator.authorizer());

        //Replace the old modules with the new ones
        orchestrator.setPaymentProcessor(IPaymentProcessor(newPaymentProcessor));
        orchestrator.setFundingManager(IFundingManager(newFundingManager));
        orchestrator.setAuthorizer(IAuthorizer(newAuthorizer));

        //Assert post-state
        assertEq(modulesBefore, orchestrator.modulesSize()); // The orchestrator is back to the original number of modules

        assertEq(newPaymentProcessor, address(orchestrator.paymentProcessor()));
        assertEq(newFundingManager, address(orchestrator.fundingManager()));
        assertEq(newAuthorizer, address(orchestrator.authorizer()));

        assertFalse(orchestrator.isModule(originalPaymentProcessor));
        assertFalse(orchestrator.isModule(originalFundingManager));
        assertFalse(orchestrator.isModule(originalAuthorizer));
    }
}
