// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Interfaces
import {IERC20PaymentClientBase_v1} from
    "@lm/interfaces/IERC20PaymentClientBase_v1.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

interface IPaymentProcessor_v1 {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice invalid caller
    error Module__PaymentProcessor__OnlyCallableByModule();

    /// @notice a client can only execute on its own orders
    error Module__PaymentProcessor__CannotCallOnOtherClientsOrders();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Emitted when a payment gets processed for execution.
    /// @param paymentClient The payment client that originated the order.
    /// @param recipient The address that will receive the payment.
    /// @param paymentToken The address of the token that will be used for the payment
    /// @param amount The amount of tokens the payment consists of.
    /// @param start Timestamp at which the payment should start being paid out.
    /// @param cliff Duration of the cliff period.
    /// @param end Timestamp at which the payment should finished being paid out.
    event PaymentOrderProcessed(
        address indexed paymentClient,
        address indexed recipient,
        address indexed paymentToken,
        uint amount,
        uint start,
        uint cliff,
        uint end
    );

    /// @notice Emitted when an amount of ERC20 tokens gets sent out of the contract.
    /// @param recipient The address that will receive the payment.
    /// @param amount The amount of tokens the payment consists of.
    event TokensReleased(
        address indexed recipient, address indexed token, uint amount
    );

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Processes all payments from an {IERC20PaymentClientBase_v1} instance.
    /// @dev It's up to the the implementation to keep up with what has been
    ///      paid out or not.
    /// @param client The {IERC20PaymentClientBase_v1} instance to process its to payments.
    function processPayments(IERC20PaymentClientBase_v1 client) external;

    /// @notice Cancels all unfinished payments from an {IERC20PaymentClientBase_v1} instance.
    /// @dev It's up to the the implementation to keep up with what has been
    ///      paid out or not.
    /// @param client The {IERC20PaymentClientBase_v1} instance to process its to payments.
    function cancelRunningPayments(IERC20PaymentClientBase_v1 client)
        external;
}
