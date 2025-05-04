# Understanding `globalAccumulativeCaps` in `LM_PC_FundingPot_v1`

The `globalAccumulativeCaps` parameter is a boolean flag within the `LM_PC_FundingPot_v1` smart contract. It can be configured individually for each funding round during its creation (`createRound`) or modification (`editRound`). This flag significantly impacts how contribution limits (both the total round cap and individual personal caps) behave across multiple funding rounds.

## Status Quo

### When `globalAccumulativeCaps` is `true` for a round:

1.  **Personal Cap Rollover:**

    - Users who did not fully utilize their _personal contribution cap_ in a _previous_ round (which _also_ had `globalAccumulativeCaps=true`) can potentially carry over that unused amount.
    - This increases their effective personal cap for the _current_ round.
    - To utilize this feature, the user must call the `contributeToRoundFor` function overload that accepts the `unspentPersonalRoundCaps_` parameter, specifying the previous round(s) and access criteria they want to draw unused capacity from.
    - The contract verifies the user's eligibility in those specified previous rounds before adding the unused capacity.

2.  **Round Cap Expansion:**
    - The _effective total contribution cap_ for the current round is potentially increased.
    - The effective cap becomes the round's base `roundCap` **plus** the sum of all _unfilled capacity_ (`roundCap - totalContributions`) from _all previous_ rounds that _also_ had `globalAccumulativeCaps=true`.
    - This allows the current round to potentially accept more total funding than its initially defined `roundCap`, especially if prior accumulative rounds were undersubscribed.
    - This calculation happens internally within the `_validateAndAdjustCapsWithUnspentCap` function.

### When `globalAccumulativeCaps` is `false` for a round:

1.  **No Personal Cap Rollover:**

    - Any unused personal contribution capacity from this round _cannot_ be carried over to future rounds, regardless of their settings.
    - This round _cannot_ benefit from unused personal capacity from previous rounds.

2.  **No Round Cap Expansion:**
    - The round's total contribution limit is strictly enforced by its own `roundCap`.
    - The cap does not increase based on undersubscription in previous rounds.
    - Any undersubscription in this round does not contribute to expanding the cap of future rounds.

### Summary

Setting `globalAccumulativeCaps = true` links the contribution capacity (both personal and total) of a round with other rounds that share the same setting. It enables a dynamic system where unused potential from earlier rounds can be utilized in later ones, potentially leading to a larger overall fundraising capacity across the series of rounds.

Conversely, setting `globalAccumulativeCaps = false` isolates the round's contribution limits, making its capacity independent of past or future rounds.

### Affected tests

- `testEditRound()`
- `testcontributeToRoundFor_worksGivenPersonalCapAccumulation()`
- `testcontributeToRoundFor_worksGivenTotalRoundCapAccumulation()`
- `testFuzz_validateAndAdjustCapsWithUnspentCap`

## New Features

### 1. Differentiation between personal and total cap

#### Acceptance Criteria

1.  **Enum Definition:** An enum `AccumulationMode` shall be defined within `LM_PC_FundingPot_v1.sol` with the following values: `Disabled`, `Personal`, `Total`, `All`.
2.  **Struct Update:** The `globalAccumulativeCaps` boolean field in the `Round` struct (`LM_PC_FundingPot_v1.sol`) shall be replaced with a field of type `AccumulationMode`, named `accumulationMode`.
3.  **Interface Update:** The `ILM_PC_FundingPot_v1` interface shall be updated to reflect the changes:
    - Function signatures for `createRound`, `editRound`, `getRoundGenericParameters` must accept/return the `AccumulationMode` enum instead of the boolean.
    - Event signatures for `RoundCreated` and `RoundEdited` must include the `AccumulationMode` enum instead of the boolean.
4.  **Core Logic Implementation:** The internal logic of `LM_PC_FundingPot_v1.sol` must correctly implement the behavior defined by the `AccumulationMode`:
    - **`Disabled`**: Behaves identically to the previous `globalAccumulativeCaps = false`. No personal cap rollover, no total round cap expansion.
    - **`Personal`**: Only personal caps accumulate. The `_validateAndAdjustCapsWithUnspentCap` function should consider `unspentPersonalCap_` (if provided via the relevant `contributeToRoundFor` overload and the source round allows it via `Personal` or `All` mode), but the effective round cap (`effectiveRoundCap`) should _not_ be increased by `_calculateUnusedCapacityFromPreviousRounds`.
    - **`Total`**: Only total round caps accumulate. The `_validateAndAdjustCapsWithUnspentCap` function should _not_ consider `unspentPersonalCap_`, but the effective round cap (`effectiveRoundCap`) _should_ be increased by `_calculateUnusedCapacityFromPreviousRounds` (considering only previous rounds set to `Total` or `All`).
    - **`All`**: Behaves identically to the previous `globalAccumulativeCaps = true`. Both personal cap rollover and total round cap expansion are enabled, considering source rounds set appropriately (`Personal` or `All` for personal, `Total` or `All` for total).
5.  **Test Adaptation:** Existing tests in `LM_PC_FundingPot_v1.t.sol` that previously tested `globalAccumulativeCaps = true` or `false` must be updated to use `AccumulationMode.All` and `AccumulationMode.Disabled` respectively and pass.
6.  **New Test Coverage:** New tests must be added to specifically validate the unique behaviors of `AccumulationMode.Personal` and `AccumulationMode.Total`.

#### Implementation Plan (TDD Approach)

1.  **Define Enum & Update Signatures (Code):**
    - Define the `AccumulationMode` enum in `LM_PC_FundingPot_v1.sol`.
    - Modify the `Round` struct in `LM_PC_FundingPot_v1.sol` to use `accumulationMode` (enum) instead of `globalAccumulativeCaps` (bool).
    - Update the function parameters and return types (`createRound`, `editRound`, `getRoundGenericParameters`) in `LM_PC_FundingPot_v1.sol` to use the enum.
    - Update the event definitions (`RoundCreated`, `RoundEdited`) in `LM_PC_FundingPot_v1.sol`.
    - Update the `ILM_PC_FundingPot_v1` interface accordingly.
2.  **Update Tests for Compile & Basic Functionality (Tests):**
    - Modify the `RoundParams` struct in `LM_PC_FundingPot_v1.t.sol` to use the enum.
    - Update test helper functions (e.g., `_helper_createEditRoundParams`) to accept and use the enum.
    - Modify existing tests that interact with round creation/editing/getters to use the new enum values (`Disabled` for old `false`, `All` for old `true`).
    - **Goal:** Get the test suite to compile. Expect tests related to accumulation logic to fail.
3.  **Write Tests for `Personal` Mode (Tests):**
    - Add a new test case (e.g., `testContribute_PersonalMode_AccumulatesPersonalOnly`) verifying:
      - Personal cap rolls over correctly when using `unspentPersonalRoundCaps_` from a previous `Personal` or `All` round.
      - Contribution fails/is capped if it exceeds the _base_ `roundCap`, even if previous `Personal` rounds were undersubscribed.
    - **Goal:** This test should fail.
4.  **Implement `Personal` Mode Logic (Code):**
    - Modify `_validateAndAdjustCapsWithUnspentCap`: Add checks for `accumulationMode == AccumulationMode.Personal`. Ensure `unspentPersonalCap_` is added to `userPersonalCap` but `_calculateUnusedCapacityFromPreviousRounds` is _not_ used for `effectiveRoundCap`.
    - Modify `contributeToRoundFor` (overload with `unspentPersonalRoundCaps_`): Ensure it only considers previous rounds with `Personal` or `All` mode for rollover.
    - **Goal:** Make the `Personal` mode test pass. Fix related failures in existing tests (now using `All`/`Disabled`).
5.  **Write Tests for `Total` Mode (Tests):**
    - Add a new test case (e.g., `testContribute_TotalMode_AccumulatesTotalOnly`) verifying:
      - The `effectiveRoundCap` expands correctly based on undersubscription in previous `Total` or `All` rounds.
      - Personal cap does _not_ roll over; contributions are capped by the current round's personal cap, even if `unspentPersonalRoundCaps_` is provided.
    - **Goal:** This test should fail.
6.  **Implement `Total` Mode Logic (Code):**
    - Modify `_validateAndAdjustCapsWithUnspentCap`: Add checks for `accumulationMode == AccumulationMode.Total`. Ensure `_calculateUnusedCapacityFromPreviousRounds` is used for `effectiveRoundCap` but `unspentPersonalCap_` is _not_ added to `userPersonalCap`.
    - Modify `_calculateUnusedCapacityFromPreviousRounds`: Ensure it only sums capacity from previous rounds with `Total` or `All` mode.
    - **Goal:** Make the `Total` mode test pass. Fix related failures in existing tests.
7.  **Refine `Disabled` & `All` Implementation (Code & Tests):**
    - Explicitly implement the logic for `Disabled` mode in conditional checks (should mirror original `false` behavior - no accumulation).
    - Ensure `All` mode correctly combines the logic implemented for `Personal` and `Total` (should mirror original `true` behavior).
    - Run the full test suite.
    - **Goal:** All tests should pass.
8.  **Documentation & Cleanup (Code):**
    - Update NatSpec comments for modified functions and events to reflect the new `AccumulationMode` enum.
    - Review code for clarity and potential gas optimizations.

## TODO

## Acceptance Criteria

1.  **Enum Definition:** An enum `AccumulationMode` shall be defined within `LM_PC_FundingPot_v1.sol` with the following values: `Disabled`, `Personal`, `Total`, `All`.
2.  **Struct Update:** The `globalAccumulativeCaps` boolean field in the `Round` struct (`LM_PC_FundingPot_v1.sol`) shall be replaced with a field of type `AccumulationMode`, named `accumulationMode`.
3.  **Interface Update:** The `ILM_PC_FundingPot_v1` interface shall be updated to reflect the changes:
    - Function signatures for `createRound`, `editRound`, `getRoundGenericParameters` must accept/return the `AccumulationMode` enum instead of the boolean.
    - Event signatures for `RoundCreated` and `RoundEdited` must include the `AccumulationMode` enum instead of the boolean.
4.  **Core Logic Implementation:** The internal logic of `LM_PC_FundingPot_v1.sol` must correctly implement the behavior defined by the `AccumulationMode`:
    - **`Disabled`**: Behaves identically to the previous `globalAccumulativeCaps = false`. No personal cap rollover, no total round cap expansion.
    - **`Personal`**: Only personal caps accumulate. The `_validateAndAdjustCapsWithUnspentCap` function should consider `unspentPersonalCap_` (if provided via the relevant `contributeToRoundFor` overload and the source round allows it via `Personal` or `All` mode), but the effective round cap (`effectiveRoundCap`) should _not_ be increased by `_calculateUnusedCapacityFromPreviousRounds`.
    - **`Total`**: Only total round caps accumulate. The `_validateAndAdjustCapsWithUnspentCap` function should _not_ consider `unspentPersonalCap_`, but the effective round cap (`effectiveRoundCap`) _should_ be increased by `_calculateUnusedCapacityFromPreviousRounds` (considering only previous rounds set to `Total` or `All`).
    - **`All`**: Behaves identically to the previous `globalAccumulativeCaps = true`. Both personal cap rollover and total round cap expansion are enabled, considering source rounds set appropriately (`Personal` or `All` for personal, `Total` or `All` for total).
5.  **Test Adaptation:** Existing tests in `LM_PC_FundingPot_v1.t.sol` that previously tested `globalAccumulativeCaps = true` or `false` must be updated to use `AccumulationMode.All` and `AccumulationMode.Disabled` respectively and pass.
6.  **New Test Coverage:** New tests must be added to specifically validate the unique behaviors of `AccumulationMode.Personal` and `AccumulationMode.Total`.

## Implementation Plan (TDD Approach)

1.  **Define Enum & Update Signatures (Code):**
    - Define the `AccumulationMode` enum in `LM_PC_FundingPot_v1.sol`.
    - Modify the `Round` struct in `LM_PC_FundingPot_v1.sol` to use `accumulationMode` (enum) instead of `globalAccumulativeCaps` (bool).
    - Update the function parameters and return types (`createRound`, `editRound`, `getRoundGenericParameters`) in `LM_PC_FundingPot_v1.sol` to use the enum.
    - Update the event definitions (`RoundCreated`, `RoundEdited`) in `LM_PC_FundingPot_v1.sol`.
    - Update the `ILM_PC_FundingPot_v1` interface accordingly.
2.  **Update Tests for Compile & Basic Functionality (Tests):**
    - Modify the `RoundParams` struct in `LM_PC_FundingPot_v1.t.sol` to use the enum.
    - Update test helper functions (e.g., `_helper_createEditRoundParams`) to accept and use the enum.
    - Modify existing tests that interact with round creation/editing/getters to use the new enum values (`Disabled` for old `false`, `All` for old `true`).
    - **Goal:** Get the test suite to compile. Expect tests related to accumulation logic to fail.
3.  **Write Tests for `Personal` Mode (Tests):**
    - Add a new test case (e.g., `testContribute_PersonalMode_AccumulatesPersonalOnly`) verifying:
      - Personal cap rolls over correctly when using `unspentPersonalRoundCaps_` from a previous `Personal` or `All` round.
      - Contribution fails/is capped if it exceeds the _base_ `roundCap`, even if previous `Personal` rounds were undersubscribed.
    - **Goal:** This test should fail.
4.  **Implement `Personal` Mode Logic (Code):**
    - Modify `_validateAndAdjustCapsWithUnspentCap`: Add checks for `accumulationMode == AccumulationMode.Personal`. Ensure `unspentPersonalCap_` is added to `userPersonalCap` but `_calculateUnusedCapacityFromPreviousRounds` is _not_ used for `effectiveRoundCap`.
    - Modify `contributeToRoundFor` (overload with `unspentPersonalRoundCaps_`): Ensure it only considers previous rounds with `Personal` or `All` mode for rollover.
    - **Goal:** Make the `Personal` mode test pass. Fix related failures in existing tests (now using `All`/`Disabled`).
5.  **Write Tests for `Total` Mode (Tests):**
    - Add a new test case (e.g., `testContribute_TotalMode_AccumulatesTotalOnly`) verifying:
      - The `effectiveRoundCap` expands correctly based on undersubscription in previous `Total` or `All` rounds.
      - Personal cap does _not_ roll over; contributions are capped by the current round's personal cap, even if `unspentPersonalRoundCaps_` is provided.
    - **Goal:** This test should fail.
6.  **Implement `Total` Mode Logic (Code):**
    - Modify `_validateAndAdjustCapsWithUnspentCap`: Add checks for `accumulationMode == AccumulationMode.Total`. Ensure `_calculateUnusedCapacityFromPreviousRounds` is used for `effectiveRoundCap` but `unspentPersonalCap_` is _not_ added to `userPersonalCap`.
    - Modify `_calculateUnusedCapacityFromPreviousRounds`: Ensure it only sums capacity from previous rounds with `Total` or `All` mode.
    - **Goal:** Make the `Total` mode test pass. Fix related failures in existing tests.
7.  **Refine `Disabled` & `All` Implementation (Code & Tests):**
    - Explicitly implement the logic for `Disabled` mode in conditional checks (should mirror original `false` behavior - no accumulation).
    - Ensure `All` mode correctly combines the logic implemented for `Personal` and `Total` (should mirror original `true` behavior).
    - Run the full test suite.
    - **Goal:** All tests should pass.
8.  **Documentation & Cleanup (Code):**
    - Update NatSpec comments for modified functions and events to reflect the new `AccumulationMode` enum.
    - Review code for clarity and potential gas optimizations.
