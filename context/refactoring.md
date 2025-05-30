Segment params:

```
    uint initialPrice_,
    uint priceIncrease_,
    uint supplyPerStep_,
    uint numberOfSteps_
```

Glossary:

- supply: refers to actually provided issuance supply (not capacity) of a curve, segment or step
- capacity: refers to the maximum issuance supply that can be provided by a curve, segment or step
- budget: the amount of collateral that is available for purchase

1. Find current segment index

- track issuance supply provided by previous segments (previousSegmentIssuanceSupply)
- track collateral supply locked by previous segments (previousSegmentCollateralSupply)

- iterate over segments

  - calc total issuance capacity of current segment:
    segmentIssuanceCapacity = supplyPerStep \* numberOfSteps
  - calc collateral capacity of current segment:
    endPrice = initialPrice* + (priceIncreasePerStep \* numberOfSteps)
    priceDiff = endPrice - initialPrice*
    segmentCollateralCapacity = priceDiff \* supplyPerStep

  - check if currentIssuanceSupply is greater than previousSegmentIssuanceSupply (= means we are definitely not in the right segment)

  - if so

    - add segmentIssuanceCapacity to previousSegmentIssuanceSupply
    - add segmentCollateralCapacity to previousSegmentCollateralSupply
    - jump to next segment

  - if not we are in the right segment for the starting point on the curve

3. Find current step index (where startpoint lies)

- calc amount of issuance supply actually provided by segment:
  segmentIssuanceSupply = currentIssuanceSupply - previousSegmentIssuanceSupply
- calc current step index:
  stepIndex = segmentIssuanceSupply / supplyPerStep

4. Distribute budget until fully exhausted

- keep track of remaining collateral budget to be spent (= budget)
- keep track of issuance amount to be issued in return for budget (= issuanceAmountOut)

4a. Fill collateral of current step (partial start step)

- calc issuance supply that is actually provided by current step (not capacity):
  currentStepIssuanceSupply = segmentIssuanceSupply % supplyPerStep
- calc price of current step:
  stepPrice = initialPriceOfSegment + (priceIncreasePerStep \* stepIndex)
- calc relative fill ratio of current step:
  fillRatio = currentStepIssuanceSupply / supplyPerStep
- calc remaining collateral capacity of current step:
  stepCollateralCapacity = stepPrice \* supplyPerStep
  currentStepCollateralSupply = fillRatio \* stepCollateralCapacity
  remainingStepCollateralCapacity = (1 - fillRatio) \* stepCollateralCapacity
- if budget is greater than remainingStepCollateralCapacity,
  - subtract remaining collateral capacity from budget
  - calc remaining issuance supply of current step:
    remainingStepIssuanceSupply = supplyPerStep - currentStepIssuanceSupply
  - add remaining issuance supply to issuanceAmountOut
- if not, end point is in current step
  - calc target fill rate of current step:
    targetFillRate = (currentStepCollateralSupply + budget) / stepCollateralCapacity
  - calc additional issuance amount provided by step:
    additionalIssuanceAmount = (targetFillRate - fillRatio) \* supplyPerStep
  - add to issuanceAmountOut and return

4b. Start iterating over steps

- for each step calc stepCollateralCapacity = stepPrice \* stepSupply
- if budget is greater than stepCollateralCapacity,

  - subtract stepCollateralCapacity from budget
  - add issuance supply capacity of current step to issuanceAmountOut
  - and jump to next step

- if next step doesn't exist in segment, we jump to the next segment and start iterating over steps there

- if budget is smaller than stepCollateralCapacity, we need to jump to 4c

4c. Calculate how much supply is provided by end step (= partially filled supply)

- calc step collateral capacity of end step:
  stepCollateralCapacity = price \* supplyPerStep
- calc relative fill ratio of end step:
  fillRatio = budget / stepCollateralCapacity
- use fill ratio to calculate end step issuance supply:
  endStepIssuanceSupply = supplyPerStep \* fillRatio
- add end step issuance supply to issuanceAmountOut

Now we should have the issuanceAmountOut, which is the goal of calculatePurchaseReturn.
