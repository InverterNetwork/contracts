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
    IRecurringPaymentManager,
    IERC20PaymentClient
} from "src/modules/logicModule/RecurringPaymentManager.sol";

import {StreamingPaymentProcessor} from
    "src/modules/paymentProcessor/StreamingPaymentProcessor.sol";

import {
    IStreamingPaymentProcessor,
    IERC20PaymentClient
} from "src/modules/paymentProcessor/IStreamingPaymentProcessor.sol";

// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

contract RecurringPayments is E2eTest {
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

    ERC20Mock token = new ERC20Mock("Mock", "MOCK");

    uint paymentReceiver1InitialBalance;
    uint paymentReceiver2InitialBalance;

    function test_e2e_RecurringPayments(uint paymentAmount) public {
        paymentAmount = bound(paymentAmount, 1, 1e18);
        RecurringPaymentManager recurringPaymentManager;

        // -----------INIT
        // address(this) creates a new orchestrator.
        IOrchestratorFactory.OrchestratorConfig memory orchestratorConfig =
        IOrchestratorFactory.OrchestratorConfig({
            owner: address(this),
            token: token
        });

        IOrchestrator orchestrator =
        _createNewOrchestratorWithAllModules_withRecurringPaymentManagerAndStreamingPaymentProcessor(
            orchestratorConfig
        );

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
        streamingPaymentProcessor.claimAll(recurringPaymentManager);

        vm.prank(paymentReceiver1);
        streamingPaymentProcessor.claimAll(recurringPaymentManager);

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
