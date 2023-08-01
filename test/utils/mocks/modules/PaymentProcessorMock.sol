// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IERC20} from "@oz/token/ERC20/IERC20.sol";

import {IPaymentProcessor} from
    "src/modules/paymentProcessor/IPaymentProcessor.sol";
import {IERC20PaymentClient} from "src/modules/base/mixins/IERC20PaymentClient.sol";

contract PaymentProcessorMock is IPaymentProcessor {
    //--------------------------------------------------------------------------
    // IPaymentProcessor Functions

    function processPayments(IERC20PaymentClient client) external {}

    function cancelRunningPayments(IERC20PaymentClient client) external {}

    function token() external pure returns (IERC20) {
        return IERC20(address(0));
    }

    function deleteAllPayments(IERC20PaymentClient client) external {
        client.collectPaymentOrders();
    }
}
