// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

/**
 * @title   Inverter Payment Router interface
 *
 * @notice  This module enables pushing payments directly to the Payment Processor.
 *
 * @dev     Extends {ERC20PaymentClientBase_v3} to integrate payment processing with
 *          bounty management, supporting dynamic additions, updates, and the locking
 *          of bounties. Utilizes roles for managing permissions and maintaining robust
 *          control over bounty operations.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
 *
 * @custom:version  v3.0.0
 *
 * @author  Inverter Network
 */
interface ILM_PC_PaymentRouter_v3 {
    // -----------------------------------------------------------------------------
    // Errors

    /// @notice Given arrays' length mismatch.
    error Module__LM_PC_PaymentRouter_v3__ArrayLengthMismatch();

    //--------------------------------------------------------------------------
    // Mutating Functions

    /// @notice Adds a new Payment Order.
    /// @dev    Function access controlled by authorizer.
    /// @dev	Reverts if an argument invalid.
    /// @param  recipient The address that will receive the payment.
    /// @param  paymentToken The token in which to pay.
    /// @param  amount The amount of tokens the payment consists of.
    /// @param  start The timestamp at which the payment SHOULD be fulfilled.
    /// @param  cliff The duration of the payment cliff.
    /// @param  end The timestamp at which the payment SHOULD be fulfilled.
    function pushPayment(
        address recipient,
        address paymentToken,
        uint amount,
        uint start,
        uint cliff,
        uint end
    ) external;

    /// @notice Adds multiple Payment Orders in one batch. These PaymentOrders will share start,
    ///         cliff and end timestamps.
    /// @dev    Function access controlled by authorizer.
    /// @dev	Reverts if an argument invalid. The number of orders to be added in one batch is capped at 255.
    /// @param  numOfOrders The number of orders to add.
    /// @param  recipients The addresses that will receive the payments.
    /// @param  paymentTokens The tokens in which to pay.
    /// @param  amounts The amounts of tokens the payments consist of.
    /// @param  start The timestamp at which the payments should start.
    /// @param  cliff The duration of the payment cliff.
    /// @param  end The timestamps at which the payments SHOULD be fulfilled.
    function pushPaymentBatched(
        uint8 numOfOrders,
        address[] calldata recipients,
        address[] calldata paymentTokens,
        uint[] calldata amounts,
        uint start,
        uint cliff,
        uint end
    ) external;
}
