// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";

import {
    Module_v2,
    IModule_v2,
    IOrchestrator_v1
} from "src/modules/base/Module_v2.sol";

// SuT
import {
    ERC20PaymentClientBase_v3,
    IERC20PaymentClientBase_v3
} from "@lm/abstracts/ERC20PaymentClientBase_v3.sol";

// Internal Interfaces
import {IPaymentProcessor_v3} from
    "src/modules/paymentProcessor/IPaymentProcessor_v3.sol";

// Mocks
import {ERC20Mock} from "@mocks/external/token/ERC20Mock.sol";

contract ERC20PaymentClientBaseV2_Exposed is ERC20PaymentClientBase_v3 {
    mapping(address => bool) authorized;

    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata,
        bytes memory // configData
    ) external override(Module_v2) initializer {
        __Module_init(orchestrator_, metadata);
    }

    //--------------------------------------------------------------------------
    // IERC20PaymentClientBase_v3 Wrapper Functions

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

    // for testing the original functionality of the internal functions I created these placeholders

    function exposed_ensureTokenBalance(address token) external {
        return _ensureTokenBalance(token);
    }

    function exposed_ensureTokenAllowance(
        IPaymentProcessor_v3 spender,
        address token
    ) external {
        return _ensureTokenAllowance(spender, token);
    }

    function exposed_isAuthorizedPaymentProcessor(
        IPaymentProcessor_v3 processor
    ) external view returns (bool) {
        return _isAuthorizedPaymentProcessor(processor);
    }

    function exposed_outstandingTokenAmount(address token, uint amount)
        external
    {
        _outstandingTokenAmounts[token] = amount;
    }

    function exposed_setFlags(bytes32 flags_) external {
        _setFlags(flags_);
    }

    function exposed_assemblePaymentConfig(bytes32[] memory flagValues_)
        external
        returns (bytes32 flags_, bytes32[] memory data_)
    {
        return _assemblePaymentConfig(flagValues_);
    }
}
