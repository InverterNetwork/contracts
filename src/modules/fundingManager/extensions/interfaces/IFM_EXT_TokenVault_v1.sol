// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

/**
 * @title   Inverter Token Vault
 *
 * @notice  Vault holding token reserves for later use.
 *
 * @dev     Funds can be withdrawn by the orchestrator admin.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to
 *                          our Security Policy at security.inverter.network or
 *                          email us directly!
 *
 * @author  Inverter Network
 */
interface IFM_EXT_TokenVault_v1 {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Error thrown when the amount is invalid.
    error Module__FM_EXT_TokenVault__InvalidAmount();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when tokens are withdrawn.
    /// @param token The token to withdraw.
    /// @param recipient The address to send the tokens to.
    /// @param amount The amount of tokens withdrawn.
    event TokensWithdrawn(
        address indexed token, address indexed recipient, uint amount
    );

    //--------------------------------------------------------------------------
    // Mutating Functions

    /// @notice Allows for withdrawal of reserve tokens.
    /// @dev    This function is only callable by the orchestrator admin.
    /// @param  token_ The token to withdraw.
    /// @param  amount_ The amount of tokens to withdraw.
    /// @param  recipient_ The address to send the tokens to.
    function withdraw(address token_, uint amount_, address recipient_)
        external;
}
