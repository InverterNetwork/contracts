// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";

// SuT
import {
    ERC20PaymentClientBase_v2,
    IERC20PaymentClientBase_v2
} from "@lm/abstracts/ERC20PaymentClientBase_v2.sol";

// Internal Interfaces
import {IPaymentProcessor_v1} from
    "src/modules/paymentProcessor/IPaymentProcessor_v1.sol";

// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

contract ERC20PaymentClientBaseV2Mock is ERC20PaymentClientBase_v2 {
    ERC20Mock token;

    mapping(address => uint) public amountPaidCounter;
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
    // IERC20PaymentClientBase_v2 Wrapper Functions

    function exposed_addPaymentOrder(PaymentOrder memory order) external {
        _addPaymentOrder(order);
    }

    // add a payment order without checking the arguments
    function addPaymentOrderUnchecked(PaymentOrder memory order) external {
        // Add order's token amount to current outstanding amount.
        _outstandingTokenAmounts[order.paymentToken] += order.amount;

        // Add new order to list of oustanding orders.
        _orders.push(order);

        emit PaymentOrderAdded(
            order.recipient,
            order.paymentToken,
            order.amount,
            order.originChainId,
            order.targetChainId,
            order.flags,
            order.data
        );
    }

    function exposed_addPaymentOrders(PaymentOrder[] memory orders) external {
        _addPaymentOrders(orders);
    }

    function exposed_addToOutstandingTokenAmounts(address token_, uint amount_)
        external
    {
        _outstandingTokenAmounts[token_] += amount_;
    }

    //--------------------------------------------------------------------------
    // IERC20PaymentClientBase_v2 Overriden Functions

    function _ensureTokenBalance(address token_)
        internal
        override(ERC20PaymentClientBase_v2)
    {
        uint amount = _outstandingTokenAmounts[token_];

        if (ERC20Mock(token_).balanceOf(address(this)) >= amount) {
            return;
        } else {
            uint amtToMint = amount - ERC20Mock(token_).balanceOf(address(this));
            token.mint(address(this), amtToMint);
        }
    }

    function _ensureTokenAllowance(IPaymentProcessor_v1 spender, address _token)
        internal
        override(ERC20PaymentClientBase_v2)
    {
        token.approve(address(spender), _outstandingTokenAmounts[_token]);
    }

    function _isAuthorizedPaymentProcessor(IPaymentProcessor_v1)
        internal
        view
        override(ERC20PaymentClientBase_v2)
        returns (bool)
    {
        return authorized[_msgSender()];
    }

    function amountPaid(address _token, uint amount)
        public
        override(ERC20PaymentClientBase_v2)
    {
        amountPaidCounter[_token] += amount;

        _outstandingTokenAmounts[_token] -= amount;
    }
}
