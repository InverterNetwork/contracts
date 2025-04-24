// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {PaymentProcessorV1Mock} from
    "test/utils/mocks/modules/PaymentProcessorV1Mock.sol";

contract PP_Queue_ManualExecution_v1_Mock is PaymentProcessorV1Mock {
    //--------------------------------------------------------------------------
    // PP_Queue_ManualExecution_v1_Mock Functions

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
