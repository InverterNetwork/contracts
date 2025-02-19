// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

import {PP_Queue_v1} from "@pp/PP_Queue_v1.sol";
import {IERC20PaymentClientBase_v2} from
    "@lm/interfaces/IERC20PaymentClientBase_v2.sol";
import {IPP_Queue_v1} from "@pp/interfaces/IPP_Queue_v1.sol";
import {LinkedIdList} from "src/modules/lib/LinkedIdList.sol";

contract PP_Queue_v1_Exposed is PP_Queue_v1 {
    using LinkedIdList for LinkedIdList.List;

    // Override _msgSender para simplificar testing
    function _msgSender() internal view virtual override returns (address) {
        return msg.sender;
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

    function exposed_addPaymentOrderToQueue(
        IERC20PaymentClientBase_v2.PaymentOrder memory order_,
        address client_
    ) external returns (uint) {
        return _addPaymentOrderToQueue(order_, client_);
    }

    function exposed_removeFromQueue(uint orderId_, address client_) external {
        _removeFromQueue(orderId_, client_);
    }

    function exposed_getPaymentQueueId(bytes32 flags_, bytes32[] memory data_)
        external
        view
        returns (uint)
    {
        return _getPaymentQueueId(flags_, data_);
    }

    // Función para exponer _validQueueId
    function exposed_validQueueId(uint queueId, address client_)
        external
        view
        returns (bool)
    {
        return _validQueueId(queueId, client_);
    }

    function exposed_updateOrderState(
        uint orderId_,
        address client_,
        RedemptionState state_
    ) external {
        _updateOrderState(orderId_, client_, state_);
    }

    function exposed_processNextOrder(address client_)
        external
        returns (bool)
    {
        return _processNextOrder(client_);
    }

    // function exposed_executePaymentTransfer(
    //     uint orderId_,
    //     IERC20PaymentClientBase_v2 client_
    // ) public returns (bool) {
    //     QueuedOrder storage order_ = getOrder(orderId_, client_);
    //     return _executePaymentTransfer(orderId_, order_);
    // }

    function exposed_executePaymentQueue(address client_) external {
        _executePaymentQueue(client_);
    }

    function exposed_orderExists(
        uint orderId_,
        IERC20PaymentClientBase_v2 client_
    ) external view returns (bool) {
        return _orderExists(orderId_, client_);
    }

    function exposed_addUnclaimableOrder(
        IERC20PaymentClientBase_v2.PaymentOrder memory order_,
        address client_
    ) external {
        _addToUnclaimableAmount(
            client_, order_.paymentToken, order_.recipient, order_.amount
        );
    }
}
