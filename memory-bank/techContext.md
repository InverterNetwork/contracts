# Technical Context

**Technologies Used:**

*   Solidity (smart contract language)
*   Foundry (development and testing framework)
*   Everclear Protocol (cross-chain communication)
*   ERC20 (token standard)

**Development Setup:**

*   The project uses Foundry for development and testing.
*   Dependencies are managed using `forge install`.
*   Code style adheres to Solidity best practices.

**Technical Constraints:**

*   Smart contract size limitations on Ethereum.
*   Gas optimization requirements for efficient execution.
*   Security considerations to prevent vulnerabilities.

**Tool Usage Patterns:**

*   **Foundry `vm.expectEmit`**:
    *   The order of `vm.expectEmit` calls must precisely match the actual sequence of emitted events. An unconsumed or unexpected event will lead to a `log != expected log` failure.
    *   When checking events from external contracts for which a local Solidity interface might not be available or desired for the `emit EventType(...)` statement in the test:
        *   The most lenient form is `vm.expectEmit(false, false, false, false, emitterAddress);`. This tells Foundry to expect an event from `emitterAddress` but not to check any topics (indexed parameters) or the data (non-indexed parameters). This is useful for consuming an external event to ensure the log queue is correctly processed for subsequent checks of internal events.
        *   It's crucial that `emitterAddress` correctly identifies the contract emitting the event. For proxied contracts, this is typically the proxy's address, as events from delegatecalls are attributed to the proxy.
    *   Foundry does *not* have an overload like `vm.expectEmit(address emitter, bytes32 topic0_signature_hash)`. To check specific topic values, one must use overloads like `vm.expectEmit(bool checkTopic1, bool checkTopic2, bool checkTopic3, bool checkData, address emitter)` and provide a corresponding `emit EventType(...)` statement in the test code. The boolean flags then control which parts of the test's `emit` statement are matched against the actual log.
    *   `topicN` in `checkTopicN` refers to the Nth *indexed* parameter of the event. `topic0` is implicitly the event signature, which is matched based on the `emit EventType(...)` statement in the test.
    *   `vm.resetExpectEmit()` can be used to clear any pending (unmatched) `vm.expectEmit` calls, which can be helpful for debugging complex event sequences.
    *   Detailed trace analysis (e.g., `forge test -vvvv`) is essential for debugging `log != expected log` errors, as it shows the actual sequence of emitted events and their parameters.
*   **Role Hashing**: For Foundry tests involving role-based access control, use the direct role `bytes32` constants from contracts (e.g., `paymentClient.PAYMENT_PUSHER_ROLE()`) rather than re-calculating hashes like `keccak256(abi.encodePacked(...))` within the test, as the latter can lead to mismatches if not done precisely as in the contract.
*   **Fork Testing**: When testing interactions with deployed contracts on a fork:
    *   Ensure RPC URLs are correctly configured in `foundry.toml` or environment variables.
    *   Be aware that external contract behavior might depend on their state on the forked chain.
    *   Event matching for external contracts can sometimes be tricky if their exact event signatures or emitting logic have subtle differences not captured in local interfaces.
