// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.23;

library DynamicFeeCalculatorLib_v1 {
    uint public constant SCALING_FACTOR = 1e18;

    // --- Fee Calculation Functions ---

    /// @notice Calculate origination fee based on utilization ratio
    /// @param utilizationRatio_ Current utilization ratio
    /// @param Z_origination Base fee component
    /// @param A_origination Utilization threshold for dynamic fee adjustment
    /// @param m_origination Multiplier for dynamic fee component
    /// @return The calculated origination fee
    function calculateOriginationFee(
        uint utilizationRatio_,
        uint Z_origination,
        uint A_origination,
        uint m_origination
    ) internal pure returns (uint) {
        // If utilization is below threshold, return base fee only
        if (utilizationRatio_ < A_origination) {
            return Z_origination;
        } else {
            // Calculate the delta: utilization ratio - threshold
            uint delta = utilizationRatio_ - A_origination;

            // Fee = base fee + (delta * multiplier / scaling factor)
            return Z_origination + (delta * m_origination) / SCALING_FACTOR;
        }
    }

    /// @notice Calculate issuance fee based on premium rate
    /// @param premiumRate The premium rate
    /// @param Z_issueRedeem Base fee component
    /// @param A_issueRedeem Utilization threshold for dynamic fee adjustment
    /// @param m_issueRedeem Multiplier for dynamic fee component
    /// @return The calculated issuance fee
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

    /// @notice Calculate redemption fee based on premium rate
    /// @param premiumRate The premium rate
    /// @param Z_issueRedeem Base fee component
    /// @param A_issueRedeem Utilization threshold for dynamic fee adjustment
    /// @param m_issueRedeem Multiplier for dynamic fee component
    /// @return the calculated redemption fee
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
