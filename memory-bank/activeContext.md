# Active Context

## Current Work Focus

**Primary**: DiscreteCurveMathLib_v1 implementation COMPLETED with code review complete

**Status**: Production-ready implementation with minor test improvements remaining

## Recent Progress

- ✅ DiscreteCurveMathLib_v1 full implementation with comprehensive validation
- ✅ PackedSegmentLib helper library with 256-bit efficient packing
- ✅ Type-safe PackedSegment custom type implementation
- ✅ Gas-optimized mathematical algorithms with edge case handling
- ✅ Comprehensive error handling with descriptive custom errors

## Implementation Quality Assessment

**High-quality, production-ready code** with:

- Defensive programming patterns (validation at multiple layers)
- Gas-optimized algorithms with safety bounds
- Clear separation of concerns between libraries
- Comprehensive edge case handling
- Type safety with custom types

## Next Immediate Steps

1. **Complete minor test improvements** for DiscreteCurveMathLib (final polish)
2. **Begin FM_BC_DBC implementation** using established patterns from math library
3. **Apply discovered patterns** to DynamicFeeCalculator design
4. **Design integration interfaces** based on actual function signatures

## Implementation Insights Discovered

### Defensive Programming Pattern ✅

**Multi-layer validation approach:**

```solidity
// 1. Parameter validation at creation
PackedSegmentLib._create() // validates ranges, no-free-segments
// 2. Array validation for curve configuration
_validateSegmentArray() // validates progression, segment limits
// 3. State validation before calculations
_validateSupplyAgainstSegments() // validates supply vs capacity
```

### Gas Optimization Strategies ✅

**Implemented optimizations:**

- **Packed storage**: 4 parameters → 1 storage slot (256 bits total)
- **Variable caching**: `uint numSegments_ = segments_.length` pattern throughout
- **Batch unpacking**: `_unpack()` for multiple parameter access
- **Linear search bounds**: `MAX_LINEAR_SEARCH_STEPS = 200` prevents gas bombs
- **Conservative rounding**: `_mulDivUp()` favors protocol in calculations

### Error Handling Pattern ✅

**Comprehensive custom errors with context:**

```solidity
DiscreteCurveMathLib__SupplyExceedsCurveCapacity(uint256 currentSupply, uint256 totalCapacity)
DiscreteCurveMathLib__InvalidPriceProgression(uint256 segmentIndex, uint256 previousFinal, uint256 nextInitial)
```

### Mathematical Precision Patterns ✅

**Protocol-favorable rounding:**

```solidity
// Conservative reserve calculations (favors protocol)
collateralForPortion_ = _mulDivUp(supplyPerStep_, totalPriceForAllStepsInPortion_, SCALING_FACTOR);
// Purchase costs rounded up (favors protocol)
uint costForCurrentStep_ = _mulDivUp(supplyPerStep_, priceForCurrentStep_, SCALING_FACTOR);
```

## Current Architecture Understanding - CONCRETE

### Library Integration Pattern ✅

```solidity
// Clean syntax enabled by library usage
using PackedSegmentLib for PackedSegment;

// Actual function signatures for FM integration:
(uint tokensToMint_, uint collateralSpentByPurchaser_) =
    _calculatePurchaseReturn(segments_, collateralToSpendProvided_, currentTotalIssuanceSupply_);

(uint collateralToReturn_, uint tokensToBurn_) =
    _calculateSaleReturn(segments_, tokensToSell_, currentTotalIssuanceSupply_);

uint totalReserve_ = _calculateReserveForSupply(segments_, targetSupply_);
```

### Bit Allocation Reality ✅

**Actual PackedSegment layout (256 bits):**

- `initialPrice`: 72 bits (max ~4.7e21 wei, ~$4,722 for $0.000001 tokens)
- `priceIncrease`: 72 bits (same max)
- `supplyPerStep`: 96 bits (max ~7.9e28 wei, ~79B tokens)
- `numberOfSteps`: 16 bits (max 65,535 steps)

### Validation Chain Implementation ✅

**Three-tier validation system:**

1. **Creation time**: `PackedSegmentLib._create()` validates parameters and prevents free segments
2. **Configuration time**: `_validateSegmentArray()` ensures price progression
3. **Calculation time**: `_validateSupplyAgainstSegments()` checks supply consistency

## Performance Characteristics Discovered

### Linear Search Implementation ✅

```solidity
function _linearSearchSloped(/* params */) internal pure returns (uint, uint) {
    // Hard cap: MAX_LINEAR_SEARCH_STEPS = 200
    while (conditions && stepsSuccessfullyPurchased_ < MAX_LINEAR_SEARCH_STEPS) {
        // Step-by-step iteration with early break
    }
}
```

**Trade-off**: Prevents gas bombs while optimizing for typical small purchases

### Arithmetic Series Optimization ✅

```solidity
// For sloped segments in _calculateReserveForSupply:
uint sumOfPrices_ = firstStepPrice_ + lastStepPrice_;
uint totalPriceForAllStepsInPortion_ = Math.mulDiv(stepsToProcessInSegment_, sumOfPrices_, 2);
// O(1) calculation instead of O(n) iteration
```

### Edge Case Handling ✅

**Comprehensive boundary condition handling:**

- Exact segment boundaries in `_findPositionForSupply`
- Partial purchase calculations for remaining budget
- Supply exceeding curve capacity validation
- Zero input validations with descriptive errors

## Integration Requirements - DEFINED FROM CODE

### FM_BC_DBC Integration Interface ✅

**Required contract structure:**

```solidity
contract FM_BC_DBC is VirtualIssuanceSupplyBase_v1, VirtualCollateralSupplyBase_v1 {
    using DiscreteCurveMathLib_v1 for PackedSegment[];

    PackedSegment[] private _segments;

    function mint(uint256 collateralIn) external {
        (uint256 tokensOut, uint256 collateralSpent) =
            _segments._calculatePurchaseReturn(collateralIn, _virtualIssuanceSupply);
    }

    function redeem(uint256 tokensIn) external {
        (uint256 collateralOut, uint256 tokensBurned) =
            _segments._calculateSaleReturn(tokensIn, _virtualIssuanceSupply);
    }
}
```

### configureCurve Function Pattern ✅

**Invariance check implementation ready:**

```solidity
function configureCurve(PackedSegment[] memory newSegments, int256 collateralChange) external {
    // Pre-change reserve calculation
    uint256 currentReserve = _segments._calculateReserveForSupply(_virtualIssuanceSupply);

    // Expected reserve after change
    uint256 expectedReserve = _virtualCollateralSupply + uint256(collateralChange);

    // New configuration reserve calculation
    uint256 newReserve = newSegments._calculateReserveForSupply(_virtualIssuanceSupply);

    require(newReserve == expectedReserve, "Reserve invariance failed");

    // Apply changes
    _segments = newSegments;
    _virtualCollateralSupply = expectedReserve;
}
```

## Implementation Standards Established

### Naming Conventions ✅

- **Underscore suffix**: All function parameters and local variables (`segments_`, `totalReserve_`)
- **Descriptive naming**: `tokensToMint_` vs `issuanceOut`, `collateralSpentByPurchaser_` vs `collateralSpent`
- **Context clarity**: `purchaseStartStepInSegment_` specifies scope clearly

### Function Organization Pattern ✅

```solidity
library DiscreteCurveMathLib_v1 {
    // Constants and using statements

    // ========= Internal Helper Functions =========
    // _validateSupplyAgainstSegments, _findPositionForSupply, _getCurrentPriceAndStep

    // ========= Core Calculation Functions =========
    // _calculateReserveForSupply, _calculatePurchaseReturn, _calculateSaleReturn

    // ========= Internal Convenience Functions =========
    // _createSegment, _validateSegmentArray

    // ========= Custom Math Helpers =========
    // _mulmod, _mulDivUp, _min3
}
```

### Security Patterns ✅

- **Conservative rounding**: Always favor protocol in financial calculations
- **Overflow protection**: Custom `_mulDivUp` with overflow checks
- **Input validation**: Multiple validation layers for different contexts
- **Gas safety**: Hard limits on iteration counts

## Known Technical Constraints - QUANTIFIED

### PackedSegment Bit Limitations ✅

**Real-world impact quantified:**

- 72-bit price fields = max ~4.7e21 wei
- For $0.000001 tokens: max ~$4.72 representable price
- For $0.0000000001 tokens: Would overflow at $0.47
- **Assessment**: Adequate for major stablecoins, potential issue for extreme micro-tokens

### Linear Search Performance ✅

- **Hard cap**: 200 steps maximum per search
- **Gas cost**: ~5-10k gas per step (estimated)
- **Max gas**: ~1-2M gas for maximum search
- **Trade-off**: Prevents gas bombs, may require multiple transactions for huge purchases

## Testing & Validation Status

- ✅ **Core implementation**: Complete and production-ready
- ✅ **Edge case handling**: Comprehensive boundary condition coverage
- 🔄 **Minor test improvements**: In progress (final polish)
- 🎯 **Integration testing**: Ready once FM_BC_DBC begins

## Next Development Priorities - CONCRETE

### Phase 1: FM_BC_DBC Implementation (Immediate)

**Can leverage established patterns:**

- Validation patterns from DiscreteCurveMathLib
- Error handling with custom errors + context
- Gas optimization strategies (caching, batching)
- Conservative rounding for financial calculations

### Phase 2: DynamicFeeCalculator (Parallel)

**Apply discovered patterns:**

- Same defensive programming approach
- Similar error handling patterns
- Gas optimization techniques
- Conservative calculation approach

### Phase 3: Integration Testing

**Test interaction patterns:**

- Library → FM_BC_DBC integration
- Fee calculator → FM_BC_DBC integration
- Virtual supply management during operations
- Invariance checks during rebalancing

## Code Quality Assessment: PRODUCTION-READY ✅

**Strengths identified:**

- Comprehensive input validation at appropriate layers
- Gas-optimized algorithms with safety bounds
- Clear separation of concerns between libraries
- Defensive programming with protocol-favorable calculations
- Excellent error messages with context

**Ready for production deployment** pending final test improvements.
