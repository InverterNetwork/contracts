**Important Note on Validation:**

The `_calculatePurchaseReturn` function, as outlined in this refactoring document, operates under a new core assumption:

- **No Internal Segment Validation**: The function will NOT perform any validation on the input `segments_` configuration (e.g., checking for price progression, zero-price segments, segment limits). It is assumed that the provided `segments_` array is pre-validated by the caller (e.g., during `configureCurve` in `FM_BC_DBC`).
- **Trust Input Parameters**: The function will trust `segments_`, `currentTotalIssuanceSupply_`, and `collateralToSpendProvided_` as given. If these parameters are inconsistent or nonsensical when combined, the function may return unexpected or "weird" results, and this is considered acceptable behavior for this specific function. The responsibility for providing valid and consistent inputs lies entirely with the calling contract.

---

## Important note on stack

- this function contains a lot of stack operations, so it is important to keep the stack size low

## Important new assumptions

- there cannot be free segments (where price is zero)
- there canot be segments that have more than one step but where the price increase is zero
- a segment can only be flat by having just one step

**Segment params:**

```
    uint initialPrice_,
    uint priceIncrease_,
    uint supplyPerStep_,
    uint numberOfSteps_
```

**Glossary:**

- supply: refers to actually provided issuance supply (not capacity) of a curve, segment or step
- capacity: refers to the maximum issuance supply that can be provided by a curve, segment or step
- budget: the amount of collateral that is available for purchase

**1. Find current segment index**

- track issuance supply provided by previous segments (previousSegmentIssuanceSupply)
- track collateral supply locked by previous segments (previousSegmentCollateralSupply)

- iterate over segments

  - calc total issuance capacity of current segment:
    segmentIssuanceCapacity = supplyPerStep \* numberOfSteps

  - calc collateral capacity of current segment:

    - if priceIncrease = 0 (flat segment):
      segmentCollateralCapacity = initialPrice \* supplyPerStep \* numberOfSteps

    - if priceIncrease > 0 (sloped segment):
      firstStepPrice = initialPrice
      lastStepPrice = initialPrice + (priceIncrease \* (numberOfSteps - 1))
      averagePrice = (firstStepPrice + lastStepPrice) / 2
      segmentCollateralCapacity = averagePrice \* supplyPerStep \* numberOfSteps

  - check if currentIssuanceSupply is greater than previousSegmentIssuanceSupply (= means we are definitely not in the right segment)

  - if so

    - add segmentIssuanceCapacity to previousSegmentIssuanceSupply
    - add segmentCollateralCapacity to previousSegmentCollateralSupply
    - jump to next segment

  - if not we are in the right segment for the starting point on the curve

**2. Find current step index (where startpoint lies)**

- calc amount of issuance supply actually provided by segment:
  segmentIssuanceSupply = currentIssuanceSupply - previousSegmentIssuanceSupply
- calc current step index:
  stepIndex = segmentIssuanceSupply / supplyPerStep (solidity rounds down, which is what we need)

**3. Distribute budget until fully exhausted**

- keep track of remaining collateral budget to be spent (= budget)
- keep track of issuance amount to be issued in return for budget (= issuanceAmountOut)

**3a. Fill collateral of current step (partial start step)**

- calc issuance supply that is actually provided by current step (not capacity):
  currentStepIssuanceSupply = segmentIssuanceSupply % supplyPerStep

- if currentStepIssuanceSupply = 0:

  - skip step 3a entirely, go straight to 3b

- if currentStepIssuanceSupply > 0:

  - calc price of current step:
    stepPrice = initialPriceOfSegment + (priceIncreasePerStep \* stepIndex)
  - calc relative fill ratio of current step:
    fillRatio = currentStepIssuanceSupply / supplyPerStep
  - calc remaining collateral capacity of current step:
    stepCollateralCapacity = stepPrice \* supplyPerStep
    currentStepCollateralSupply = fillRatio \* stepCollateralCapacity
    remainingStepCollateralCapacity = (1 - fillRatio) \* stepCollateralCapacity

  - if budget is greater than remainingStepCollateralCapacity:

    - subtract remaining collateral capacity from budget
    - calc remaining issuance supply of current step:
      remainingStepIssuanceSupply = supplyPerStep - currentStepIssuanceSupply
    - add remaining issuance supply to issuanceAmountOut
    - increment stepIndex

  - if not, end point is in current step:
    - calc target fill rate of current step:
      targetFillRate = (currentStepCollateralSupply + budget) / stepCollateralCapacity
    - calc additional issuance amount provided by step:
      additionalIssuanceAmount = (targetFillRate - fillRatio) \* supplyPerStep
    - add additionalIssuanceAmount to issuanceAmountOut and return

3b. Start iterating over steps:

- while budget > 0:
  - if stepIndex >= numberOfSteps: [move to next segment logic]

  - if current segment has numberOfSteps = 1:
    // Handle single-step (flat) segment in one operation
    [calculate full segment cost and process]
  - else:
    // Handle multi-step (sloped) segment step-by-step
    [your existing step logic]

**3c. Calculate how much supply is provided by end step (= partially filled supply)**

- calc step collateral capacity of end step:
  stepCollateralCapacity = stepPrice \* supplyPerStep
- calc relative fill ratio of end step:
  fillRatio = budget / stepCollateralCapacity
- use fill ratio to calculate end step issuance supply:
  endStepIssuanceSupply = supplyPerStep \* fillRatio
- add endStepIssuanceSupply to issuanceAmountOut

Now we should have the issuanceAmountOut, which is the goal of calculatePurchaseReturn.
