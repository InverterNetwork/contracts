// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IOrchestrator} from "src/orchestrator/IOrchestrator.sol";

import {Module, IModule, IOrchestrator} from "src/modules/base/Module.sol";

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

contract ERC20PaymentClientAccessMock is ERC20PaymentClient {
    mapping(address => bool) authorized;

    function init(
        IOrchestrator orchestrator_,
        Metadata memory metadata,
        bytes memory //configData
    ) external override(Module) initializer {
        __Module_init(orchestrator_, metadata);
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

    //for testing the original functionality of the internal functions I created these placeholders

    function originalEnsureTokenBalance(uint amount) external {
        return _ensureTokenBalance(amount);
    }

    function originalEnsureTokenAllowance(
        IPaymentProcessor spender,
        uint amount
    ) external {
        return _ensureTokenAllowance(spender, amount);
    }

    function originalIsAuthorizedPaymentProcessor(IPaymentProcessor processor)
        external
        view
        returns (bool)
    {
        return _isAuthorizedPaymentProcessor(processor);
    }

    function set_outstandingTokenAmount(uint amount) external {
        _outstandingTokenAmount = amount;
    }
}
