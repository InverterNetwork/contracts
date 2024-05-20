// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";

import {
    Module_v1,
    IModule_v1,
    IOrchestrator_v1
} from "src/modules/base/Module_v1.sol";

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

contract ERC20PaymentClientBaseV1AccessMock is ERC20PaymentClientBase_v1 {
    mapping(address => bool) authorized;

    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata,
        bytes memory //configData
    ) external override(Module_v1) initializer {
        __Module_init(orchestrator_, metadata);
    }

    //--------------------------------------------------------------------------
    // IERC20PaymentClientBase_v1 Wrapper Functions

    function addPaymentOrder(PaymentOrder memory order) external {
        _addPaymentOrder(order);
    }

    // add a payment order without checking the arguments
    function addPaymentOrderUnchecked(PaymentOrder memory order) external {
        // Add order's token amount to current outstanding amount.
        _outstandingTokenAmounts[order.paymentToken] += order.amount;

        // Add new order to list of oustanding orders.
        _orders.push(order);

        emit PaymentOrderAdded(
            order.recipient, order.paymentToken, order.amount
        );
    }

    function addPaymentOrders(PaymentOrder[] memory orders) external {
        _addPaymentOrders(orders);
    }

    //for testing the original functionality of the internal functions I created these placeholders

    function originalEnsureTokenBalance(address token, uint amount) external {
        return _ensureTokenBalance(token, amount);
    }

    function originalEnsureTokenAllowance(
        IPaymentProcessor_v1 spender,
        address token,
        uint amount
    ) external {
        return _ensureTokenAllowance(spender, token, amount);
    }

    function originalIsAuthorizedPaymentProcessor(
        IPaymentProcessor_v1 processor
    ) external view returns (bool) {
        return _isAuthorizedPaymentProcessor(processor);
    }

    function set_outstandingTokenAmount(address token, uint amount) external {
        _outstandingTokenAmounts[token] = amount;
    }
}
