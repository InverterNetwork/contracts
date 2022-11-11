// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

// Internal Dependencies
import {
    IPaymentClient,
    IPaymentProcessor
} from "src/modules/mixins/IPaymentClient.sol";

abstract contract PaymentClient is IPaymentClient {
    //--------------------------------------------------------------------------
    // State

    /// @dev The list of oustanding orders.
    /// @dev Emptied whenever orders are collected.
    PaymentOrder[] internal _orders;

    /// @dev The current cumulative amount of tokens outstanding.
    uint internal _outstandingTokenAmount;

    //--------------------------------------------------------------------------
    // Internal Functions Implemented in Downstream Contract

    /// @dev Ensures `amount` of payment tokens exist in address(this).
    /// @dev MUST be overriden by downstream contract.
    function _ensureTokenBalance(uint amount) internal virtual;

    /// @dev Ensures `amount` of token allowance for payment processor(s).
    /// @dev MUST be overriden by downstream contract.
    function _ensureTokenAllowance(IPaymentProcessor spender, uint amount)
        internal
        virtual;

    /// @dev Returns whether address `who` is an authorized payment processor.
    /// @dev MUST be overriden by downstream contract.
    function _isAuthorizedPaymentProcessor(IPaymentProcessor who)
        internal
        view
        virtual
        returns (bool);

    //--------------------------------------------------------------------------
    // Internal Mutating Functions

    /// @dev Adds a new {PaymentOrder} to the list of outstanding orders.
    /// @param recipient The recipient of the payment.
    /// @param amount The amount to be paid out.
    /// @param dueTo Timestamp at which the payment SHOULD be fulfilled.
    function _addPaymentOrder(address recipient, uint amount, uint dueTo)
        internal
        virtual
    {
        // Create new PaymentOrder instance.
        PaymentOrder memory order =
            PaymentOrder(recipient, amount, block.timestamp, dueTo);

        // Add order's token amount to current outstanding amount.
        _outstandingTokenAmount += amount;

        // Ensure our token balance is sufficient.
        // Note that function is implemented in downstream contract.
        _ensureTokenBalance(_outstandingTokenAmount);

        // Add order to list of oustanding orders.
        _orders.push(order);

        emit PaymentAdded(recipient, amount);
    }

    //--------------------------------------------------------------------------
    // IPaymentClient Functions

    /// @inheritdoc IPaymentClient
    function collectPaymentOrders()
        external
        virtual
        returns (PaymentOrder[] memory, uint)
    {
        // Ensure caller is authorized to act as payment processor.
        // Note that function is implemented in downstream contract.
        if (!_isAuthorizedPaymentProcessor(IPaymentProcessor(msg.sender))) {
            revert Module__PaymentClient__CallerNotAuthorized();
        }

        // Ensure payment processor is able to fetch the tokens from
        // address(this).
        // Note that function is implemented in downstream contract.
        _ensureTokenAllowance(
            IPaymentProcessor(msg.sender), _outstandingTokenAmount
        );

        // Create a copy of all orders to return.
        PaymentOrder[] memory copy = new PaymentOrder[](_orders.length);
        for (uint i; i < _orders.length; i++) {
            copy[i] = _orders[i];
        }

        // Delete all outstanding orders.
        delete _orders;

        // Cache outstanding token amount.
        uint outstandingTokenAmountCache = _outstandingTokenAmount;

        // Set outstanding token amount to zero.
        _outstandingTokenAmount = 0;

        // Return copy of orders to payment processor.
        return (copy, outstandingTokenAmountCache);
    }

    /// @inheritdoc IPaymentClient
    function paymentOrders()
        external
        view
        virtual
        returns (PaymentOrder[] memory)
    {
        return _orders;
    }
}
