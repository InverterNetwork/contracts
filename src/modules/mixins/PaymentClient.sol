// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

// External Dependencies
import {ContextUpgradeable} from "@oz-up/utils/ContextUpgradeable.sol";

// Internal Dependencies
import {
    IPaymentClient,
    IPaymentProcessor
} from "src/modules/mixins/IPaymentClient.sol";

abstract contract PaymentClient is IPaymentClient, ContextUpgradeable {
    //--------------------------------------------------------------------------
    // Modifiers

    modifier validRecipient(address recipient) {
        if (!_isValidRecipient(recipient)) {
            revert Module__PaymentClient__InvalidRecipient();
        }
        _;
    }

    modifier validAmount(uint amount) {
        if (!_isValidAmount(amount)) {
            revert Module__PaymentClient__InvalidAmount();
        }
        _;
    }

    modifier validDueTo(uint dueTo) {
        if (!_isValidDueTo(dueTo)) {
            revert Module__PaymentClient__InvalidDueTo();
        }
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
        validDueTo(dueTo)
    {
        // Add order's token amount to current outstanding amount.
        _outstandingTokenAmount += amount;

        // Ensure our token balance is sufficient.
        // Note that function is implemented in downstream contract.
        _ensureTokenBalance(_outstandingTokenAmount);

        // Add new order to list of oustanding orders.
        _orders.push(PaymentOrder(recipient, amount, block.timestamp, dueTo));

        emit PaymentAdded(recipient, amount);
    }

    function _addPaymentOrders(
        address[] memory recipients,
        uint[] memory amounts,
        uint[] memory dueTos
    ) internal virtual {
        uint len = recipients.length;

        // Revert if arrays' length mismatch.
        if (len != amounts.length || len != dueTos.length) {
            revert Module__PaymentClient__ArrayLengthMismatch();
        }

        uint totalOrdersAmount;
        for (uint i; i < len; i++) {
            if (!_isValidRecipient(recipients[i])) {
                revert Module__PaymentClient__InvalidRecipient();
            }
            if (!_isValidAmount(amounts[i])) {
                revert Module__PaymentClient__InvalidAmount();
            }
            if (!_isValidDueTo(dueTos[i])) {
                revert Module__PaymentClient__InvalidDueTo();
            }

            // Add order's amount to total amount of new orders.
            totalOrdersAmount += amounts[i];

            // Add new order to list of oustanding orders.
            _orders.push(
                PaymentOrder(
                    recipients[i], amounts[i], block.timestamp, dueTos[i]
                )
            );

            emit PaymentAdded(recipients[i], amounts[i]);
        }

        // Adds total orders' amount to current outstanding amount.
        _outstandingTokenAmount += totalOrdersAmount;

        // Ensure our token balance is sufficient.
        // Note that functions is implemented in downstream contract.
        _ensureTokenBalance(_outstandingTokenAmount);
    }

    /// @dev Adds a bulk of payment orders with identical amount and dueTo.
    function _addIdenticalPaymentOrders(
        address[] memory recipients,
        uint amount,
        uint dueTo
    ) internal virtual validAmount(amount) validDueTo(dueTo) {
        uint orderAmount = recipients.length;

        for (uint i; i < orderAmount; i++) {
            if (!_isValidRecipient(recipients[i])) {
                revert Module__PaymentClient__InvalidRecipient();
            }

            // Add new order to list of oustanding orders.
            _orders.push(
                PaymentOrder(recipients[i], amount, block.timestamp, dueTo)
            );

            emit PaymentAdded(recipients[i], amount);
        }

        // Adds total orders' amount to current outstanding amount.
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

    function outstandingTokenAmount() external view virtual returns (uint) {
        return _outstandingTokenAmount;
    }

    //--------------------------------------------------------------------------
    // Private Functions

    function _isValidRecipient(address recipient) private view returns (bool) {
        return recipient != address(0) && recipient != address(this);
    }

    function _isValidAmount(uint amount) private pure returns (bool) {
        return amount != 0;
    }

    function _isValidDueTo(uint dueTo) private view returns (bool) {
        return dueTo >= block.timestamp;
    }
}
