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

    /// @notice invalid caller.
    error Module__PaymentProcessor__OnlyCallableByModule();

    /// @notice a client can only execute on its own orders.
    error Module__PaymentProcessor__CannotCallOnOtherClientsOrders();

    /// @notice the paymentReceiver is not owed any money by the paymentClient.
    error Module__PaymentProcessor__NothingToClaim(
        address paymentClient, address paymentReceiver
    );

    //--------------------------------------------------------------------------
    // Events

    /// @notice Emitted when a payment gets processed for execution.
    /// @param  paymentClient The payment client that originated the order.
    /// @param  recipient The address that will receive the payment.
    /// @param  paymentToken The address of the token that will be used for the payment.
    /// @param  amount The amount of tokens the payment consists of.
    event PaymentOrderProcessed(
        address indexed paymentClient,
        address indexed recipient,
        address indexed paymentToken,
        uint amount
    );

    /// @notice Emitted when an amount of ERC20 tokens gets sent out of the contract.
    /// @param  recipient The address that will receive the payment.
    /// @param  token The token address in which the payment should have happened.
    /// @param  amount The amount of tokens the payment consists of.
    event TokensReleased(
        address indexed recipient, address indexed token, uint amount
    );

    /// @notice Emitted when a payment was unclaimable due to a token error.
    /// @param  paymentClient The payment client that originated the order.
    /// @param  paymentClient The token address in which the payment should have happened.
    /// @param  recipient The address that should have received the payment.
    /// @param  amount The amount of tokens that were unclaimable.
    event UnclaimableAmountAdded(
        address indexed paymentClient,
        address indexed token,
        address indexed recipient,
        uint amount
    );

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Processes all payments from an {IERC20PaymentClientBase_v1} instance. Please note:
    ///         this function does not support callbacks on transfer of tokens.
    /// @dev    It's up to the the implementation to keep up with what has been
    ///         paid out or not.
    /// @dev	Currently callback functions on token transfers are not supported and thus not checked.
    ///         This could lead to a failed transaction which could influence the batched processing of
    ///         payments.
    /// @param  client The {IERC20PaymentClientBase_v1} instance to process its to payments.
    function processPayments(IERC20PaymentClientBase_v1 client) external;

    /// @notice Cancels all unfinished payments from an {IERC20PaymentClientBase_v1} instance.
    /// @dev	It's up to the the implementation to keep up with what has been
    ///         paid out or not.
    /// @param  client The {IERC20PaymentClientBase_v1} instance to process its to payments.
    function cancelRunningPayments(IERC20PaymentClientBase_v1 client)
        external;

    /// @notice Getter for the amount of tokens that could not be claimed.
    /// @param  client address of the payment client.
    /// @param  token address of the payment token.
    /// @param  paymentReceiver PaymentReceiver's address.
    /// @return amount Amount of tokens that could not be claimed.
    function unclaimable(address client, address token, address paymentReceiver)
        external
        view
        returns (uint amount);

    /// @notice claim every unclaimable amount that the paymentClient owes to the _msgSender and send it to a
    ///         specified receiver.
    /// @dev	This function should be callable if the _msgSender has unclaimedAmounts.
    /// @param  client The IERC20PaymentClientBase_v1 instance address that processes all claims from _msgSender.
    /// @param  token address of the payment token.
    /// @param  receiver The address that will receive the previously unclaimable amount.
    function claimPreviouslyUnclaimable(
        address client,
        address token,
        address receiver
    ) external;

    /// @notice Function that checks if the given PaymentOrder was valid.
    /// @param  order The IERC20PaymentClientBase_v1 Order that needs to be checked.
    /// @return valid Bool if the Payment Order is valid.
    function validPaymentOrder(
        IERC20PaymentClientBase_v1.PaymentOrder memory order
    ) external returns (bool);
}
