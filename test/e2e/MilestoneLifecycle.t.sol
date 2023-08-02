// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {E2eTest} from "test/e2e/E2eTest.sol";

import {IOrchestratorFactory} from "src/factories/OrchestratorFactory.sol";
import {IOrchestrator} from "src/orchestrator/Orchestrator.sol";

import {
    MilestoneManager,
    IMilestoneManager
} from "src/modules/logicModule/MilestoneManager.sol";

import {RebasingFundingManager} from
    "src/modules/fundingManager/RebasingFundingManager.sol";

import {SimplePaymentProcessor} from
    "src/modules/paymentProcessor/SimplePaymentProcessor.sol";
import {IERC20PaymentClient} from
    "src/modules/base/mixins/IERC20PaymentClient.sol";

// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

/**
 * E2e test demonstrating how to add, start, and complete a Milestone.
 */
contract MilestoneLifecycle is E2eTest {
    // Before we can start a milestone, two things need to be present:
    // 1. A non-empty list of contributors for it
    // 2. The percentage of milestone funding to pay the contributors for the milestone.

    // So lets add Alice and Bob as contributors to the orchestrator.
    // Note the salary is specified in relation to the SALARY_PRECISION variable in the MilestoneManager.
    IMilestoneManager.Contributor alice = IMilestoneManager.Contributor(
        address(0xA11CE), 50_000_000, "AliceIdHash"
    );
    IMilestoneManager.Contributor bob =
        IMilestoneManager.Contributor(address(0x606), 50_000_000, "BobIdHash");
    IMilestoneManager.Contributor[] contributors;

    address funder1 = address(0xF1);
    address funder2 = address(0xF2);

    ERC20Mock token = new ERC20Mock("Mock", "MOCK");

    function test_e2e_MilestoneLifecycle() public {
        // First, we create a new orchestrator.
        IOrchestratorFactory.OrchestratorConfig memory orchestratorConfig =
        IOrchestratorFactory.OrchestratorConfig({
            owner: address(this),
            token: token
        });

        IOrchestrator orchestrator =
            _createNewOrchestratorWithAllModules(orchestratorConfig);

        RebasingFundingManager fundingManager =
            RebasingFundingManager(address(orchestrator.fundingManager()));

        // Now we add a few milestones.
        // For that, we need to access the orchestrator's milestone module.
        MilestoneManager milestoneManager;

        address[] memory modulesList = orchestrator.listModules();
        for (uint i; i < modulesList.length; ++i) {
            try IMilestoneManager(modulesList[i]).hasActiveMilestone() returns (
                bool
            ) {
                milestoneManager = MilestoneManager(modulesList[i]);
                break;
            } catch {
                continue;
            }
        }

        // making sure we got the correct address of milestoneManager
        assertTrue(!(milestoneManager.hasActiveMilestone()));

        contributors.push(alice);
        contributors.push(bob);

        milestoneManager.addMilestone(
            1 weeks,
            1000e18,
            contributors,
            bytes("Here could be a more detailed description")
        );
        milestoneManager.addMilestone(
            2 weeks,
            5000e18,
            contributors,
            bytes("The second milestone, right after the first one")
        );

        // IMPORTANT
        // =========
        // Due to how the underlying rebase mechanism works, it is necessary
        // to always have some amount of tokens in the orchestrator.
        // It's best, if the owner deposits them right after deployment.
        uint initialDeposit = 10e18;
        token.mint(address(this), initialDeposit);
        token.approve(address(fundingManager), initialDeposit);
        fundingManager.deposit(initialDeposit);

        // However, the salary is not yet taken into in the Milestone module.
        // The milestone's budget is shared equally between all contributors.

        assertTrue(milestoneManager.isContributor(1, alice.addr));
        assertTrue(milestoneManager.isContributor(1, bob.addr));

        // Seeing this great working on the orchestrator, funder1 decides to fund
        // the orchestrator with 1k of tokens.
        token.mint(funder1, 1000e18);

        vm.startPrank(funder1);
        {
            token.approve(address(fundingManager), 1000e18);
            fundingManager.deposit(1000e18);
        }
        vm.stopPrank();

        // The orchestrator now has 1k tokens of funding. Exactly the amount needed
        // for the first milestone.
        assertEq(
            token.balanceOf(address(fundingManager)), 1000e18 + initialDeposit
        );
        assertEq(fundingManager.totalSupply(), 1000e18 + initialDeposit);

        // Now we ait for the timelock to pass and start the first milestone.
        vm.warp(
            block.timestamp + milestoneManager.getMilestoneUpdateTimelock() + 1
        );
        milestoneManager.startNextMilestone();

        // The MilestoneManager DOES NOT pay the contributors itself, but
        // creates set set of payment orders inside the module and calls
        // the SimplePaymentProcessor module to process them. Note however, that the
        // orders are guaranteed to be payable, i.e. the tokens are already
        // fetched from the orchestrator on creation of the order.

        // since we take 1% fee, the expected balance is 990e18/2

        assertEq(token.balanceOf(alice.addr), 990e18 / 2);
        assertEq(token.balanceOf(bob.addr), 990e18 / 2);

        // Lets wait some time now for Alice and Bob to submit their work for
        // the milestone.
        vm.warp(block.timestamp + 3 days);

        // After 3 days, Bob is ready to submit the milestone.
        // For that, he needs to provide the milestone's id (1 in this case, as
        // it's) the first milestone, and additional data.
        // The submission data can not be empty, and is intended for off-chain
        // systems to check Bob's work.
        vm.prank(bob.addr);
        milestoneManager.submitMilestone({
            milestoneId: 1,
            submissionData: bytes("https://bob.com/paper-for-milestone.pdf")
        });

        // Now some authorized addresses need to either mark the milestone as
        // complete or decline Bob's submission. Declining a submission makes
        // it possible for contributors to submit data again.
        milestoneManager.completeMilestone(1);

        // Wuhuu.. The first milestone is completed.

        // Sadly we can not start the next milestone... There is not funding
        // yet.
        // Luckily funder2 comes in and deposits some tokens.
        // Eventhough the milestone only needs 5k of tokens, funder2 deposits
        // 10k.
        token.mint(funder2, 10_000e18);

        vm.startPrank(funder2);
        {
            token.approve(address(fundingManager), 10_000e18);
            fundingManager.deposit(10_000e18);
        }
        vm.stopPrank();

        // Note that we can not yet start the next milestone before the
        // previous' milestone's duration is not over.
        // This is independent whether the milestone is completed or not.
        vm.warp(block.timestamp + 1 weeks);

        // Now start the next orchestrator...
        milestoneManager.startNextMilestone();
        // ...which leaves 5k of tokens left in the orchestrator.
        assertEq(
            token.balanceOf(address(fundingManager)), 5000e18 + initialDeposit
        );

        // These tokens can now be withdrawn by funder1 and funder2.
        vm.startPrank(funder1);
        {
            fundingManager.withdraw(fundingManager.balanceOf(funder1));
        }
        vm.stopPrank();

        vm.startPrank(funder2);
        {
            fundingManager.withdraw(fundingManager.balanceOf(funder2));
        }
        vm.stopPrank();
    }
}
