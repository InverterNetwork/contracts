// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import {E2eTest} from "test/e2e/E2eTest.sol";

import {IProposalFactory} from "src/factories/ProposalFactory.sol";
import {IProposal} from "src/proposal/Proposal.sol";

// Mocks
import {BlockableToken} from "test/utils/mocks/weird_ERC20/BlockableToken.sol";

 /**
  * @title ProposaFundManagementBlocklist
  *
  * @dev Blockable token has the ability to block (blacklist) addresses,
  *      preventing use of transferFrom, if either source or desitnation
  *      address is on the list. Examples of popular tokens with blacklist are
  *      stablecoins such as USDT, USDC, BUSD and Dai.
  * @dev For this test we block funders Alice and Bob so they can't withdraw
  *      their unspent tokens right away. After first failed withdraw we unblock
  *      their address and call withdraw again. Second call should be successful
  *      and they should receive their respective amounts nevertheless.
  * @author byterocket
  */

contract ProposaFundManagementBlocklist is E2eTest {
    address alice = address(0xA11CE);
    address bob = address(0x606);

    // @note Blockable token allows blocking(blacklisting)/unblocking
    //       individual addresses.
    // @dev transfer() is not overwritten by BlockableToken,
    //      so it may stil work.
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

        // In the meantime Alice and Bob get blocked
        token.blockUser(alice);
        token.blockUser(bob);
        assertTrue(token.isBlocked(alice));
        assertTrue(token.isBlocked(bob));

        // Alice is not able to withdraw half her funded tokens as long as she
        // is blocked. After being unblocked, withdraw is possible again.
        vm.startPrank(alice);
        {
            try proposal.withdraw(proposal.balanceOf(alice)) {
                // if withdraw is successful, test should fail.
                assertTrue(false);
            } catch {
                // Alice gets is unblocked again
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

        // Bob is not able to withdraw half his funded tokens since he
        // is blocked. After being unblocked, withdraw is possible again.
        vm.startPrank(bob);
        {
            try proposal.withdraw(proposal.balanceOf(bob)) {
                // if withdraw is successful, test should fail.
                assertTrue(false);
            } catch {
                // Bob gets in unblocked again
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
