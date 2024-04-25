// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";

// SuT
import {
    ERC20PaymentClientBase_v1,
    IERC20PaymentClientBase_v1
} from "@lm/abstracts/ERC20PaymentClientBase_v1.sol";

// Internal Interfaces
import {IPaymentProcessor_v1} from
    "src/modules/paymentProcessor/IPaymentProcessor_v1.sol";

// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

contract ERC20PaymentClientBaseV1Mock is ERC20PaymentClientBase_v1 {
    ERC20Mock token;

    uint public amountPaidCounter;
    mapping(address => bool) authorized;

    //--------------------------------------------------------------------------
    // Mock Functions

    function setIsAuthorized(address who, bool to) external {
        authorized[who] = to;
    }

    function setOrchestrator(IOrchestrator_v1 orchestrator) external {
        __Module_orchestrator = orchestrator;
    }

    function setToken(ERC20Mock token_) external {
        token = token_;
    }

    //--------------------------------------------------------------------------
    // IERC20PaymentClientBase_v1 Wrapper Functions

    function addPaymentOrder(PaymentOrder memory order) external {
        _addPaymentOrder(order);
    }

    // add a payment order without checking the arguments
    function addPaymentOrderUnchecked(PaymentOrder memory order) external {
        // Add order's token amount to current outstanding amount.
        _outstandingTokenAmount += order.amount;

        // Add new order to list of oustanding orders.
        _orders.push(order);

        emit PaymentOrderAdded(order.recipient, order.amount);
    }

    function addPaymentOrders(PaymentOrder[] memory orders) external {
        _addPaymentOrders(orders);
    }

    //--------------------------------------------------------------------------
    // IERC20PaymentClientBase_v1 Overriden Functions

    function _ensureTokenBalance(uint amount)
        internal
        override(ERC20PaymentClientBase_v1)
    {
        if (token.balanceOf(address(this)) >= amount) {
            return;
        } else {
            uint amtToMint = amount - token.balanceOf(address(this));
            token.mint(address(this), amtToMint);
        }
    }

    function _ensureTokenAllowance(IPaymentProcessor_v1 spender, uint amount)
        internal
        override(ERC20PaymentClientBase_v1)
    {
        uint currentAllowance = token.allowance(_msgSender(), address(spender));
        token.approve(address(spender), amount + currentAllowance);
    }

    function _isAuthorizedPaymentProcessor(IPaymentProcessor_v1)
        internal
        view
        override(ERC20PaymentClientBase_v1)
        returns (bool)
    {
        return authorized[_msgSender()];
    }

    function amountPaid(uint amount)
        external
        override(ERC20PaymentClientBase_v1)
    {
        amountPaidCounter += amount;
        _outstandingTokenAmount -= amount;
    }
}
