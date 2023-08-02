// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {E2eTest} from "test/e2e/E2eTest.sol";
import "forge-std/console.sol";

//Internal Dependencies
import {ModuleTest, IModule, IOrchestrator} from "test/modules/ModuleTest.sol";
import {IOrchestratorFactory} from "src/factories/OrchestratorFactory.sol";
import {AuthorizerMock} from "test/utils/mocks/modules/AuthorizerMock.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

import {RebasingFundingManager} from
    "src/modules/fundingManager/RebasingFundingManager.sol";
// SuT
import {
    RecurringPaymentManager,
    IRecurringPaymentManager
} from "src/modules/logicModule/RecurringPaymentManager.sol";

import {StreamingPaymentProcessor} from
    "src/modules/paymentProcessor/StreamingPaymentProcessor.sol";

import {
    IStreamingPaymentProcessor,
    IERC20PaymentClient
} from "src/modules/paymentProcessor/IStreamingPaymentProcessor.sol";

// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

contract StreamingPaymentsLifecycle is E2eTest {
    // Let's create a list of PaymentReceivers
    address alice = makeAddr("Alice");
    address bob = makeAddr("Bob");
    address charlie = makeAddr("Charlie");

    // Parameters for recurring payments
    uint startEpoch = 52;
    uint epochLength = 1 weeks; // 1 week;
    uint epochsAmount = 10;

    ERC20Mock token = new ERC20Mock("Mock", "MOCK");
    IOrchestrator orchestrator;
    RebasingFundingManager fundingManager;
    RecurringPaymentManager recurringPaymentManager;
    StreamingPaymentProcessor streamingPaymentProcessor;

    uint paymentReceiver1InitialBalance;
    uint paymentReceiver2InitialBalance;

    function fetchReferences() private {}

    function init() private {
        // -----------INIT
        // address(this) creates a new orchestrator.
        IOrchestratorFactory.OrchestratorConfig memory orchestratorConfig =
        IOrchestratorFactory.OrchestratorConfig({
            owner: address(this),
            token: token
        });

        orchestrator =
        _createNewOrchestratorWithAllModules_withRecurringPaymentManagerAndStreamingPaymentProcessor(
            orchestratorConfig
        );

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
            recurringPaymentManager, vestings[0]._vestingWalletID, false
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
        streamingPaymentProcessor.claimAll(recurringPaymentManager);
        //Check token
        assertTrue(token.balanceOf(alice) == paymentAmount / 2 * 3);

        //Time Jump to the end of the week
        vm.warp(block.timestamp + 1 weeks / 2);

        //Claim all
        vm.prank(alice);
        streamingPaymentProcessor.claimAll(recurringPaymentManager);
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
            recurringPaymentManager, alice, vestings[0]._vestingWalletID, false
        );

        vestings = streamingPaymentProcessor.viewAllPaymentOrders(
            address(recurringPaymentManager), alice
        );
        assertTrue(vestings.length == 2);

        //remove all Payments from Alice
        streamingPaymentProcessor.removeAllPaymentReceiverPayments(
            recurringPaymentManager, alice
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
