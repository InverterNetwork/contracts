// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

// External Dependencies
import {ContextUpgradeable} from "@oz-up/utils/ContextUpgradeable.sol";

// Internal Dependencies
import {
    IPaymentClient,
    IPaymentProcessor
} from "src/modules/base/mixins/IPaymentClient.sol";

/**
 * @title PaymentClient
 *
 * @dev The PaymentClient mixin enables modules to create payment orders that
 *      are processable by a proposal's {IPaymentProcessor} module.
 *
 * @author Inverter Network
 */
abstract contract PaymentClient is IPaymentClient, ContextUpgradeable {
    //--------------------------------------------------------------------------
    // Modifiers

    modifier validRecipient(address recipient) {
        _ensureValidRecipient(recipient);
        _;
    }

    modifier validAmount(uint amount) {
        _ensureValidAmount(amount);
        _;
    }

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
        validRecipient(recipient)
        validAmount(amount)
    {
        // Add order's token amount to current outstanding amount.
        _outstandingTokenAmount += amount;

        // Add new order to list of oustanding orders.
        _orders.push(PaymentOrder(recipient, amount, block.timestamp, dueTo));

        // Ensure our token balance is sufficient.
        // Note that function is implemented in downstream contract.
        _ensureTokenBalance(_outstandingTokenAmount);

        emit PaymentOrderAdded(recipient, amount);
    }

    /// @dev Adds a set of new {PaymentOrder}s to the list of outstanding
    ///      orders.
    /// @param recipients The list of recipients of the payments.
    /// @param amounts The amounts to be paid out.
    /// @param dueTos Timestamps at which the payments SHOULD be fulfilled.
    function _addPaymentOrders(
        address[] memory recipients,
        uint[] memory amounts,
        uint[] memory dueTos
    ) internal virtual {
        uint orderAmount = recipients.length;

        // Revert if arrays' length mismatch.
        if (orderAmount != amounts.length || orderAmount != dueTos.length) {
            revert Module__PaymentClient__ArrayLengthMismatch();
        }

        uint totalTokenAmount;
        for (uint i; i < orderAmount; ++i) {
            _ensureValidRecipient(recipients[i]);
            _ensureValidAmount(amounts[i]);

            // Add order's amount to total amount of new orders.
            totalTokenAmount += amounts[i];

            // Add new order to list of oustanding orders.
            _orders.push(
                PaymentOrder(
                    recipients[i], amounts[i], block.timestamp, dueTos[i]
                )
            );

            emit PaymentOrderAdded(recipients[i], amounts[i]);
        }

        // Add total orders' amount to current outstanding amount.
        _outstandingTokenAmount += totalTokenAmount;

        // Ensure our token balance is sufficient.
        // Note that functions is implemented in downstream contract.
        _ensureTokenBalance(_outstandingTokenAmount);
    }

    /// @dev Adds a set of new identical {PaymentOrder}s to the list of
    ///      outstanding orders.
    /// @param recipients The list of recipients of the payments.
    /// @param amount The amount to be paid out in each order.
    /// @param dueTo Timestamp at which the payments SHOULD be fulfilled.
    function _addIdenticalPaymentOrders(
        address[] memory recipients,
        uint amount,
        uint dueTo
    ) internal virtual validAmount(amount) {
        uint orderAmount = recipients.length;

        for (uint i; i < orderAmount; ++i) {
            _ensureValidRecipient(recipients[i]);

            // Add new order to list of oustanding orders.
            _orders.push(
                PaymentOrder(recipients[i], amount, block.timestamp, dueTo)
            );

            emit PaymentOrderAdded(recipients[i], amount);
        }

        // Add total orders' amount to current outstanding amount.
        _outstandingTokenAmount += amount * orderAmount;

        // Ensure our token balance is sufficient.
        // Note that functions is implemented in downstream contract.
        _ensureTokenBalance(_outstandingTokenAmount);
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
        if (!_isAuthorizedPaymentProcessor(IPaymentProcessor(_msgSender()))) {
            revert Module__PaymentClient__CallerNotAuthorized();
        }

        // Ensure payment processor is able to fetch the tokens from
        // address(this).
        // Note that function is implemented in downstream contract.
        _ensureTokenAllowance(
            IPaymentProcessor(_msgSender()), _outstandingTokenAmount
        );

        // Create a copy of all orders to return.
        uint ordersLength = _orders.length;
        PaymentOrder[] memory copy = new PaymentOrder[](ordersLength);
        for (uint i; i < ordersLength; ++i) {
            copy[i] = _orders[i];
        }

        // Delete all outstanding orders.
        delete _orders;

        // Cache outstanding token amount.
        uint outstandingTokenAmountCache = _outstandingTokenAmount;

        // Set outstanding token amount to zero.
        _outstandingTokenAmount = 0;

        //Ensure that the Client will have sufficient funds.
        // Note that function is implemented in downstream contract.
        // Note that while we also control when adding a payment order, more complex payment systems with f.ex. deferred payments may not guarantee that having enough balance available when adding the order means it'll have enough balance when the order is processed.
        _ensureTokenBalance(outstandingTokenAmountCache);

        // Return copy of orders and orders' total token amount to payment
        // processor.
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

    /// @inheritdoc IPaymentClient
    function outstandingTokenAmount() external view virtual returns (uint) {
        return _outstandingTokenAmount;
    }

    //--------------------------------------------------------------------------
    // Private Functions

    function _ensureValidRecipient(address recipient) private view {
        if (recipient == address(0) || recipient == address(this)) {
            revert Module__PaymentClient__InvalidRecipient();
        }
    }

    function _ensureValidAmount(uint amount) private pure {
        if (amount == 0) {
            revert Module__PaymentClient__InvalidAmount();
        }
    }
}
