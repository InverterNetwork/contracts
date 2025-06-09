# System Patterns & Architecture

## Overall Architecture

Built on Inverter stack using modular approach with clear separation of concerns.

## Core Module Structure

### Funding Manager Pattern

(Content remains the same)

### Logic Module Pattern

(Content remains the same)

### Library Pattern - ✅ STABLE, FULLY TESTED & DOCUMENTED (All Refactoring Complete, New Test Added)

- **DiscreteCurveMathLib_v1**: Pure mathematical functions for curve calculations. All refactorings (including `_calculatePurchaseReturn` and removal of `_getCurrentPriceAndStep`) are complete. NatSpec comments added to key functions. State mutability of core functions confirmed as `pure`. The `DiscreteCurveMathLib_v1.t.sol` test suite has been fully refactored, all compiler warnings fixed, and all 65 tests are passing (100% coverage), confirming library stability and production-readiness.
- **PackedSegmentLib**: Helper library for bit manipulation and validation. (`_create` function's stricter validation for "True Flat" and "True Sloped" segments confirmed and fully tested with 10/10 tests passing).
- Stateless (all core math functions are `pure`), reusable across multiple modules.
- Type-safe with custom PackedSegment type.
- **New Test Added**: `testInternal_SetSegments_EmitsEvent` added to `test/unit/modules/fundingManager/bondingCurve/FM_BC_Discrete_Redeeming_VirtualSupply_v1.t.sol`.

### Auxiliary Module Pattern

(Content remains the same)

## Implementation Patterns - ✅ DISCOVERED FROM CODE (Validation pattern revised)

### Defensive Programming Pattern ✅ (Stable & Fully Tested for Libraries)

**Revised Multi-layer validation strategy:**

```solidity
// Layer 1: Parameter validation at creation (PackedSegmentLib._create()):
//    - Validates individual parameter ranges (price, supply, steps within bit limits).
//    - Prevents zero supplyPerStep, zero numberOfSteps.
//    - Prevents entirely free segments (initialPrice == 0 && priceIncrease == 0).
//    - NEW: Enforces "True Flat" (steps=1, increase=0) and "True Sloped" (steps>1, increase>0) segments.
//      - Reverts with DiscreteCurveMathLib__InvalidFlatSegment for multi-step flat segments.
//      - Reverts with DiscreteCurveMathLib__InvalidPointSegment for single-step sloped segments.
// Layer 2: Array validation for curve configuration (DiscreteCurveMathLib_v1._validateSegmentArray()):
//    - Validates segment array properties (not empty, not too many segments).
//    - Validates price progression between segments.
//    - This is the responsibility of the calling contract (e.g., FM_BC_Discrete) to invoke.
// Layer 3: State validation before calculations (e.g., DiscreteCurveMathLib_v1._validateSupplyAgainstSegments()):
//    - Validates current state (like supply) against curve capacity.
//    - Responsibility of calling contracts or specific library functions.
//    - _calculatePurchaseReturn does NOT perform this for segment array structure or supply capacity.
```

**Validation Approach for `_calculatePurchaseReturn` (Post-Refactor)**:

- **No Internal Segment Array/Capacity Validation**: `_calculatePurchaseReturn` does NOT internally validate the `segments_` array structure (e.g., price progression, segment limits) nor does it validate `currentTotalIssuanceSupply_` against curve capacity.
- **Caller Responsibility**: The calling contract (e.g., `FM_BC_Discrete`) is responsible for ensuring the `segments_` array is valid (using `_validateSegmentArray`) and that `currentTotalIssuanceSupply_` is consistent before calling `_calculatePurchaseReturn`.
- **Input Trust**: `_calculatePurchaseReturn` trusts its input parameters regarding segment validity and supply consistency.
- **Basic Input Checks**: The refactored `_calculatePurchaseReturn` includes its own checks for `collateralToSpendProvided_ > 0` and `segments_.length > 0`, reverting with specific errors.

**Application to Future Modules:**

- `FM_BC_Discrete` **must** validate segment arrays (using `DiscreteCurveMathLib_v1._validateSegmentArray`) and supply capacity (e.g., using `DiscreteCurveMathLib_v1._validateSupplyAgainstSegments`) during configuration and before calling `_calculatePurchaseReturn`.
- `DynamicFeeCalculator` should validate its own fee parameters and calculation inputs.
- `Credit facility` should validate its own loan parameters and system state.

### Type-Safe Packed Storage Pattern - ✅ IMPLEMENTED

(Content remains the same)

### Gas Optimization Pattern - ✅ IMPLEMENTED (Reflects `_calculatePurchaseReturn` refactor)

(Content remains the same, noting `_calculatePurchaseReturn`'s internal iteration logic has changed from using helpers like `_linearSearchSloped` to direct iteration).

### Mathematical Precision Pattern - ✅ IMPLEMENTED

(Content remains the same)

### Error Handling Pattern - ✅ STABLE & FULLY TESTED (New segment errors integrated and covered)

**Descriptive custom errors with context:**

```solidity
// Interface defines contextual errors (IDiscreteCurveMathLib_v1.sol)
interface IDiscreteCurveMathLib_v1 {
    // ... (existing errors)
    error DiscreteCurveMathLib__InvalidFlatSegment(); // NEW: For multi-step flat segments
    error DiscreteCurveMathLib__InvalidPointSegment(); // NEW: For single-step sloped segments
    // ... (other errors like ZeroCollateralInput, NoSegmentsConfigured used by _calculatePurchaseReturn)
}
```

- `PackedSegmentLib._create()` now throws `DiscreteCurveMathLib__InvalidFlatSegment` and `DiscreteCurveMathLib__InvalidPointSegment`.
- `_calculatePurchaseReturn` now directly throws `DiscreteCurveMathLib__ZeroCollateralInput` and `DiscreteCurveMathLib__NoSegmentsConfigured`.
- The source of errors like `InvalidPriceProgression` (from `_validateSegmentArray`) remains the caller's responsibility to handle if they call that utility.

### Naming Convention Pattern - ✅ ESTABLISHED

(Content remains the same)

### Library Architecture Pattern - ✅ STABLE & FULLY TESTED (Reflects all refactoring, including `_calculatePurchaseReturn` and removal of helpers/other functions like `_getCurrentPriceAndStep`)

## Integration Patterns - ✅ READY FOR IMPLEMENTATION (Caller validation emphasized)

### Library → FM_BC_Discrete Integration Pattern

**Established function signatures (with new validation context for `mint`):**

```solidity
contract FM_BC_Discrete is VirtualIssuanceSupplyBase_v1, VirtualCollateralSupplyBase_v1 {
    using DiscreteCurveMathLib_v1 for PackedSegment[];

    PackedSegment[] private _segments;

    function mint(uint256 collateralIn, uint256 minTokensOut) external {
        // Apply basic input validation
        if (collateralIn == 0) revert FM_BC_Discrete__ZeroCollateralInput(); // Or similar FM-level error

        // CRITICAL: _segments array is assumed to be pre-validated by configureCurve.
        // _calculatePurchaseReturn will not re-validate segment progression, etc.
        (uint256 tokensOut, uint256 collateralSpent) =
            _segments._calculatePurchaseReturn(collateralIn, _virtualIssuanceSupply);

        // Validate user expectations
        if (tokensOut < minTokensOut) revert FM_BC_Discrete__InsufficientOutput(); // Or similar FM-level error
        // ...
    }
}
```

### Invariance Check Pattern - ✅ READY FOR IMPLEMENTATION

**`configureCurve` function with mathematical validation (and now explicit segment array validation):**

```solidity
function configureCurve(PackedSegment[] memory newSegments, int256 collateralChangeAmount) external {
    // CRITICAL: Apply segment array validation using the library's utility
    DiscreteCurveMathLib_v1._validateSegmentArray(newSegments); // Or newSegments._validateSegmentArray() if using 'for PackedSegment[]'

    // Calculate current state
    uint256 currentReserve = _segments._calculateReserveForSupply(_virtualIssuanceSupply);

    // Calculate expected new state
    uint256 expectedNewReserve = uint256(int256(_virtualCollateralSupply) + collateralChangeAmount);

    // Validate new configuration
    uint256 newCalculatedReserve = newSegments._calculateReserveForSupply(_virtualIssuanceSupply);

    // Invariance check with descriptive error
    if (newCalculatedReserve != expectedNewReserve) {
        revert FM_BC_Discrete__ReserveInvarianeMismatch(newCalculatedReserve, expectedNewReserve); // FM-level error
    }

    // Apply changes atomically
    _segments = newSegments;
    _virtualCollateralSupply = expectedNewReserve;
    // Handle collateral transfer logic
}
```

### Fee Calculator Integration Pattern

(Content remains the same)

## Performance Optimization Patterns - ✅ IMPLEMENTED

(Content remains the same, noting `_calculatePurchaseReturn`'s internal iteration logic is changing)

## State Management Patterns

(Content remains the same)

## Implementation Readiness Assessment

### ✅ Patterns Confirmed, Stable & Fully Tested (Ready for `FM_BC_Discrete` Application, New Test Added)

1.  **Defensive programming**: Multi-layer validation approach (stricter `PackedSegmentLib._create` rules, revised `_calculatePurchaseReturn` caller responsibilities) is now stable and fully tested within the libraries, with all associated unit tests passing.
    (Other patterns like Type-Safe Packed Storage, Gas Optimization, Mathematical Precision, Error Handling, Naming Conventions, Library Architecture, Integration Patterns, Performance Optimization, and State Management are also stable, tested, and reflect the final state of the libraries.)
2.  **New Test Added**: `testInternal_SetSegments_EmitsEvent` added to `test/unit/modules/fundingManager/bondingCurve/FM_BC_Discrete_Redeeming_VirtualSupply_v1.t.sol`.
3.  **`setVirtualCollateralSupply` Implementation**: The pattern for setting virtual collateral supply has been successfully applied and tested within `FM_BC_Discrete_Redeeming_VirtualSupply_v1.sol`.
4.  **`reconfigureSegments` Invariance Check**: The invariance check for `reconfigureSegments` has been confirmed to be working correctly, with the associated test now passing.
