# Weird ERC20 Tests

Check whether the contracts work with "weird" ERC20 tokens.

Contains End-to-End tests based on ProposalFundManagement.t.sol.

Each test is adopted differently to test the peculiarities of given token.

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
-Bob is also able to withdraw his remaining tokens normally.

LowDecimals & HighDecimals:
-For this test we will use fuzzing with different initialDeposits,
 aliceInitialBalance and bobInitialBalance and verify balances are correct and
 no errors are thrown.
