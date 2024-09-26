// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

interface IFM_EXT_ReservePool_v1 {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Error thrown when the amount is zero.
    error Module__FM_EXT_ReservePool__InvalidAmount();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when eth is withdrawn.
    /// @param dst The address to send the eth to.
    /// @param amount The amount of eth withdrawn.
    event EthWithdrawn(address indexed dst, uint amount);

    /// @notice Event emitted when tokens are withdrawn.
    /// @param token The token to withdraw.
    /// @param dst The address to send the tokens to.
    /// @param amount The amount of tokens withdrawn.
    event TokensWithdrawn(
        address indexed token, address indexed dst, uint amount
    );

    //--------------------------------------------------------------------------
    // Mutating Functions

    /// @notice Enables withdrawal of reserve
    /// @dev    This function is only callable by the owner.
    /// @param  tok The token to withdraw.
    /// @param  amt The amount to withdraw.
    /// @param  dst The address to send the tokens to.
    function withdraw(address tok, uint amt, address dst) external;
}
