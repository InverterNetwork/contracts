# Implementation Plan: DiscreteCurveMathLib_v1.sol (Revised for Type-Safe Packed Storage)

**Design Decision Context:** This plan assumes a small number of curve segments (e.g., 2-7, with 2-3 initially). To achieve maximum gas efficiency on L1, we use a type-safe packed storage approach where each segment consumes exactly 1 storage slot (2,100 gas) while maintaining a clean codebase through custom types and accessor functions. The primary optimizations focus on efficiently handling calculations _within_ each segment, especially sloped ones which can have 100-200 steps, using arithmetic series formulas and binary search for affordable steps.

## I. Preliminaries & Project Structure Integration

1.  **File Creation & Structure:** Following Inverter patterns:
    - `src/modules/fundingManager/bondingCurve/interfaces/IDiscreteCurveMathLib_v1.sol`
    - `src/modules/fundingManager/bondingCurve/libraries/DiscreteCurveMathLib_v1.sol`
    - `src/modules/fundingManager/bondingCurve/types/PackedSegment_v1.sol` (new file for type definition)
2.  **License & Pragma:** Add SPDX license identifier (`LGPL-3.0-only`) and Solidity pragma (`^0.8.19`).
3.  **Custom Type Definition (PackedSegment_v1.sol):**
    ```solidity
    // Type-safe wrapper for packed segment data
    type PackedSegment is bytes32;
    ```
4.  **Interface Definition (IDiscreteCurveMathLib_v1.sol):**
    - Import PackedSegment type from types file.
    - Define clean external struct: `struct SegmentConfig { uint256 initialPriceOfSegment; uint256 priceIncreasePerStep; uint256 supplyPerStep; uint256 numberOfStepsInSegment; }`
    - Define Inverter-style error declarations: `DiscreteCurveMathLib__InvalidSegmentConfiguration()`, `DiscreteCurveMathLib__InsufficientLiquidity()`, etc.
    - Define events following project patterns: `DiscreteCurveMathLib__SegmentCreated(PackedSegment indexed segment)`.
5.  **Library Definition (DiscreteCurveMathLib_v1.sol):**
    - Import interface, PackedSegment type.
    - Add library constants: `SCALING_FACTOR = 1e18`, `MAX_SEGMENTS = 10`.
6.  **Internal Struct `CurvePosition` (Helper for clarity):**
    - Define `struct CurvePosition { uint256 segmentIndex; uint256 stepIndexWithinSegment; uint256 priceAtCurrentStep; uint256 supplyCoveredUpToThisPosition; }`

## II. PackedSegment Library Implementation

Create comprehensive packing/unpacking functionality with type safety and validation.

1.  **PackedSegment Library (in DiscreteCurveMathLib_v1.sol):**

    ```solidity
    library PackedSegmentLib {
        // Bit field specifications
        uint256 private constant INITIAL_PRICE_BITS = 72;       // Max: ~$4,722
        uint256 private constant PRICE_INCREASE_BITS = 72;      // Max: ~$4,722
        uint256 private constant SUPPLY_BITS = 96;              // Max: ~79B tokens
        uint256 private constant STEPS_BITS = 16;               // Max: 65,535 steps

        uint256 private constant INITIAL_PRICE_MASK = (1 << INITIAL_PRICE_BITS) - 1;
        uint256 private constant PRICE_INCREASE_MASK = (1 << PRICE_INCREASE_BITS) - 1;
        uint256 private constant SUPPLY_MASK = (1 << SUPPLY_BITS) - 1;
        uint256 private constant STEPS_MASK = (1 << STEPS_BITS) - 1;

        uint256 private constant PRICE_INCREASE_OFFSET = 72;
        uint256 private constant SUPPLY_OFFSET = 144;
        uint256 private constant STEPS_OFFSET = 240;

        // Factory function with comprehensive validation
        function create(
            uint256 initialPrice,
            uint256 priceIncrease,
            uint256 supplyPerStep,
            uint256 numberOfSteps
        ) internal pure returns (PackedSegment) {
            // Validation with descriptive errors
            if (initialPrice > INITIAL_PRICE_MASK) {
                revert DiscreteCurveMathLib__InitialPriceTooLarge();
            }
            if (priceIncrease > PRICE_INCREASE_MASK) {
                revert DiscreteCurveMathLib__PriceIncreaseTooLarge();
            }
            if (supplyPerStep > SUPPLY_MASK) {
                revert DiscreteCurveMathLib__SupplyPerStepTooLarge();
            }
            if (numberOfSteps > STEPS_MASK || numberOfSteps == 0) {
                revert DiscreteCurveMathLib__InvalidNumberOfSteps();
            }

            // Pack into single bytes32
            bytes32 packed = bytes32(
                initialPrice |
                (priceIncrease << PRICE_INCREASE_OFFSET) |
                (supplyPerStep << SUPPLY_OFFSET) |
                (numberOfSteps << STEPS_OFFSET)
            );

            return PackedSegment.wrap(packed);
        }

        // Clean accessor functions
        function initialPrice(PackedSegment self) internal pure returns (uint256) {
            return uint256(PackedSegment.unwrap(self)) & INITIAL_PRICE_MASK;
        }

        function priceIncrease(PackedSegment self) internal pure returns (uint256) {
            return (uint256(PackedSegment.unwrap(self)) >> PRICE_INCREASE_OFFSET) & PRICE_INCREASE_MASK;
        }

        function supplyPerStep(PackedSegment self) internal pure returns (uint256) {
            return (uint256(PackedSegment.unwrap(self)) >> SUPPLY_OFFSET) & SUPPLY_MASK;
        }

        function numberOfSteps(PackedSegment self) internal pure returns (uint256) {
            return (uint256(PackedSegment.unwrap(self)) >> STEPS_OFFSET) & STEPS_MASK;
        }

        // Batch accessor for efficiency
        function unpack(PackedSegment self) internal pure returns (
            uint256 initialPrice,
            uint256 priceIncrease,
            uint256 supplyPerStep,
            uint256 numberOfSteps
        ) {
            uint256 data = uint256(PackedSegment.unwrap(self));
            initialPrice = data & INITIAL_PRICE_MASK;
            priceIncrease = (data >> PRICE_INCREASE_OFFSET) & PRICE_INCREASE_MASK;
            supplyPerStep = (data >> SUPPLY_OFFSET) & SUPPLY_MASK;
            numberOfSteps = (data >> STEPS_OFFSET) & STEPS_MASK;
        }
    }

    // Enable clean syntax: segment.initialPrice()
    using PackedSegmentLib for PackedSegment;
    ```

## III. Helper Function: `_findPositionForSupply`

Determines segment, step, and price for `targetTotalIssuanceSupply` via linear scan, working with PackedSegment arrays.

1.  **Function Signature:**
    `function _findPositionForSupply(PackedSegment[] memory segments, uint256 targetTotalIssuanceSupply) internal pure returns (CurvePosition memory pos)`
2.  **Initialization & Edge Cases:**
    - Initialize `pos` members. `cumulativeSupply = 0;`
    - If `segments.length == 0`, revert with `DiscreteCurveMathLib__NoSegmentsConfigured()`.
    - Add validation: `segments.length <= MAX_SEGMENTS`.
3.  **Iterate Linearly Through Segments:**
    - Loop `i` from `0` to `segments.length - 1`.
    - Extract segment data: `(uint256 initialPrice, uint256 priceIncrease, uint256 supply, uint256 steps) = segments[i].unpack();` (batch extraction for efficiency).
    - OR use individual accessors: `uint256 supply = segments[i].supplyPerStep(); uint256 steps = segments[i].numberOfSteps();`
    - `supplyInCurrentSegment = steps * supply;`
    - **If `targetTotalIssuanceSupply <= cumulativeSupply + supplyInCurrentSegment`:** (Target is within this segment)
      - `pos.segmentIndex = i;`
      - `supplyNeededFromThisSegment = targetTotalIssuanceSupply - cumulativeSupply;`
      - `pos.stepIndexWithinSegment = supplyNeededFromThisSegment / supply;` (Floor division)
      - `pos.priceAtCurrentStep = initialPrice + (pos.stepIndexWithinSegment * priceIncrease);`
      - `pos.supplyCoveredUpToThisPosition = targetTotalIssuanceSupply;`
      - `return pos;`
    - **Else:** `cumulativeSupply += supplyInCurrentSegment;`
4.  **Handle Target Beyond All Segments:** Set `pos.supplyCoveredUpToThisPosition = cumulativeSupply;` and return.

## IV. `getCurrentPriceAndStep` Function

1.  **Function Signature:**
    `function getCurrentPriceAndStep(PackedSegment[] memory segments, uint256 currentTotalIssuanceSupply) internal pure returns (uint256 price, uint256 stepIndex, uint256 segmentIndex)`
2.  **Implementation:**
    - Call `_findPositionForSupply(segments, currentTotalIssuanceSupply)` to get `pos`.
    - Validate that `currentTotalIssuanceSupply` is within curve bounds.
    - Handle boundary case: If `currentTotalIssuanceSupply` exactly filled a step, next purchase uses price of next step.
    - Return `(pos.priceAtCurrentStep, pos.stepIndexWithinSegment, pos.segmentIndex)`.

## V. `calculateReserveForSupply` Function

1.  **Function Signature:**
    `function calculateReserveForSupply(PackedSegment[] memory segments, uint256 targetSupply) internal pure returns (uint256 totalReserve)`
2.  **Initialization:**
    - `totalCollateralReserve = 0; cumulativeSupplyProcessed = 0;`
    - Handle `targetSupply == 0`: Return `0`.
    - Validate segments array is non-empty.
3.  **Iterate Linearly Through Segments:**
    - Loop `i` from `0` to `segments.length - 1`.
    - Early exit: If `cumulativeSupplyProcessed >= targetSupply`, break.
    - **Extract segment data cleanly:**
      - Option A (batch): `(uint256 pInitial, uint256 pIncrease, uint256 sPerStep, uint256 nSteps) = segments[i].unpack();`
      - Option B (individual): `uint256 pInitial = segments[i].initialPrice();` etc.
    - `supplyRemainingInTarget = targetSupply - cumulativeSupplyProcessed;`
    - `nStepsToProcessThisSeg = (supplyRemainingInTarget + sPerStep - 1) / sPerStep;` (Ceiling division)
    - Cap at segment's total steps: `if (nStepsToProcessThisSeg > nSteps) nStepsToProcessThisSeg = nSteps;`
    - **Calculate collateral using arithmetic series (Formula A) or direct calculation:**
      - **Sloped Segment:** `termVal = (2 * pInitial) + (nStepsToProcessThisSeg > 0 ? (nStepsToProcessThisSeg - 1) * pIncrease : 0); collateralForPortion = (sPerStep * nStepsToProcessThisSeg * termVal) / (2 * SCALING_FACTOR);`
      - **Flat Segment:** `collateralForPortion = nStepsToProcessThisSeg * sPerStep * pInitial / SCALING_FACTOR;`
    - `totalCollateralReserve += collateralForPortion;`
    - `cumulativeSupplyProcessed += nStepsToProcessThisSeg * sPerStep;`
4.  **Return:** `totalCollateralReserve`

## VI. `calculatePurchaseReturn` Function

1.  **Function Signature:**
    `function calculatePurchaseReturn(PackedSegment[] memory segments, uint256 collateralAmountIn, uint256 currentTotalIssuanceSupply) internal pure returns (uint256 issuanceAmountOut, uint256 collateralAmountSpent)`
2.  **Initial Checks & Setup:**
    - Early returns: If `collateralAmountIn == 0` or `segments.length == 0`, return `(0, 0)`.
    - Initialize accumulators: `totalIssuanceAmountOut = 0; totalCollateralSpent = 0; remainingCollateral = collateralAmountIn;`
    - Find starting position: `pos = _findPositionForSupply(segments, currentTotalIssuanceSupply);`
    - `startSegmentIdx = pos.segmentIndex; startStepInSeg = pos.stepIndexWithinSegment;`
3.  **Iterate Linearly Through Segments (from `startSegmentIdx`):**
    - Loop `i` from `startSegmentIdx` to `segments.length - 1`.
    - Early exit optimization: If `remainingCollateral == 0`, break.
    - **Extract segment data cleanly:** `(uint256 pInitial, uint256 pIncrease, uint256 sPerStep, uint256 nSteps) = segments[i].unpack();`
    - `effectiveStartStep = (i == startSegmentIdx) ? startStepInSeg : 0;`
    - Skip full segments: If `effectiveStartStep >= nSteps`, continue.
    - `stepsAvailableInSeg = nSteps - effectiveStartStep;`
    - `priceAtEffectiveStartStep = pInitial + (effectiveStartStep * pIncrease);`
    - **Flat Segment Logic (pIncrease == 0):**
      - Calculate max affordable: `maxIssuanceFromRemFlatSegment = stepsAvailableInSeg * sPerStep;`
      - `costToBuyRemFlatSegment = (maxIssuanceFromRemFlatSegment * priceAtEffectiveStartStep) / SCALING_FACTOR;`
      - **If affordable:** Purchase entire remainder, update accumulators.
      - **Else:** Partial purchase: `issuanceBought = (remainingCollateral * SCALING_FACTOR) / priceAtEffectiveStartStep;` Cap at step supply. Update and break.
    - **Sloped Segment Logic (pIncrease > 0):**
      - **Binary search for `best_n_steps`** within available steps:
        - Inputs: `remainingCollateral`, `priceAtEffectiveStartStep`, `pIncrease`, `sPerStep`, `stepsAvailableInSeg`.
        - Binary search loop: Calculate cost using Formula A for `mid_n` steps.
        - `cost = (sPerStep * mid_n * (2*priceAtEffectiveStartStep + (mid_n > 0 ? (mid_n-1)*pIncrease : 0))) / (2 * SCALING_FACTOR);`
        - Update `best_n_steps` and `cost_for_best_n_steps` based on affordability.
      - Update accumulators with complete steps purchased.
      - **Handle Partial Final Step:** Following established pattern with proper scaling.
4.  **Return:** `(totalIssuanceAmountOut, totalCollateralSpent)`

## VII. `calculateSaleReturn` Function

1.  **Function Signature:**
    `function calculateSaleReturn(PackedSegment[] memory segments, uint256 issuanceAmountIn, uint256 currentTotalIssuanceSupply) internal pure returns (uint256 collateralAmountOut, uint256 issuanceAmountBurned)`
2.  **Optimized Approach (Leveraging `calculateReserveForSupply`):**
    - Cap input: `issuanceToSell = issuanceAmountIn > currentTotalIssuanceSupply ? currentTotalIssuanceSupply : issuanceAmountIn;`
    - `finalSupplyAfterSale = currentTotalIssuanceSupply - issuanceToSell;`
    - `collateralAtCurrentSupply = calculateReserveForSupply(segments, currentTotalIssuanceSupply);`
    - `collateralAtFinalSupply = calculateReserveForSupply(segments, finalSupplyAfterSale);`
    - `totalCollateralAmountOut = collateralAtCurrentSupply - collateralAtFinalSupply;`
    - Add safety check: Ensure `collateralAtCurrentSupply >= collateralAtFinalSupply`.
3.  **Return:** `(totalCollateralAmountOut, issuanceToSell)`

## VIII. Public API Functions

Add convenience functions for external integration with clean interfaces.

1.  **Segment Creation Function:**

    ```solidity
    function createSegment(
        uint256 initialPrice,
        uint256 priceIncrease,
        uint256 supplyPerStep,
        uint256 numberOfSteps
    ) internal pure returns (PackedSegment) {
        return PackedSegmentLib.create(initialPrice, priceIncrease, supplyPerStep, numberOfSteps);
    }
    ```

2.  **Segment Configuration Validation:**

    ```solidity
    function validateSegmentArray(PackedSegment[] memory segments) internal pure {
        require(segments.length > 0, "DiscreteCurveMathLib__NoSegments");
        require(segments.length <= MAX_SEGMENTS, "DiscreteCurveMathLib__TooManySegments");

        for (uint256 i = 0; i < segments.length; i++) {
            // Validation is done during segment creation, but can add additional logic here
            require(segments[i].supplyPerStep() > 0, "DiscreteCurveMathLib__ZeroSupply");
        }
    }
    ```

## IX. General Implementation Notes

- **Error Handling:** Use Inverter-style error declarations consistently. Add specific errors for packed segment issues: `DiscreteCurveMathLib__InitialPriceTooLarge()`, `DiscreteCurveMathLib__SupplyPerStepTooLarge()`, etc.
- **Gas Optimization:**
  - Use batch unpacking (`segments[i].unpack()`) when accessing multiple fields.
  - Use individual accessors (`segments[i].initialPrice()`) when accessing single fields.
  - Cache frequently accessed values in local variables.
- **Precision:** Maintain consistent scaling with `SCALING_FACTOR = 1e18` throughout calculations.
- **Type Safety:** PackedSegment type prevents accidental mixing with other bytes32 values.

## X. Testing Strategy

1.  **File Structure:**
    - `test/unit/modules/fundingManager/bondingCurve/libraries/DiscreteCurveMathLib_v1.t.sol`
    - `test/mocks/modules/fundingManager/bondingCurve/DiscreteCurveMathLibV1_Exposed.sol` (for testing internal functions)
2.  **Test Setup:**
    - Helper function `_createTestSegment(uint256 price, uint256 increase, uint256 supply, uint256 steps) returns (PackedSegment)` using the clean factory function.
    - Test segment validation by attempting to create segments with values exceeding bit limits.
3.  **Unit Test Categories:**
    - **PackedSegment Creation & Access:** Test factory function validation, accessor functions, batch vs individual access performance.
    - **`_findPositionForSupply`:** All edge cases using PackedSegment arrays.
    - **Core Functions:** All established test patterns, but using PackedSegment arrays instead of struct arrays.
    - **Type Safety Tests:** Ensure PackedSegment cannot be mixed with other bytes32 values, test compiler type checking.
    - **Gas Benchmarking:** Measure single-slot storage versus multi-slot alternatives.
4.  **Gas Benchmarking Suite:**
    - Compare storage costs: 1 slot (PackedSegment) vs 2 slots (uint128 struct) vs 4 slots (uint256 struct).
    - Measure access pattern performance: batch unpack vs individual accessors.
    - Test realistic bonding curve scenarios (2-7 segments, various step counts).

This revised plan achieves both maximum gas efficiency (1 storage slot per segment) and clean codebase maintainability through type-safe packed storage with helper functions that abstract away the complexity of bit manipulation.
