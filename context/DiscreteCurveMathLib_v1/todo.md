# TODO

### Gas Optimization: Pre-calculate Cumulative Supply

The getCurrentPriceAndStep function recalculates cumulative supply:

```solidity
// Current (inefficient):
uint256 cumulativeSupplyBeforeThisSegment = 0;
for (uint k = 0; k < segmentIndex; ++k) {
    cumulativeSupplyBeforeThisSegment += segments[k].numberOfSteps() * segments[k].supplyPerStep();
}

// More efficient approach:
function _getCumulativeSupplyBeforeSegment(
    PackedSegment[] memory segments,
    uint256 segmentIndex
) private pure returns (uint256) {
    uint256 cumulative = 0;
    for (uint256 i = 0; i < segmentIndex; ++i) {
        cumulative += segments[i].numberOfSteps() * segments[i].supplyPerStep();
    }
    return cumulative;
}
```

### Potential Overflow in Arithmetic Series

```solidity
// Current implementation:
uint256 term_sum_prices = (2 * priceAtSegmentInitialStep) + (mid_n_steps_to_buy - 1) * pIncreaseSeg;
uint256 cost_for_mid_n = (sPerStepSeg * mid_n_steps_to_buy * term_sum_prices) / (2 * SCALING_FACTOR);

// Safer implementation:
function _calculateArithmeticSeriesCost(
    uint256 steps,
    uint256 startPrice,
    uint256 priceIncrease,
    uint256 supplyPerStep
) internal pure returns (uint256) {
    if (steps == 0) return 0;

    // Check for potential overflow before calculation
    uint256 lastPrice = startPrice + (steps - 1) * priceIncrease;

    // Use safer arithmetic: avoid intermediate overflow
    uint256 avgPrice = (startPrice + lastPrice) / 2;
    return (steps * supplyPerStep * avgPrice) / SCALING_FACTOR;
}
```
