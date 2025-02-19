// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies
import {
    E2ETest,
    IOrchestratorFactory_v1,
    IOrchestrator_v1
} from "test/e2e/E2ETest.sol";

import {FM_Rebasing_v1} from "@fm/rebasing/FM_Rebasing_v1.sol";
// SuT
import {
    LM_PC_RecurringPayments_v2,
    ILM_PC_RecurringPayments_v2
} from "@lm/LM_PC_RecurringPayments_v2.sol";

import {PP_Streaming_v2} from "src/modules/paymentProcessor/PP_Streaming_v2.sol";

import {IPP_Streaming_v2} from "@pp/interfaces/IPP_Streaming_v2.sol";

import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

contract StreamingPaymentProcessorE2E is E2ETest {
    // Module Configurations for the current E2E test. Should be filled during setUp() call.
    IOrchestratorFactory_v1.ModuleConfig[] moduleConfigurations;

    //---------------------------------------------------------------------------------------------
    // Test variables

    // Users
    address alice = makeAddr("Alice");
    address bob = makeAddr("Bob");
    address charlie = makeAddr("Charlie");

    // Parameters for recurring payments
    uint startEpoch = 52;
    uint epochLength = 1 weeks; // 1 week;
    uint epochsAmount = 10;

    // Default values for the streaming payments
    uint defaultStart = 10;
    uint defaultCliff = 5;
    uint defaultEnd = 30;

    // Modules, for reference between functions
    IOrchestrator_v1 orchestrator;
    FM_Rebasing_v1 fundingManager;
    LM_PC_RecurringPayments_v2 recurringPaymentManager;
    PP_Streaming_v2 streamingPaymentProcessor;

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
        setUpStreamingPaymentProcessor();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                streamingPaymentProcessorMetadata,
                abi.encode(defaultStart, defaultCliff, defaultEnd)
            )
        );

        // Additional Logic Modules
        setUpRecurringPaymentManager();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                recurringPaymentManagerMetadata, abi.encode(1 weeks)
            )
        );
    }

    function init() private {
        //--------------------------------------------------------------------------
        // Orchestrator_v1 Initialization
        //--------------------------------------------------------------------------
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig =
        IOrchestratorFactory_v1.WorkflowConfig({
            independentUpdates: false,
            independentUpdateAdmin: address(0)
        });

        orchestrator =
            _create_E2E_Orchestrator(workflowConfig, moduleConfigurations);

        fundingManager = FM_Rebasing_v1(address(orchestrator.fundingManager()));

        address[] memory modulesList = orchestrator.listModules();
        for (uint i; i < modulesList.length; ++i) {
            if (
                ERC165Upgradeable(modulesList[i]).supportsInterface(
                    type(ILM_PC_RecurringPayments_v2).interfaceId
                )
            ) {
                recurringPaymentManager =
                    LM_PC_RecurringPayments_v2(modulesList[i]);
                break;
            }
        }

        // check if the recurringPaymentManager is initialized correctly or not.
        assertEq(recurringPaymentManager.getEpochLength(), 1 weeks);

        for (uint i; i < modulesList.length; ++i) {
            if (
                ERC165Upgradeable(modulesList[i]).supportsInterface(
                    type(IPP_Streaming_v2).interfaceId
                )
            ) {
                streamingPaymentProcessor = PP_Streaming_v2(modulesList[i]);
                break;
            }
        }

        // deposit some funds to fundingManager
        uint initialDeposit = 10e22;
        token.mint(address(this), initialDeposit);
        token.approve(address(fundingManager), initialDeposit);
        fundingManager.deposit(initialDeposit);

        // Set Block.timestamp to startEpoch
        vm.warp(startEpoch * epochLength);
    }

    function test_e2e_StreamingPaymentsLifecycleUserFunctions() public {
        init();

        // ---------------------------------------------------------------------------------------------------
        // User side of the PP_Streaming_v2

        // Create 3 different Payments

        uint paymentAmount = 1e18;

        recurringPaymentManager.addRecurringPayment(
            paymentAmount, startEpoch, alice
        );
        recurringPaymentManager.addRecurringPayment(
            paymentAmount, startEpoch, alice
        );
        recurringPaymentManager.addRecurringPayment(
            paymentAmount, startEpoch, alice
        );
        // this should create 3 streamingpayments with end timestamp of startEpoch * epochLength + 1 week
        recurringPaymentManager.trigger();

        // ----------------
        // Getter Functions

        // Check Payments
        // viewAllPaymentOrders
        // Lets see all avaialable orders
        IPP_Streaming_v2.Stream[] memory streams = streamingPaymentProcessor
            .viewAllPaymentOrders(address(recurringPaymentManager), alice);
        assertTrue(streams.length == 3);

        // startForSpecificStream
        // When does the payment start stream?
        uint start = streamingPaymentProcessor.startForSpecificStream(
            address(recurringPaymentManager), alice, streams[0]._streamId
        );
        assertTrue(start == block.timestamp);

        // endForSpecificStream
        // When is the payment end?
        uint end = streamingPaymentProcessor.endForSpecificStream(
            address(recurringPaymentManager), alice, streams[0]._streamId
        );
        assertTrue(end == startEpoch * epochLength + 1 weeks);

        // streamedAmountForSpecificStream
        // lets see what is hypotheically realeasable in half a week
        uint streamedAmount = streamingPaymentProcessor
            .streamedAmountForSpecificStream(
            address(recurringPaymentManager),
            alice,
            streams[0]._streamId,
            block.timestamp + 1 weeks / 2
        );
        assertTrue(streamedAmount == paymentAmount / 2);

        // releasedForSpecificStream
        // What got already released for that specific wallet id?
        uint released = streamingPaymentProcessor.releasedForSpecificStream(
            address(recurringPaymentManager), alice, streams[0]._streamId
        );
        assertTrue(released == 0);

        // releasableForSpecificStream
        // What is currently releasable? Emphasis on "currently"
        uint releasable = streamingPaymentProcessor.releasableForSpecificStream(
            address(recurringPaymentManager), alice, streams[0]._streamId
        );
        assertTrue(releasable == 0);

        // unclaimable
        // In case a transfer should fail this can be checked here
        uint unclaimable = streamingPaymentProcessor.unclaimable(
            address(recurringPaymentManager), address(token), alice
        );
        assertTrue(unclaimable == 0);

        // ----------------
        // Claim Functions

        // Lets do a time jump of half a week
        vm.warp(block.timestamp + 1 weeks / 2);
        // And check how much is releasable
        releasable = streamingPaymentProcessor.releasableForSpecificStream(
            address(recurringPaymentManager), alice, streams[0]._streamId
        );
        assertTrue(releasable == paymentAmount / 2);

        // Lets claim the releasable tokens for a single stream
        vm.prank(alice);
        streamingPaymentProcessor.claimForSpecificStream(
            address(recurringPaymentManager), streams[0]._streamId
        );
        // check what got released
        released = streamingPaymentProcessor.releasedForSpecificStream(
            address(recurringPaymentManager), alice, streams[0]._streamId
        );
        assertTrue(released == paymentAmount / 2);

        // Check it on the tokensied too
        assertTrue(token.balanceOf(alice) == paymentAmount / 2);

        // claim rest up to point
        // claimAll
        vm.prank(alice);
        streamingPaymentProcessor.claimAll(address(recurringPaymentManager));
        // Check token
        assertTrue(token.balanceOf(alice) == paymentAmount / 2 * 3);

        // Time Jump to the end of the week
        vm.warp(block.timestamp + 1 weeks / 2);

        // Claim all
        vm.prank(alice);
        streamingPaymentProcessor.claimAll(address(recurringPaymentManager));
        // Check token
        assertTrue(token.balanceOf(alice) == paymentAmount * 3);
    }

    function test_e2e_StreamingPaymentsLifecycleAdminFunctions() public {
        init();

        // ---------------------------------------------------------------------------------------------------
        // Admin Functions

        // Lets set up a few payments to test
        // 5 Payments
        // 3 Alice
        // 1 Bob
        // 1 Charlie

        recurringPaymentManager.addRecurringPayment(1, startEpoch, alice);
        recurringPaymentManager.addRecurringPayment(1, startEpoch, alice);
        recurringPaymentManager.addRecurringPayment(1, startEpoch, alice);
        recurringPaymentManager.addRecurringPayment(1, startEpoch, bob);
        recurringPaymentManager.addRecurringPayment(1, startEpoch, bob);
        recurringPaymentManager.addRecurringPayment(1, startEpoch, charlie);

        // Trigger starts the payments
        recurringPaymentManager.trigger();

        // Check if everyone has a running payment active
        IPP_Streaming_v2.Stream[] memory streams = streamingPaymentProcessor
            .viewAllPaymentOrders(address(recurringPaymentManager), alice);
        assertTrue(streams.length == 3);

        assertTrue(
            streamingPaymentProcessor.isActivePaymentReceiver(
                address(recurringPaymentManager), bob
            )
        );
        assertTrue(
            streamingPaymentProcessor.isActivePaymentReceiver(
                address(recurringPaymentManager), charlie
            )
        );

        // ----------------
        // RemovePayment Functions

        // remove 1 Alice
        // removePaymentForSpecificStream
        streamingPaymentProcessor.removePaymentForSpecificStream(
            address(recurringPaymentManager), alice, streams[0]._streamId
        );

        streams = streamingPaymentProcessor.viewAllPaymentOrders(
            address(recurringPaymentManager), alice
        );
        assertTrue(streams.length == 2);

        // remove all Payments from Alice
        streamingPaymentProcessor.removeAllPaymentReceiverPayments(
            address(recurringPaymentManager), alice
        );

        // Make sure alice has no payments left
        assertFalse(
            streamingPaymentProcessor.isActivePaymentReceiver(
                address(recurringPaymentManager), alice
            )
        );

        // As a bonus
        // If calling from a module its possible to cancel all running payments
        // remove All running payments
        vm.prank(address(recurringPaymentManager));
        streamingPaymentProcessor.cancelRunningPayments(recurringPaymentManager);

        // Make sure the others are also removed
        assertFalse(
            streamingPaymentProcessor.isActivePaymentReceiver(
                address(recurringPaymentManager), bob
            )
        );
        assertFalse(
            streamingPaymentProcessor.isActivePaymentReceiver(
                address(recurringPaymentManager), charlie
            )
        );
    }
}
