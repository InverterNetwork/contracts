// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import {E2eTest} from "test/e2e/E2eTest.sol";

import {IProposalFactory} from "src/factories/ProposalFactory.sol";
import {IProposal} from "src/proposal/Proposal.sol";

// Mocks
import {BlockableToken} from "test/utils/mocks/weird_ERC20/BlockableToken.sol";
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

contract ProposaFundManagementBlocklist is E2eTest {
    address alice = address(0xA11CE);
    address bob = address(0x606);

    // weird_ERC20: Blockable token allows blocking/unblocking
    // (blacklisting) individual addresses.
    // Note transfer() is not overwritten by BlockableToken,
    // so it may stil work.
    BlockableToken token = new BlockableToken(10e18);

    function test_e2e_ProposalFundManagement() public {
        // address(this) creates a new proposal.
        IProposalFactory.ProposalConfig memory proposalConfig = IProposalFactory
            .ProposalConfig({owner: address(this), token: token});

        IProposal proposal = _createNewProposalWithAllModules(proposalConfig);

        // IMPORTANT
        // =========
        // Due to how the underlying rebase mechanism works, it is necessary
        // to always have some amount of tokens in the proposal.
        // It's best, if the owner deposits them right after deployment.
        uint initialDeposit = 10e18;
        token.mint(address(this), initialDeposit);
        token.approve(address(proposal), initialDeposit);
        proposal.deposit(initialDeposit);

        // Mint some tokens to alice and bob in order to fund the proposal.
        token.mint(alice, 1000e18);
        token.mint(bob, 5000e18);

        // Alice funds the proposal with 1k tokens.
        vm.startPrank(alice);
        {
            // Approve tokens to proposal.
            token.approve(address(proposal), 1000e18);

            // Deposit tokens, i.e. fund the proposal.
            proposal.deposit(1000e18);

            // After the deposit, alice received some amount of receipt tokens
            // from the proposal.
            assertTrue(proposal.balanceOf(alice) > 0);
        }
        vm.stopPrank();

        // Bob funds the proposal with 5k tokens.
        vm.startPrank(bob);
        {
            // Approve tokens to proposal.
            token.approve(address(proposal), 5000e18);

            // Deposit tokens, i.e. fund the proposal.
            proposal.deposit(5000e18);

            // After the deposit, bob received some amount of receipt tokens
            // from the proposal.
            assertTrue(proposal.balanceOf(bob) > 0);
        }
        vm.stopPrank();

        // If the proposal spends half their tokens, i.e. for a milestone,
        // alice and bob are still able to withdraw their respective leftover
        // of the tokens.
        // Note that we simulate proposal spending by just burning tokens.
        token.burn(address(proposal), token.balanceOf(address(proposal)) / 2);

        // weird_ERC20: In the meantime Alice gets blocked
        token.blockUser(alice);
        token.blockUser(bob);
        assertTrue(token.isBlocked(alice));
        assertTrue(token.isBlocked(bob));

        // weird_ERC20: Alice is not able to withdraw half her funded tokens
        // as long as she is blocked. After that withdraw is possible again.
        vm.startPrank(alice);
        {
            try proposal.withdraw(proposal.balanceOf(alice)) {
                // if withdraw is successful, test should fail.
                assertTrue(false);
            } catch {
                // weird_ERC20: Alice gets in unblocked again
                vm.stopPrank();
                token.allow(alice);
                assertFalse(token.isBlocked(alice));
                // Another attempt at withdrawing should be successful.
                vm.startPrank(alice);
                {
                    proposal.withdraw(proposal.balanceOf(alice));
                }
                vm.stopPrank();
                // Verify alice balances are correct.
                assertEq(token.balanceOf(alice), 500e18);
            }
        }

        // weird_ERC20: Bob is not able to withdraw half his funded tokens
        // as long as he is blocked. After that withdraw is possible again.
        vm.startPrank(bob);
        {
            try proposal.withdraw(proposal.balanceOf(bob)) {
                // if withdraw is successful, test should fail.
                assertTrue(false);
            } catch {
                // weird_ERC20: Bob gets in unblocked again
                vm.stopPrank();
                token.allow(bob);
                assertFalse(token.isBlocked(bob));
                // Another attempt at withdrawing should be successful.
                vm.startPrank(bob);
                {
                    proposal.withdraw(proposal.balanceOf(bob));
                }
                vm.stopPrank();
                // Verify alice balances are correct.
                assertEq(token.balanceOf(bob), 2500e18);
            }
        }

        // After redeeming all their proposal function tokens, the tokens got
        // burned.
        assertEq(proposal.balanceOf(alice), 0);
        assertEq(proposal.balanceOf(bob), 0);
    }
}
