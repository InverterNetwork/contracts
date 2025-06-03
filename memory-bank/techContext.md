# Technical Context

## Core Technologies

(Content remains the same)

## Smart Contract Dependencies

(Content remains the same)

## Development Setup

(Content remains the same)

## Build Configuration

(Content remains the same)

## Testing Framework

(Content remains the same)

## Technical Implementation Details - ✅ STABLE & TESTED (`_calculatePurchaseReturn` fixed, `PackedSegmentLib` validation confirmed)

### DiscreteCurveMathLib_v1 Technical Specifications

#### Library Architecture

(Content remains the same)

#### File Structure & Organization

(Content remains the same)

#### Bit Allocation for PackedSegment - ✅ IMPLEMENTED

(Content remains the same)

#### Core Functions Implemented - ✅ STABLE & TESTED (Reflects fixes, new validation, NatSpec, and `pure` status)

```solidity
// Primary calculation functions
function _calculatePurchaseReturn(
    PackedSegment[] memory segments_,
    uint collateralToSpendProvided_,
    uint currentTotalIssuanceSupply_
) internal pure returns (uint tokensToMint_, uint collateralSpentByPurchaser_); // STABLE & TESTED: Refactored algorithm, fixed, caller validates segments/supply capacity. NatSpec added. Is pure.

function _calculateSaleReturn(
    PackedSegment[] memory segments_,
    uint tokensToSell_,
    uint currentTotalIssuanceSupply_
) internal pure returns (uint collateralToReturn_, uint tokensToBurn_); // Stable. Is pure.

function _calculateReserveForSupply(
    PackedSegment[] memory segments_,
    uint targetSupply_
) internal pure returns (uint totalReserve_); // Stable. NatSpec added. Is pure.

// Configuration & validation functions
function _createSegment( // This is a convenience function in DiscreteCurveMathLib_v1
    uint initialPrice_,
    uint priceIncrease_,
    uint supplyPerStep_,
    uint numberOfSteps_
) internal pure returns (PackedSegment); // Calls PackedSegmentLib._create() which now has stricter validation.

function _validateSegmentArray(PackedSegment[] memory segments_) internal pure; // Utility for callers like FM_BC_DBC. Validates array properties and price progression.

// Position tracking functions
function _getCurrentPriceAndStep( // Still used by other functions, e.g., potentially by a UI or analytics.
    PackedSegment[] memory segments_,
    uint currentTotalIssuanceSupply_
) internal pure returns (uint price_, uint stepIndex_, uint segmentIndex_); // Is pure.

function _findPositionForSupply( // Still used by other functions.
    PackedSegment[] memory segments_,
    uint targetSupply_
) internal pure returns (IDiscreteCurveMathLib_v1.CurvePosition memory position_); // Is pure.
// Note: _calculatePurchaseReturn no longer uses _getCurrentPriceAndStep or _findPositionForSupply directly.
```

### Mathematical Optimization Implementation - ✅ CONFIRMED

(Content for Arithmetic Series remains. New `_calculatePurchaseReturn` uses direct iteration).

### Custom Mathematical Utilities - ✅ IMPLEMENTED

(Content remains the same)

## Performance Considerations - ✅ ANALYZED (Parts may change with refactor)

(Content remains the same)

## Security Considerations - ✅ STABLE & TESTED (Input Validation Strategy and Economic Safety Rules confirmed)

### Input Validation Strategy ✅ (Stable & Tested)

**Revised Three-Layer Approach:**

```solidity
// Layer 1: Parameter validation at segment creation (PackedSegmentLib._create()):
//    - Validates individual parameter ranges (price, supply, steps within bit limits).
//    - Prevents zero supplyPerStep, zero numberOfSteps.
//    - Prevents entirely free segments (initialPrice == 0 && priceIncrease == 0).
//    - NEW: Enforces "True Flat" (steps=1, increase=0) and "True Sloped" (steps>1, increase>0) segments.
//      - Reverts with DiscreteCurveMathLib__InvalidFlatSegment and DiscreteCurveMathLib__InvalidPointSegment.
// Layer 2: Array validation for curve configuration (DiscreteCurveMathLib_v1._validateSegmentArray() by caller):
//    - Validates segment array properties (not empty, MAX_SEGMENTS).
//    - Validates price progression between segments.
// Layer 3: State validation before calculations (e.g., DiscreteCurveMathLib_v1._validateSupplyAgainstSegments() by caller or other lib functions):
//    - Validates current state (like supply) against curve capacity.
```

**Validation for `_calculatePurchaseReturn` (Post-Refactor)**:

- Trusts pre-validated segment array and `currentTotalIssuanceSupply_` (caller responsibility).
- Performs basic checks for zero collateral and empty segments array.

**Other Library Functions**: Functions like `_calculateSaleReturn`, `_calculateReserveForSupply`, `_getCurrentPriceAndStep` still use `_validateSupplyAgainstSegments` internally as appropriate for their logic.

### Economic Safety Rules - ✅ CONFIRMED & TESTED (New segment rules integrated)

1.  **No free segments**: Enforced by `PackedSegmentLib._create`.
2.  **Non-decreasing progression**: Enforced by `_validateSegmentArray` (called by `FM_BC_DBC`).
3.  **Positive step values (supplyPerStep, numberOfSteps)**: Enforced by `PackedSegmentLib._create`.
4.  **Valid Segment Types**: "True Flat" (`steps==1, increase==0`) and "True Sloped" (`steps>1, increase>0`) enforced by `PackedSegmentLib._create`.
5.  **Bounded iterations**: Refactored `_calculatePurchaseReturn` uses direct iteration; gas safety relies on `segments_.length` (checked by `_validateSegmentArray` via caller, implicitly by `MAX_SEGMENTS`) and number of steps within segments (checked by `PackedSegmentLib._create` via `STEPS_MASK`).

### Type Safety - ✅ IMPLEMENTED

(Content remains the same)

### Error Handling - ✅ STABLE & TESTED (New errors integrated)

(Content remains the same, noting addition of `DiscreteCurveMathLib__InvalidFlatSegment` and `DiscreteCurveMathLib__InvalidPointSegment` thrown by `PackedSegmentLib._create`, and `_calculatePurchaseReturn` now directly throws for zero collateral/no segments.)

## Integration Requirements - ✅ DEFINED (Caller validation emphasized)

(Content for Library Usage Pattern and Invariance Check Integration remains, emphasizing caller's role in validating segment array for `_calculatePurchaseReturn`)

## Deployment Considerations

(Content remains the same)

## Known Limitations & Workarounds - ✅ DOCUMENTED

(Content remains the same)

## Implementation Status Summary (Stable)

### ✅ `DiscreteCurveMathLib_v1` (Stable, All Tests Green)

- **`_calculatePurchaseReturn`**: Successfully refactored and fixed. All calculation/rounding issues resolved. Validation strategy (caller validates segments/supply capacity, internal basic checks) confirmed and tested. NatSpec added. Confirmed `pure`.
- **`_calculateReserveForSupply`**: Stable and production-ready. NatSpec added. Confirmed `pure`.
- **Other functions**: Stable, `pure`, and production-ready.
- **PackedSegmentLib**: `_create` function's stricter validation for "True Flat" and "True Sloped" segments is implemented and fully tested.
- **Validation Strategy**: Confirmed and tested. `PackedSegmentLib` is stricter; `_calculatePurchaseReturn` relies on caller validation as designed.
- **Interface**: `IDiscreteCurveMathLib_v1.sol` new error types integrated and tested.
- **Testing**: All 65 unit tests in `DiscreteCurveMathLib_v1.t.sol` (after refactoring out `segmentsData` and fixing compiler warnings) and all 10 unit tests in `PackedSegmentLib.t.sol` are passing.
- **Documentation**: NatSpec added for key functions.

### ✅ Integration Interfaces Confirmed (Caller validation is key)

(Content remains the same, emphasizing caller's role in validating segment array and supply capacity before calling `_calculatePurchaseReturn`).

### ✅ Development Readiness (Ready for `FM_BC_DBC` Integration)

- **Architectural patterns for `_calculatePurchaseReturn` refactor**: Implemented, tested, and stable.
- **Performance and Security for refactor**: Confirmed through successful testing.
- **Next**: Synchronize all documentation (Memory Bank, Markdown docs), then strengthen fuzz testing before proceeding with `FM_BC_DBC` module implementation.

**Overall Assessment**: `DiscreteCurveMathLib_v1`, `PackedSegmentLib.sol`, and the `DiscreteCurveMathLib_v1.t.sol` test suite are stable, internally documented (NatSpec), fully tested (unit tests and compiler warning fixes), and production-ready. External documentation is currently being updated.
