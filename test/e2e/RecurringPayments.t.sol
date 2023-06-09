// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import {e2e} from "test/e2e/e2e_test.sol";
import "forge-std/console.sol";

//Internal Dependencies
import {ModuleTest, IModule, IProposal} from "test/modules/ModuleTest.sol";
import {IProposalFactory} from "src/factories/ProposalFactory.sol";
import {AuthorizerMock} from "test/utils/mocks/modules/AuthorizerMock.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

import {RebasingFundingManager} from
    "src/modules/fundingManager/RebasingFundingManager.sol";
// SuT
import {
    RecurringPaymentManager,
    IRecurringPaymentManager,
    IPaymentClient
} from "src/modules/logicModule/RecurringPaymentManager.sol";

import {StreamingPaymentProcessor} from
    "src/modules/paymentProcessor/StreamingPaymentProcessor.sol";

import {
    IStreamingPaymentProcessor,
    IPaymentClient
} from "src/modules/paymentProcessor/IStreamingPaymentProcessor.sol";

// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

contract RecurringPayments is e2e {
    // Let's create a list of contributors
    address contributor1 = makeAddr("contributor 1");
    address contributor2 = makeAddr("contributor 2");
    address contributor3 = makeAddr("contributor 3");
    address contributor4 = makeAddr("contributor 4");

    // Parameters for recurring payments
    uint startEpoch;
    uint epochLength = 1 weeks; // 1 week;
    uint epochsAmount = 10;

    // Constants
    uint constant _SENTINEL = type(uint).max;

    ERC20Mock token = new ERC20Mock("Mock", "MOCK");

    // Module Constants
    uint constant _MAJOR_VERSION = 1;
    uint constant _MINOR_VERSION = 1;
    string constant _URL = "https://github.com/organization/module";
    string constant _TITLE = "Module";

    uint contributor1InitialBalance;
    uint contributor2InitialBalance;

    function test_e2e_RecurringPayments(uint paymentAmount) public {
        vm.assume(paymentAmount > 0 && paymentAmount <= 1e18);
        RecurringPaymentManager recurringPaymentManager;

        // -----------INIT
        // address(this) creates a new proposal.
        IProposalFactory.ProposalConfig memory proposalConfig = IProposalFactory
            .ProposalConfig({owner: address(this), token: token});

        IProposal proposal =
        _createNewProposalWithAllModules_withStreamingPaymentProcessor(
            proposalConfig
        );

        RebasingFundingManager fundingManager =
            RebasingFundingManager(address(proposal.fundingManager()));

        // ------------------ FROM ModuleTest.sol
        address[] memory modulesList = proposal.listModules();
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

        AuthorizerMock _authorizer = new AuthorizerMock();
        _authorizer.setIsAuthorized(address(this), true);

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

        contributor1InitialBalance = token.balanceOf(contributor1);
        contributor2InitialBalance = token.balanceOf(contributor2);

        // paymentAmount => amount that has to be paid out each epoch
        recurringPaymentManager.addRecurringPayment(
            paymentAmount, startEpoch + 1, contributor1
        );
        recurringPaymentManager.addRecurringPayment(
            paymentAmount, startEpoch + 1, contributor2
        );
        recurringPaymentManager.addRecurringPayment(
            (paymentAmount * 2), startEpoch + 1, contributor2
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

        // 4. Let the contributors claim their vested tokens
        /// Let's first find the address of the streamingPaymentProcessor
        StreamingPaymentProcessor streamingPaymentProcessor;
        for (uint i; i < modulesList.length; ++i) {
            try IStreamingPaymentProcessor(modulesList[i]).unclaimable(
                contributor1, contributor2
            ) returns (uint) {
                streamingPaymentProcessor =
                    StreamingPaymentProcessor(modulesList[i]);
                break;
            } catch {
                continue;
            }
        }

        // Checking whether we got the right address for streamingPaymentProcessor
        IStreamingPaymentProcessor.StreamingWallet[] memory wallets =
        streamingPaymentProcessor.viewAllPaymentOrders(
            address(recurringPaymentManager), contributor1
        );
        assertEq(wallets.length, 1);
        wallets = streamingPaymentProcessor.viewAllPaymentOrders(
            address(recurringPaymentManager), contributor2
        );
        assertEq(wallets.length, 2);

        vm.prank(contributor2);
        streamingPaymentProcessor.claimAll(recurringPaymentManager);

        vm.prank(contributor1);
        streamingPaymentProcessor.claimAll(recurringPaymentManager);

        // Contributor2 should have got payments from both of their payment orders
        // Contributor1 should have got payment from one of their payment order
        assertEq(
            (token.balanceOf(contributor1) - contributor1InitialBalance),
            (paymentAmount * epochsAmount)
        );
        assertEq(
            (token.balanceOf(contributor2) - contributor2InitialBalance),
            ((paymentAmount * 2 + paymentAmount) * epochsAmount)
        );

        // Now since the entire vested amount was claimed by the contributors, their payment orders should no longer exist.
        // Let's check that
        assertTrue(
            !streamingPaymentProcessor.isActiveContributor(
                address(recurringPaymentManager), contributor1
            )
        );
        assertTrue(
            !streamingPaymentProcessor.isActiveContributor(
                address(recurringPaymentManager), contributor2
            )
        );
    }
}
