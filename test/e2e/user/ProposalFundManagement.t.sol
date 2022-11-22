// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import {E2eTest} from "test/e2e/E2eTest.sol";

import {IProposalFactory} from "src/factories/ProposalFactory.sol";
import {IProposal} from "src/proposal/Proposal.sol";

// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

/**
 * E2e test demonstrating a proposal's fund management.
 *
 * Funding of a proposal is managed via an ERC4626 vault.
 * For more info, see [FundingVault.sol](src/proposal/base/FundingVault.sol).
 *
 * Upon deposit of funds, users receive receipt token.
 *
 * The withdrawal amount of funds is _always_ in relation of the amount of
 * receipt tokens to the total amount of funds left in the proposal.
 */
contract ProposaFundManagement is E2eTest {
    address alice = address(0xA11CE);
    address bob = address(0x606);

    ERC20Mock token = new ERC20Mock("Mock", "MOCK");

    function test_e2e_ProposalFundManagement() public {
        // address(this) creates a new proposal.
        IProposalFactory.ProposalConfig memory proposalConfig = IProposalFactory
            .ProposalConfig({owner: address(this), token: token});

        IProposal proposal = _createNewProposalWithAllModules(proposalConfig);

        // Mint some tokens to alice and bob in order to fund the proposal.
        token.mint(alice, 1000e18);
        token.mint(bob, 10_000e18);

        // Alice funds the proposal with 1k tokens.
        vm.startPrank(alice);
        {
            // Approve tokens to proposal.
            token.approve(address(proposal), 1000e18);

            // Deposit tokens, i.e. fund the proposal.
            proposal.deposit(1000e18, alice);

            // After the deposit, alice received some amount of receipt tokens
            // from the proposal.
            assertTrue(proposal.balanceOf(alice) > 0);

            // With this amount of receipt tokens, alice could withdraw her
            // whole deposit again.
            assertEq(
                proposal.previewRedeem(proposal.balanceOf(alice)), 1000e18
            );
        }
        vm.stopPrank();

        // Bob funds the proposal with 5k tokens.
        vm.startPrank(bob);
        {
            // Approve tokens to proposal.
            token.approve(address(proposal), 5000e18);

            // Deposit tokens, i.e. fund the proposal.
            proposal.deposit(5000e18, bob);

            // After the deposit, bob received some amount of receipt tokens
            // from the proposal.
            assertTrue(proposal.balanceOf(alice) > 0);

            // With this amount of receipt tokens, bob could withdraw her whole
            // deposit again.
            assertEq(
                proposal.previewRedeem(proposal.balanceOf(bob)), 5000e18
            );

        }
        vm.stopPrank();

        // If the proposal spends half their tokens, i.e. for a milestone,
        // alice and bob are still able to withdraw their respective leftover
        // of the tokens.
        // Note that we simulate proposal spending by just burning their tokens.
        token.burn(address(proposal), token.balanceOf(address(proposal)) / 2);

        // Alice is now able to withdraw half her funded tokens.
        vm.startPrank(alice);
        {
            assertEq(proposal.redeem(proposal.balanceOf(alice), alice, alice), 500e18);
        }
        vm.stopPrank();

        // Bob is also able to withdraw half of his funded tokens.
        vm.startPrank(bob);
        {
            assertEq(proposal.redeem(proposal.balanceOf(bob), bob, bob), 2500e18);
        }
        vm.stopPrank();

        // After redeeming all their proposal function tokens, the tokens got
        // burned.
        assertEq(proposal.balanceOf(alice), 0);
        assertEq(proposal.balanceOf(bob), 0);
    }
}
