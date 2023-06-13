// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import {IERC20} from "@oz/token/ERC20/IERC20.sol";

import {IPaymentProcessor} from
    "src/modules/paymentProcessor/IPaymentProcessor.sol";
import {IPaymentClient} from "src/modules/base/mixins/IPaymentClient.sol";

contract PaymentProcessorMock is IPaymentProcessor {
    //--------------------------------------------------------------------------
    // IPaymentProcessor Functions

    function processPayments(IPaymentClient client) external {}

    function cancelRunningPayments(IPaymentClient client) external {}

    function token() external pure returns (IERC20) {
        return IERC20(address(0));
    }

    function deleteAllPayments(IPaymentClient client) external {
        client.collectPaymentOrders();
    }
}
