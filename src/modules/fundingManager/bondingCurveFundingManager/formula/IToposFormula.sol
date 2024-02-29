// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;


interface IToposFormula {

    //--------------------------------------------------------------------------
    // Errors

    /// @dev Input amount is invalid
    error ToposFormula__InvalidInputAmount();

    //--------------------------------------------------------------------------
    // Functions

	/// @dev Compute spot price for a given capital available given current capital
	///      requirements
	/// p = f(C_a, C_r) = B * (C_a^2 / C_r)
	///
	/// @param _capitalAvailable Capital available to use for bonding curve mint.
	/// @param _basePriceToCaptialRatio Precomputed factor which combines the base price multiplier with captial required
	function spotPrice( uint256 _capitalAvailable, uint _basePriceToCaptialRatio) external view returns (uint256);

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
	/// @param _basePriceToCaptialRatio Precomputed factor which combines the base price multiplier with captial required
    function tokenOut(uint256 _in, uint256 _capitalAvailable, uint _basePriceToCaptialRatio) external view returns (uint256);

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
	/// @param _basePriceToCaptialRatio Precomputed factor which combines the base price multiplier with captial required
    function tokenIn(uint256 _out, uint256 _capitalAvailable,uint _basePriceToCaptialRatio) external view returns (uint256);

}