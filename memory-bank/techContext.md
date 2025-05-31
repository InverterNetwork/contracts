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

## Technical Implementation Details - ✅ COMPLETED (but `_calculatePurchaseReturn` under refactor)

### DiscreteCurveMathLib_v1 Technical Specifications

#### Library Architecture

(Content remains the same)

#### File Structure & Organization

(Content remains the same)

#### Bit Allocation for PackedSegment - ✅ IMPLEMENTED

(Content remains the same)

#### Core Functions Implemented - ✅ PRODUCTION READY (`_calculatePurchaseReturn` being refactored)

```solidity
// Primary calculation functions
function _calculatePurchaseReturn(
    PackedSegment[] memory segments_,
    uint collateralToSpendProvided_,
    uint currentTotalIssuanceSupply_
) internal pure returns (uint tokensToMint_, uint collateralSpentByPurchaser_); // UNDER REFACTORING

function _calculateSaleReturn(
    PackedSegment[] memory segments_,
    uint tokensToSell_,
    uint currentTotalIssuanceSupply_
) internal pure returns (uint collateralToReturn_, uint tokensToBurn_);

function _calculateReserveForSupply(
    PackedSegment[] memory segments_,
    uint targetSupply_
) internal pure returns (uint totalReserve_);

// Configuration & validation functions
function _createSegment(
    uint initialPrice_,
    uint priceIncrease_,
    uint supplyPerStep_,
    uint numberOfSteps_
) internal pure returns (PackedSegment);

function _validateSegmentArray(PackedSegment[] memory segments_) internal pure; // Utility for callers like FM_BC_DBC

// Position tracking functions
function _getCurrentPriceAndStep(
    PackedSegment[] memory segments_,
    uint currentTotalIssuanceSupply_
) internal pure returns (uint price_, uint stepIndex_, uint segmentIndex_);

function _findPositionForSupply(
    PackedSegment[] memory segments_,
    uint targetSupply_
) internal pure returns (IDiscreteCurveMathLib_v1.CurvePosition memory position_);
// Note: _findPositionForSupply and _getCurrentPriceAndStep might be modified or made obsolete by the _calculatePurchaseReturn refactor.
```

### Mathematical Optimization Implementation - ✅ BENCHMARKED (Parts may change with refactor)

(Content for Arithmetic Series and Linear Search Strategy remains, noting Linear Search is for original `_calculatePurchaseReturn` logic)

### Custom Mathematical Utilities - ✅ IMPLEMENTED

(Content remains the same)

## Performance Considerations - ✅ ANALYZED (Parts may change with refactor)

(Content remains the same, noting Linear Search performance is for original `_calculatePurchaseReturn` logic)

## Security Considerations - ✅ IMPLEMENTED (Input Validation Strategy revised)

### Input Validation Strategy 🔄 (Revised for `_calculatePurchaseReturn`)

**Original Three-Layer Approach:**

```solidity
// Layer 1: Parameter validation at segment creation (in PackedSegmentLib._create)
// Layer 2: Array validation for curve configuration (in DiscreteCurveMathLib_v1._validateSegmentArray)
// Layer 3: State validation before calculations (in DiscreteCurveMathLib_v1._validateSupplyAgainstSegments)
```

**Revised Validation Model for `_calculatePurchaseReturn`**:

- **`PackedSegmentLib._create`**: Continues to validate individual segment parameters (e.g., non-zero supply per step, price/increase within bit limits, no free segments). This is **Layer 1**.
- **`DiscreteCurveMathLib_v1._validateSegmentArray`**: This function remains a utility for callers. It validates the structural integrity of the `segments_` array (e.g., price progression, `MAX_SEGMENTS`). This is **Layer 2**, but its execution is now the responsibility of the calling contract (e.g., `FM_BC_DBC` during `configureCurve`).
- **`_calculatePurchaseReturn` (Refactored)**:
  - **No Internal Segment Array Validation**: It will **not** call `_validateSegmentArray` or `_validateSupplyAgainstSegments` (for segment structure validation) internally. It trusts the `segments_` array is pre-validated by the caller.
  - **Basic Input Checks**: May perform checks on its direct inputs like `collateralToSpendProvided_ > 0` or `segments_.length > 0`.
  - It does not perform **Layer 3** (state validation like `_validateSupplyAgainstSegments` regarding the `segments_` array structure) internally; if such a check is needed before purchase, the caller should perform it.
- **Other Library Functions**: Functions like `_calculateSaleReturn` or `_calculateReserveForSupply` currently maintain their existing validation logic, which might include calls to `_validateSegmentArray` or `_validateSupplyAgainstSegments` if appropriate for their needs. This could be harmonized later if the "caller validates segments" pattern is adopted library-wide.

### Economic Safety Rules - ✅ ENFORCED (Responsibility partly shifted for `_calculatePurchaseReturn`)

1.  **No free segments**: Enforced by `PackedSegmentLib._create` and `_validateSegmentArray`.
2.  **Non-decreasing progression**: Enforced by `_validateSegmentArray` (called by `FM_BC_DBC`).
3.  **Positive step values**: Enforced by `PackedSegmentLib._create`.
4.  **Bounded iterations**: `MAX_LINEAR_SEARCH_STEPS` (for old `_calculatePurchaseReturn` logic; new logic in refactored function will also need gas safety considerations).

### Type Safety - ✅ IMPLEMENTED

(Content remains the same)

### Error Handling - ✅ COMPREHENSIVE

(Content remains the same, noting source of errors may shift as per `systemPatterns.md`)

## Integration Requirements - ✅ DEFINED (Caller validation emphasized)

(Content for Library Usage Pattern and Invariance Check Integration remains, emphasizing caller's role in validating segment array for `_calculatePurchaseReturn`)

## Deployment Considerations

(Content remains the same)

## Known Limitations & Workarounds - ✅ DOCUMENTED

(Content remains the same)

## Implementation Status Summary (Revised)

### 🔄 `DiscreteCurveMathLib_v1` (`_calculatePurchaseReturn` under refactor)

- **`_calculatePurchaseReturn`**: Undergoing refactoring with new algorithm and validation strategy.
- **Other functions**: Largely stable and production-ready.
- **PackedSegmentLib**: Complete and production-ready.
- **Validation Strategy**: Shifted for `_calculatePurchaseReturn`; segment array validation is now externalized to the caller.

### 🔄 Integration Interfaces Defined (Caller validation is key)

(Content remains the same)

### 📋 Development Readiness (Focus on refactor)

- **Architectural patterns for refactor**: Defined in `context/refactoring.md`.
- **Performance and Security for refactor**: To be re-assessed post-implementation.

**Overall Assessment**: Core library component `_calculatePurchaseReturn` is being refactored. This changes its internal validation logic, placing more responsibility on the calling contracts to ensure segment array integrity. Other parts of the library remain robust.
