// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import {E2eTest} from "test/e2e/E2eTest.sol";
import "forge-std/Test.sol";

import {IProposalFactory} from "src/factories/ProposalFactory.sol";
import {IProposal} from "src/proposal/Proposal.sol";

// Mocks
import {LowDecimalsToken} from "test/utils/mocks/weird_ERC20/LowDecimalsToken.sol";

/**
 * @title ProposaFundManagementLowDecimals
 *
 * @dev LowDecimals token has significantly less decimals than the standard
 *      18. We will use token with 2 decimals, which simulates token
 *     such as BUSD, a widely used stablecoin issued on the
 *      Binance Smart Chain.
 *
 * @author byterocket
 */

contract ProposaFundManagementLowDecimals is E2eTest {
    address alice = address(0xA11CE);
    address bob = address(0x606);


    LowDecimalsToken token = new LowDecimalsToken(10e18);

    function test_e2e_ProposalFundManagement(
        uint initialDeposit,
        uint aliceInitialBalance,
        uint bobInitialBalance
    )
        public
    {
        // @dev Make sure amounts are divisible by 2, otherwise tests may fail.
        // @note DEPOSIT_CAP in FundingManager ensures proposal never holds
        //       more than 100_000_000e18
        initialDeposit = bound(initialDeposit, 2, 10e27);
        aliceInitialBalance = bound(aliceInitialBalance, 2, 10e27);
        bobInitialBalance = bound(bobInitialBalance, 2, 10e27);
        vm.assume(initialDeposit %2== 0);
        vm.assume(aliceInitialBalance %2== 0);
        vm.assume(bobInitialBalance %2== 0);
        vm.assume(
            initialDeposit + aliceInitialBalance + bobInitialBalance <=
            100_000_000e18
        );
        // address(this) creates a new proposal.
        IProposalFactory.ProposalConfig memory proposalConfig = IProposalFactory
            .ProposalConfig({owner: address(this), token: token});

        IProposal proposal = _createNewProposalWithAllModules(proposalConfig);

        // IMPORTANT
        // =========
        // Due to how the underlying rebase mechanism works, it is necessary
        // to always have some amount of tokens in the proposal.
        // It's best, if the owner deposits them right after deployment.

        // @dev Make sure amounts are divisible by 2, otherwise tests may fail.
        // uint initialDeposit = 10e18;
        // uint aliceInitialBalance = 10;
        // uint bobInitialBalance = 50;

        token.mint(address(this), initialDeposit);
        token.approve(address(proposal), initialDeposit);
        proposal.deposit(initialDeposit);

        // Mint some tokens to alice and bob in order to fund the proposal.
        token.mint(alice, aliceInitialBalance);
        token.mint(bob, bobInitialBalance);

        // Alice funds the proposal with 1k tokens.
        vm.startPrank(alice);
        {
            // Approve tokens to proposal.
            token.approve(address(proposal), aliceInitialBalance);

            // Deposit tokens, i.e. fund the proposal.
            proposal.deposit(aliceInitialBalance);

            // After the deposit, alice received some amount of receipt tokens
            // from the proposal.
            assertTrue(proposal.balanceOf(alice) > 0);
        }
        vm.stopPrank();

        // Bob funds the proposal with 5k tokens.
        vm.startPrank(bob);
        {
            // Approve tokens to proposal.
            token.approve(address(proposal), bobInitialBalance);

            // Deposit tokens, i.e. fund the proposal.
            proposal.deposit(bobInitialBalance);

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

        // Alice is now able to withdraw half her funded tokens.
        vm.startPrank(alice);
        {
            proposal.withdraw(proposal.balanceOf(alice));
            assertEq(token.balanceOf(alice), aliceInitialBalance/2);
        }
        vm.stopPrank();

        // Bob is also able to withdraw half of his funded tokens.
        vm.startPrank(bob);
        {
            proposal.withdraw(proposal.balanceOf(bob));
            assertEq(token.balanceOf(bob), bobInitialBalance/2);
        }
        vm.stopPrank();

        // After redeeming all their proposal function tokens, the tokens got
        // burned.
        assertEq(proposal.balanceOf(alice), 0);
        assertEq(proposal.balanceOf(bob), 0);
    }
}
