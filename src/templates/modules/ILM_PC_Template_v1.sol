// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal
import {IERC20PaymentClientBase_v2} from
    "@lm/interfaces/IERC20PaymentClientBase_v2.sol";

/**
 * @title   Inverter Template Payment Processor
 *
 * @notice  Basic template payment processor used as base for developing new
 *          payment processors.
 *
 * @dev     This contract is used to showcase a basic setup for a payment
 *          processor. The contract showcases the following:
 *          - Inherit from the Module_v1 contract to enable interaction with
 *            the Inverter workflow.
 *          - Use of the IPaymentProcessor_v2 interface to facilitate
 *            interaction with a payment client.
 *          - Implement custom interface which has all the public facing
 *            functions, errors, events and structs.
 *          - Pre-defined layout for all contract functions, modifiers, state
 *            variables etc.
 *          - Use of the ERC165Upgradeable contract to check for interface
 *            support.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer
 *                          to our Security Policy at security.inverter.network
 *                          or email us directly!
 *
 * @custom:version 1.0.0
 *
 * @author  Inverter Network
 */
interface ILM_PC_Template_v1 is IERC20PaymentClientBase_v2 {
    // =========================================================================
    // Events

    /// @notice Emit when the token amount has been deposited.
    /// @param  sender_ The address of the depositor.
    /// @param  amount_ The amount of tokens deposited.
    event Deposited(address indexed sender_, uint amount_);

    // =========================================================================
    // Errors

    /// @notice Amount can not be zero.
    error Module__LM_PC_Template_InvalidDepositAmount();

    // =========================================================================
    // Public - Getters

    /// @notice Returns the deposited balance of a specific address.
    /// @param  user_ The address of the user.
    /// @return amount_ Deposited amount of the user.
    function getDepositedAmount(address user_) external view returns (uint amount_);

    // =========================================================================
    // Public - Mutating

    /// @notice Deposits tokens to the funding manager.
    /// @param  amount_ The amount of tokens to deposit.
    function deposit(uint amount_) external;

    /// @notice Process a specific deposit by calling processPayments on the payment processor
    /// @param user_ The address of the user whose deposit to process
    function processDeposit(address user_) external;
}
