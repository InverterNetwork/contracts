# System Patterns & Architecture

## Overall Architecture

Built on Inverter stack using modular approach with clear separation of concerns.

## Core Module Structure

### Funding Manager Pattern

(Content remains the same)

### Logic Module Pattern

(Content remains the same)

### Library Pattern - ✅ IMPLEMENTED (Partially under refactor)

- **DiscreteCurveMathLib_v1**: Pure mathematical functions for curve calculations. (`_calculatePurchaseReturn` is currently being refactored).
- **PackedSegmentLib**: Helper library for bit manipulation and validation.
- Stateless, reusable across multiple modules.
- Type-safe with custom PackedSegment type.

### Auxiliary Module Pattern

(Content remains the same)

## Implementation Patterns - ✅ DISCOVERED FROM CODE (Validation pattern revised)

### Defensive Programming Pattern 🔄 (Revised for `_calculatePurchaseReturn`)

**Original Multi-layer validation strategy implemented:**

```solidity
// Layer 1: Parameter validation at creation
// function _create(uint initialPrice_, uint priceIncrease_, uint supplyPerStep_, uint numberOfSteps_) { ... }

// Layer 2: Array-level validation
// function _validateSegmentArray(PackedSegment[] memory segments_) { ... }

// Layer 3: State validation before calculations
// function _validateSupplyAgainstSegments(PackedSegment[] memory segments_, uint currentSupply_) { ... }
```

**Revised Validation Approach for `_calculatePurchaseReturn` within `DiscreteCurveMathLib_v1`**:

- **No Internal Segment Array Validation by `_calculatePurchaseReturn`**: The `_calculatePurchaseReturn` function will **not** perform internal validation on the `segments_` array structure (e.g., checking for price progression, segment limits, total capacity vs. current supply related to segment structure).
- **Caller Responsibility for Segment Array Validation**: The primary responsibility for ensuring the `segments_` array is valid and consistent (e.g., correct price progression, no free segments, within `MAX_SEGMENTS`) lies with the calling contract, typically `FM_BC_DBC` during its `configureCurve` (or equivalent initialization/update) function. `FM_BC_DBC` should use utilities like `DiscreteCurveMathLib_v1._validateSegmentArray` for this.
- **`_calculatePurchaseReturn` Input Trust**: This function will trust its direct input parameters (`segments_`, `collateralToSpendProvided_`, `currentTotalIssuanceSupply_`). If these parameters are inconsistent (e.g., `currentTotalIssuanceSupply_` exceeds the capacity of a _validly structured but too small_ `segments_` array, or `collateralToSpendProvided_` is zero), the function might return zero tokens or spend zero collateral, or behave according to the mathematical interpretation of those inputs without throwing structural validation errors for the `segments_` array itself.
- **Basic Input Validation in `_calculatePurchaseReturn`**: The function may still perform basic checks on its direct inputs, for example, ensuring `collateralToSpendProvided_` is not zero if that's a logical requirement for purchasing, or that `segments_` is not an empty array.
- **`PackedSegmentLib._create`**: Continues to validate individual segment parameters upon creation.
- **Other Library Functions**: Other functions within `DiscreteCurveMathLib_v1` (e.g., `_calculateSaleReturn`, `_calculateReserveForSupply`) will maintain their existing validation logic until or unless they are also specified for refactoring with a similar validation responsibility shift.

**Application to Future Modules:**

- `FM_BC_DBC` **must** validate segment arrays during configuration and before they are used in calculations by `DiscreteCurveMathLib_v1` functions that expect pre-validated arrays.
- `DynamicFeeCalculator` should validate fee parameters + calculation inputs.
- `Credit facility` should validate loan parameters + system state.

### Type-Safe Packed Storage Pattern - ✅ IMPLEMENTED

(Content remains the same)

### Gas Optimization Pattern - ✅ IMPLEMENTED

(Content remains the same, noting `_calculatePurchaseReturn`'s internal iteration logic is changing)

### Mathematical Precision Pattern - ✅ IMPLEMENTED

(Content remains the same)

### Error Handling Pattern - ✅ IMPLEMENTED (Contextual errors still key)

**Descriptive custom errors with context:**

```solidity
// Interface defines contextual errors
interface IDiscreteCurveMathLib_v1 {
    error DiscreteCurveMathLib__SupplyExceedsCurveCapacity(uint256 currentSupply, uint256 totalCapacity); // May be thrown by _validateSupplyAgainstSegments if called by FM, or by other lib functions.
    error DiscreteCurveMathLib__InvalidPriceProgression(uint256 segmentIndex, uint256 previousFinal, uint256 nextInitial); // Primarily expected from _validateSegmentArray, called by FM.
    error DiscreteCurveMathLib__SegmentIsFree(); // From _createSegment or _validateSegmentArray.
    error DiscreteCurveMathLib__ZeroCollateralInput(); // Could be from _calculatePurchaseReturn if collateral is 0.
}
```

The source of some errors (like `InvalidPriceProgression`) will now more clearly be from the caller's validation step (e.g., `FM_BC_DBC` calling `_validateSegmentArray`) rather than deep within `_calculatePurchaseReturn`'s logic for segment array issues.

### Naming Convention Pattern - ✅ ESTABLISHED

(Content remains the same)

### Library Architecture Pattern - ✅ IMPLEMENTED (Core logic of one function changing)

(Content remains the same, noting `_calculatePurchaseReturn` is being refactored)

## Integration Patterns - ✅ READY FOR IMPLEMENTATION (Caller validation emphasized)

### Library → FM_BC_DBC Integration Pattern

**Established function signatures (with new validation context for `mint`):**

```solidity
contract FM_BC_DBC is VirtualIssuanceSupplyBase_v1, VirtualCollateralSupplyBase_v1 {
    using DiscreteCurveMathLib_v1 for PackedSegment[];

    PackedSegment[] private _segments;

    function mint(uint256 collateralIn, uint256 minTokensOut) external {
        // Apply basic input validation
        if (collateralIn == 0) revert FM_BC_DBC__ZeroCollateralInput(); // Or similar FM-level error

        // CRITICAL: _segments array is assumed to be pre-validated by configureCurve.
        // _calculatePurchaseReturn will not re-validate segment progression, etc.
        (uint256 tokensOut, uint256 collateralSpent) =
            _segments._calculatePurchaseReturn(collateralIn, _virtualIssuanceSupply);

        // Validate user expectations
        if (tokensOut < minTokensOut) revert FM_BC_DBC__InsufficientOutput(); // Or similar FM-level error
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
        revert FM_BC_DBC__ReserveInvarianeMismatch(newCalculatedReserve, expectedNewReserve); // FM-level error
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

### ✅ Patterns Ready for Immediate Application (with revised validation understanding)

1.  **Defensive programming**: Multi-layer validation approach (responsibility for segment array validation shifted for `_calculatePurchaseReturn`).
    (Other patterns remain the same)
