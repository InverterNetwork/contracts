// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

import {PP_Queue_ManualExecution_v1} from "@pp/PP_Queue_ManualExecution_v1.sol";
import {IERC20PaymentClientBase_v2} from
    "@lm/interfaces/IERC20PaymentClientBase_v2.sol";
import {IPP_Queue_v1} from "@pp/interfaces/IPP_Queue_v1.sol";
import {LinkedIdList} from "src/modules/lib/LinkedIdList.sol";

contract PP_Queue_ManualExecution_v1_Exposed is PP_Queue_ManualExecution_v1 {
    using LinkedIdList for LinkedIdList.List;

    function exposed_addPaymentOrderToQueue(
        IERC20PaymentClientBase_v2.PaymentOrder memory order_,
        address client_
    ) external returns (uint) {
        return _addPaymentOrderToQueue(order_, client_);
    }

    function exposed_removeFromQueue(uint orderId_, address client_) external {
        _removeFromQueue(orderId_, client_);
    }

    function exposed_validPaymentReceiver(address addr)
        external
        view
        returns (bool)
    {
        return _validPaymentReceiver(addr);
    }

    function exposed_validTotalAmount(uint amount)
        external
        pure
        returns (bool)
    {
        return _validTotalAmount(amount);
    }

    function exposed_validTokenBalance(
        address token,
        address client,
        uint amount
    ) external view returns (bool) {
        return _validTokenBalance(token, client, amount);
    }

    function exposed_executePaymentQueue(address client_) external {
        _executePaymentQueue(client_);
    }
}
