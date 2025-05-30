# Issue in `_calculatePurchaseReturn`: Incorrect Handling of Partially Filled Initial Step

**Date:** 2025-05-30

## 1. Affected Function

- `DiscreteCurveMathLib_v1._calculatePurchaseReturn`
- Primarily its internal helper `_calculatePurchaseForSingleSegment` and the functions it calls for purchasing within that first segment (e.g., `_linearSearchSloped`, `_calculateFullStepsForFlatSegment`).

## 2. Problem Description

When a purchase transaction begins and the `currentTotalIssuanceSupply` indicates that the step from which the purchase should start is already partially filled, the current logic incorrectly attempts to make available the _entire_ `supplyPerStep` of that initial step for purchase (budget permitting). It does not correctly limit the purchase to only the _remaining_ supply within that partially filled step. This can lead to calculating a `tokensToMint` value that exceeds the actual available capacity of the curve from the `currentTotalIssuanceSupply` point onwards.

## 3. Simplified Test Case

- **Curve Setup:**
  - A single segment.
  - `initialPrice = 1 ether`
  - `priceIncrease = 0` (flat price for simplicity)
  - `supplyPerStep = 100 ether`
  - `numberOfSteps = 1`
  - (Total curve capacity = 100 ether)
- **Scenario:**
  - `currentTotalIssuanceSupply = 50 ether` (The single step is 50% filled).
  - `collateralToSpendProvided = 30 ether` (Sufficient budget to buy 30 tokens at price 1).

## 4. Expected Behavior

- The function should identify that the purchase starts within the first (and only) step, which has 100 ether total supply but 50 ether already minted.
- The actual remaining supply in this step is `100 ether (total step supply) - 50 ether (already minted in step) = 50 ether`.
- The purchase should be capped by this remaining 50 ether and the provided budget (30 ether).
- `tokensToMint` should be `30 ether`.
- `collateralSpentByPurchaser` should be `30 ether`.

## 5. Actual Behavior (as indicated by fuzz test failure)

- The logic in `_calculatePurchaseForSingleSegment` (and its helpers) is called for the first step (index 0).
- It considers the full `supplyPerStep` (100 ether) of this step as potentially available for purchase from its beginning, without accounting for the 50 ether already minted within it.
- If the budget were, for example, 100 ether (enough to buy all 100 tokens of the step if it were empty), the function would calculate `tokensToMint` as 100 ether based on this flawed premise.
- This calculated `tokensToMint` (e.g., 100 ether in the hypothetical budget case, or a large portion of it in the actual fuzz test) is then compared against the actual remaining capacity of the _entire curve_ (`totalCurveCapacity - currentTotalIssuanceSupply` = `100 ether - 50 ether = 50 ether`).
- The assertion `tokensToMint <= remainingCurveCapacity` (e.g., `100 ether <= 50 ether`) would fail, leading to the "Minted more than available capacity" error seen in the `testFuzz_CalculatePurchaseReturn_Properties` fuzz test.

## 6. Impact

- Causes `testFuzz_CalculatePurchaseReturn_Properties` to fail.
- If this logic were used in a live system without further checks in the consuming contract (e.g., FM_BC_DBC), it could lead to attempts to mint more tokens than are actually available from the current supply point, potentially causing reverts or incorrect state updates.

## 7. Suggested Fix (High-Level Summary)

The core purchasing logic within `_calculatePurchaseForSingleSegment` needs to be revised. When handling the very first segment/step of a purchase operation, it must:
a. Calculate the actual `supplyRemainingInStartStep` (i.e., how much of the `supplyPerStep` is actually available in the step where `currentTotalIssuanceSupply` currently lies).
b. The initial purchase attempt (whether it's a partial amount or fills that remaining portion of the start step) must be capped by this `supplyRemainingInStartStep`.
c. Only after this initial (potentially partial) step is handled should the logic proceed to purchase subsequent _full_ steps, if any, from the next step onwards.
d. A final partial purchase for any remaining budget is then handled by `_calculatePartialPurchaseAmount` as currently designed.
