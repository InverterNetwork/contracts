// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {PaymentProcessor_v3_Mock} from
    "@mocks/modules/paymentProcessor/PaymentProcessor_v3_Mock.sol";

contract PP_Queue_ManualExecution_v2_Mock is PaymentProcessor_v3_Mock {
    //--------------------------------------------------------------------------
    // PP_Queue_ManualExecution_v2_Mock Functions

    function executePaymentQueue(address /*client_*/ ) external {
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
    }
}
