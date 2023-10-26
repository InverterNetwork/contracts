// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Internal Dependencies
import {Module, ContextUpgradeable} from "src/modules/base/Module.sol";
import {
    IERC20PaymentClient,
    IPaymentProcessor
} from "src/modules/logicModule/paymentClient/IERC20PaymentClient.sol";

import {IFundingManager} from "src/modules/fundingManager/IFundingManager.sol";

/**
 * @title ERC20PaymentClient
 *
 * @dev The ERC20PaymentClient mixin enables modules to create payment orders that
 *      are processable by a orchestrator's {IPaymentProcessor} module.
 *
 * @author Inverter Network
 */
abstract contract ERC20PaymentClient is IERC20PaymentClient, Module {
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
    // IERC20PaymentClient Functions

    /// @inheritdoc IERC20PaymentClient
    function collectPaymentOrders()
        external
        virtual
        returns (PaymentOrder[] memory, uint)
    {
        // Ensure caller is authorized to act as payment processor.
        if (!_isAuthorizedPaymentProcessor(IPaymentProcessor(_msgSender()))) {
            revert Module__ERC20PaymentClient__CallerNotAuthorized();
        }

        // Ensure payment processor is able to fetch the tokens from
        // address(this).
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
        // Note that while we also control when adding a payment order, more complex payment systems with f.ex. deferred payments may not guarantee that having enough balance available when adding the order means it'll have enough balance when the order is processed.
        _ensureTokenBalance(outstandingTokenAmountCache);

        // Return copy of orders and orders' total token amount to payment
        // processor.
        return (copy, outstandingTokenAmountCache);
    }

    /// @inheritdoc IERC20PaymentClient
    function paymentOrders()
        external
        view
        virtual
        returns (PaymentOrder[] memory)
    {
        return _orders;
    }

    /// @inheritdoc IERC20PaymentClient
    function outstandingTokenAmount() external view virtual returns (uint) {
        return _outstandingTokenAmount;
    }

    //--------------------------------------------------------------------------
    // Private Functions

    function _ensureValidRecipient(address recipient) private view {
        if (recipient == address(0) || recipient == address(this)) {
            revert Module__ERC20PaymentClient__InvalidRecipient();
        }
    }

    function _ensureValidAmount(uint amount) private pure {
        if (amount == 0) revert Module__ERC20PaymentClient__InvalidAmount();
    }

    function _ensureValidPaymentOrder(PaymentOrder memory order) private view {
        if (order.amount == 0) {
            revert Module__ERC20PaymentClient__InvalidAmount();
        }
        if (order.recipient == address(0) || order.recipient == address(this)) {
            revert Module__ERC20PaymentClient__InvalidRecipient();
        }
    }

    //--------------------------------------------------------------------------
    // {ERC20PaymentClient} Function Implementations

    /// @dev Ensures `amount` of payment tokens exist in address(this).
    function _ensureTokenBalance(uint amount) internal virtual {
        // Trigger callback from orchestrator to transfer tokens
        // to address(this).
        bool ok;
        (ok, /*returnData*/ ) = __Module_orchestrator.executeTxFromModule(
            address(__Module_orchestrator.fundingManager()),
            abi.encodeCall(
                IFundingManager.transferOrchestratorToken,
                (address(this), amount)
            )
        );

        if (!ok) {
            revert Module__ERC20PaymentClient__TokenTransferFailed();
        }
    }

    /// @dev Ensures `amount` of token allowance for payment processor(s).
    function _ensureTokenAllowance(IPaymentProcessor spender, uint amount)
        internal
        virtual
    {
        IERC20 token = __Module_orchestrator.fundingManager().token();
        uint allowance = token.allowance(address(this), address(spender));

        if (allowance < amount) {
            token.safeIncreaseAllowance(address(spender), amount - allowance);
        }
    }

    /// @dev Returns whether address `who` is an authorized payment processor.
    function _isAuthorizedPaymentProcessor(IPaymentProcessor who)
        internal
        view
        virtual
        returns (bool)
    {
        return __Module_orchestrator.paymentProcessor() == who;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(Module)
        returns (bool)
    {
        bytes4 interfaceId_IERC20PaymentClient =
            type(IERC20PaymentClient).interfaceId;
        return interfaceId == interfaceId_IERC20PaymentClient
            || super.supportsInterface(interfaceId);
    }
}
