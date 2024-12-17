// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies
import {
    E2ETest,
    IOrchestratorFactory_v1,
    IOrchestrator_v1
} from "test/e2e/E2ETest.sol";

// SuT
import {
    LM_PC_RecurringPayments_v1,
    ILM_PC_RecurringPayments_v1,
    IERC20PaymentClientBase_v1
} from "@lm/LM_PC_RecurringPayments_v1.sol";

// Modules that are used in this E2E test
import {
    PP_Streaming_v1,
    IPP_Streaming_v1,
    IERC20PaymentClientBase_v1
} from "src/modules/paymentProcessor/PP_Streaming_v1.sol";
import {FM_Rebasing_v1} from "@fm/rebasing/FM_Rebasing_v1.sol";
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

contract RecurringPaymentManagerE2E is E2ETest {
    // Module Configurations for the current E2E test. Should be filled during setUp() call.
    IOrchestratorFactory_v1.ModuleConfig[] moduleConfigurations;

    // Let's create a list of paymentReceivers
    address paymentReceiver1 = makeAddr("paymentReceiver 1");
    address paymentReceiver2 = makeAddr("paymentReceiver 2");
    address paymentReceiver3 = makeAddr("paymentReceiver 3");
    address paymentReceiver4 = makeAddr("paymentReceiver 4");

    // Parameters for recurring payments
    uint startEpoch;
    uint epochLength = 1 weeks; // 1 week;
    uint epochsAmount = 10;

    // Default values for the streaming payments
    uint defaultStart = 10;
    uint defaultCliff = 0;
    uint defaultEnd = 30;

    // Constants
    uint constant _SENTINEL = type(uint).max;

    uint paymentReceiver1InitialBalance;
    uint paymentReceiver2InitialBalance;

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

    function test_e2e_RecurringPayments(uint paymentAmount) public {
        paymentAmount = bound(paymentAmount, 1, 1e18);
        LM_PC_RecurringPayments_v1 recurringPaymentManager;

        //--------------------------------------------------------------------------
        // Orchestrator_v1 Initialization
        //--------------------------------------------------------------------------
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig =
        IOrchestratorFactory_v1.WorkflowConfig({
            independentUpdates: false,
            independentUpdateAdmin: address(0)
        });

        IOrchestrator_v1 orchestrator =
            _create_E2E_Orchestrator(workflowConfig, moduleConfigurations);

        FM_Rebasing_v1 fundingManager =
            FM_Rebasing_v1(address(orchestrator.fundingManager()));

        // ------------------ FROM ModuleTest.sol
        address[] memory modulesList = orchestrator.listModules();
        for (uint i; i < modulesList.length; ++i) {
            if (
                ERC165Upgradeable(modulesList[i]).supportsInterface(
                    type(ILM_PC_RecurringPayments_v1).interfaceId
                )
            ) {
                recurringPaymentManager =
                    LM_PC_RecurringPayments_v1(modulesList[i]);
                break;
            }
        }

        // check if the recurringPaymentManager is initialized correctly or not.
        assertEq(recurringPaymentManager.getEpochLength(), 1 weeks);

        // ----------------

        // 1. deopsit some funds to fundingManager
        uint initialDeposit = 10e22;
        token.mint(address(this), initialDeposit);
        token.approve(address(fundingManager), initialDeposit);
        fundingManager.deposit(initialDeposit);

        // 2. create recurringPayments: 2 for alice, 1 for bob
        startEpoch = recurringPaymentManager.getCurrentEpoch();

        paymentReceiver1InitialBalance = token.balanceOf(paymentReceiver1);
        paymentReceiver2InitialBalance = token.balanceOf(paymentReceiver2);

        // paymentAmount => amount that has to be paid out each epoch
        recurringPaymentManager.addRecurringPayment(
            paymentAmount, startEpoch + 1, paymentReceiver1
        );
        recurringPaymentManager.addRecurringPayment(
            paymentAmount, startEpoch + 1, paymentReceiver2
        );
        recurringPaymentManager.addRecurringPayment(
            (paymentAmount * 2), startEpoch + 1, paymentReceiver2
        );

        // 3. warp forward, they both withdraw
        vm.warp(
            (startEpoch * epochLength)
                + (recurringPaymentManager.getFutureEpoch(10) * epochLength)
        );
        recurringPaymentManager.trigger();

        // 3.1 jump another epoch, so that we can claim the vested tokens
        vm.warp(
            (block.timestamp)
                + (recurringPaymentManager.getFutureEpoch(1) * epochLength)
        );

        // 4. Let the paymentReceivers claim their vested tokens
        /// Let's first find the address of the streamingPaymentProcessor
        PP_Streaming_v1 streamingPaymentProcessor;
        for (uint i; i < modulesList.length; ++i) {
            try IPP_Streaming_v1(modulesList[i]).unclaimable(
                paymentReceiver1, address(token), paymentReceiver2
            ) returns (uint) {
                streamingPaymentProcessor = PP_Streaming_v1(modulesList[i]);
                break;
            } catch {
                continue;
            }
        }

        // Checking whether we got the right address for streamingPaymentProcessor
        IPP_Streaming_v1.Stream[] memory streams = streamingPaymentProcessor
            .viewAllPaymentOrders(
            address(recurringPaymentManager), paymentReceiver1
        );
        // One Paymentorder for the current epoch and one for all past payment orders -> 2 orders
        assertEq(streams.length, 2);
        streams = streamingPaymentProcessor.viewAllPaymentOrders(
            address(recurringPaymentManager), paymentReceiver2
        );
        assertEq(streams.length, 4);

        vm.prank(paymentReceiver2);
        streamingPaymentProcessor.claimAll(address(recurringPaymentManager));

        vm.prank(paymentReceiver1);
        streamingPaymentProcessor.claimAll(address(recurringPaymentManager));

        // PaymentReceiver2 should have got payments from both of their payment orders
        // PaymentReceiver1 should have got payment from one of their payment order
        assertEq(
            (token.balanceOf(paymentReceiver1) - paymentReceiver1InitialBalance),
            (paymentAmount * epochsAmount)
        );
        assertEq(
            (token.balanceOf(paymentReceiver2) - paymentReceiver2InitialBalance),
            ((paymentAmount * 2 + paymentAmount) * epochsAmount)
        );

        // Now since the entire vested amount was claimed by the paymentReceivers, their payment orders should no longer exist.
        // Let's check that
        assertTrue(
            !streamingPaymentProcessor.isActivePaymentReceiver(
                address(recurringPaymentManager), paymentReceiver1
            )
        );
        assertTrue(
            !streamingPaymentProcessor.isActivePaymentReceiver(
                address(recurringPaymentManager), paymentReceiver2
            )
        );
    }
}
