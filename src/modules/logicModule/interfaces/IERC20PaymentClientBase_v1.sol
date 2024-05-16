// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Interfaces
import {IPaymentProcessor_v1} from
    "src/modules/paymentProcessor/IPaymentProcessor_v1.sol";

interface IERC20PaymentClientBase_v1 {
    struct PaymentOrder {
        /// @dev The recipient of the payment.
        address recipient;
        /// @dev The token in which to pay.
        address paymentToken;
        /// @dev The amount of tokens to pay.
        uint amount;
        /// @dev Timestamp at which the order got created.
        uint createdAt;
        /// @dev Timestamp at which the payment SHOULD be fulfilled.
        uint dueTo;
    }

    //--------------------------------------------------------------------------
    // Errors

    /// @notice Function is only callable by authorized address.
    error Module__ERC20PaymentClientBase__CallerNotAuthorized();

    /// @notice ERC20 token transfer failed.
    error Module__ERC20PaymentClientBase__TokenTransferFailed();

    /// @notice Given recipient invalid.
    error Module__ERC20PaymentClientBase__InvalidRecipient();

    /// @notice Given token invalid.
    error Module__ERC20PaymentClientBase__InvalidToken();

    /// @notice Given amount invalid.
    error Module__ERC20PaymentClientBase__InvalidAmount();

    /// @notice Given dueTo invalid.
    error Module__ERC20PaymentClientBase__InvalidDueTo();

    /// @notice Given arrays' length mismatch.
    error Module__ERC20PaymentClientBase__ArrayLengthMismatch();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Added a payment order.
    /// @param recipient The address that will receive the payment.
    /// @param amount The amount of tokens the payment consists of.
    event PaymentOrderAdded(
        address indexed recipient, address indexed token, uint amount
    );

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Returns the list of outstanding payment orders.
    function paymentOrders() external view returns (PaymentOrder[] memory);

    /// @notice Returns the total outstanding token payment amount.
    function outstandingTokenAmount() external view returns (uint);

    /// @notice Collects outstanding payment orders.
    /// @dev Marks the orders as completed for the client.
    ///      The responsibility to fulfill the orders are now in the caller's
    ///      hand!
    /// @return list of payment orders
    /// @return total amount of token to pay
    function collectPaymentOrders()
        external
        returns (PaymentOrder[] memory, uint);

    /// @notice Notifies the PaymentClient, that tokens have been paid out accordingly
    /// @dev Payment Client will reduce the total amount of tokens it will stock up by the given amount
    /// This has to be called by a paymentProcessor
    /// @param amount amount of tokens that have been paid out
    function amountPaid(uint amount) external;
}
