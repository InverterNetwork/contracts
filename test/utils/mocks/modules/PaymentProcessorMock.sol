// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IERC20} from "@oz/token/ERC20/IERC20.sol";

import {ERC165} from "@oz/utils/introspection/ERC165.sol";

import {IPaymentProcessor} from
    "src/modules/paymentProcessor/IPaymentProcessor.sol";
import {IERC20PaymentClient} from
    "src/modules/logicModule/paymentClient/IERC20PaymentClient.sol";
import {IModule_v1} from "src/modules/base/Module_v1.sol";

contract PaymentProcessorMock is IPaymentProcessor, ERC165 {
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC165)
        returns (bool)
    {
        bytes4 interfaceId_IPaymentProcessor =
            type(IPaymentProcessor).interfaceId;
        bytes4 interfaceId_IModule = type(IModule_v1).interfaceId;
        return interfaceId == interfaceId_IPaymentProcessor
            || interfaceId == interfaceId_IModule
            || super.supportsInterface(interfaceId);
    }

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
