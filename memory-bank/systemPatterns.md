# System Patterns & Architecture

## Overall Architecture

Built on Inverter stack using modular approach with clear separation of concerns.

## Core Module Structure

### Funding Manager Pattern

- **FM_BC_DBC**: Central funding manager implementing discrete bonding curve
- Inherits from VirtualIssuanceSupplyBase_v1 and VirtualCollateralSupplyBase_v1
- Manages minting/redeeming operations
- Holds and manages collateral token reserves

### Logic Module Pattern

- **LM_PC_Credit_Facility**: Manages lending against locked tokens
- **LM_PC_Shift**: Handles liquidity rebalancing (reserve-invariant)
- **LM_PC_Elevator**: Manages revenue injection for floor price elevation

### Library Pattern - ✅ IMPLEMENTED

- **DiscreteCurveMathLib_v1**: Pure mathematical functions for curve calculations
- **PackedSegmentLib**: Helper library for bit manipulation and validation
- Stateless, reusable across multiple modules
- Type-safe with custom PackedSegment type

### Auxiliary Module Pattern

- **DynamicFeeCalculator**: Exchangeable fee calculation module
- **AUT_Roles**: Role-based access control (existing)

## Implementation Patterns - ✅ DISCOVERED FROM CODE

### Defensive Programming Pattern

**Multi-layer validation strategy implemented:**

```solidity
// Layer 1: Parameter validation at creation
function _create(uint initialPrice_, uint priceIncrease_, uint supplyPerStep_, uint numberOfSteps_) {
    if (initialPrice_ > INITIAL_PRICE_MASK) revert DiscreteCurveMathLib__InitialPriceTooLarge();
    if (initialPrice_ == 0 && priceIncrease_ == 0) revert DiscreteCurveMathLib__SegmentIsFree();
    // Additional validations...
}

// Layer 2: Array-level validation
function _validateSegmentArray(PackedSegment[] memory segments_) {
    // Check price progression between segments
    // Validate segment count limits
}

// Layer 3: State validation before calculations
function _validateSupplyAgainstSegments(PackedSegment[] memory segments_, uint currentSupply_) {
    // Validate supply against total curve capacity
}
```

**Application to Future Modules:**

- FM_BC_DBC should validate inputs at function entry + state consistency
- DynamicFeeCalculator should validate fee parameters + calculation inputs
- Credit facility should validate loan parameters + system state

### Type-Safe Packed Storage Pattern - ✅ IMPLEMENTED

**Concrete implementation:**

```solidity
type PackedSegment is bytes32;

library PackedSegmentLib {
    // Bit allocation (total 256 bits)
    uint private constant INITIAL_PRICE_BITS = 72;    // 0-71
    uint private constant PRICE_INCREASE_BITS = 72;   // 72-143
    uint private constant SUPPLY_BITS = 96;           // 144-239
    uint private constant STEPS_BITS = 16;            // 240-255

    function _create(...) internal pure returns (PackedSegment) {
        bytes32 packed_ = bytes32(
            initialPrice_ | (priceIncrease_ << PRICE_INCREASE_OFFSET)
            | (supplyPerStep_ << SUPPLY_OFFSET) | (numberOfSteps_ << STEPS_OFFSET)
        );
        return PackedSegment.wrap(packed_);
    }
}
```

**Benefits Realized:**

- 75% storage reduction (4 slots → 1 slot per segment)
- Type safety prevents mixing with other bytes32 values
- Clean accessor syntax: `segment._initialPrice()`
- Compile-time validation of packed data usage

### Gas Optimization Pattern - ✅ IMPLEMENTED

**Specific optimizations discovered:**

#### Variable Caching

```solidity
uint numSegments_ = segments_.length; // Cache array length
for (uint segmentIndex_ = 0; segmentIndex_ < numSegments_; ++segmentIndex_) {
    // Use cached length instead of repeated .length access
}
```

#### Batch Data Access

```solidity
// Batch unpack when multiple fields needed
(uint initialPrice_, uint priceIncrease_, uint supplyPerStep_, uint totalSteps_) =
    segments_[segmentIndex_]._unpack();

// vs individual access when only one field needed
uint price = segments_[segmentIndex_]._initialPrice();
```

#### Gas Bomb Prevention

```solidity
uint private constant MAX_LINEAR_SEARCH_STEPS = 200;

while (
    stepsSuccessfullyPurchased_ < maxStepsPurchasableInSegment_
    && stepsSuccessfullyPurchased_ < MAX_LINEAR_SEARCH_STEPS  // Hard limit
) {
    // Calculate step costs
}
```

### Mathematical Precision Pattern - ✅ IMPLEMENTED

**Conservative calculation strategy:**

```solidity
// Custom rounding function that favors protocol
function _mulDivUp(uint a_, uint b_, uint denominator_) private pure returns (uint result_) {
    result_ = Math.mulDiv(a_, b_, denominator_); // Floor division
    if (_mulmod(a_, b_, denominator_) > 0) {     // If remainder exists
        result_++;                               // Round up
    }
}

// Applied in financial calculations
collateralCost_ = _mulDivUp(tokenAmount_, price_, SCALING_FACTOR);  // Favors protocol
tokensAffordable_ = Math.mulDiv(budget_, SCALING_FACTOR, price_);   // Standard for user benefit
```

### Error Handling Pattern - ✅ IMPLEMENTED

**Descriptive custom errors with context:**

```solidity
// Interface defines contextual errors
interface IDiscreteCurveMathLib_v1 {
    error DiscreteCurveMathLib__SupplyExceedsCurveCapacity(uint256 currentSupply, uint256 totalCapacity);
    error DiscreteCurveMathLib__InvalidPriceProgression(uint256 segmentIndex, uint256 previousFinal, uint256 nextInitial);
    error DiscreteCurveMathLib__SegmentIsFree();
    error DiscreteCurveMathLib__ZeroCollateralInput();
}

// Usage provides debugging context
if (initialPriceNext_ < finalPriceCurrent_) {
    revert DiscreteCurveMathLib__InvalidPriceProgression(
        i_, finalPriceCurrent_, initialPriceNext_
    );
}
```

### Naming Convention Pattern - ✅ ESTABLISHED

**Consistent underscore suffixed naming:**

```solidity
function _calculatePurchaseReturn(
    PackedSegment[] memory segments_,           // Input parameters
    uint collateralToSpendProvided_,
    uint currentTotalIssuanceSupply_
) internal pure returns (
    uint tokensToMint_,                        // Return values
    uint collateralSpentByPurchaser_
) {
    uint numSegments_ = segments_.length;      // Local variables
    uint budgetRemaining_ = collateralToSpendProvided_;
}
```

**Benefits:**

- Clear distinction between parameters, locals, and state variables
- Improved readability and reduced naming conflicts
- Consistent across all functions

### Library Architecture Pattern - ✅ IMPLEMENTED

**Clean separation of concerns:**

```solidity
library DiscreteCurveMathLib_v1 {
    using PackedSegmentLib for PackedSegment;  // Enable clean syntax

    // ========= Internal Helper Functions =========
    // Low-level operations and validations

    // ========= Core Calculation Functions =========
    // Business logic calculations

    // ========= Internal Convenience Functions =========
    // High-level operations and wrappers

    // ========= Custom Math Helpers =========
    // Mathematical utilities
}

library PackedSegmentLib {
    // Pure bit manipulation and validation
    // No business logic, only data structure operations
}
```

## Integration Patterns - ✅ READY FOR IMPLEMENTATION

### Library → FM_BC_DBC Integration Pattern

**Established function signatures:**

```solidity
contract FM_BC_DBC is VirtualIssuanceSupplyBase_v1, VirtualCollateralSupplyBase_v1 {
    using DiscreteCurveMathLib_v1 for PackedSegment[];

    PackedSegment[] private _segments;

    function mint(uint256 collateralIn, uint256 minTokensOut) external {
        // Apply defensive programming pattern
        if (collateralIn == 0) revert FM_BC_DBC__ZeroCollateralInput();

        // Use library for calculations
        (uint256 tokensOut, uint256 collateralSpent) =
            _segments._calculatePurchaseReturn(collateralIn, _virtualIssuanceSupply);

        // Validate user expectations
        if (tokensOut < minTokensOut) revert FM_BC_DBC__InsufficientOutput();

        // Gas optimization: cache frequently used values
        uint256 currentVirtualSupply = _virtualIssuanceSupply;

        // Apply conservative calculation: round fees up
        // Handle token transfers, fee processing, state updates
    }
}
```

### Invariance Check Pattern - ✅ READY FOR IMPLEMENTATION

**configureCurve function with mathematical validation:**

```solidity
function configureCurve(PackedSegment[] memory newSegments, int256 collateralChangeAmount) external {
    // Apply validation pattern from library
    _segments._validateSegmentArray(newSegments);

    // Calculate current state
    uint256 currentReserve = _segments._calculateReserveForSupply(_virtualIssuanceSupply);

    // Calculate expected new state
    uint256 expectedNewReserve = uint256(int256(_virtualCollateralSupply) + collateralChangeAmount);

    // Validate new configuration
    uint256 newCalculatedReserve = newSegments._calculateReserveForSupply(_virtualIssuanceSupply);

    // Invariance check with descriptive error
    if (newCalculatedReserve != expectedNewReserve) {
        revert FM_BC_DBC__ReserveInvarianeMismatch(newCalculatedReserve, expectedNewReserve);
    }

    // Apply changes atomically
    _segments = newSegments;
    _virtualCollateralSupply = expectedNewReserve;
    // Handle collateral transfer logic
}
```

### Fee Calculator Integration Pattern

**Based on established patterns:**

```solidity
interface IDynamicFeeCalculator {
    function calculateMintFee(uint256 premiumRate, uint256 amount, bytes memory context)
        external view returns (uint256 fee);
    function calculateRedeemFee(uint256 premiumRate, uint256 amount, bytes memory context)
        external view returns (uint256 fee);
    function calculateOriginationFee(uint256 utilizationRate, uint256 amount, bytes memory context)
        external view returns (uint256 fee);
}

// In FM_BC_DBC
contract FM_BC_DBC {
    IDynamicFeeCalculator private _feeCalculator;

    function mint(uint256 collateralIn) external {
        // Calculate base purchase
        (uint256 tokensOut, uint256 collateralSpent) =
            _segments._calculatePurchaseReturn(collateralIn, _virtualIssuanceSupply);

        // Calculate dynamic fee
        uint256 premiumRate = _calculatePremiumRate(); // Based on current price vs floor
        uint256 dynamicFee = _feeCalculator.calculateMintFee(premiumRate, collateralSpent, "");

        // Apply conservative rounding for fee (favors protocol)
        uint256 totalCollateralNeeded = collateralSpent + dynamicFee;

        // Validate and execute
        if (totalCollateralNeeded > collateralIn) revert FM_BC_DBC__InsufficientCollateral();
    }
}
```

## Performance Optimization Patterns - ✅ IMPLEMENTED

### Arithmetic Series Optimization

**O(1) calculation for sloped segments:**

```solidity
// Instead of: for (uint i = 0; i < steps; i++) { sum += initialPrice + i * priceIncrease; }
// Use arithmetic series formula:
uint256 firstStepPrice_ = initialPrice_;
uint256 lastStepPrice_ = initialPrice_ + (stepsToProcess_ - 1) * priceIncrease_;
uint256 sumOfPrices_ = firstStepPrice_ + lastStepPrice_;
uint256 totalPriceForAllSteps_ = Math.mulDiv(stepsToProcess_, sumOfPrices_, 2);
```

### Linear vs Binary Search Strategy

**Implemented decision tree:**

```solidity
function _calculatePurchaseForSingleSegment(/* params */) private pure returns (uint, uint) {
    if (priceIncreasePerStep_ == 0) {
        // Flat segment: Use direct calculation (O(1))
        return _calculateFullStepsForFlatSegment(/* params */);
    } else {
        // Sloped segment: Use linear search (O(n), bounded by MAX_LINEAR_SEARCH_STEPS)
        return _linearSearchSloped(/* params */);
    }
}
```

**Rationale**: Linear search more efficient for expected small purchases due to lower per-step overhead

### Boundary Condition Optimization

**Single function handles all edge cases:**

```solidity
function _findPositionForSupply(PackedSegment[] memory segments_, uint targetSupply_) internal pure {
    // Handles: within segment, at segment boundary, next segment start, curve end
    if (targetSupply_ == segmentEndSupply_ && i_ + 1 < numSegments_) {
        // Exactly at boundary AND there's a next segment: point to next segment start
        position_.segmentIndex = i_ + 1;
        position_.stepIndexWithinSegment = 0;
        position_.priceAtCurrentStep = segments_[i_ + 1]._initialPrice();
    } else {
        // Within segment or at final segment end
        // Calculate step index and price
    }
}
```

## State Management Patterns

### Virtual Supply Pattern

**Separation of virtual tracking from actual tokens:**

```solidity
// In FM_BC_DBC (planned)
contract FM_BC_DBC is VirtualIssuanceSupplyBase_v1, VirtualCollateralSupplyBase_v1 {
    // _virtualIssuanceSupply: Used for curve calculations
    // _virtualCollateralSupply: Used for curve backing
    // Actual ERC20 totalSupply(): May differ due to external factors

    function mint(uint256 collateralIn) external {
        // Use virtual supply for curve calculations
        (uint256 tokensOut, ) = _segments._calculatePurchaseReturn(collateralIn, _virtualIssuanceSupply);

        // Update virtual state
        _virtualIssuanceSupply += tokensOut;
        _virtualCollateralSupply += collateralSpent;

        // Handle actual token transfers
        _issuanceToken.mint(msg.sender, tokensOut);
        _collateralToken.transferFrom(msg.sender, address(this), collateralSpent);
    }
}
```

### Credit Facility Non-Interference Pattern

**Lending operations bypass virtual supply:**

```solidity
// In credit facility (planned)
contract LM_PC_CreditFacility {
    function borrowAgainstTokens(uint256 loanAmount) external {
        // Locking/unlocking issuance tokens does NOT affect _virtualIssuanceSupply
        // Transferring collateral for loans does NOT affect _virtualCollateralSupply
        // Only mint/redeem operations on the curve affect virtual supplies

        _issuanceToken.transferFrom(msg.sender, address(this), collateralValue);
        _fundingManager.transferCollateral(msg.sender, loanAmount); // Direct transfer, no virtual impact
    }
}
```

## Implementation Readiness Assessment

### ✅ Patterns Ready for Immediate Application

1. **Defensive programming**: Multi-layer validation approach
2. **Gas optimization**: Caching, batching, bounded operations
3. **Type safety**: Custom types for packed data
4. **Conservative math**: Protocol-favorable rounding
5. **Error handling**: Descriptive errors with context

### 🎯 Next Implementation Targets Using Established Patterns

1. **FM_BC_DBC**: Apply all discovered patterns directly
2. **DynamicFeeCalculator**: Use validation + gas optimization patterns
3. **Credit facility**: Apply validation + state management patterns
4. **Rebalancing modules**: Use invariance check + math patterns
