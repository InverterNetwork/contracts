// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IOrchestrator} from "src/orchestrator/IOrchestrator.sol";

// SuT
import {
    ERC20PaymentClient,
    IERC20PaymentClient
} from "src/modules/logicModule/paymentClient/ERC20PaymentClient.sol";

// Internal Interfaces
import {IPaymentProcessor} from
    "src/modules/paymentProcessor/IPaymentProcessor.sol";

// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

contract ERC20PaymentClientMock is ERC20PaymentClient {
    ERC20Mock token;

    uint public amountPaidCounter;
    mapping(address => bool) authorized;

    //--------------------------------------------------------------------------
    // Mock Functions

    function setIsAuthorized(address who, bool to) external {
        authorized[who] = to;
    }

    function setOrchestrator(IOrchestrator orchestrator) external {
        __Module_orchestrator = orchestrator;
    }

    function setToken(ERC20Mock token_) external {
        token = token_;
    }

    //--------------------------------------------------------------------------
    // IERC20PaymentClient Wrapper Functions

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
    // IERC20PaymentClient Overriden Functions

    function _ensureTokenBalance(uint amount)
        internal
        override(ERC20PaymentClient)
    {
        if (token.balanceOf(address(this)) >= amount) {
            return;
        } else {
            uint amtToMint = amount - token.balanceOf(address(this));
            token.mint(address(this), amtToMint);
        }
    }

    function _ensureTokenAllowance(IPaymentProcessor spender, uint amount)
        internal
        override(ERC20PaymentClient)
    {
        uint currentAllowance = token.allowance(_msgSender(), address(spender));
        token.approve(address(spender), amount + currentAllowance);
    }

    function _isAuthorizedPaymentProcessor(IPaymentProcessor)
        internal
        view
        override(ERC20PaymentClient)
        returns (bool)
    {
        return authorized[_msgSender()];
    }

    function amountPaid(uint amount) external override(ERC20PaymentClient) {
        amountPaidCounter += amount;
        _outstandingTokenAmount -= amount;
    }
}
