// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.23;

interface IDynamicFeeCalculator_v1 {
    // -----------------------------------------------------------------------------
    // Events

    /// @notice Emitted when the dynamic fee calculator parameters are updated
    /// @param dynamicFeeParameters_ The new dynamic fee calculator parameters
    event DynamicFeeCalculatorParamsUpdated(
        DynamicFeeParameters dynamicFeeParameters_
    );

    // -----------------------------------------------------------------------------
    // Errors

    /// @notice Invalid dynamic fee parameters
    error Module__IDynamicFeeCalculator_v1_InvalidDynamicFeeParameters();

    // -----------------------------------------------------------------------------
    // Structs

    /// @notice Parameters for the dynamic fee calculator
    /// @dev These parameters are used to calculate the dynamic fee for issuance/redemption and origination fees
    ///      based on the floor liquidity rate.
    ///      Z_issueRedeem: Base fee component for issuance/redemption fees.
    ///      A_issueRedeem: PremiumRate threshold for dynamic issuance/redemption fee adjustment.
    ///      m_issueRedeem: Multiplier for dynamic issuance/redemption fee component.
    ///      Z_origination: Base fee component for origination fees.
    ///      A_origination: FloorLiquidityRate threshold for dynamic origination fee adjustment.
    ///      m_origination: Multiplier for dynamic origination fee component.
    struct DynamicFeeParameters {
        uint Z_issueRedeem;
        uint A_issueRedeem;
        uint m_issueRedeem;
        uint Z_origination;
        uint A_origination;
        uint m_origination;
    }

    // -----------------------------------------------------------------------------
    // Constants

    /// @notice Scaling factor for the dynamic fee calculator
    function SCALING_FACTOR() external view returns (uint);

    // -----------------------------------------------------------------------------
    // View Functions

    /// @notice Calculate the origination fee based on the utilization ratio
    /// @param utilizationRatio_ The utilization ratio
    /// @return The origination fee
    function calculateOriginationFee(uint utilizationRatio_)
        external
        view
        returns (uint);

    /// @notice Calculate the issuance fee based on the premium rate
    /// @param premiumRate_ The premium rate
    /// @return The issuance fee
    function calculateIssuanceFee(uint premiumRate_)
        external
        view
        returns (uint);

    /// @notice Calculate the redemption fee based on the premium rate
    /// @param premiumRate_ The premium rate
    /// @return The redemption fee
    function calculateRedemptionFee(uint premiumRate_)
        external
        view
        returns (uint);

    // -----------------------------------------------------------------------------
    // Mutating Functions

    /// @notice Set the dynamic fee calculator parameters
    /// @param dynamicFeeParameters_ The new dynamic fee calculator parameters
    function setDynamicFeeCalculatorParams(
        DynamicFeeParameters memory dynamicFeeParameters_
    ) external;
}
