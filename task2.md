# Task 2: Global Accumulation Start Round

## Feature Description

Implement a feature allowing the `FUNDING_POT_ADMIN_ROLE` to configure a single, global minimum `roundId` (`globalAccumulationStartRoundId`) from which previous rounds should be considered for accumulative cap calculations (both personal and total), _if_ accumulation is enabled by the target round's `AccumulationMode`. This provides flexibility to globally exclude older rounds from contributing unused capacity to subsequent rounds.

## Acceptance Criteria

1.  **State Variable:**

    - A new `public` state variable `uint32 public globalAccumulationStartRoundId` shall be added to `LM_PC_FundingPot_v1.sol`.
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

    - The `public` visibility of the `globalAccumulationStartRoundId` variable serves as the getter. No separate getter function is required.

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
      - Verification of the default initial value (should be 1).
    - Modify existing accumulation tests (or add new ones) for modes `Personal`, `Total`, and `All` to incorporate the global start round:
      - Test Case 1: In a multi-round setup (e.g., Round 1, 2, 3), set `globalAccumulationStartRoundId = 2`. Verify that accumulation calculations for Round 3 (when its mode is `Personal`, `Total`, or `All`) only consider Round 2 and ignore Round 1.
      - Test Case 2: In a multi-round setup (e.g., Round 1, 2, 3), keep the default `globalAccumulationStartRoundId = 1`. Verify that accumulation calculations for Round 3 (when its mode allows) consider both Round 1 and Round 2.
      - Test Case 3: Verify that if the target round's mode is `Disabled`, accumulation does not occur even if `globalAccumulationStartRoundId` is set to allow previous rounds.

8.  **Documentation (NatSpec):**
    - Add NatSpec comments for the new `globalAccumulationStartRoundId` state variable in `LM_PC_FundingPot_v1.sol`.
    - Add NatSpec comments for the `setGlobalAccumulationStart` function and `GlobalAccumulationStartSet` event in both the interface (`ILM_PC_FundingPot_v1.sol`) and implementation (`LM_PC_FundingPot_v1.sol`) files.
    - Update existing NatSpec comments where relevant to mention the global start round constraint on accumulation.

## Implementation Plan

**(Commit-sized tasks)**

1.  **Interface Definitions (`ILM_PC_FundingPot_v1.sol`):**

    - Define the `GlobalAccumulationStartSet(uint32 startRoundId)` event.
    - Define the `setGlobalAccumulationStart(uint32 startRoundId_)` external function signature.
    - Add NatSpec comments for the new event and function.

2.  **State and Setter Implementation (`LM_PC_FundingPot_v1.sol`):**

    - Add the `uint32 public globalAccumulationStartRoundId = 1;` state variable.
    - Implement the `setGlobalAccumulationStart(uint32 startRoundId_)` function:
      - Add `onlyModuleRole(FUNDING_POT_ADMIN_ROLE)` modifier.
      - Add revert checks: `startRoundId_ == 0` and `startRoundId_ > roundCount`.
      - Update the `globalAccumulationStartRoundId` state variable.
      - Emit the `GlobalAccumulationStartSet` event.
    - Add NatSpec comments for the state variable and the implemented function.

3.  **Logic Integration - Total Cap (`LM_PC_FundingPot_v1.sol`):**

    - Modify the internal function `_calculateUnusedCapacityFromPreviousRounds`:
      - Read `globalAccumulationStartRoundId`.
      - Add check: `if (startRound >= targetRoundId_) return 0;`
      - Adjust the loop to start from `globalAccumulationStartRoundId`: `for (uint32 i = startRound; i < targetRoundId_; ++i)`.

4.  **Logic Integration - Personal Cap (`LM_PC_FundingPot_v1.sol`):**

    - Modify the `external` function `contributeToRoundFor(..., UnspentPersonalRoundCap[] ...)`:
      - Inside the loop processing `unspentPersonalRoundCaps_`, read `globalAccumulationStartRoundId`.
      - Add a check: `if (roundCap.roundId < startRound) continue;` before calculating/adding the unspent capacity for that specific previous round.

5.  **Setter Function Tests (`LM_PC_FundingPot_v1.t.sol`):**

    - Add a new test suite or section for `setGlobalAccumulationStart`.
    - Test role access control.
    - Test revert condition `startRoundId_ == 0`.
    - Test revert condition `startRoundId_ > roundCount`.
    - Test successful setting and event emission.
    - Test correct state variable update.
    - Test reading the default value (should be 1 initially).

6.  **Accumulation Logic Tests (`LM_PC_FundingPot_v1.t.sol`):**

    - Modify existing accumulation tests (`Personal`, `Total`, `All` modes) or add specific new tests to verify the interaction with `globalAccumulationStartRoundId`.
    - Cover the scenarios outlined in Acceptance Criterion #7 (e.g., setting start round to 2, verifying default start round 1, checking interaction with `Disabled` mode).

7.  **Documentation Update (`ILM_PC_FundingPot_v1.sol` & `LM_PC_FundingPot_v1.sol`):**
    - Review and update NatSpec comments for functions/structs/enums affected by accumulation (e.g., `AccumulationMode`, `contributeToRoundFor`, `_calculateUnusedCapacityFromPreviousRounds`) to mention the constraint imposed by `globalAccumulationStartRoundId`.
