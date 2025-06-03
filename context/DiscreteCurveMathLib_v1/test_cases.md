# Test Cases for \_calculatePurchaseReturn

**Legend:**

- `[COVERED by: test_function_name]`
- `[PARTIALLY COVERED by: test_function_name]`
- `[NEEDS SPECIFIC TEST]`
- `[FUZZ MAY COVER: fuzz_test_name]`
- `[DESIGN NOTE: ... ]`

## Test Assumptions

- Not more than 1 segment transition per calculatePurchaseReturn call
- Not more than 15 step transitions per calculatePurchaseReturn call

## Input Validation Tests

- **Case 0: Input validation**
  - 0.1: `collateralToSpendProvided_ = 0` (should revert) `[COVERED by: testRevert_CalculatePurchaseReturn_ZeroCollateralInput]`
  - 0.2: `segments_` array is empty (should revert) `[COVERED by: testPass_CalculatePurchaseReturn_NoSegments_SupplyZero, testRevert_CalculatePurchaseReturn_NoSegments_SupplyPositive]`
  - 0.3: `currentTotalIssuanceSupply_` > total curve capacity `[DESIGN NOTE: This validation is expected to be done by the caller *before* calling _calculatePurchaseReturn, as per recent refactoring. The function itself may not revert for this directly but might behave unexpectedly or revert due to subsequent calculations if this precondition is violated. The fuzz test `testFuzz_CalculatePurchaseReturn_Properties`sets up`currentTotalIssuanceSupply` within capacity.]`

## Phase 2 Tests (Partial Start Step Handling)

- **Case P2: Starting position within a step**
  - P2.1: CurrentSupply exactly at start of step (Phase 2 logic skipped)
    - P2.1.1: Flat segment `[COVERED by: test_CalculatePurchaseReturn_SingleFlatSegment_PartialBuy_AffordSome, test_CalculatePurchaseReturn_SingleFlatSegment_PartialBuy_AffordAllInStep (currentSupply = 0), test_CalculatePurchaseReturn_StartStepBoundary_Flat_NotFirstStep_TBD]`
    - P2.1.2: Sloped segment `[COVERED by: test_CalculatePurchaseReturn_SingleSlopedSegment_AffordMultipleFullSteps, test_CalculatePurchaseReturn_Edge_CollateralForExactlyOneStep_Sloped, test_CalculatePurchaseReturn_Edge_CollateralLessThanOneStep_Sloped (all start currentSupply = 0); test_CalculatePurchaseReturn_StartEndOfStep_Sloped (starts at next step boundary)]`
  - P2.2: CurrentSupply mid-step, budget can complete current step
    - P2.2.1: Flat segment `[COVERED by: test_CalculatePurchaseReturn_StartMidStep_CompleteStep_FlatSegment]`
    - P2.2.2: Sloped segment `[COVERED by: test_CalculatePurchaseReturn_StartMidStep_Sloped]`
  - P2.3: CurrentSupply mid-step, budget cannot complete current step (early exit)
    - P2.3.1: Flat segment `[COVERED by: test_CalculatePurchaseReturn_StartMidStep_CannotCompleteStep_FlatSegment]`
    - P2.3.2: Sloped segment `[COVERED by: test_CalculatePurchaseReturn_StartMidStep_Sloped (covers if budget is sufficient for partial completion), test_CalculatePurchaseReturn_StartMidStep_CannotCompleteStep_Sloped_TBD]`

## Phase 3 Tests (Main Purchase Loop)

- **Case P3: Purchase ending conditions**
  - P3.1: End with partial step purchase (within same step)
    - P3.1.1: Flat segment `[COVERED by: test_CalculatePurchaseReturn_Edge_CollateralLessThanOneStep_Flat (ends with partial purchase of the single step)]`
    - P3.1.2: Sloped segment `[COVERED by: test_CalculatePurchaseReturn_SingleSlopedSegment_AffordMultipleFullSteps (ends in a partial step), test_CalculatePurchaseReturn_Edge_CollateralLessThanOneStep_Sloped, test_CalculatePurchaseReturn_StartMidStep_Sloped (can end in a partial step)]`
  - P3.2: End at exact step boundary (complete step purchase)
    - P3.2.1: Flat segment `[COVERED by: test_CalculatePurchaseReturn_SingleFlatSegment_PartialBuy_AffordAllInStep (completes the single step of the true flat segment)]`
    - P3.2.2: Sloped segment `[COVERED by: test_CalculatePurchaseReturn_Edge_CollateralForExactlyOneStep_Sloped]`
  - P3.3: End at exact segment boundary (complete segment purchase)
    - P3.3.1: Flat segment → next segment `[COVERED by: test_CalculatePurchaseReturn_SingleFlatSegment_PartialBuy_AffordAllInStep (completes single flat segment), test_CalculatePurchaseReturn_EndAtFlatSegmentBoundary_ThenTransition_TBD]`
    - P3.3.2: Sloped segment → next segment `[COVERED by: test_CalculatePurchaseReturn_SpanningSegments_EndsWithPartialInSecondSegment (completes seg0), test_CalculatePurchaseReturn_EndAtSlopedSegmentBoundary_ThenTransition_TBD]`
  - P3.4: End in next segment (segment transition)
    - P3.4.1: From flat segment to flat segment `[COVERED by: test_CalculatePurchaseReturn_Transition_FlatToFlatSegment]`
    - P3.4.2: From flat segment to sloped segment `[COVERED by: test_CalculatePurchaseReturn_Transition_FlatToSloped_PartialBuyInSlopedSegment]`
    - P3.4.3: From sloped segment to flat segment `[COVERED by: test_CalculatePurchaseReturn_Transition_SlopedToFlatSegment_TBD]`
    - P3.4.4: From sloped segment to sloped segment `[COVERED by: test_CalculatePurchaseReturn_SpanningSegments_EndsWithPartialInSecondSegment]`
  - P3.5: Budget exhausted before completing any full step
    - P3.5.1: Flat segment `[COVERED by: test_CalculatePurchaseReturn_Edge_CollateralLessThanOneStep_Flat]`
    - P3.5.2: Sloped segment `[COVERED by: test_CalculatePurchaseReturn_Edge_CollateralLessThanOneStep_Sloped]`

## Comprehensive Integration Tests

- **Case 1: Starting exactly at segment beginning**

  - 1.1: Buy exactly remaining segment capacity
    - 1.1.1: Flat segment `[COVERED by: test_CalculatePurchaseReturn_SingleFlatSegment_PartialBuy_AffordAllInStep (for a single-step flat segment)]`
    - 1.1.2: Sloped segment `[COVERED by: test_CalculatePurchaseReturn_Edge_CollateralToBuyoutCurve (buys out entire curve), test_CalculatePurchaseReturn_StartAtSegment_BuyoutFirstSlopedSegment_TBD]`
  - 1.2: Buy less than remaining segment capacity
    - 1.2.1: Flat segment `[COVERED by: test_CalculatePurchaseReturn_Edge_CollateralLessThanOneStep_Flat (for a single-step flat segment)]`
    - 1.2.2: Sloped segment (multiple step transitions) `[COVERED by: test_CalculatePurchaseReturn_SingleSlopedSegment_AffordMultipleFullSteps]`
  - 1.3: Buy more than remaining segment capacity
    - 1.3.1: Flat segment → next segment `[COVERED by: test_CalculatePurchaseReturn_Transition_FlatToSloped_PartialBuyInSlopedSegment, test_CalculatePurchaseReturn_Transition_FlatToFlatSegment]`
    - 1.3.2: Sloped segment → next segment `[COVERED by: test_CalculatePurchaseReturn_SpanningSegments_EndsWithPartialInSecondSegment]`

- **Case 2: Starting mid-segment (not at first step)**

  - 2.1: Buy exactly remaining segment capacity
    - 2.1.1: Flat segment `[COVERED by: test_CalculatePurchaseReturn_StartMidStep_CompleteStep_FlatSegment (for True Flat 1-step segments)]`
    - 2.1.2: Sloped segment `[COVERED by: test_CalculatePurchaseReturn_StartMidSegment_BuyoutRemainingSloped_TBD]`
  - 2.2: Buy less than remaining segment capacity
    - 2.2.1: Flat segment `[COVERED by: test_CalculatePurchaseReturn_StartMidStep_CannotCompleteStep_FlatSegment]`
    - 2.2.2: Sloped segment `[COVERED by: test_CalculatePurchaseReturn_StartEndOfStep_Sloped (starts at step 1 of seg0, buys only that step, less than seg0 capacity)]`
  - 2.3: Buy more than remaining segment capacity
    - 2.3.1: Flat segment → next segment `[COVERED by: test_CalculatePurchaseReturn_StartMidSegment_BuyoutFlatAndTransition_TBD]`
    - 2.3.2: Sloped segment → next segment `[COVERED by: test_CalculatePurchaseReturn_StartEndOfSegment_MultiSegment (starts at boundary), test_CalculatePurchaseReturn_StartMidSlopedSegment_Transition_TBD]`

- **Case 3: Starting mid-step (Phase 2 + Phase 3 integration)**
  - 3.1: Complete partial step, then continue with full steps
    - 3.1.1: Flat segment `[COVERED by: test_CalculatePurchaseReturn_StartMidStep_CompleteStep_FlatSegment (for True Flat 1-step segments, implies transition for more steps)]`
    - 3.1.2: Sloped segment `[COVERED by: test_CalculatePurchaseReturn_StartMidStep_Sloped (completes partial, then partial next), test_CalculatePurchaseReturn_StartMidStep_CompletePartialThenFullSteps_Sloped_TBD]`
  - 3.2: Complete partial step, then partial purchase next step
    - 3.2.1: Flat segment `[COVERED by: test_CalculatePurchaseReturn_StartMidFlat_CompleteFlat_PartialNextFlat]`
    - 3.2.2: Sloped segment `[COVERED by: test_CalculatePurchaseReturn_StartMidStep_Sloped]`

## Edge Case Tests

- **Case E: Extreme scenarios**
  - E.1: Very small budget (can't afford any complete step)
    - E.1.1: Flat segment `[COVERED by: test_CalculatePurchaseReturn_Edge_CollateralLessThanOneStep_Flat]`
    - E.1.2: Sloped segment `[COVERED by: test_CalculatePurchaseReturn_Edge_CollateralLessThanOneStep_Sloped]`
  - E.2: Budget exactly matches remaining curve capacity `[COVERED by: test_CalculatePurchaseReturn_Edge_CollateralToBuyoutCurve (exact part)]`
  - E.3: Budget exceeds total remaining curve capacity `[COVERED by: test_CalculatePurchaseReturn_Edge_CollateralToBuyoutCurve (more collateral part)]`
  - E.4: Single step remaining in segment `[COVERED by: (tests on single-step flat segments & penultimate step scenarios), test_CalculatePurchaseReturn_Edge_SingleStepRemaining_MultiStepSegment_TBD]`
  - E.5: Last segment of curve `[COVERED by many single-segment tests (e.g. using `segments[0] = defaultSegments[0]`) and `test_CalculatePurchaseReturn_Edge_CollateralToBuyoutCurve`]`
  - E.6: Mathematical precision edge cases
    - E.6.1: Rounding behavior verification (Math.mulDiv vs \_mulDivUp) `[COVERED by: The correctness of expected values in various tests like test_CalculatePurchaseReturn_SingleSlopedSegment_AffordMultipleFullSteps and LessThanOneStep tests implicitly verifies the aggregate effect of internal rounding.]`
    - E.6.2: Very small amounts near precision limits `[FUZZ MAY COVER: testFuzz_CalculatePurchaseReturn_Properties. Specific unit tests with 1 wei could be added for targeted verification if needed.]`
    - E.6.3: Very large amounts near bit field limits `[FUZZ MAY COVER: testFuzz_CalculatePurchaseReturn_Properties (for collateralIn, currentSupply). Segment parameters are fuzzed in _createSegment fuzz tests.]`

## Boundary Condition Tests

- **Case B: Exact boundary scenarios**
  - B.1: Starting exactly at step boundary `[COVERED by: test_CalculatePurchaseReturn_StartEndOfStep_Sloped]`
  - B.2: Starting exactly at segment boundary `[COVERED by: test_CalculatePurchaseReturn_StartEndOfSegment_MultiSegment; also many tests with currentSupply = 0]`
  - B.3: Ending exactly at step boundary `[COVERED by: test_CalculatePurchaseReturn_Edge_CollateralForExactlyOneStep_Sloped]`
  - B.4: Ending exactly at segment boundary `[COVERED by: test_CalculatePurchaseReturn_SingleFlatSegment_PartialBuy_AffordAllInStep (for single-step flat), test_CalculatePurchaseReturn_SpanningSegments_EndsWithPartialInSecondSegment (buys out first segment exactly), test_CalculatePurchaseReturn_EndExactlyAtSegmentBoundary_MultiStep_TBD]`
  - B.5: Ending exactly at curve end `[COVERED by: test_CalculatePurchaseReturn_Edge_CollateralToBuyoutCurve (exact part)]`

## Test Cases for \_calculateSaleReturn (Reversed from Purchase)

**Legend:**

- `[COVERED by: test_function_name]`
- `[PARTIALLY COVERED by: test_function_name]`
- `[NEEDS SPECIFIC TEST]`
- `[FUZZ MAY COVER: fuzz_test_name]`
- `[DESIGN NOTE: ... ]`

**Note**: These test cases are derived by reversing the "start" and "end" points/conditions of the `_calculatePurchaseReturn` test cases. The core logic of selling tokens (decreasing supply) is the inverse of purchasing them (increasing supply) along the curve.

### Input Validation Tests (for \_calculateSaleReturn)

- **Case 0: Input validation**
  - 0.1: `tokensToSell_ = 0` (should revert) `[COVERED by: testRevert_CalculateSaleReturn_ZeroIssuanceInput]`
  - 0.3: `currentTotalIssuanceSupply_ = 0` (should revert, as there's nothing to sell) `[COVERED by: testPass_CalculateSaleReturn_SupplyZero_TokensPositive]`
  - 0.4: `tokensToSell_` > `currentTotalIssuanceSupply_` (should revert) `[COVERED by: testPass_CalculateSaleReturn_SellMoreThanSupply_SellsAllAvailable]`

### Phase 2 Tests (Partial End Step Handling - Reversed from Purchase Start Step)

- **Case P2: Sale operation ending position within a step**
  - P2.1: TargetSupply (after sale) exactly at end of a step (Analogous to purchase starting at step boundary; sale's "partial step" logic might be skipped if sale ends precisely at a step boundary from a higher supply)
    - P2.1.1: Flat segment `[COVERED by: test_CalculateSaleReturn_SingleTrueFlat_SellToEndOfStep]`
    - P2.1.2: Sloped segment `[COVERED by: test_CalculateSaleReturn_SingleSloped_SellToEndOfLowerStep]`
  - P2.2: TargetSupply (after sale) mid-step, tokens sold were sufficient to cross from a higher step/segment
    - P2.2.1: Flat segment `[COVERED by: test_CalculateSaleReturn_TransitionFlatToFlat_EndMidLowerFlatSegment]`
    - P2.2.2: Sloped segment `[COVERED by: test_CalculateSaleReturn_TransitionSlopedToSloped_EndMidLowerSlopedSegment]`
  - P2.3: TargetSupply (after sale) mid-step, tokens sold were not sufficient to cross from a higher step/segment (sale ends within the step it started in, from a higher supply point)
    - P2.3.1: Flat segment `[COVERED by: test_CalculateSaleReturn_SingleFlat_StartMidStep_EndMidSameStep_NotEnoughToClearStep]`
    - P2.3.2: Sloped segment `[COVERED by: test_CalculateSaleReturn_SingleSloped_StartMidStep_EndMidSameStep_NotEnoughToClearStep]`

### Phase 3 Tests (Main Sale Loop - Reversed from Purchase Loop)

- **Case P3: Sale starting conditions (reversed from purchase ending conditions)**
  - P3.1: Start with partial step sale (selling from a partially filled step, sale ends within the same step)
    - P3.1.1: Flat segment `[COVERED by: test_CalculateSaleReturn_Flat_StartPartial_EndSamePartialStep]`
    - P3.1.2: Sloped segment `[COVERED by: test_CalculateSaleReturn_Sloped_StartPartial_EndSamePartialStep]`
  - P3.2: Start at exact step boundary (selling from a supply level that is an exact step boundary)
    - P3.2.1: Flat segment `[COVERED by: test_CalculateSaleReturn_Flat_StartExactStepBoundary_SellIntoStep]`
    - P3.2.2: Sloped segment `[COVERED by: test_CalculateSaleReturn_Sloped_StartExactStepBoundary_SellIntoLowerStep]`
  - P3.3: Start at exact segment boundary (selling from a supply level that is an exact segment boundary)
    - P3.3.1: From higher segment into Flat segment `[COVERED by: test_CalculateSaleReturn_Transition_SlopedToFlat_StartSegBoundary_EndInFlat]`
    - P3.3.2: From higher segment into Sloped segment `[COVERED by: test_CalculateSaleReturn_Transition_SlopedToSloped_StartSegBoundary_EndInLowerSloped]`
  - P3.4: Start in a higher supply segment (segment transition during sale)
    - P3.4.1: From flat segment to flat segment (selling across boundary) `[COVERED by: test_CalculateSaleReturn_Transition_FlatToFlat_SellAcrossBoundary_MidHigherFlat]`
    - P3.4.2: From sloped segment to flat segment (selling across boundary) `[COVERED by: test_CalculateSaleReturn_Transition_SlopedToFlat_SellAcrossBoundary_EndInFlat]`
    - P3.4.3: From flat segment to sloped segment (selling across boundary) `[COVERED by: test_CalculateSaleReturn_Transition_FlatToSloped_SellAcrossBoundary_EndInSloped]`
    - P3.4.4: From sloped segment to sloped segment (selling across boundary) `[COVERED by: test_CalculateSaleReturn_Transition_SlopedToSloped_SellAcrossBoundary_MidHigherSloped]`
  - P3.5: Tokens to sell exhausted before completing any full step sale (selling less than one step from current position)
    - P3.5.1: Flat segment `[COVERED by: test_CalculateSaleReturn_Flat_SellLessThanOneStep_FromMidStep]`
    - P3.5.2: Sloped segment `[COVERED by: test_CalculateSaleReturn_Sloped_SellLessThanOneStep_FromMidStep]`

### Comprehensive Integration Tests (Reversed)

- **Case 1: Ending exactly at segment beginning (selling out a segment from a higher supply point)**

  - 1.1: Sell tokens equivalent to exactly the current segment's capacity (from its current supply to its start)
    - 1.1.1: Flat segment `[COVERED by: test_CalculateSaleReturn_Flat_SellExactlySegmentCapacity_FromHigherSegmentEnd]`
    - 1.1.2: Sloped segment `[COVERED by: test_CalculateSaleReturn_Sloped_SellExactlySegmentCapacity_FromHigherSegmentEnd]`
  - 1.2: Sell less than current segment's capacity (from its current supply, ending mid-segment)
    - 1.2.1: Flat segment `[COVERED by: test_CalculateSaleReturn_C1_2_1_Flat_SellLessThanCurSegCapacity_EndMidSeg]`
    - 1.2.2: Sloped segment (multiple step transitions during sale) `[COVERED by: test_CalculateSaleReturn_C1_2_2_Sloped_SellLessThanCurSegCapacity_EndMidSeg_MultiStep]`
  - 1.3: Sell more than current segment's capacity (from its current supply, ending in a previous segment)
    - 1.3.1: From higher segment, crossing into and ending in a Flat segment `[COVERED by: test_CalculateSaleReturn_C1_3_1_Transition_SellMoreThanCurSegCapacity_EndInLowerFlat]`
    - 1.3.2: From higher segment, crossing into and ending in a Sloped segment `[COVERED by: test_CalculateSaleReturn_C1_3_2_Transition_SellMoreThanCurSegCapacity_EndInLowerSloped]`

- **Case 2: Ending mid-segment (not at first step of segment - selling from a supply point not at the very end of the segment)**

  - 2.1: Sell tokens equivalent to exactly the remaining capacity from current supply to segment start
    - 2.1.1: Flat segment `[COVERED by: test_CalculateSaleReturn_C2_1_1_Flat_SellExactlyRemainingToSegStart_FromMidSeg]`
    - 2.1.2: Sloped segment `[COVERED by: test_CalculateSaleReturn_C2_1_2_Sloped_SellExactlyRemainingToSegStart_FromMidSeg]`
  - 2.2: Sell less than remaining capacity from current supply to segment start (ending mid-segment)
    - 2.2.1: Flat segment `[COVERED by: test_CalculateSaleReturn_C2_2_1_Flat_EndMidSeg_SellLessThanRemainingToSegStart]`
    - 2.2.2: Sloped segment `[COVERED by: test_CalculateSaleReturn_C2_2_2_Sloped_EndMidSeg_SellLessThanRemainingToSegStart]`
  - 2.3: Sell more than remaining capacity from current supply to segment start (ending in a previous segment)
    - 2.3.1: From higher segment, crossing into and ending in a Flat segment `[COVERED by: test_CalculateSaleReturn_C2_3_1_FlatTransition_EndInPrevFlat_SellMoreThanRemainingToSegStart]`
    - 2.3.2: From higher segment, crossing into and ending in a Sloped segment `[COVERED by: test_CalculateSaleReturn_C2_3_2_SlopedTransition_EndInPrevSloped_SellMoreThanRemainingToSegStart]`

- **Case 3: Ending mid-step (Phase 2 for sale + Phase 3 for sale integration - selling across step boundaries and landing mid-step)**
  - 3.1: Start selling from a full step, then continue with partial step sale into a lower step
    - 3.1.1: Flat segment `[COVERED by: test_CalculateSaleReturn_C3_1_1_Flat_StartFullStep_EndPartialLowerStep]`
    - 3.1.2: Sloped segment `[COVERED by: test_CalculateSaleReturn_C3_1_2_Sloped_StartFullStep_EndPartialLowerStep]`
  - 3.2: Start selling from a partial step, then partial sale from the previous step
    - 3.2.1: Flat segment `[COVERED by: test_CalculateSaleReturn_C3_2_1_Flat_StartPartialStep_EndPartialPrevStep]`
    - 3.2.2: Sloped segment `[PENDING IMPLEMENTATION: test_CalculateSaleReturn_C3_2_2_Sloped_StartPartialStep_EndPartialPrevStep]`

### Edge Case Tests (Reversed/Adapted for Sale)

- **Case E: Extreme scenarios**
  - E.1: Very small token amount to sell (cannot clear any complete step downwards)
    - E.1.1: Flat segment `[COVERED by: test_CalculateSaleReturn_E1_1_Flat_SellVerySmallAmount_NoStepClear]`
    - E.1.2: Sloped segment `[COVERED by: test_CalculateSaleReturn_E1_2_Sloped_SellVerySmallAmount_NoStepClear]`
  - E.2: Tokens to sell exactly matches current total issuance supply (selling entire supply) `[COVERED by: test_CalculateSaleReturn_E2_SellExactlyTotalSupply]`
  - E.3: Tokens to sell exceeds total current issuance supply (should sell all available or revert) `[COVERED by: testPass_CalculateSaleReturn_SellMoreThanSupply_SellsAllAvailable (revert part)]`
  - E.4: Only a single step of supply exists in the current segment (selling from a segment with minimal population) `[COVERED by: test_CalculateSaleReturn_E4_SellFromSingleStepSegmentPopulation]`
  - E.5: Selling from the "first" segment of the curve (lowest priced tokens) `[COVERED by: test_CalculateSaleReturn_E5_SellFromFirstSegment]`
  - E.6: Mathematical precision edge cases for sale calculations
    - E.6.1: Rounding behavior verification (e.g., `_mulDivDown` vs internal rounding for collateral returned) `[COVERED by: test_CalculateSaleReturn_E6_1_RoundingBehaviorVerification]`
    - E.6.2: Very small amounts near precision limits `[COVERED by: test_CalculateSaleReturn_E6_2_PrecisionLimits_SmallAmounts]`
    - E.6.3: Very large amounts near bit field limits `[PENDING IMPLEMENTATION: test_CalculateSaleReturn_E6_3_PrecisionLimits_LargeAmounts]`

### Boundary Condition Tests (Reversed/Adapted for Sale)

- **Case B: Exact boundary scenarios**
  - B.1: Ending (after sale) exactly at step boundary `[PENDING IMPLEMENTATION: test_CalculateSaleReturn_B1_EndAtStepBoundary]`
  - B.2: Ending (after sale) exactly at segment boundary `[PENDING IMPLEMENTATION: test_CalculateSaleReturn_B2_EndAtSegmentBoundary]`
  - B.3: Starting (before sale) exactly at step boundary `[PENDING IMPLEMENTATION: test_CalculateSaleReturn_B3_StartAtStepBoundary]`
  - B.4: Starting (before sale) exactly at segment boundary `[PENDING IMPLEMENTATION: test_CalculateSaleReturn_B4_StartAtSegmentBoundary]`
  - B.5: Ending (after sale) exactly at curve start (supply becomes zero) `[PENDING IMPLEMENTATION: test_CalculateSaleReturn_B5_EndAtCurveStart]`

## Verification Checklist

For each test case, verify:

- ✅ `tokensToMint_` calculation matches expected mathematical result
- ✅ `collateralSpentByPurchaser_` ≤ `collateralToSpendProvided_`
- ✅ `collateralSpentByPurchaser_` matches sum of individual step costs
- ✅ Pricing formula applied correctly for segment type
- ✅ State transitions handled properly
- ✅ No unexpected reverts or state changes
- ✅ Gas usage within reasonable bounds
- ✅ Return values are internally consistent

## Test Data Considerations

- Use segments with different price ranges (low, medium, high)
- Test with different `supplyPerStep_` values
- Include segments with varying `numberOfSteps_` (1 step vs many steps)
- Test curves with 1, 2, and multiple segments
- Use both small and large budget amounts relative to step costs

This comprehensive test suite should catch edge cases, boundary conditions, and integration issues while ensuring mathematical correctness across all scenarios.

## Fuzz Testing

While the above unit tests cover specific scenarios, comprehensive fuzz testing will be implemented next to ensure robustness across a wider range of inputs and curve configurations for core calculation functions.

- **`testFuzz_CalculateReserveForSupply_Properties`**: Review, uncomment/complete, and verify.
  - Ensure coverage for various `targetSupply` values (zero, within segments, at capacity, beyond capacity for reverts).
- **`testFuzz_CalculatePurchaseReturn_Properties`**: Review, uncomment/complete, and verify.
  - Ensure coverage for diverse `collateralToSpendProvided_` and `currentTotalIssuanceSupply_` combinations.
  - Verify properties like `collateralSpentByPurchaser <= collateralToSpendProvided_`, `tokensToMint` within available capacity, and correct handling of zero/full capacity.
  - Check expected reverts.
- **New `testFuzz_CalculateSaleReturn_Properties`**: Implement.
  - Cover various `tokensToSell_` and `currentTotalIssuanceSupply_` values.
  - Verify properties like `tokensToBurn_` constraints and consistency with reserve calculations.
  - Check expected reverts.
- **Helper `_generateFuzzedValidSegmentsAndCapacity`**: Review and potentially enhance to generate more diverse valid curve structures for fuzz inputs.
