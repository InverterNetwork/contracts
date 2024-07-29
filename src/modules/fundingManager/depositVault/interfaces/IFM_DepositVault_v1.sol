// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface IFM_DepositVault_v1 {
    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when a deposit takes place.
    /// @param _from The address depositing tokens.
    /// @param _amount The amount of tokens deposited.
    event Deposit(address indexed _from, uint _amount);

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Deposits a specified amount of tokens into the contract from the sender's account.
    /// @dev    Reverts if attempting self-deposits
    /// @dev    When using the transactionForwarder, validate transaction success to prevent nonce
    ///         exploitation and ensure transaction integrity.
    /// @param amount The number of tokens to deposit.
    function deposit(uint amount) external;

    /// @notice Deposits a specified amount of tokens into the contract for the address defined in
    ///         the `from` parameter.
    /// @dev    Reverts if attempting self-deposits
    /// @dev    When using the transactionForwarder, validate transaction success to prevent nonce
    ///         exploitation and ensure transaction integrity.
    /// @param from The address to deposit tokens for.
    /// @param amount The number of tokens to deposit.
    function depositFor(address from, uint amount) external;
}
