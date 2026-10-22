// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

/**
 * @title   Inverter Deposit Vault Funding Manager
 *
 * @notice  This contract allows users to deposit tokens to fund the workflow.
 *
 * @dev     Implements {IFundingManager_v1} interface.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer
 *                          to our Security Policy at security.inverter.network
 *                          or email us directly!
 *
 * @custom:version 1.1.0
 *
 * @author  Inverter Network
 */
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

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Deposits a specified amount of tokens into the contract from the sender's account.
    /// @dev    When using the {TransactionForwarder_v1}, validate transaction success to prevent nonce
    ///         exploitation and ensure transaction integrity.
    /// @param  amount The number of tokens to deposit.
    function deposit(uint amount) external;
}
