// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.23;

import {IDynamicFeeCalculator_v1} from
    "src/modules/logicModule/libraries/IDynamicFeeCalculator_v1.sol";

contract DynamicFeeCalculator_v1 is IDynamicFeeCalculator_v1 {
    // =========================================================================
    // Constants

    /// @notice Scaling factor for the dynamic fee calculator
    uint public constant SCALING_FACTOR = 1e18;

    /// @notice Maximum fee percentage (100% in 1e18 format)
    uint internal constant _MAX_FEE_PERCENTAGE = 1e18;
    // =========================================================================
    // State

    /// @notice Parameters for the dynamic fee calculator
    DynamicFeeParameters public dynamicFeeParameters;

    // --- Fee Calculation Functions ---

    /// @notice Calculate origination fee based on utilization ratio
    /// @param utilizationRatio_ Current utilization ratio
    /// @return The calculated origination fee
    function calculateOriginationFee(uint utilizationRatio_)
        external
        view
        returns (uint)
    {
        // If utilization is below threshold, return base fee only
        if (utilizationRatio_ < dynamicFeeParameters.A_origination) {
            return dynamicFeeParameters.Z_origination;
        } else {
            // Calculate the delta: utilization ratio - threshold
            uint delta = utilizationRatio_ - dynamicFeeParameters.A_origination;

            // Fee = base fee + (delta * multiplier / scaling factor)
            return dynamicFeeParameters.Z_origination
                + (delta * dynamicFeeParameters.m_origination) / SCALING_FACTOR;
        }
    }

    /// @notice Calculate issuance fee based on premium rate
    /// @param premiumRate The premium rate
    /// @return The calculated issuance fee
    function calculateIssuanceFee(uint premiumRate)
        external
        view
        returns (uint)
    {
        if (premiumRate < dynamicFeeParameters.A_issueRedeem) {
            return dynamicFeeParameters.Z_issueRedeem;
        } else {
            return dynamicFeeParameters.Z_issueRedeem
                + (premiumRate - dynamicFeeParameters.A_issueRedeem)
                    * dynamicFeeParameters.m_issueRedeem / SCALING_FACTOR;
        }
    }

    /// @notice Calculate redemption fee based on premium rate
    /// @param premiumRate The premium rate
    /// @return the calculated redemption fee
    function calculateRedemptionFee(uint premiumRate)
        external
        view
        returns (uint)
    {
        if (premiumRate > dynamicFeeParameters.A_issueRedeem) {
            return dynamicFeeParameters.Z_issueRedeem;
        } else {
            return dynamicFeeParameters.Z_issueRedeem
                + (dynamicFeeParameters.A_issueRedeem - premiumRate)
                    * dynamicFeeParameters.m_issueRedeem / SCALING_FACTOR;
        }
    }

    // ------------------------------------------------------------------------
    // Public - Getters

    /// @notice Get the dynamic fee calculator parameters
    /// @return The dynamic fee calculator parameters
    function getDynamicFeeParameters()
        external
        view
        returns (DynamicFeeParameters memory)
    {
        return dynamicFeeParameters;
    }

    // =========================================================================
    // Public - Configuration (Fee Calculator Admin only)

    /// @notice Set the dynamic fee calculator parameters
    /// @param dynamicFeeParameters_ The new dynamic fee calculator parameters
    function setDynamicFeeCalculatorParams(
        DynamicFeeParameters memory dynamicFeeParameters_
    ) external {
        if (
            dynamicFeeParameters_.Z_issueRedeem == 0
                || dynamicFeeParameters_.A_issueRedeem == 0
                || dynamicFeeParameters_.m_issueRedeem == 0
                || dynamicFeeParameters_.Z_origination == 0
                || dynamicFeeParameters_.A_origination == 0
                || dynamicFeeParameters_.m_origination == 0
                || dynamicFeeParameters_.Z_issueRedeem > _MAX_FEE_PERCENTAGE
                || dynamicFeeParameters_.A_issueRedeem > _MAX_FEE_PERCENTAGE
                || dynamicFeeParameters_.m_issueRedeem > _MAX_FEE_PERCENTAGE
                || dynamicFeeParameters_.Z_origination > _MAX_FEE_PERCENTAGE
                || dynamicFeeParameters_.A_origination > _MAX_FEE_PERCENTAGE
                || dynamicFeeParameters_.m_origination > _MAX_FEE_PERCENTAGE
        ) {
            revert
                IDynamicFeeCalculator_v1
                .Module__IDynamicFeeCalculator_v1_InvalidDynamicFeeParameters();
        }
        dynamicFeeParameters = dynamicFeeParameters_;
        emit DynamicFeeCalculatorParamsUpdated(dynamicFeeParameters_);
    }
}
