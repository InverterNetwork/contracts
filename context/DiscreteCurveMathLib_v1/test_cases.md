<!-- # Task instructions (OUTDATED)

- focus on calculatePurchaseReturn only for now
- add all tests that are missing according to this doc (except fuzz tests)
- don't add any fuzz tests yet, first we want to nail all test cases in a controlled setting
- all segment configurations required by the various tests need to be provided as default configurations on the top of the file, or retrieved through calling a helper function (but not defined repetitively in the test cases)
- test names need to be descriptive and not reference this doc
- approach: add one test, run the tests `contracts git:(experimental/per) ✗ forge test --match-path test/unit/modules/fundingManager/bondingCurve/formulas/Discret
eCurveMathLib_v1.t.sol -vv`, make sure it is green, continue (don't add many tests at the same time)
- via-ir is not an option -->

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
    - P2.1.1: Flat segment `[PARTIALLY COVERED by: test_CalculatePurchaseReturn_SingleFlatSegment_PartialBuy_AffordSome, test_CalculatePurchaseReturn_SingleFlatSegment_PartialBuy_AffordAllInStep (currentSupply = 0)]`
    - P2.1.2: Sloped segment `[COVERED by: test_CalculatePurchaseReturn_SingleSlopedSegment_AffordMultipleFullSteps, test_CalculatePurchaseReturn_Edge_CollateralForExactlyOneStep_Sloped, test_CalculatePurchaseReturn_Edge_CollateralLessThanOneStep_Sloped (all start currentSupply = 0); test_CalculatePurchaseReturn_StartEndOfStep_Sloped (starts at next step boundary)]`
  - P2.2: CurrentSupply mid-step, budget can complete current step
    - P2.2.1: Flat segment `[COVERED by: test_CalculatePurchaseReturn_StartMidStep_CompleteStep_FlatSegment]`
    - P2.2.2: Sloped segment `[COVERED by: test_CalculatePurchaseReturn_StartMidStep_Sloped]`
  - P2.3: CurrentSupply mid-step, budget cannot complete current step (early exit)
    - P2.3.1: Flat segment `[COVERED by: test_CalculatePurchaseReturn_StartMidStep_CannotCompleteStep_FlatSegment]`
    - P2.3.2: Sloped segment `[PARTIALLY COVERED by: test_CalculatePurchaseReturn_StartMidStep_Sloped (if budget was smaller to cause early exit in first partial step)]`

## Phase 3 Tests (Main Purchase Loop)

- **Case P3: Purchase ending conditions**
  - P3.1: End with partial step purchase (within same step)
    - P3.1.1: Flat segment `[COVERED by: test_CalculatePurchaseReturn_Edge_CollateralLessThanOneStep_Flat (ends with partial purchase of the single step)]`
    - P3.1.2: Sloped segment `[COVERED by: test_CalculatePurchaseReturn_SingleSlopedSegment_AffordMultipleFullSteps (ends in a partial step), test_CalculatePurchaseReturn_Edge_CollateralLessThanOneStep_Sloped, test_CalculatePurchaseReturn_StartMidStep_Sloped (can end in a partial step)]`
  - P3.2: End at exact step boundary (complete step purchase)
    - P3.2.1: Flat segment `[COVERED by: test_CalculatePurchaseReturn_SingleFlatSegment_PartialBuy_AffordAllInStep (completes the single step of the true flat segment)]`
    - P3.2.2: Sloped segment `[COVERED by: test_CalculatePurchaseReturn_Edge_CollateralForExactlyOneStep_Sloped]`
  - P3.3: End at exact segment boundary (complete segment purchase)
    - P3.3.1: Flat segment → next segment `[PARTIALLY COVERED by: test_CalculatePurchaseReturn_SingleFlatSegment_PartialBuy_AffordAllInStep (if it's the last segment, it completes it. If followed by another, this covers completing the flat one)]`
    - P3.3.2: Sloped segment → next segment `[PARTIALLY COVERED by: test_CalculatePurchaseReturn_SpanningSegments_EndsWithPartialInSecondSegment (completes seg0 before moving to seg1)]`
  - P3.4: End in next segment (segment transition)
    - P3.4.1: From flat segment to flat segment `[COVERED by: test_CalculatePurchaseReturn_Transition_FlatToFlatSegment]`
    - P3.4.2: From flat segment to sloped segment `[COVERED by: test_CalculatePurchaseReturn_Transition_FlatToSloped_PartialBuyInSlopedSegment]`
    - P3.4.3: From sloped segment to flat segment `[NEEDS SPECIFIC TEST]`
    - P3.4.4: From sloped segment to sloped segment `[COVERED by: test_CalculatePurchaseReturn_SpanningSegments_EndsWithPartialInSecondSegment]`
  - P3.5: Budget exhausted before completing any full step
    - P3.5.1: Flat segment `[COVERED by: test_CalculatePurchaseReturn_Edge_CollateralLessThanOneStep_Flat]`
    - P3.5.2: Sloped segment `[COVERED by: test_CalculatePurchaseReturn_Edge_CollateralLessThanOneStep_Sloped]`

## Comprehensive Integration Tests

- **Case 1: Starting exactly at segment beginning**

  - 1.1: Buy exactly remaining segment capacity
    - 1.1.1: Flat segment `[COVERED by: test_CalculatePurchaseReturn_SingleFlatSegment_PartialBuy_AffordAllInStep (for a single-step flat segment)]`
    - 1.1.2: Sloped segment `[PARTIALLY COVERED by: test_CalculatePurchaseReturn_Edge_CollateralToBuyoutCurve (buys out entire curve, implies buying out first segment from its beginning if currentSupply=0)]`
  - 1.2: Buy less than remaining segment capacity
    - 1.2.1: Flat segment `[COVERED by: test_CalculatePurchaseReturn_Edge_CollateralLessThanOneStep_Flat (for a single-step flat segment)]`
    - 1.2.2: Sloped segment (multiple step transitions) `[COVERED by: test_CalculatePurchaseReturn_SingleSlopedSegment_AffordMultipleFullSteps]`
  - 1.3: Buy more than remaining segment capacity
    - 1.3.1: Flat segment → next segment `[COVERED by: test_CalculatePurchaseReturn_Transition_FlatToSloped_PartialBuyInSlopedSegment, test_CalculatePurchaseReturn_Transition_FlatToFlatSegment]`
    - 1.3.2: Sloped segment → next segment `[COVERED by: test_CalculatePurchaseReturn_SpanningSegments_EndsWithPartialInSecondSegment]`

- **Case 2: Starting mid-segment (not at first step)**

  - 2.1: Buy exactly remaining segment capacity
    - 2.1.1: Flat segment `[COVERED by: test_CalculatePurchaseReturn_StartMidStep_CompleteStep_FlatSegment (for True Flat 1-step segments)]`
    - 2.1.2: Sloped segment `[NEEDS SPECIFIC TEST (e.g. start at step 1 of twoSlopedSegmentsTestCurve's seg0, buy out steps 1 & 2)]`
  - 2.2: Buy less than remaining segment capacity
    - 2.2.1: Flat segment `[COVERED by: test_CalculatePurchaseReturn_StartMidStep_CannotCompleteStep_FlatSegment]`
    - 2.2.2: Sloped segment `[COVERED by: test_CalculatePurchaseReturn_StartEndOfStep_Sloped (starts at step 1 of seg0, buys only that step, less than seg0 capacity)]`
  - 2.3: Buy more than remaining segment capacity
    - 2.3.1: Flat segment → next segment `[NEEDS SPECIFIC TEST]`
    - 2.3.2: Sloped segment → next segment `[PARTIALLY COVERED by: test_CalculatePurchaseReturn_StartEndOfSegment_MultiSegment (starts at boundary, not mid-segment before transition)]`

- **Case 3: Starting mid-step (Phase 2 + Phase 3 integration)**
  - 3.1: Complete partial step, then continue with full steps
    - 3.1.1: Flat segment `[COVERED by: test_CalculatePurchaseReturn_StartMidStep_CompleteStep_FlatSegment (for True Flat 1-step segments, implies transition for more steps)]`
    - 3.1.2: Sloped segment `[PARTIALLY COVERED by: test_CalculatePurchaseReturn_StartMidStep_Sloped (completes partial, then partial next; needs larger budget for full steps after)]`
  - 3.2: Complete partial step, then partial purchase next step
    - 3.2.1: Flat segment `[PARTIALLY COVERED by: test_CalculatePurchaseReturn_Transition_FlatToFlatSegment or test_CalculatePurchaseReturn_Transition_FlatToSloped_PartialBuyInSlopedSegment (if interpreted as transition and partial buy in next segment)]`
    - 3.2.2: Sloped segment `[COVERED by: test_CalculatePurchaseReturn_StartMidStep_Sloped]`

## Edge Case Tests

- **Case E: Extreme scenarios**
  - E.1: Very small budget (can't afford any complete step)
    - E.1.1: Flat segment `[COVERED by: test_CalculatePurchaseReturn_Edge_CollateralLessThanOneStep_Flat]`
    - E.1.2: Sloped segment `[COVERED by: test_CalculatePurchaseReturn_Edge_CollateralLessThanOneStep_Sloped]`
  - E.2: Budget exactly matches remaining curve capacity `[COVERED by: test_CalculatePurchaseReturn_Edge_CollateralToBuyoutCurve (exact part)]`
  - E.3: Budget exceeds total remaining curve capacity `[COVERED by: test_CalculatePurchaseReturn_Edge_CollateralToBuyoutCurve (more collateral part)]`
  - E.4: Single step remaining in segment `[PARTIALLY COVERED by tests on single-step flat segments, or if currentSupply is at the penultimate step of a multi-step segment. Needs specific setup for clarity on a multi-step segment.]`
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
  - B.4: Ending exactly at segment boundary `[PARTIALLY COVERED by: test_CalculatePurchaseReturn_SingleFlatSegment_PartialBuy_AffordAllInStep (for single-step flat); test_CalculatePurchaseReturn_SpanningSegments_EndsWithPartialInSecondSegment (buys out first segment exactly)]`
  - B.5: Ending exactly at curve end `[COVERED by: test_CalculatePurchaseReturn_Edge_CollateralToBuyoutCurve (exact part)]`

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

## Fuzz Testing (Next Priority)

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
