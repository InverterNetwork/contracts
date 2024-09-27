// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface IFM_DepositVault_v1 {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Receiver address can not be zero address or
    /// Deposit Vault Funding Manager itself.
    error Module__DepositVault__InvalidRecipient();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when a deposit takes place.
    /// @param  _from The address depositing tokens.
    /// @param  _amount The amount of tokens deposited.
    event Deposit(address indexed _from, uint _amount);

    /// @notice Event emitted when protocol fee has been transferred to the treasury.
    /// @param  token The token received as protocol fee.
    /// @param  treasury The protocol treasury address receiving the token fee amount.
    /// @param  feeAmount The fee amount transferred to the treasury.
    event ProtocolFeeTransferred(
        address indexed token, address indexed treasury, uint feeAmount
    );

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Deposits a specified amount of tokens into the contract from the sender's account.
    /// @dev    When using the {TransactionForwarder_v1}, validate transaction success to prevent nonce
    ///         exploitation and ensure transaction integrity.
    /// @param  amount The number of tokens to deposit.
    function deposit(uint amount) external;
}
