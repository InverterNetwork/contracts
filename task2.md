# Task 2: Global Accumulation Start Round

## Feature Description

Implement a feature allowing the `FUNDING_POT_ADMIN_ROLE` to configure a single, global minimum `roundId` (`globalAccumulationStartRoundId`) from which previous rounds should be considered for accumulative cap calculations (both personal and total), _if_ accumulation is enabled by the target round's `AccumulationMode`. This provides flexibility to globally exclude older rounds from contributing unused capacity to subsequent rounds.

## Acceptance Criteria

1.  **State Variable:**

    - A new `internal` state variable `uint32 internal globalAccumulationStartRoundId` shall be added to `LM_PC_FundingPot_v1.sol`.
    - The value stored represents the minimum `roundId` (inclusive) of a previous round to be included in accumulation calculations, _if_ the target round's `AccumulationMode` allows for accumulation (`Personal`, `Total`, or `All`).
    - The variable shall be initialized to `1` in the contract (e.g., via `__LM_PC_FundingPot_init` or directly if using Solidity >=0.8.18 default initialization feature), meaning accumulation considers rounds starting from round 1 by default.

2.  **Configuration Function:**

    - A new `external` function `setGlobalAccumulationStart(uint32 startRoundId_)` shall be implemented in `LM_PC_FundingPot_v1.sol`.
    - The function must be callable only by addresses holding the `FUNDING_POT_ADMIN_ROLE`.
    - It must revert if `startRoundId_ == 0` (minimum start round is 1).
    - It must revert if `startRoundId_` is greater than the current `roundCount` (cannot set a start round that doesn't exist yet).
    - On success, it updates `globalAccumulationStartRoundId = startRoundId_`.
    - On success, it emits the `GlobalAccumulationStartSet` event.

3.  **Getter Function:**

    - A new `external view` function `getGlobalAccumulationStartRoundId() returns (uint32)` shall be implemented in `LM_PC_FundingPot_v1.sol` and defined in the `ILM_PC_FundingPot_v1.sol` interface.
    - This function shall return the current value of the `globalAccumulationStartRoundId` state variable.

4.  **Event:**

    - A new event `GlobalAccumulationStartSet(uint32 startRoundId)` shall be defined in `ILM_PC_FundingPot_v1.sol` and emitted by `setGlobalAccumulationStart`.

5.  **Logic Integration - Total Cap Expansion:**

    - The internal function `_calculateUnusedCapacityFromPreviousRounds(uint32 targetRoundId_)` in `LM_PC_FundingPot_v1.sol` must be modified:
      - It shall read the global start round: `uint32 startRound = globalAccumulationStartRoundId`.
      - The check `if (startRound >= targetRoundId_)` (preventing looping when the start round is not strictly less than the target) must be performed. If true, return 0.
      - The loop calculating `unusedCapacityFromPrevious` must only iterate through rounds `i` where `startRound <= i < targetRoundId_`.

6.  **Logic Integration - Personal Cap Rollover:**

    - The `external` function `contributeToRoundFor(..., UnspentPersonalRoundCap[] calldata unspentPersonalRoundCaps_)` in `LM_PC_FundingPot_v1.sol` must be modified:
      - Inside the loop processing `unspentPersonalRoundCaps_`, it shall read the global start round: `uint32 startRound = globalAccumulationStartRoundId`.
      - An additional check must be performed within the loop: if the previous round ID from the struct (`roundCap.roundId`) is less than `startRound`, this specific `roundCap` entry must be skipped (`continue`), and its potential unused capacity must not be added to `unspentPersonalCap`.

7.  **Testing (`LM_PC_FundingPot_v1.t.sol`):**

    - Add tests for the `setGlobalAccumulationStart` function, covering:
      - Role-based access control (`FUNDING_POT_ADMIN_ROLE`).
      - Revert condition: `startRoundId_ == 0`.
      - Revert condition: `startRoundId_ > roundCount`.
      - Successful setting and event emission.
      - Correct update of the `globalAccumulationStartRoundId` state variable.
    - Add tests for the `getGlobalAccumulationStartRoundId` getter function:
      - Verify it returns the correct default value (1) initially.
      - Verify it returns the updated value after `setGlobalAccumulationStart` is called successfully.
    - Modify existing accumulation tests (or add new ones) for modes `Personal`, `Total`, and `All` to incorporate the global start round:
      - Test Case 1: In a multi-round setup (e.g., Round 1, 2, 3), set `globalAccumulationStartRoundId = 2`. Verify that accumulation calculations for Round 3 (when its mode is `Personal`, `Total`, or `All`) only consider Round 2 and ignore Round 1.
      - Test Case 2: In a multi-round setup (e.g., Round 1, 2, 3), keep the default `globalAccumulationStartRoundId = 1` (verify via getter). Verify that accumulation calculations for Round 3 (when its mode allows) consider both Round 1 and Round 2.
      - Test Case 3: Verify that if the target round's mode is `Disabled`, accumulation does not occur even if `globalAccumulationStartRoundId` is set to allow previous rounds.

8.  **Documentation (NatSpec):**
    - Add NatSpec comments for the new `globalAccumulationStartRoundId` state variable (documenting its purpose even though internal).
    - Add NatSpec comments for the `setGlobalAccumulationStart` function, `getGlobalAccumulationStartRoundId` function, and `GlobalAccumulationStartSet` event in both the interface (`ILM_PC_FundingPot_v1.sol`) and implementation (`LM_PC_FundingPot_v1.sol`) files.
    - Update existing NatSpec comments where relevant to mention the global start round constraint on accumulation.

## Implementation Plan

**(TDD Approach - Commit-sized tasks)**

1.  **Interface Definitions (`ILM_PC_FundingPot_v1.sol`):**

    - Define the `GlobalAccumulationStartSet(uint32 startRoundId)` event.
    - Define the `setGlobalAccumulationStart(uint32 startRoundId_)` external function signature.
    - Define the `getGlobalAccumulationStartRoundId() external view returns (uint32)` function signature.
    - Add NatSpec comments for the new event and functions.
    - _(Commit 1: Interface updates)_

2.  **Setter & Getter Tests (`LM_PC_FundingPot_v1.t.sol`):**

    - Add a new test suite or section for `setGlobalAccumulationStart` and `getGlobalAccumulationStartRoundId`.
    - Test role access control for the setter.
    - Test revert condition `startRoundId_ == 0` for the setter.
    - Test revert condition `startRoundId_ > roundCount` for the setter.
    - Test successful setting and event emission for the setter.
    - Test the getter returns the correct value after successful setting.
    - Test the getter returns the default value (1) initially.
    - _(Commit 2: Failing tests for setter/getter)_

3.  **State, Setter & Getter Implementation (`LM_PC_FundingPot_v1.sol`):**

    - Add the `uint32 internal globalAccumulationStartRoundId = 1;` state variable.
    - Implement the `setGlobalAccumulationStart(uint32 startRoundId_)` function (including role check, reverts, state update, event emission).
    - Implement the `getGlobalAccumulationStartRoundId() external view returns (uint32)` function.
    - Add basic NatSpec for the new state var and functions (in the interface contract).
    - _(Commit 3: Implement setter/getter to make tests pass)_

4.  **Accumulation Logic Tests (`LM_PC_FundingPot_v1.t.sol`):**

    - Add _new, separate_ tests dedicated to verifying the interaction between `AccumulationMode` (`Personal`, `Total`, `All`) and the `globalAccumulationStartRoundId` constraint.
    - Cover scenarios like setting start round to 2, verifying default start round 1 via getter, and interaction with `Disabled` mode (Acceptance Criterion #7).
    - _(Commit 4: Failing tests for accumulation logic with global start)_

5.  **Logic Integration (Total & Personal Cap) (`LM_PC_FundingPot_v1.sol`):**

    - Modify `_calculateUnusedCapacityFromPreviousRounds` to read `globalAccumulationStartRoundId`, check `startRound >= targetRoundId_`, and adjust the loop start.
    - Modify `contributeToRoundFor(..., UnspentPersonalRoundCap[] ...)` to read `globalAccumulationStartRoundId` within the loop and skip rounds where `roundCap.roundId < startRound`.
    - _(Commit 5: Implement logic changes to make accumulation tests pass)_

6.  **Documentation Update (`ILM_PC_FundingPot_v1.sol` & `LM_PC_FundingPot_v1.sol`):**
    - Review and update all relevant NatSpec comments (interface and implementation) to comprehensively document the new variable, functions, event, and the global start round constraint's effect on accumulation.
    - _(Commit 6: Final documentation)_
