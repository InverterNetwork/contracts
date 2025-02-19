// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IERC20} from "@oz/token/ERC20/IERC20.sol";

import {ERC165} from "@oz/utils/introspection/ERC165.sol";

import {IPaymentProcessor_v1} from
    "src/modules/paymentProcessor/IPaymentProcessor_v1.sol";
import {IERC20PaymentClientBase_v2} from
    "@lm/interfaces/IERC20PaymentClientBase_v2.sol";
import {IModule_v1} from "src/modules/base/Module_v1.sol";

contract PaymentProcessorV1Mock is IPaymentProcessor_v1, ERC165 {
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC165)
        returns (bool)
    {
        bytes4 interfaceId_IPaymentProcessor =
            type(IPaymentProcessor_v1).interfaceId;
        bytes4 interfaceId_IModule = type(IModule_v1).interfaceId;
        return interfaceId == interfaceId_IPaymentProcessor
            || interfaceId == interfaceId_IModule
            || super.supportsInterface(interfaceId);
    }

    uint public processPaymentsTriggered;
    bool public validOrder = true;

    //--------------------------------------------------------------------------
    // IPaymentProcessor_v1 Functions

    function processPayments(IERC20PaymentClientBase_v2 /*client*/ ) external {
        emit PaymentOrderProcessed(
            address(0),
            address(0),
            address(0),
            0,
            0,
            0,
            bytes32(0),
            new bytes32[](0)
        );
        processPaymentsTriggered += 1;
    }

    function cancelRunningPayments(IERC20PaymentClientBase_v2) external {}

    function token() external pure returns (IERC20) {
        return IERC20(address(0));
    }

    function deleteAllPayments(IERC20PaymentClientBase_v2 client) external {
        client.collectPaymentOrders();
    }

    function unclaimable(address, address, address)
        external
        view
        returns (uint)
    {}

    function claimPreviouslyUnclaimable(address, address, address) external {}

    function validPaymentOrder(IERC20PaymentClientBase_v2.PaymentOrder memory)
        external
        view
        returns (bool)
    {
        return validOrder;
    }

    // Mock Functions

    function flipValidOrder() external {
        validOrder = !validOrder;
    }
}
