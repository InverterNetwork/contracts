// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

/**
 * @title   Inverter Inverter Bonding Curve Tools Library
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
 *
 * @author  Inverter Network
 */
library FM_BC_Tools {
    /// @dev    Error thrown when the fee amount is too high.
    ///         This error is thrown when the fee amount is greater than the maximum fee percentage.
    ///         It takes care of both upscaling and downscaling the decimals based on the required decimals.
    /// @param  _amount The amount to be converted.
    /// @param  _tokenDecimals The current decimal places of the token.
    /// @param  _requiredDecimals The required decimal places for the token.
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
}
