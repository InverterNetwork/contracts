// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

interface IFM_EXT_TokenVault_v1 {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Error thrown when the amount is zero.
    error Module__FM_EXT_TokenVault__InvalidAmount();

    //--------------------------------------------------------------------------
    // Events

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
    /// @param  tok_ The token to withdraw.
    /// @param  amt_ The amount to withdraw.
    /// @param  dst_ The address to send the tokens to.
    function withdraw(address tok_, uint amt_, address dst_) external;
}
