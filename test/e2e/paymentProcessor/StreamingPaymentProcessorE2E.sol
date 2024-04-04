// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

//Internal Dependencies
import {
    E2ETest, IOrchestratorFactory, IOrchestrator
} from "test/e2e/E2ETest.sol";

import {RebasingFundingManager} from
    "src/modules/fundingManager/rebasing/RebasingFundingManager.sol";
// SuT
import {
    RecurringPaymentManager,
    IRecurringPaymentManager
} from "src/modules/logicModule/RecurringPaymentManager.sol";

import {StreamingPaymentProcessor} from
    "src/modules/paymentProcessor/StreamingPaymentProcessor.sol";

import {IStreamingPaymentProcessor} from
    "src/modules/paymentProcessor/IStreamingPaymentProcessor.sol";

contract StreamingPaymentProcessorE2E is E2ETest {
    // Module Configurations for the current E2E test. Should be filled during setUp() call.
    IOrchestratorFactory.ModuleConfig[] moduleConfigurations;

    //---------------------------------------------------------------------------------------------------
    // Test variables

    // Users
    address alice = makeAddr("Alice");
    address bob = makeAddr("Bob");
    address charlie = makeAddr("Charlie");

    // Parameters for recurring payments
    uint startEpoch = 52;
    uint epochLength = 1 weeks; // 1 week;
    uint epochsAmount = 10;

    // Modules, for reference between functions
    IOrchestrator orchestrator;
    RebasingFundingManager fundingManager;
    RecurringPaymentManager recurringPaymentManager;
    StreamingPaymentProcessor streamingPaymentProcessor;

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

    function init() private {
        //--------------------------------------------------------------------------------
        // Orchestrator Initialization
        //--------------------------------------------------------------------------------
        IOrchestratorFactory.OrchestratorConfig memory orchestratorConfig =
        IOrchestratorFactory.OrchestratorConfig({
            owner: address(this),
            token: token
        });

        orchestrator =
            _create_E2E_Orchestrator(orchestratorConfig, moduleConfigurations);

        fundingManager =
            RebasingFundingManager(address(orchestrator.fundingManager()));

        recurringPaymentManager = RecurringPaymentManager(
            orchestrator.findModuleAddressInOrchestrator(
                "RecurringPaymentManager"
            )
        );
        // check if the recurringPaymentManager is initialized correctly or not.
        assertEq(recurringPaymentManager.getEpochLength(), 1 weeks);

        streamingPaymentProcessor = StreamingPaymentProcessor(
            orchestrator.findModuleAddressInOrchestrator(
                "StreamingPaymentProcessor"
            )
        );

        //deposit some funds to fundingManager
        uint initialDeposit = 10e22;
        token.mint(address(this), initialDeposit);
        token.approve(address(fundingManager), initialDeposit);
        fundingManager.deposit(initialDeposit);

        //Set Block.timestamp to startEpoch
        vm.warp(startEpoch * epochLength);
    }

    function test_e2e_StreamingPaymentsLifecycleUserFunctions() public {
        init();

        // ---------------------------------------------------------------------------------------------------
        // User side of the StreamingPaymentProcessor

        //Create 3 different Payments

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
        //this should create 3 streamingpayments with dueTo timestamp of startEpoch * epochLength + 1 week
        recurringPaymentManager.trigger();

        // ----------------
        // Getter Functions

        //Check Payments
        //viewAllPaymentOrders
        //Lets see all avaialable orders
        IStreamingPaymentProcessor.VestingWallet[] memory vestings =
        streamingPaymentProcessor.viewAllPaymentOrders(
            address(recurringPaymentManager), alice
        );
        assertTrue(vestings.length == 3);

        //startForSpecificWalletId
        //When does the payment start vesting?
        uint start = streamingPaymentProcessor.startForSpecificWalletId(
            address(recurringPaymentManager),
            alice,
            vestings[0]._vestingWalletID
        );
        assertTrue(start == block.timestamp);

        //dueToForSpecificWalletId
        //When is the payment dueTo?
        uint dueTo = streamingPaymentProcessor.dueToForSpecificWalletId(
            address(recurringPaymentManager),
            alice,
            vestings[0]._vestingWalletID
        );
        assertTrue(dueTo == startEpoch * epochLength + 1 weeks);

        //vestedAmountForSpecificWalletId
        //lets see what is hypotheically realeasable in half a week
        uint vestedAmount = streamingPaymentProcessor
            .vestedAmountForSpecificWalletId(
            address(recurringPaymentManager),
            alice,
            block.timestamp + 1 weeks / 2,
            vestings[0]._vestingWalletID
        );
        assertTrue(vestedAmount == paymentAmount / 2);

        //releasedForSpecificWalletId
        //What got already released for that specific wallet id?
        uint released = streamingPaymentProcessor.releasedForSpecificWalletId(
            address(recurringPaymentManager),
            alice,
            vestings[0]._vestingWalletID
        );
        assertTrue(released == 0);

        //releasableForSpecificWalletId
        //What is currently releasable? Emphasis on "currently"
        uint releasable = streamingPaymentProcessor
            .releasableForSpecificWalletId(
            address(recurringPaymentManager),
            alice,
            vestings[0]._vestingWalletID
        );
        assertTrue(releasable == 0);

        //unclaimable
        //In case a transfer should fail this can be checked here
        uint unclaimable = streamingPaymentProcessor.unclaimable(
            address(recurringPaymentManager), alice
        );
        assertTrue(unclaimable == 0);

        // ----------------
        // Claim Functions

        //Lets do a time jump of half a week
        vm.warp(block.timestamp + 1 weeks / 2);
        //And check how much is releasable
        releasable = streamingPaymentProcessor.releasableForSpecificWalletId(
            address(recurringPaymentManager),
            alice,
            vestings[0]._vestingWalletID
        );
        assertTrue(releasable == paymentAmount / 2);

        //Lets claim the releasable tokens for a single vestingwallet
        vm.prank(alice);
        streamingPaymentProcessor.claimForSpecificWalletId(
            address(recurringPaymentManager),
            vestings[0]._vestingWalletID,
            false
        );
        //check what got released
        released = streamingPaymentProcessor.releasedForSpecificWalletId(
            address(recurringPaymentManager),
            alice,
            vestings[0]._vestingWalletID
        );
        assertTrue(released == paymentAmount / 2);

        //Check it on the tokensied too
        assertTrue(token.balanceOf(alice) == paymentAmount / 2);

        //claim rest up to point
        //claimAll
        vm.prank(alice);
        streamingPaymentProcessor.claimAll(address(recurringPaymentManager));
        //Check token
        assertTrue(token.balanceOf(alice) == paymentAmount / 2 * 3);

        //Time Jump to the end of the week
        vm.warp(block.timestamp + 1 weeks / 2);

        //Claim all
        vm.prank(alice);
        streamingPaymentProcessor.claimAll(address(recurringPaymentManager));
        //Check token
        assertTrue(token.balanceOf(alice) == paymentAmount * 3);
    }

    function test_e2e_StreamingPaymentsLifecycleAdminFunctions() public {
        init();

        // ---------------------------------------------------------------------------------------------------
        //Admin Functions

        //Lets set up a few payments to test
        //5 Payments
        //3 Alice
        //1 Bob
        //1 Charlie

        recurringPaymentManager.addRecurringPayment(1, startEpoch, alice);
        recurringPaymentManager.addRecurringPayment(1, startEpoch, alice);
        recurringPaymentManager.addRecurringPayment(1, startEpoch, alice);
        recurringPaymentManager.addRecurringPayment(1, startEpoch, bob);
        recurringPaymentManager.addRecurringPayment(1, startEpoch, bob);
        recurringPaymentManager.addRecurringPayment(1, startEpoch, charlie);

        //Trigger starts the payments
        recurringPaymentManager.trigger();

        //Check if everyone has a running payment active
        IStreamingPaymentProcessor.VestingWallet[] memory vestings =
        streamingPaymentProcessor.viewAllPaymentOrders(
            address(recurringPaymentManager), alice
        );
        assertTrue(vestings.length == 3);

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

        //remove 1 Alice
        //removePaymentForSpecificWalletId
        streamingPaymentProcessor.removePaymentForSpecificWalletId(
            address(recurringPaymentManager),
            alice,
            vestings[0]._vestingWalletID,
            false
        );

        vestings = streamingPaymentProcessor.viewAllPaymentOrders(
            address(recurringPaymentManager), alice
        );
        assertTrue(vestings.length == 2);

        //remove all Payments from Alice
        streamingPaymentProcessor.removeAllPaymentReceiverPayments(
            address(recurringPaymentManager), alice
        );

        //Make sure alice has no payments left
        assertFalse(
            streamingPaymentProcessor.isActivePaymentReceiver(
                address(recurringPaymentManager), alice
            )
        );

        //As a bonus
        //If calling from a module its possible to cancel all running payments
        //remove All running payments
        vm.prank(address(recurringPaymentManager));
        streamingPaymentProcessor.cancelRunningPayments(recurringPaymentManager);

        //Make sure the others are also removed
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
