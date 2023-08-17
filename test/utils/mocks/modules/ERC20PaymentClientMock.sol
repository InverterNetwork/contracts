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

    mapping(address => bool) authorized;

    constructor(ERC20Mock token_) {
        token = token_;
    }

    //--------------------------------------------------------------------------
    // Mock Functions

    function setIsAuthorized(address who, bool to) external {
        authorized[who] = to;
    }

    function setOrchestrator(IOrchestrator orchestrator) external {
        __Module_orchestrator = orchestrator;
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

        // Ensure our token balance is sufficient.
        // Note that function is implemented in downstream contract.
        _ensureTokenBalance(_outstandingTokenAmount);

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
        token.approve(address(spender), amount);
    }

    function _isAuthorizedPaymentProcessor(IPaymentProcessor)
        internal
        view
        override(ERC20PaymentClient)
        returns (bool)
    {
        return authorized[_msgSender()];
    }

    //for testing the original functionality of the internal functions I created this placeholders

    function originalEnsureTokenBalance(uint amount) external {
        return super._ensureTokenBalance(amount);
    }

    function originalEnsureTokenAllowance(
        IPaymentProcessor spender,
        uint amount
    ) external {
        return super._ensureTokenAllowance(spender, amount);
    }

    function originalIsAuthorizedPaymentProcessor(IPaymentProcessor processor)
        external
        view
        returns (bool)
    {
        return super._isAuthorizedPaymentProcessor(processor);
    }
}
