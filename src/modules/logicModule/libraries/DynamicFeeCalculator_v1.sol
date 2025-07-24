// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

library DynamicFeeCalculatorLib_v1 {
    uint public constant SCALING_FACTOR = 1e18;

    // --- Fee Calculation Functions ---

    function calculateOriginationFee(
        uint floorLiquidityRate,
        uint Z_origination,
        uint A_origination,
        uint m_origination
    ) internal pure returns (uint) {
        if (floorLiquidityRate < A_origination) {
            return Z_origination;
        } else {
            return Z_origination
                + (floorLiquidityRate - A_origination) * m_origination
                    / SCALING_FACTOR;
        }
    }

    function calculateIssuanceFee(
        uint premiumRate,
        uint Z_issueRedeem,
        uint A_issueRedeem,
        uint m_issueRedeem
    ) internal pure returns (uint) {
        if (premiumRate < A_issueRedeem) {
            return Z_issueRedeem;
        } else {
            return Z_issueRedeem
                + (premiumRate - A_issueRedeem) * m_issueRedeem / SCALING_FACTOR;
        }
    }

    function calculateRedemptionFee(
        uint premiumRate,
        uint Z_issueRedeem,
        uint A_issueRedeem,
        uint m_issueRedeem
    ) internal pure returns (uint) {
        if (premiumRate > A_issueRedeem) {
            return Z_issueRedeem;
        } else {
            return Z_issueRedeem
                + (A_issueRedeem - premiumRate) * m_issueRedeem / SCALING_FACTOR;
        }
    }
}
