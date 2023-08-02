// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IERC20} from "@oz/token/ERC20/IERC20.sol";

import {IERC20PaymentClient} from
    "src/modules/base/mixins/IERC20PaymentClient.sol";

interface IPaymentProcessor {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice invalid caller
    error Module__PaymentManager__OnlyCallableByModule();

    /// @notice a client can only execute on its own orders
    error Module__PaymentManager__CannotCallOnOtherClientsOrders();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Emitted when a payment gets processed for execution.
    /// @param paymentClient The payment client that originated the order.
    /// @param recipient The address that will receive the payment.
    /// @param amount The amount of tokens the payment consists of.
    /// @param createdAt Timestamp at which the order was created.
    /// @param dueTo Timestamp at which the full amount should be payed out/claimable.
    event PaymentOrderProcessed(
        address indexed paymentClient,
        address indexed recipient,
        uint amount,
        uint createdAt,
        uint dueTo
    );

    /// @notice Emitted when an amount of ERC20 tokens gets sent out of the contract.
    /// @param recipient The address that will receive the payment.
    /// @param amount The amount of tokens the payment consists of.
    event TokensReleased(
        address indexed recipient, address indexed token, uint amount
    );

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Processes all payments from an {IERC20PaymentClient} instance.
    /// @dev It's up to the the implementation to keep up with what has been
    ///      paid out or not.
    /// @param client The {IERC20PaymentClient} instance to process its to payments.
    function processPayments(IERC20PaymentClient client) external;

    /// @notice Cancels all unfinished payments from an {IERC20PaymentClient} instance.
    /// @dev It's up to the the implementation to keep up with what has been
    ///      paid out or not.
    /// @param client The {IERC20PaymentClient} instance to process its to payments.
    function cancelRunningPayments(IERC20PaymentClient client) external;

    /// @notice Returns the IERC20 token the payment processor can process.
    function token() external view returns (IERC20);
}
