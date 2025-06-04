# Active Context

## Current Work Focus

**Primary**: Updating documentation for `DiscreteCurveMathLib_v1` (NatSpec in code, Memory Bank files, and Markdown documentation).
**Secondary**: Preparing for strengthening fuzz testing for `DiscreteCurveMathLib_v1.t.sol` once all documentation is synchronized.

**Reason for Shift**: NatSpec comments have been added to key functions in `DiscreteCurveMathLib_v1.sol`, their state mutability confirmed as `pure`, and compiler warnings in the test file `DiscreteCurveMathLib_v1.t.sol` have been resolved. The immediate next step is to ensure all related documentation reflects these changes accurately.

## Recent Progress

- ✅ NatSpec comments added to `_calculateReserveForSupply` and `_calculatePurchaseReturn` in `DiscreteCurveMathLib_v1.sol`.
- ✅ State mutability for `_calculateReserveForSupply` and `_calculatePurchaseReturn` in `DiscreteCurveMathLib_v1.sol` confirmed/updated to `pure`.
- ✅ Compiler warnings in `test/unit/modules/fundingManager/bondingCurve/formulas/DiscreteCurveMathLib_v1.t.sol` (related to unused variables in destructuring and try-catch returns) have been fixed.
- ✅ `DiscreteCurveMathLib_v1.t.sol` refactored to remove `segmentsData` and use `packedSegmentsArray` directly.
- ✅ `_getCurrentPriceAndStep` function removed from `DiscreteCurveMathLib_v1.sol`.
- ✅ Tests in `DiscreteCurveMathLib_v1.t.sol` previously using `_getCurrentPriceAndStep` refactored to use `_findPositionForSupply`.
- ✅ `exposed_getCurrentPriceAndStep` function removed from mock contract `DiscreteCurveMathLibV1_Exposed.sol`.
- ⚠️ 9 tests in `test/unit/modules/fundingManager/bondingCurve/formulas/DiscreteCurveMathLib_v1.t.sol` are failing after these changes.
- ✅ `_calculatePurchaseReturn` in `DiscreteCurveMathLib_v1.sol` refactored by user (previous session).
- ✅ `IDiscreteCurveMathLib_v1.sol` updated with new error types (`InvalidFlatSegment`, `InvalidPointSegment`) (previous session).
- ✅ `PackedSegmentLib.sol`'s `_create` function confirmed to contain stricter validation rules (previous session).
- ✅ All tests in `test/unit/modules/fundingManager/bondingCurve/libraries/PackedSegmentLib.t.sol` are passing (previous session).
- ✅ `DiscreteCurveMathLib_v1.sol` and `PackedSegmentLib.sol` are considered stable, internally well-documented (NatSpec), and fully tested.
- ✅ Fixed type mismatch in `test_ValidateSegmentArray_SegmentWithZeroSteps` in `DiscreteCurveMathLib_v1.t.sol` by casting `uint256` `packedValue` to `bytes32` for `PackedSegment.wrap()`.

## Implementation Quality Assessment (DiscreteCurveMathLib_v1 & Tests)

**`DiscreteCurveMathLib_v1` has been refactored (removal of `_getCurrentPriceAndStep`) and its test suite `DiscreteCurveMathLib_v1.t.sol` adapted. However, 9 tests are currently failing and require debugging.** Core library and tests maintain:

- Defensive programming patterns (validation strategy updated, see below).
- Gas-optimized algorithms with safety bounds.
- Clear separation of concerns between libraries.
- Comprehensive edge case handling.
- Type safety with custom types.

## Next Immediate Steps

1.  **Debug and fix 9 failing tests** in `test/unit/modules/fundingManager/bondingCurve/formulas/DiscreteCurveMathLib_v1.t.sol`.
2.  **Update Memory Bank files** (`activeContext.md` - this step, `progress.md`, `systemPatterns.md`, `techContext.md`) to reflect test fixes and current library state (including removal of `_getCurrentPriceAndStep`).
3.  **Update the Markdown documentation file** `src/modules/fundingManager/bondingCurve/formulas/DiscreteCurveMathLib_v1.md` to align with the latest code changes (removal of `_getCurrentPriceAndStep`, test status) and ensure consistency.
4.  Once all unit tests pass: **Strengthen Fuzz Testing for `DiscreteCurveMathLib_v1.t.sol`**:
    - Review existing fuzz tests and identify gaps.
    - Implement new/enhanced fuzz tests for `_calculateReserveForSupply`, `_calculatePurchaseReturn`, `_findPositionForSupply`.
    - Add a new fuzz test for `_calculateSaleReturn`.
5.  **Update Memory Bank** again after fuzz tests are implemented and passing.
6.  Then, proceed to **plan `FM_BC_DBC` Implementation**.

## Implementation Insights Discovered (And Being Revised)

### Defensive Programming Pattern 🔄 (Updated for `PackedSegmentLib` and `_calculatePurchaseReturn`)

**Revised Multi-layer validation approach:**

```solidity
// 1. Parameter validation at creation (PackedSegmentLib._create()):
//    - Validates individual parameter ranges (price, supply, steps within bit limits).
//    - Prevents zero supplyPerStep, zero numberOfSteps.
//    - Prevents entirely free segments (initialPrice == 0 && priceIncrease == 0).
//    - NEW: Enforces "True Flat" (steps=1, increase=0) and "True Sloped" (steps>1, increase>0) segments.
//      - Reverts on multi-step flat segments (InvalidFlatSegment).
//      - Reverts on single-step sloped segments (InvalidPointSegment).
// 2. Array validation for curve configuration (DiscreteCurveMathLib_v1._validateSegmentArray()):
//    - Validates segment array properties (not empty, not too many segments).
//    - Validates price progression between segments.
//    - Responsibility of the calling contract (e.g., FM_BC_DBC) to call this.
// 3. State validation before calculations (e.g., DiscreteCurveMathLib_v1._validateSupplyAgainstSegments()):
//    - Validates current state (like supply) against curve capacity.
//    - Responsibility of calling contracts or specific library functions (but not _calculatePurchaseReturn for segment array structure or supply capacity).

```

**Approach for `_calculatePurchaseReturn` (Post-Refactor)**:

- **No Internal Segment Array/Capacity Validation**: `_calculatePurchaseReturn` does NOT internally validate the `segments_` array structure (e.g., price progression, segment limits) nor does it validate `currentTotalIssuanceSupply_` against curve capacity.
- **Caller Responsibility**: The calling contract (e.g., `FM_BC_DBC`) is responsible for ensuring the `segments_` array is valid (using `_validateSegmentArray`) and that `currentTotalIssuanceSupply_` is consistent before calling `_calculatePurchaseReturn`.
- **Input Trust**: `_calculatePurchaseReturn` trusts its input parameters.
- **Basic Input Checks**: The refactored `_calculatePurchaseReturn` includes checks for `collateralToSpendProvided_ > 0` and `segments_.length > 0`.

### Gas Optimization Strategies ✅ (Still Applicable, `_calculatePurchaseReturn` refactored)

**Implemented optimizations:**

- **Packed storage**: 4 parameters → 1 storage slot (256 bits total)
- **Variable caching**: `uint numSegments_ = segments_.length` pattern throughout
- **Batch unpacking**: `_unpack()` for multiple parameter access
- **Conservative rounding**: `_mulDivUp()` favors protocol in calculations (used for step costs). `Math.mulDiv` (rounds down) used for token calculations from budget.

### Error Handling Pattern ✅ (Updated for new segment errors)

**Comprehensive custom errors with context:**

```solidity
// ... (existing errors)
DiscreteCurveMathLib__InvalidFlatSegment() // NEW: For multi-step flat segments
DiscreteCurveMathLib__InvalidPointSegment() // NEW: For single-step sloped segments
// Note: Errors like InvalidPriceProgression will now primarily be reverted by the caller's validation (e.g., FM_BC_DBC).
// _calculatePurchaseReturn now has its own checks for ZeroCollateralInput and NoSegmentsConfigured.
// PackedSegmentLib._create() now throws InvalidFlatSegment and InvalidPointSegment.
```

### Mathematical Precision Patterns ✅ (Still Applicable)

**Protocol-favorable rounding:**

```solidity
// Conservative reserve calculations (favors protocol)
// collateralForPortion_ = _mulDivUp(supplyPerStep_, totalPriceForAllStepsInPortion_, SCALING_FACTOR);
// Purchase costs rounded up (favors protocol)
// uint costForCurrentStep_ = _mulDivUp(supplyPerStep_, priceForCurrentStep_, SCALING_FACTOR);
```

The refactored `_calculatePurchaseReturn` will continue to use these established precision patterns.

## Current Architecture Understanding - CONCRETE (with notes on refactoring impact)

### Library Integration Pattern ✅ (Reflects refactored `_calculatePurchaseReturn`)

```solidity
// Clean syntax enabled by library usage
using PackedSegmentLib for PackedSegment;

// Actual function signatures for FM integration:
(uint tokensToMint_, uint collateralSpentByPurchaser_) =
    _calculatePurchaseReturn(segments_, collateralToSpendProvided_, currentTotalIssuanceSupply_); // This function has been refactored.

(uint collateralToReturn_, uint tokensToBurn_) =
    _calculateSaleReturn(segments_, tokensToSell_, currentTotalIssuanceSupply_);

uint totalReserve_ = _calculateReserveForSupply(segments_, targetSupply_);
```

### Bit Allocation Reality ✅ (Unchanged)

(Content remains the same)

### Validation Chain Implementation 🔄 (Updated for `PackedSegmentLib` and `_calculatePurchaseReturn`)

**Revised Three-tier validation system:**

1.  **Creation time (`PackedSegmentLib._create()`):**
    - Validates individual parameter ranges.
    - Prevents zero `supplyPerStep_`, zero `numberOfSteps_`.
    - Prevents entirely free segments (`initialPrice_ == 0 && priceIncrease_ == 0`).
    - **NEW**: Enforces "True Flat" (`steps==1, increase==0`) via `DiscreteCurveMathLib__InvalidFlatSegment`.
    - **NEW**: Enforces "True Sloped" (`steps>1, increase>0`) via `DiscreteCurveMathLib__InvalidPointSegment`.
2.  **Configuration time (`DiscreteCurveMathLib_v1._validateSegmentArray()` by caller):**
    - Validates array properties (not empty, `MAX_SEGMENTS`).
    - Validates price progression between segments.
3.  **Calculation time (various functions):**
    - `_calculatePurchaseReturn`: Trusts pre-validated segment array and `currentTotalIssuanceSupply_`. Performs basic checks for zero collateral and empty segments array.
    - Other functions like `_calculateReserveForSupply`, `_calculateSaleReturn`, `_findPositionForSupply` still use `_validateSupplyAgainstSegments` internally as appropriate for their logic.

**New Model for `_calculatePurchaseReturn`**: Trusts pre-validated `segments_` array and `currentTotalIssuanceSupply_` relative to capacity.

## Performance Characteristics Discovered (May change for `_calculatePurchaseReturn`)

### Arithmetic Series Optimization ✅ (Still applicable for other functions like `_calculateReserveForSupply`)

(Content remains the same)

### Edge Case Handling ✅ (To be re-evaluated for refactored `_calculatePurchaseReturn`)

The refactored `_calculatePurchaseReturn` will need its own robust edge case handling based on the new algorithm.

## Integration Requirements - DEFINED FROM CODE (Caller validation is now key)

### FM_BC_DBC Integration Interface ✅

The interface remains, but the _assumption_ about `_calculatePurchaseReturn`'s internal validation changes. `FM_BC_DBC` must ensure `_segments` is valid before calling.

### configureCurve Function Pattern ✅

This function in `FM_BC_DBC` becomes even more critical as it's the point where `_segments.validateSegmentArray()` (or equivalent logic) _must_ be called to ensure the integrity of the curve configuration before it's used by `_calculatePurchaseReturn`.

## Implementation Standards Established ✅ (Still Applicable)

(Naming Conventions, Function Organization Pattern, Security Patterns sections remain largely applicable, though Function Organization might see changes to helpers for `_calculatePurchaseReturn`)

## Known Technical Constraints - QUANTIFIED ✅ (Still Applicable)

(PackedSegment Bit Limitations, Linear Search Performance (for old logic), etc., remain relevant context for the library as a whole)

## Testing & Validation Status ⚠️ (9 Tests Failing)

- ✅ **`DiscreteCurveMathLib_v1.t.sol`**: Refactored to use `_findPositionForSupply` instead of `_getCurrentPriceAndStep`.
- ⚠️ **9 tests are currently failing** in `DiscreteCurveMathLib_v1.t.sol` after the refactor.
- ✅ `exposed_getCurrentPriceAndStep` removed from `DiscreteCurveMathLibV1_Exposed.sol`.
- ✅ **`_calculatePurchaseReturn`**: Successfully refactored, fixed, and all related tests are passing (previous session).
- ✅ **`PackedSegmentLib._create`**: Stricter validation for "True Flat" and "True Sloped" segments implemented and tested (previous session).
- ✅ **`IDiscreteCurveMathLib_v1.sol`**: New error types `InvalidFlatSegment` and `InvalidPointSegment` integrated and covered (previous session).
- ✅ **Unit Tests (`test/unit/modules/fundingManager/bondingCurve/libraries/PackedSegmentLib.t.sol`)**: All 10 tests passing (previous session).
- ✅ **Unit Tests (`test/unit/modules/fundingManager/bondingCurve/formulas/DiscreteCurveMathLib_v1.t.sol`)**: 9 tests failing after refactoring to use `_findPositionForSupply`.
- ✅ **NatSpec**: Added to `_calculateReserveForSupply` and `_calculatePurchaseReturn` in `DiscreteCurveMathLib_v1.sol`.
- ✅ **State Mutability**: `_calculateReserveForSupply` and `_calculatePurchaseReturn` confirmed/updated to `pure`.
- 🎯 **Next**: Debug and fix the 9 failing tests in `DiscreteCurveMathLib_v1.t.sol`.

## Next Development Priorities - REVISED

1.  **Fix Failing Tests (Current Task)**:
    - Debug and fix the 9 failing tests in `test/unit/modules/fundingManager/bondingCurve/formulas/DiscreteCurveMathLib_v1.t.sol`.
2.  **Synchronize Documentation**:
    - Update Memory Bank files (`activeContext.md`, `progress.md`, `systemPatterns.md`, `techContext.md`) to reflect test fixes and current library state.
    - Update `src/modules/fundingManager/bondingCurve/formulas/DiscreteCurveMathLib_v1.md`.
3.  **Strengthen Fuzz Testing for `DiscreteCurveMathLib_v1.t.sol` (once unit tests pass)**:
    - Review existing fuzz tests and identify gaps.
    - Implement new/enhanced fuzz tests for `_calculateReserveForSupply`, `_calculatePurchaseReturn`, `_findPositionForSupply`.
    - Add a new fuzz test for `_calculateSaleReturn`.
4.  **Update Memory Bank** after fuzz tests are implemented and passing.
5.  **Plan `FM_BC_DBC` Implementation**: Outline the structure, functions, and integration points.
6.  **Implement `FM_BC_DBC`**: Begin coding the core logic.

## Code Quality Assessment: `DiscreteCurveMathLib_v1` & Tests (Refactored - Test Regressions)

**`DiscreteCurveMathLib_v1` has been refactored (removal of `_getCurrentPriceAndStep`), and the test suite adapted. However, this has introduced 9 failing tests that need to be addressed to restore stability.** The core library's logic for other functions and the stricter validation in `PackedSegmentLib` remain positive aspects.
