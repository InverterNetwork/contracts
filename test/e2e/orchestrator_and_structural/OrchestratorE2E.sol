// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies
import {
    E2ETest,
    IOrchestratorFactory_v1,
    IOrchestrator_v1,
    ModuleFactory_v1
} from "test/e2e/E2ETest.sol";

// SuT
import {
    IOrchestrator_v1,
    Orchestrator_v1
} from "src/orchestrator/Orchestrator_v1.sol";

// Modules that are used in this E2E test
import {IPaymentProcessor_v1} from
    "src/modules/paymentProcessor/IPaymentProcessor_v1.sol";
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";
import {IAuthorizer_v1} from "@aut/IAuthorizer_v1.sol";
import {
    ILM_PC_Bounties_v2, LM_PC_Bounties_v2
} from "@lm/LM_PC_Bounties_v2.sol";

// Beacon
import {InverterBeacon_v1} from "src/proxies/InverterBeacon_v1.sol";

/**
 * e2e PoC test to show how to create a new orchestrator via the {OrchestratorFactory_v1}.
 */
contract OrchestratorE2E is E2ETest {
    // Module Configurations for the current E2E test. Should be filled during setUp() call.
    IOrchestratorFactory_v1.ModuleConfig[] moduleConfigurations;

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
            IOrchestratorFactory_v1.ModuleConfig(
                rebasingFundingManagerMetadata, abi.encode(address(token))
            )
        );

        // Authorizer
        setUpRoleAuthorizer();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                roleAuthorizerMetadata, abi.encode(address(this))
            )
        );

        // PaymentProcessor
        setUpSimplePaymentProcessor();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                simplePaymentProcessorMetadata, bytes("")
            )
        );

        // We also set up the LM_PC_Bounties_v2, even though we'll add it later
        setUpBountyManager();
    }

    // We're adding and removing a Module during the lifetime of the orchestrator
    function testManageModulesLiveOnOrchestrator() public {
        // address(this) creates a new orchestrator.
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig =
        IOrchestratorFactory_v1.WorkflowConfig({
            independentUpdates: false,
            independentUpdateAdmin: address(0)
        });

        IOrchestrator_v1 orchestrator =
            _create_E2E_Orchestrator(workflowConfig, moduleConfigurations);

        uint timelock =
            Orchestrator_v1(address(orchestrator)).MODULE_UPDATE_TIMELOCK();
        //------------------------------------------------------------------------------------------
        // Adding Module

        uint modulesBefore = orchestrator.modulesSize(); // We store the number of modules the orchestrator has

        // Create the module via the moduleFactory
        address bountyManager = moduleFactory.createAndInitModule(
            bountyManagerMetadata, orchestrator, bytes(""), workflowConfig
        );

        orchestrator.initiateAddModuleWithTimelock(bountyManager);
        // skip timelock
        vm.warp(block.timestamp + timelock);

        // Add Module to the orchestrator
        orchestrator.executeAddModule(bountyManager);

        assertEq((modulesBefore + 1), orchestrator.modulesSize()); // The orchestrator now has one more module

        //------------------------------------------------------------------------------------------
        // Removing Module
        orchestrator.initiateRemoveModuleWithTimelock(bountyManager);
        // skip timelock
        vm.warp(block.timestamp + timelock);
        orchestrator.executeRemoveModule(bountyManager);

        assertEq(modulesBefore, orchestrator.modulesSize()); // The orchestrator is back to the original number of modules

        //------------------------------------------------------------------------------------------
        // In case there is a need to replace the  paymentProcessor / fundingManager / authorizer

        // Create the new modules via the moduleFactory
        address newPaymentProcessor = moduleFactory.createAndInitModule(
            simplePaymentProcessorMetadata,
            orchestrator,
            bytes(""),
            workflowConfig
        );

        address newFundingManager = moduleFactory.createAndInitModule(
            rebasingFundingManagerMetadata,
            orchestrator,
            abi.encode(address(orchestrator.fundingManager().token())),
            workflowConfig
        );

        address[] memory initialAuthorizedAddresses = new address[](1);
        initialAuthorizedAddresses[0] = address(this);

        address newAuthorizer = moduleFactory.createAndInitModule(
            roleAuthorizerMetadata,
            orchestrator,
            abi.encode(initialAuthorizedAddresses),
            workflowConfig
        );

        modulesBefore = orchestrator.modulesSize(); // We store the number of modules the orchestrator has

        // We store the original module addresses
        address originalPaymentProcessor =
            address(orchestrator.paymentProcessor());
        address originalFundingManager = address(orchestrator.fundingManager());
        address originalAuthorizer = address(orchestrator.authorizer());

        // Replace the old modules with the new ones
        orchestrator.initiateSetPaymentProcessorWithTimelock(
            IPaymentProcessor_v1(newPaymentProcessor)
        );
        vm.warp(block.timestamp + timelock);

        orchestrator.executeSetPaymentProcessor(
            IPaymentProcessor_v1(newPaymentProcessor)
        );
        orchestrator.initiateSetFundingManagerWithTimelock(
            IFundingManager_v1(newFundingManager)
        );
        vm.warp(block.timestamp + timelock);

        orchestrator.executeSetFundingManager(
            IFundingManager_v1(newFundingManager)
        );
        orchestrator.initiateSetAuthorizerWithTimelock(
            IAuthorizer_v1(newAuthorizer)
        );
        vm.warp(block.timestamp + timelock);

        orchestrator.executeSetAuthorizer(IAuthorizer_v1(newAuthorizer));

        // Assert post-state
        assertEq(modulesBefore, orchestrator.modulesSize()); // The orchestrator is back to the original number of modules

        assertEq(newPaymentProcessor, address(orchestrator.paymentProcessor()));
        assertEq(newFundingManager, address(orchestrator.fundingManager()));
        assertEq(newAuthorizer, address(orchestrator.authorizer()));

        assertFalse(orchestrator.isModule(originalPaymentProcessor));
        assertFalse(orchestrator.isModule(originalFundingManager));
        assertFalse(orchestrator.isModule(originalAuthorizer));
    }
}
