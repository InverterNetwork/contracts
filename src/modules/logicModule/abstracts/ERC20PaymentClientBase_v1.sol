// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

import "forge-std/console.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Internal Dependencies
import {Module_v1, ContextUpgradeable} from "src/modules/base/Module_v1.sol";
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
    mapping(address => uint) internal _outstandingTokenAmounts;

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
        _outstandingTokenAmounts[order.paymentToken] += order.amount;

        console.log(
            "Outstanding token amount for token %s : %s",
            order.paymentToken,
            _outstandingTokenAmounts[order.paymentToken]
        );

        // Add new order to list of oustanding orders.
        _orders.push(order);

        emit PaymentOrderAdded(
            order.recipient, order.paymentToken, order.amount
        );
    }

    /// @dev Adds a set of new {PaymentOrder}s to the list of outstanding
    ///      orders.
    /// @param orders The list of new Payment Orders.
    function _addPaymentOrders(PaymentOrder[] memory orders) internal virtual {
        uint orderAmount = orders.length;

        PaymentOrder memory currentOrder;

        for (uint i; i < orderAmount; ++i) {
            currentOrder = orders[i];
            _ensureValidPaymentOrder(currentOrder);

            // Add order's amount to total amount of new orders.
            _outstandingTokenAmounts[currentOrder.paymentToken] +=
                currentOrder.amount;

            // Add new order to list of oustanding orders.
            _orders.push(currentOrder);

            emit PaymentOrderAdded(
                currentOrder.recipient,
                currentOrder.paymentToken,
                currentOrder.amount
            );
        }
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
    function outstandingTokenAmount(address _token)
        external
        view
        virtual
        returns (uint)
    {
        return _outstandingTokenAmounts[_token];
    }

    /// @inheritdoc IERC20PaymentClientBase_v1
    function collectPaymentOrders()
        external
        virtual
        returns (PaymentOrder[] memory, address[] memory, uint[] memory)
    {
        // Ensure caller is authorized to act as payment processor.
        if (!_isAuthorizedPaymentProcessor(IPaymentProcessor_v1(_msgSender())))
        {
            revert Module__ERC20PaymentClientBase__CallerNotAuthorized();
        }

        // Create a copy of all orders to return.
        uint ordersLength = _orders.length;
        uint tokenCount;

        address[] memory tokens_buffer = new address[](ordersLength);
        uint[] memory amounts_buffer = new uint[](ordersLength);
        PaymentOrder[] memory copy = new PaymentOrder[](ordersLength);

        for (uint i; i < ordersLength; ++i) {
            copy[i] = _orders[i];
            bool found;
            for (uint j; j < tokenCount; ++j) {
                if (tokens_buffer[j] == copy[i].paymentToken) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                // if the token is not in the list, add it
                tokens_buffer[tokenCount] = copy[i].paymentToken;
                amounts_buffer[tokenCount] =
                    _outstandingTokenAmounts[copy[i].paymentToken];
                tokenCount++;
            }
        }

        // Delete all outstanding orders.
        delete _orders;

        // Prepare the arrays that will be sent back
        address[] memory tokens = new address[](tokenCount);
        uint[] memory amounts = new uint[](tokenCount);

        for (uint i; i < tokenCount; ++i) {
            console.log("CollectPaymentOrder: token %s: %s", i, tokens[i]);
            console.log(
                "CollectPaymentOrder: totalAmount %s: %s", i, amounts[i]
            );

            tokens[i] = tokens_buffer[i];
            amounts[i] = amounts_buffer[i];

            // Ensure payment processor is able to fetch the tokens from address(this).
            _ensureTokenAllowance(
                IPaymentProcessor_v1(_msgSender()), tokens[i], amounts[i]
            );

            //Ensure that the Client will have sufficient funds.
            // Note that while we also control when adding a payment order, more complex payment systems with f.ex. deferred payments may not guarantee that having enough balance available when adding the order means it'll have enough balance when the order is processed.
            _ensureTokenBalance(tokens[i], amounts[i]);
        }

        // Ensure payment processor is able to fetch the tokens from address(this).
        //_ensureTokenAllowance(IPaymentProcessor_v1(_msgSender()), totalAmount);

        // TODO: collect what tokens are in the orders
        // ensure nbalance for all
        // return orders, tokenAddresses and amounts (these two worted correctly )
        // write tests for this

        // New TODO: remove totalAmount, use only outstandngAmount.  do the array thing to check outstanding on all tokens and then refactor all the way down with outstadningAmounts[token]

        //Ensure that the Client will have sufficient funds.
        // Note that while we also control when adding a payment order, more complex payment systems with f.ex. deferred payments may not guarantee that having enough balance available when adding the order means it'll have enough balance when the order is processed.
        //_ensureTokenBalance(_outstandingTokenAmounts);

        // Return copy of orders and orders' total token amount to payment
        // processor.
        return (copy, tokens, amounts);
    }

    /// @inheritdoc IERC20PaymentClientBase_v1
    function amountPaid(address token, uint amount) external virtual {
        // Ensure caller is authorized to act as payment processor.
        if (!_isAuthorizedPaymentProcessor(IPaymentProcessor_v1(_msgSender())))
        {
            revert Module__ERC20PaymentClientBase__CallerNotAuthorized();
        }

        // reduce outstanding token amount by the given amount
        _outstandingTokenAmounts[token] -= amount;

        console.log(
            "Outstanding token amount for token %s : %s",
            token,
            _outstandingTokenAmounts[token]
        );
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
    function _ensureTokenBalance(address token, uint amount) internal virtual {
        uint currentFunds = IERC20(token).balanceOf(address(this));

        // If current funds are not enough
        if (currentFunds < amount) {
            // check if the token is the FudningManager token and transfer it
            if (
                token == address(__Module_orchestrator.fundingManager().token())
            ) {
                // Trigger callback from orchestrator to transfer tokens
                // to address(this).
                bool ok;
                (ok, /*returnData*/ ) = __Module_orchestrator
                    .executeTxFromModule(
                    address(__Module_orchestrator.fundingManager()),
                    abi.encodeCall(
                        IFundingManager_v1.transferOrchestratorToken,
                        (address(this), amount - currentFunds)
                    )
                );

                if (!ok) {
                    revert Module__ERC20PaymentClientBase__TokenTransferFailed();
                }
            } else {
                revert Module__ERC20PaymentClientBase__InsufficientFunds(token);
            }
        }
    }

    /// @dev Ensures `amount` of token allowance for payment processor(s).
    function _ensureTokenAllowance(
        IPaymentProcessor_v1 spender,
        address token,
        uint amount
    ) internal virtual {
        IERC20(token).safeIncreaseAllowance(address(spender), amount);
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
