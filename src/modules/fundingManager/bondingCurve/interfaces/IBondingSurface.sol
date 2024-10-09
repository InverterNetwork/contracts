// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

interface IBondingSurface {
    //--------------------------------------------------------------------------
    // Errors

    /// @dev Input amount is invalid
    error BondingSurface__InvalidInputAmount();

    //--------------------------------------------------------------------------
    // Functions

    /// @dev Compute spot price for a given capital available and capital required
    /// p = f(C_a, C_r) = B * (C_a^2 / C_r)
    ///
    /// @param _capitalAvailable Capital pool to base the spot price on.
    /// @param _capitalRequirements Capital requirements to base the spot price on.
    /// @param _basePriceMultiplier Base Price Multiplier
    function spotPrice(
        uint _capitalAvailable,
        uint _capitalRequirements,
        uint _basePriceMultiplier
    ) external view returns (uint);

    /// @dev To get the number of tokens we have the following formula:
    ///
    ///        1          1         1
    /// n = ------- * (------- - -------)
    ///      B/C_r      C_a_1     C_a_2
    ///
    /// _ca must be > 0
    /// @notice Calculate number of tokens to mint based on `_in` tokens supplied
    ///         and `_ca` of capital available.
    /// @param _in Assets added to the pool.
    /// @param _capitalAvailable Capital available to use for bonding curve mint.
    /// @param _basePriceToCapitalRatio Precomputed factor which combines the base price multiplier with capital required
    function tokenOut(
        uint _in,
        uint _capitalAvailable,
        uint _basePriceToCapitalRatio
    ) external view returns (uint);

    /// @dev To get the change in assests when burning tokens
    ///
    ///        B            1
    /// x = (----- * m + -------)^-1
    ///       C_r         C_a_2
    ///
    /// m is the token burn amount and C_a_2 is the capitalAvailable before burn
    /// _ca must be > 0
    /// @notice Calculate number of assets to return based on `_out` tokens being burnt,
    ///         `_ca` of capital available and `_supply` TPG minted.
    /// @param _out TPG to burn
    /// @param _capitalAvailable Capital available to use for bonding curve burn.
    /// @param _basePriceToCapitalRatio Precomputed factor which combines the base price multiplier with capital required
    function tokenIn(
        uint _out,
        uint _capitalAvailable,
        uint _basePriceToCapitalRatio
    ) external view returns (uint);
}
