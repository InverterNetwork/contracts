// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

//Internal Dependencies
import {
    E2ETest, IOrchestratorFactory, IOrchestrator
} from "test/e2e/E2ETest.sol";

// SuT
import {
    RecurringPaymentManager,
    IRecurringPaymentManager,
    IERC20PaymentClient
} from "src/modules/logicModule/RecurringPaymentManager.sol";

// Modules that are used in this E2E test
import {
    StreamingPaymentProcessor,
    IStreamingPaymentProcessor,
    IERC20PaymentClient
} from "src/modules/paymentProcessor/StreamingPaymentProcessor.sol";
import {RebasingFundingManager} from
    "src/modules/fundingManager/rebasing/RebasingFundingManager.sol";

contract RecurringPaymentManagerE2E is E2ETest {
    // Module Configurations for the current E2E test. Should be filled during setUp() call.
    IOrchestratorFactory.ModuleConfig[] moduleConfigurations;

    // Let's create a list of paymentReceivers
    address paymentReceiver1 = makeAddr("paymentReceiver 1");
    address paymentReceiver2 = makeAddr("paymentReceiver 2");
    address paymentReceiver3 = makeAddr("paymentReceiver 3");
    address paymentReceiver4 = makeAddr("paymentReceiver 4");

    // Parameters for recurring payments
    uint startEpoch;
    uint epochLength = 1 weeks; // 1 week;
    uint epochsAmount = 10;

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
        setUpStreamingPaymentProcessor();
        moduleConfigurations.push(
            IOrchestratorFactory.ModuleConfig(
                streamingPaymentProcessorMetadata,
                bytes(""),
                abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
            )
        );

        // Additional Logic Modules
        setUpRecurringPaymentManager();
        moduleConfigurations.push(
            IOrchestratorFactory.ModuleConfig(
                recurringPaymentManagerMetadata,
                abi.encode(1 weeks),
                abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
            )
        );
    }

    function test_e2e_RecurringPayments(uint paymentAmount) public {
        paymentAmount = bound(paymentAmount, 1, 1e18);
        RecurringPaymentManager recurringPaymentManager;

        //--------------------------------------------------------------------------------
        // Orchestrator Initialization
        //--------------------------------------------------------------------------------
        IOrchestratorFactory.OrchestratorConfig memory orchestratorConfig =
        IOrchestratorFactory.OrchestratorConfig({
            owner: address(this),
            token: token
        });

        IOrchestrator orchestrator =
            _create_E2E_Orchestrator(orchestratorConfig, moduleConfigurations);

        RebasingFundingManager fundingManager =
            RebasingFundingManager(address(orchestrator.fundingManager()));

        // ------------------ FROM ModuleTest.sol
        address[] memory modulesList = orchestrator.listModules();
        for (uint i; i < modulesList.length; ++i) {
            try IRecurringPaymentManager(modulesList[i]).getCurrentEpoch()
            returns (uint) {
                recurringPaymentManager =
                    RecurringPaymentManager(modulesList[i]);
                break;
            } catch {
                continue;
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
        StreamingPaymentProcessor streamingPaymentProcessor;
        for (uint i; i < modulesList.length; ++i) {
            try IStreamingPaymentProcessor(modulesList[i]).unclaimable(
                paymentReceiver1, paymentReceiver2
            ) returns (uint) {
                streamingPaymentProcessor =
                    StreamingPaymentProcessor(modulesList[i]);
                break;
            } catch {
                continue;
            }
        }

        // Checking whether we got the right address for streamingPaymentProcessor
        IStreamingPaymentProcessor.VestingWallet[] memory wallets =
        streamingPaymentProcessor.viewAllPaymentOrders(
            address(recurringPaymentManager), paymentReceiver1
        );
        //One Paymentorder for the current epoch and one for all past payment orders -> 2 orders
        assertEq(wallets.length, 2);
        wallets = streamingPaymentProcessor.viewAllPaymentOrders(
            address(recurringPaymentManager), paymentReceiver2
        );
        assertEq(wallets.length, 4);

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
