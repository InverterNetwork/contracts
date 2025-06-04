# Test Cases to Improve Coverage for DiscreteCurveMathLib_v1.sol

Based on the coverage report (`coverage/src/modules/fundingManager/bondingCurve/formulas/DiscreteCurveMathLib_v1.sol.gcov.html`), the following test cases are needed to reach 100% line and branch coverage.

## 1. `_validateSupplyAgainstSegments`

- **File:** `test/unit/modules/fundingManager/bondingCurve/formulas/DiscreteCurveMathLib_v1.t.sol`
- **Function to Test:** `exposed_validateSupplyAgainstSegments` (via mock contract)
- **Target Uncovered Branch/Line:**
  - Line 43: `if (currentTotalIssuanceSupply_ > 0)` within the `if (numSegments_ == 0)` block.
  - Line 45: `revert IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__NoSegmentsConfigured();`
- **Test Case Description:**
  - Call `exposed_validateSupplyAgainstSegments` with an empty `segments_` array and `currentTotalIssuanceSupply_ = 1` (or any value > 0).
- **Expected Outcome:**
  - The function should revert with `DiscreteCurveMathLib__NoSegmentsConfigured`.

## 2. `_validateSegmentArray`

- **File:** `test/unit/modules/fundingManager/bondingCurve/formulas/DiscreteCurveMathLib_v1.t.sol`
- **Function to Test:** `exposed_validateSegmentArray` (via mock contract)
- **Target Uncovered Branch/Line:**
  - Line 770: `if (currentNumberOfSteps_ == 0)`
  - Line 777: `finalPriceCurrentSegment_ = currentInitialPrice_;`
- **Test Case Description:**
  - This branch is tricky because `PackedSegmentLib._create` should prevent `numberOfSteps_` from being 0.
  - To hit this, we would need to manually craft a `PackedSegment` with `numberOfSteps_ = 0` and pass it to `_validateSegmentArray`.
  - Create a `PackedSegment[]` array with at least two segments.
  - For the first segment (`segments_[0]`), manually construct its `bytes32` value such that `_numberOfSteps()` returns 0.
    - Example: `uint initialPrice = 1e18; uint priceIncrease = 0; uint supplyPerStep = 100e18; uint numberOfSteps = 0;`
    - `bytes32 malformedSegment = abi.encodePacked(initialPrice, priceIncrease, supplyPerStep, numberOfSteps);`
    - `segments[0] = PackedSegment.wrap(malformedSegment);`
  - The second segment (`segments_[1]`) can be a valid segment.
  - Call `exposed_validateSegmentArray` with this array.
- **Expected Outcome:**

  - The test should execute the targeted lines. The overall behavior might depend on how the rest of the `_validateSegmentArray` logic interacts with a segment having 0 steps, potentially leading to a revert like `InvalidPriceProgression` if the "final price" calculation based on 0 steps leads to an unexpected value compared to the next segment's initial price. The primary goal is to cover the line.
    Let's simplify the list for the markdown file, focusing on the direct actions. The detailed reasoning for L851 can be kept for implementation notes.

```markdown
# Test Cases to Improve Coverage for DiscreteCurveMathLib_v1.sol

To achieve 100% line and branch coverage for `DiscreteCurveMathLib_v1.sol`, the following test cases should be implemented in `test/unit/modules/fundingManager/bondingCurve/formulas/DiscreteCurveMathLib_v1.t.sol`. These tests will target uncovered branches identified in the coverage report.

## 1. `_validateSupplyAgainstSegments` - Empty Segments with Positive Supply

- **Target Function (via mock):** `exposed_validateSupplyAgainstSegments`
- **Scenario:** `segments_` array is empty, `currentTotalIssuanceSupply_ > 0`.
- **Action:** Call `exposed_validateSupplyAgainstSegments(new PackedSegment[](0), 1)`.
- **Expected Revert:** `DiscreteCurveMathLib__NoSegmentsConfigured`
- **Covers:** Line 45 (revert) and the branch at Line 43.

## 2. `_validateSegmentArray` - Segment with Zero Steps

- **Target Function (via mock):** `exposed_validateSegmentArray`
- **Scenario:** A segment in the `segments_` array has `numberOfSteps_ == 0`. This requires manual construction of the `PackedSegment` as `PackedSegmentLib._create` prevents this.
- **Action:**
  1.  Create `segments[0]` by manually encoding `initialPrice=1e18, priceIncrease=0, supplyPerStep=100e18, numberOfSteps=0` into a `bytes32` and wrapping with `PackedSegment.wrap()`.
  2.  Create `segments[1]` as a valid segment.
  3.  Call `exposed_validateSegmentArray` with this two-segment array.
- **Expected Behavior:** The test should execute line 777. The function might subsequently revert due to price progression issues, but the primary goal is to cover the branch at line 770.
- **Covers:** Branch at Line 770 and Line 777.
```
