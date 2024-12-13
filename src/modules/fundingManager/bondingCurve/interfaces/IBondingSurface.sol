// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

/**
 * @title   Bonding Surface Formula Interface
 *
 * @notice  Interface for the Bonding Surface Formula. Enables calculation of the
 *         bonding surface of a given set of tokens.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to
 *                          our Security Policy at security.inverter.network or
 *                          email us directly!
 *
 * @custom:version  v1.0.0
 *
 * @custom:inverter-standard-version    0.1.0
 *
 * @author  Inverter Network
 */
interface IBondingSurface {
    // -------------------------------------------------------------------------
    // Errors

    /// @notice    Input amount is invalid.
    error BondingSurface__InvalidInputAmount();

    // ========================================================================
    // Public Getter Functions

    /// @notice    Compute spot price for a given capital available and capital required
    /// @dev       p = f(C_a, C_r) = B * (C_a^2 / C_r)
    ///
    /// @param  capitalAvailable_ Capital pool to base the spot price on.
    /// @param  capitalRequirements_ Capital requirements to base the spot price on.
    /// @param  basePriceMultiplier_ Base Price Multiplier.
    /// @return spotPrice_ The spot price.
    function spotPrice(
        uint capitalAvailable_,
        uint capitalRequirements_,
        uint basePriceMultiplier_
    ) external view returns (uint spotPrice_);

    /// @notice Calculate number of tokens to mint based on `_in` tokens supplied
    ///         and `_ca` of capital available.
    /// @dev    To get the number of tokens we have the following formula:
    ///
    ///                1          1         1
    ///         n = ------- * (------- - -------)
    ///              B/C_r      C_a_1     C_a_2
    ///
    ///         _ca must be > 0
    /// @param  in_ Assets added to the pool.
    /// @param  capitalAvailable_ Capital available to use for bonding curve mint.
    /// @param  basePriceToCapitalRatio_ Precomputed factor which combines the
    ///         base price multiplier with capital required.
    /// @return amount_ The amount of tokens to mint.
    function tokenOut(
        uint in_,
        uint capitalAvailable_,
        uint basePriceToCapitalRatio_
    ) external view returns (uint amount_);

    /// @notice Calculate number of assets to return based on `_out` tokens being burnt,
    ///         `_ca` of capital available and `_supply` TPG minted.
    /// @dev    To get the change in assests when burning tokens:
    ///
    ///                B            1
    ///         x = (----- * m + -------)^-1
    ///               C_r         C_a_2
    ///
    ///         m is the token burn amount and C_a_2 is the capitalAvailable before burn
    ///         _ca must be > 0
    /// @param  out_ TPG to burn.
    /// @param  capitalAvailable_ Capital available to use for bonding curve burn.
    /// @param  basePriceToCapitalRatio_ Precomputed factor which combines the
    ///         base price multiplier with capital required.
    /// @return amount_ The amount of assets to return.
    function tokenIn(
        uint out_,
        uint capitalAvailable_,
        uint basePriceToCapitalRatio_
    ) external view returns (uint amount_);
}
