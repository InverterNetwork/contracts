# Weird ERC20 Tests

Check whether the contracts work with "weird" ERC20 tokens.

Contains End-to-End tests based on ProposalFundManagement.t.sol.

Tests are adjusted differently to test the peculiarities of given token.

We check that balances on withdrawals and deposits are still correct.

LIST:

Blocklist:
-If a user is blocked and cannot withdraw, they should still be able to withdraw
 later.
-Other users are able to withdraw tokens normally afterwards, keeping internal
 tracking of balances intact.

Pauseable:
-Alice can't approve tokens in order to deposit them to proposal. Once she is
 unblocked, she can deposit as usual.
-Bob gets blocked after he has already approved the deposit to proposal. Deposit
 will fail, but if he gets unblocked again, he can deposit without the need
 to approve again.
-Alice is not able to withdraw half her funded tokens as long token is Paused.
 After that withdraw is possible again.
-Bob is also able to withdraw his remaining tokens normally demonstrating
 correctness of internal balance tracking

LowDecimals & HighDecimals:
-For this test we will use fuzzing with different initialDeposits,
 aliceInitialBalance and bobInitialBalance and verify balances are correct and
 no errors are thrown during the token transfers.

CONSTRAINS:

-contributors payout is not actually implemented in the tests but is instead
 simulated by simply burning tokens in proposal.
 For more accurate results it might be worth testing actual contributor payouts
 as well, and initiating weird ERC20 specific operations for either every
 transfer operation, or in random sequences. This goes for tokens with special
 callable functions, such pause/unpause or block/unblock.
-some weird erc20 tokens without explicitly callable functions are instead
 fuzzed to check if different amounts can break internal contract state.
