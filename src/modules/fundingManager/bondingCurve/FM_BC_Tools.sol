// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

library FM_BC_Tools {
    error Module__BondingCurveBase__FeeAmountToHigh();
    error Module__FM_BC_Bancor_Redeeming_VirtualSupply__InvalidReserveRatio();

    /*     /// @dev Calculates the static price for either selling or buying the issuance token,
    /// based on the provided issuance token supply, collateral supply, and buy or sell reserve ratio.
    /// Note: The reserve ratio specifies whether the sell or buy price is returned.
    /// The formula used is: PPM * PPM * collateralSupply / (issuanceTokenSupply * reserveRatio).
    /// The formula is based on Aragon's BatchedBancorMarketMaker, which can be found here:
    /// https://github.com/AragonBlack/fundraising/blob/5ad1332955bab9d36cfad345ae92b7ad7dc0bdbe/apps/batched-bancor-market-maker/contracts/BatchedBancorMarketMaker.sol#L415
    /// @param _issuanceSupply The total supply of the issuance tokens.
    /// @param _collateralSupply The total supply of the collateral held by the FundingManager.
    /// @param _reserveRatio The reserve ratio, specified as either sell or buy reserve ratio.
    /// @return uint The calculated static price for the specified operation, formatted in PPM
    function _staticPricePPM(
        uint32 PPM,
        uint _issuanceSupply,
        uint _collateralSupply,
        uint32 _reserveRatio
    ) internal pure returns (uint) {
        return uint(PPM) * uint(PPM) * _collateralSupply
            / (_issuanceSupply * uint(_reserveRatio));
    }*/

    /// @dev Converts an amount to a required decimal representation.
    /// This function is useful for handling tokens with different decimal places.
    /// It takes care of both upscaling and downscaling the decimals based on the required decimals.
    ///
    /// @param _amount The amount to be converted.
    /// @param _tokenDecimals The current decimal places of the token.
    /// @param _requiredDecimals The required decimal places for the token.
    ///
    /// @return The converted amount with required decimal places.
    function _convertAmountToRequiredDecimal(
        uint _amount,
        uint8 _tokenDecimals,
        uint8 _requiredDecimals
    ) internal pure returns (uint) {
        // If the token decimal is the same as required decimal, return amount
        if (_tokenDecimals == _requiredDecimals) {
            return _amount;
        }
        // If the decimal of token is > required decimal, calculate conversion rate and
        // return amount converted to required decimal
        if (_tokenDecimals > _requiredDecimals) {
            uint conversionFactor = (10 ** (_tokenDecimals - _requiredDecimals));
            return (_amount / conversionFactor);
        } else {
            // If the decimal of token is < required decimal, calculate conversion rate and
            // return amount converted to required decimals
            uint conversionFactor = (10 ** (_requiredDecimals - _tokenDecimals));
            return (_amount * conversionFactor);
        }
    }
    /*
        /// @dev Calculates the net amount after fee deduction and the fee amount based on
    /// a transaction amount and a specified fee percentage.
    /// @param _transactionAmount The amount involved in the transaction before fee deduction.
    /// @param _feePct The fee percentage to be deducted, represented in basis points (BPS).
    /// @return netAmount The transaction amount after fee deduction.
    /// @return feeAmount The amount of fee deducted from the transaction amount.
    function _calculateNetAmountAndFee(uint _transactionAmount, uint _feePct)
        internal
        pure
        virtual
        returns (uint netAmount, uint feeAmount)
    {
        // Return transaction amount as net amount if fee percentage is zero
        if (_feePct == 0) return (_transactionAmount, feeAmount);
        // Calculate fee amount
        feeAmount = (_transactionAmount * _feePct) / BPS;
        // Calculate net amount after fee deduction
        netAmount = _transactionAmount - feeAmount;
    }*/
    /*
    function _calculateNetAndSplitFees(
        uint _totalAmount,
        uint _protocolFee,
        uint _workflowFee,
        uint BPS
    )
        public
        pure
        returns (uint netAmount, uint protocolFeeAmount, uint workflowFeeAmount)
    {
        if ((_protocolFee + _workflowFee) > BPS) {
            revert Module__BondingCurveBase__FeeAmountToHigh();
        }
        protocolFeeAmount = _totalAmount * _protocolFee / BPS;
        workflowFeeAmount = _totalAmount * _workflowFee / BPS;
        netAmount = _totalAmount - protocolFeeAmount - workflowFeeAmount;
    }
    */
}
