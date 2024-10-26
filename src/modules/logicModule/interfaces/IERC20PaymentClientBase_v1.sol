// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Interfaces
import {IPaymentProcessor_v1} from
    "src/modules/paymentProcessor/IPaymentProcessor_v1.sol";

interface IERC20PaymentClientBase_v1 {
    //--------------------------------------------------------------------------
    // Structs

    // TODO: change struct

    /// @notice Struct used to store information about a payment order.
    /// @param  recipient The recipient of the payment.
    /// @param  paymentToken The token in which to pay.
    /// @param  amount The amount of tokens to pay.
    /// @param  originChainId TODO
    /// @param  targetChainId TODO
    /// @param  flags TODO
    /// @param  data TODO
    struct PaymentOrder {
        address recipient;
        address paymentToken; // token should be always on the local chain_id?
        uint amount;
        uint originChainId; // for futerproofing, not sure if it makes sense at this point
        uint targetChainId;
        bytes16 flags; // 0-127
        bytes32[] data; //
    }

    //--------------------------------------------------------------------------
    // Errors

    /// @notice Function is only callable by authorized address.
    error Module__ERC20PaymentClientBase__CallerNotAuthorized();

    /// @notice ERC20 token transfer failed.
    error Module__ERC20PaymentClientBase__TokenTransferFailed();

    /// @notice Insufficient funds to fulfill the payment.
    /// @param  token The token in which the payment was made.
    error Module__ERC20PaymentClientBase__InsufficientFunds(address token);

    /// @notice Given recipient invalid.
    error Module__ERC20PaymentClientBase__InvalidRecipient();

    /// @notice Given token invalid.
    error Module__ERC20PaymentClientBase__InvalidToken();

    /// @notice Given amount invalid.
    error Module__ERC20PaymentClientBase__InvalidAmount();

    /// @notice Given paymentOrder is invalid.
    error Module__ERC20PaymentClientBase__InvalidPaymentOrder();

    /// @notice Given end invalid.
    error Module__ERC20PaymentClientBase__Invalidend();

    /// @notice Given arrays' length mismatch.
    error Module__ERC20PaymentClientBase__ArrayLengthMismatch();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Added a payment order.
    /// @param  recipient The address that will receive the payment.
    /// @param  token The token in which to pay.
    /// @param  amount The amount of tokens the payment consists of.
    event PaymentOrderAdded(
        address indexed recipient, address indexed token, uint amount
    );

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Returns the list of outstanding payment orders.
    /// @return list of payment orders.
    function paymentOrders() external view returns (PaymentOrder[] memory);

    /// @notice Returns the total outstanding token payment amount.
    /// @param  token The token in which to pay.
    /// @return total amount of token to pay.
    function outstandingTokenAmount(address token)
        external
        view
        returns (uint);

    /// @notice Collects outstanding payment orders.
    /// @dev	Marks the orders as completed for the client.
    /// @return list of payment orders.
    /// @return list of token addresses.
    /// @return list of amounts.
    function collectPaymentOrders()
        external
        returns (PaymentOrder[] memory, address[] memory, uint[] memory);

    /// @notice Notifies the PaymentClient, that tokens have been paid out accordingly.
    /// @dev	Payment Client will reduce the total amount of tokens it will stock up by the given amount.
    /// @dev	This has to be called by a paymentProcessor.
    /// @param  token The token in which the payment was made.
    /// @param  amount amount of tokens that have been paid out.
    function amountPaid(address token, uint amount) external;
}
