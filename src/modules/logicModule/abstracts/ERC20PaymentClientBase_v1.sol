// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Internal Dependencies
import {Module_v1} from "src/modules/base/Module_v1.sol";
import {
    IERC20PaymentClientBase_v1,
    IPaymentProcessor_v1
} from "@lm/interfaces/IERC20PaymentClientBase_v1.sol";

import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";

/**
 * @title   ERC20 Payment Client Base
 *
 * @notice  Enables modules within the Inverter Network to create and manage payment orders
 *          that can be processed by authorized payment processors, ensuring efficient
 *          and secure transactions.
 *
 * @dev     Utilizes {SafeERC20} for token operations and integrates with {IPaymentProcessor_v1}
 *          to handle token payments. This abstract contract must be extended by modules
 *          that manage ERC20 payment orders, supporting complex payment scenarios.
 *
 * @author  Inverter Network
 */
abstract contract ERC20PaymentClientBase_v1 is
    IERC20PaymentClientBase_v1,
    Module_v1
{
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(Module_v1)
        returns (bool)
    {
        return interfaceId == type(IERC20PaymentClientBase_v1).interfaceId
            || super.supportsInterface(interfaceId);
    }

    using SafeERC20 for IERC20;
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

    modifier validPaymentOrder(PaymentOrder memory order) {
        _ensureValidPaymentOrder(order);
        _;
    }

    //--------------------------------------------------------------------------
    // State

    /// @dev The list of oustanding orders.
    /// @dev Emptied whenever orders are collected.
    PaymentOrder[] internal _orders;

    /// @dev The current cumulative amount of tokens outstanding.
    uint internal _outstandingTokenAmount;

    // Storage gap for future upgrades
    uint[50] private __gap;

    //--------------------------------------------------------------------------
    // Internal Mutating Functions

    /// @dev Adds a new {PaymentOrder} to the list of outstanding orders.
    /// @param order The new payment order.
    function _addPaymentOrder(PaymentOrder memory order)
        internal
        virtual
        validPaymentOrder(order)
    {
        // Add order's token amount to current outstanding amount.
        _outstandingTokenAmount += order.amount;

        // Add new order to list of oustanding orders.
        _orders.push(order);

        emit PaymentOrderAdded(order.recipient, order.amount);
    }

    /// @dev Adds a set of new {PaymentOrder}s to the list of outstanding
    ///      orders.
    /// @param orders The list of new Payment Orders.
    function _addPaymentOrders(PaymentOrder[] memory orders) internal virtual {
        uint orderAmount = orders.length;

        PaymentOrder memory currentOrder;

        uint totalTokenAmount;
        for (uint i; i < orderAmount; ++i) {
            currentOrder = orders[i];
            _ensureValidPaymentOrder(currentOrder);

            // Add order's amount to total amount of new orders.
            totalTokenAmount += currentOrder.amount;

            // Add new order to list of oustanding orders.
            _orders.push(currentOrder);

            emit PaymentOrderAdded(currentOrder.recipient, currentOrder.amount);
        }

        // Add total orders' amount to current outstanding amount.
        _outstandingTokenAmount += totalTokenAmount;
    }

    //--------------------------------------------------------------------------
    // IERC20PaymentClientBase_v1 Functions

    /// @inheritdoc IERC20PaymentClientBase_v1
    function paymentOrders()
        external
        view
        virtual
        returns (PaymentOrder[] memory)
    {
        return _orders;
    }

    /// @inheritdoc IERC20PaymentClientBase_v1
    function outstandingTokenAmount() external view virtual returns (uint) {
        return _outstandingTokenAmount;
    }

    /// @inheritdoc IERC20PaymentClientBase_v1
    function collectPaymentOrders()
        external
        virtual
        returns (PaymentOrder[] memory, uint)
    {
        // Ensure caller is authorized to act as payment processor.
        if (!_isAuthorizedPaymentProcessor(IPaymentProcessor_v1(_msgSender())))
        {
            revert Module__ERC20PaymentClientBase__CallerNotAuthorized();
        }

        // Create a copy of all orders to return.
        uint totalAmount;
        uint ordersLength = _orders.length;
        PaymentOrder[] memory copy = new PaymentOrder[](ordersLength);
        for (uint i; i < ordersLength; ++i) {
            copy[i] = _orders[i];
            totalAmount += copy[i].amount;
        }

        // Delete all outstanding orders.
        delete _orders;

        // Ensure payment processor is able to fetch the tokens from address(this).
        _ensureTokenAllowance(IPaymentProcessor_v1(_msgSender()), totalAmount);

        //Ensure that the Client will have sufficient funds.
        // Note that while we also control when adding a payment order, more complex payment systems with f.ex. deferred payments may not guarantee that having enough balance available when adding the order means it'll have enough balance when the order is processed.
        _ensureTokenBalance(_outstandingTokenAmount);

        // Return copy of orders and orders' total token amount to payment
        // processor.
        return (copy, _outstandingTokenAmount);
    }

    /// @inheritdoc IERC20PaymentClientBase_v1
    function amountPaid(uint amount) external virtual {
        // Ensure caller is authorized to act as payment processor.
        if (!_isAuthorizedPaymentProcessor(IPaymentProcessor_v1(_msgSender())))
        {
            revert Module__ERC20PaymentClientBase__CallerNotAuthorized();
        }

        // reduce outstanding token amount by the given amount
        _outstandingTokenAmount -= amount;
    }

    //--------------------------------------------------------------------------
    // Private Functions

    function _ensureValidRecipient(address recipient) private view {
        if (recipient == address(0) || recipient == address(this)) {
            revert Module__ERC20PaymentClientBase__InvalidRecipient();
        }
    }

    function _ensureValidAmount(uint amount) private pure {
        if (amount == 0) {
            revert Module__ERC20PaymentClientBase__InvalidAmount();
        }
    }

    function _ensureValidPaymentOrder(PaymentOrder memory order) private view {
        if (order.amount == 0) {
            revert Module__ERC20PaymentClientBase__InvalidAmount();
        }
        if (order.recipient == address(0) || order.recipient == address(this)) {
            revert Module__ERC20PaymentClientBase__InvalidRecipient();
        }
    }

    //--------------------------------------------------------------------------
    // {ERC20PaymentClientBase_v1} Function Implementations

    /// @dev Ensures `amount` of payment tokens exist in address(this).
    function _ensureTokenBalance(uint amount) internal virtual {
        uint currentFunds = __Module_orchestrator.fundingManager().token()
            .balanceOf(address(this));

        // If current funds are not enough
        if (currentFunds < amount) {
            // Trigger callback from orchestrator to transfer tokens
            // to address(this).
            bool ok;
            (ok, /*returnData*/ ) = __Module_orchestrator.executeTxFromModule(
                address(__Module_orchestrator.fundingManager()),
                abi.encodeCall(
                    IFundingManager_v1.transferOrchestratorToken,
                    (address(this), amount - currentFunds)
                )
            );

            if (!ok) {
                revert Module__ERC20PaymentClientBase__TokenTransferFailed();
            }
        }
    }

    /// @dev Ensures `amount` of token allowance for payment processor(s).
    function _ensureTokenAllowance(IPaymentProcessor_v1 spender, uint amount)
        internal
        virtual
    {
        __Module_orchestrator.fundingManager().token().safeIncreaseAllowance(
            address(spender), amount
        );
    }

    /// @dev Returns whether address `who` is an authorized payment processor.
    function _isAuthorizedPaymentProcessor(IPaymentProcessor_v1 who)
        internal
        view
        virtual
        returns (bool)
    {
        return __Module_orchestrator.paymentProcessor() == who;
    }
}
