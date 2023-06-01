// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import {E2eTest} from "test/e2e/E2eTest.sol";

import {IProposalFactory} from "src/factories/ProposalFactory.sol";
import {IProposal} from "src/proposal/Proposal.sol";

import {RebasingFundingManager} from
    "src/modules/fundingManager/RebasingFundingManager.sol";

// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";
/**
 * E2e test demonstrating a proposal's fund management.
 *
 * Funding of a proposal is managed via a fundingmanager.
 *
 * Upon deposit of funds, users receive receipt token.
 * The withdrawal amount of funds is _always_ in relation of the amount of
 * receipt tokens to the total amount of funds left in the fundingmanager.
 */

contract FundManagement is E2eTest {
    address alice = address(0xA11CE);
    address bob = address(0x606);

    ERC20Mock token = new ERC20Mock("Mock", "MOCK");

    function test_e2e_ProposalFundManagement() public {
        // address(this) creates a new proposal.
        IProposalFactory.ProposalConfig memory proposalConfig = IProposalFactory
            .ProposalConfig({owner: address(this), token: token});

        IProposal proposal = _createNewProposalWithAllModules(proposalConfig);

        RebasingFundingManager fundingManager =
            RebasingFundingManager(address(proposal.fundingManager()));

        // IMPORTANT
        // =========
        // Due to how the underlying rebase mechanism works, it is necessary
        // to always have some amount of tokens in the fundingmanager.
        // It's best, if the owner deposits them right after deployment.
        uint initialDeposit = 10e18;
        token.mint(address(this), initialDeposit);
        token.approve(address(fundingManager), initialDeposit);
        fundingManager.deposit(initialDeposit);

        // Mint some tokens to alice and bob in order to fund the fundingmanager.
        token.mint(alice, 1000e18);
        token.mint(bob, 5000e18);

        // Alice funds the fundingmanager with 1k tokens.
        vm.startPrank(alice);
        {
            // Approve tokens to proposal.
            token.approve(address(fundingManager), 1000e18);

            // Deposit tokens, i.e. fund the fundingmanager.
            fundingManager.deposit(1000e18);

            // After the deposit, alice received some amount of receipt tokens
            // from the fundingmanager.
            assertTrue(fundingManager.balanceOf(alice) > 0);
        }
        vm.stopPrank();

        // Bob funds the fundingmanager with 5k tokens.
        vm.startPrank(bob);
        {
            // Approve tokens to fundingmanager.
            token.approve(address(fundingManager), 5000e18);

            // Deposit tokens, i.e. fund the fundingmanager.
            fundingManager.deposit(5000e18);

            // After the deposit, bob received some amount of receipt tokens
            // from the fundingmanager.
            assertTrue(fundingManager.balanceOf(bob) > 0);
        }
        vm.stopPrank();

        // If the proposal spends half of the deposited tokens in the fundingmanager, i.e. for a milestone,
        // alice and bob are still able to withdraw their respective leftover
        // of the tokens.
        // Note that we simulate proposal spending by just burning tokens.
        token.burn(
            address(fundingManager),
            token.balanceOf(address(fundingManager)) / 2
        );

        // Alice is now able to withdraw half her funded tokens.
        vm.startPrank(alice);
        {
            fundingManager.withdraw(fundingManager.balanceOf(alice));
            assertEq(token.balanceOf(alice), 500e18);
        }
        vm.stopPrank();

        // Bob is also able to withdraw half of his funded tokens.
        vm.startPrank(bob);
        {
            fundingManager.withdraw(fundingManager.balanceOf(bob));
            assertEq(token.balanceOf(bob), 2500e18);
        }
        vm.stopPrank();

        // After redeeming all their fundingmanager function tokens, the tokens got
        // burned.
        assertEq(fundingManager.balanceOf(alice), 0);
        assertEq(fundingManager.balanceOf(bob), 0);
    }
}
