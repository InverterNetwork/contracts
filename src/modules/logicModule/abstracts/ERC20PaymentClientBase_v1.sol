// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {
    IERC20PaymentClientBase_v1,
    IPaymentProcessor_v1
} from "@lm/interfaces/IERC20PaymentClientBase_v1.sol";
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";

// Internal Dependencies
import {
    Module_v1,
    ERC165,
    ContextUpgradeable
} from "src/modules/base/Module_v1.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

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
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
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
        _outstandingTokenAmounts[order.paymentToken] += order.amount;

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

        for (uint i; i < orderAmount; ++i) {
            _addPaymentOrder(orders[i]);
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
            tokens[i] = tokens_buffer[i];
            amounts[i] = amounts_buffer[i];

            // Ensure payment processor is able to fetch the tokens from address(this).
            _ensureTokenAllowance(IPaymentProcessor_v1(_msgSender()), tokens[i]);

            // Ensure that the Client will have sufficient funds.
            // Note that while we also control when adding a payment order, more complex payment systems with f.ex. deferred payments may not guarantee that having enough balance available when adding the order means it'll have enough balance when the order is processed.
            _ensureTokenBalance(tokens[i]);
        }

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

    function _ensureValidToken(address token) private pure {
        if (token == address(0)) {
            revert Module__ERC20PaymentClientBase__InvalidToken();
        }
    }

    function _ensureValidPaymentOrder(PaymentOrder memory order) private view {
        _ensureValidRecipient(order.recipient);
        _ensureValidToken(order.paymentToken);
        _ensureValidAmount(order.amount);
    }

    //--------------------------------------------------------------------------
    // {ERC20PaymentClientBase_v1} Function Implementations

    /// @dev Ensures `amount` of payment tokens exist in address(this). In case the token being paid out is the FundingManager token, it will trigger a callback to the FundingManager to transfer the tokens to address(this). If the token is not the FundingManager token, it will only check if the local balance is sufficient.
    function _ensureTokenBalance(address token) internal virtual {
        uint amount = _outstandingTokenAmounts[token];
        uint currentFunds = IERC20(token).balanceOf(address(this));

        // If current funds are not enough
        if (currentFunds < amount) {
            // check if the token is the FudningManager token and transfer it
            if (
                token == address(__Module_orchestrator.fundingManager().token())
            ) {
                // Get FundingManager address from orchestrator to transfer tokens
                // to address(this). Fails on ERC20 level if insufficient balance

                __Module_orchestrator.fundingManager().transferOrchestratorToken(
                    address(this), (amount - currentFunds)
                );
            } else {
                revert Module__ERC20PaymentClientBase__InsufficientFunds(token);
            }
        }
    }

    /// @dev Ensures `amount` of token allowance for payment processor(s).
    function _ensureTokenAllowance(IPaymentProcessor_v1 spender, address token)
        internal
        virtual
    {
        IERC20(token).forceApprove(
            address(spender), _outstandingTokenAmounts[token]
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
