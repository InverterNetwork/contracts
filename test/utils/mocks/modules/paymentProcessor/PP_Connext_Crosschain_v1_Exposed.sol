pragma solidity ^0.8.20;

import {PP_Connext_Crosschain_v1} from
    "src/modules/paymentProcessor/PP_Connext_Crosschain_v1.sol";
import {IERC20PaymentClientBase_v1} from
    "@lm/interfaces/IERC20PaymentClientBase_v1.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

contract PP_Connext_Crosschain_v1_Exposed is PP_Connext_Crosschain_v1 {
    // Expose internal _executeBridgeTransfer function
    function exposed_executeBridgeTransfer(
        IERC20PaymentClientBase_v1.PaymentOrder memory order,
        bytes memory executionData
    ) external returns (bytes memory) {
        return _executeBridgeTransfer(order, executionData);
    }

    // Expose internal xcall function
    function exposed_createCrossChainIntent(
        IERC20PaymentClientBase_v1.PaymentOrder memory order,
        bytes memory executionData
    ) external returns (bytes32) {
        return _createCrossChainIntent(order, executionData, false);
    }

    function exposed_setFailedTransfer(
        address client,
        address recipient,
        bytes memory intentId,
        uint amount
    ) external {
        failedTransfers[client][recipient][intentId] = amount;
    }
}
