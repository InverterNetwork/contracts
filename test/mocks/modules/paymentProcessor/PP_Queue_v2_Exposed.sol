// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

import {PP_Queue_v2} from "@pp/PP_Queue_v2.sol";
import {IERC20PaymentClientBase_v3} from
    "@lm/interfaces/IERC20PaymentClientBase_v3.sol";
import {IPP_Queue_v2} from "@pp/interfaces/IPP_Queue_v2.sol";
import {LinkedIdList} from "src/modules/lib/LinkedIdList.sol";

contract PP_Queue_v2_Exposed is PP_Queue_v2 {
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
        IERC20PaymentClientBase_v3.PaymentOrder memory order_,
        address client_
    ) external returns (uint) {
        return _addPaymentOrderToQueue(order_, client_);
    }

    function exposed_removeFromQueue(uint orderId_, address client_) external {
        _removeFromQueue(orderId_, client_);
    }

    function exposed_getOrderDetailsFromFlagsAndData(
        bytes32 flags_,
        bytes32[] memory data_
    ) external view returns (uint orderId_, uint projectFee_) {
        return _getOrderDetailsFromFlagsAndData(flags_, data_);
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

    function exposed_executePaymentQueue(address client_) external {
        _executePaymentQueue(client_);
    }

    function exposed_tryPaymentTransfer(
        address token_,
        address client_,
        address recipient_,
        uint amount_,
        bool collectProtocolFee_,
        uint projectFee_
    ) external returns (bool) {
        return _tryPaymentTransfer(
            token_,
            client_,
            recipient_,
            amount_,
            collectProtocolFee_,
            projectFee_
        );
    }

    function exposed_lowLevelTransfer(
        address token_,
        address client_,
        address recipient_,
        uint amount_
    ) external returns (bool) {
        return _lowLevelTransfer(token_, client_, recipient_, amount_);
    }

    function exposed_calculateProtocolFeeAmount(
        uint totalAmount_,
        bytes4 functionSelector_,
        bool collectProtocolFee_,
        uint projectFee_
    ) external view returns (uint, uint, address) {
        return _calculateProtocolFeeAmount(
            totalAmount_, functionSelector_, collectProtocolFee_, projectFee_
        );
    }

    function exposed_executePaymentTransfer(
        uint orderId_,
        QueuedOrder memory order_
    ) external {
        _executePaymentTransfer(orderId_, order_);
    }

    function exposed_orderExists(
        uint orderId_,
        IERC20PaymentClientBase_v3 client_
    ) external view returns (bool) {
        return _orderExists(orderId_, client_);
    }

    function exposed_addUnclaimableOrder(
        IERC20PaymentClientBase_v3.PaymentOrder memory order_,
        address client_
    ) external {
        _addToUnclaimableAmount(
            client_, order_.paymentToken, order_.recipient, order_.amount
        );
    }

    function exposed_validPaymentOrder(
        IERC20PaymentClientBase_v3.PaymentOrder memory order_
    ) external view returns (bool) {
        return _validPaymentOrder(order_);
    }

    function exposed_validChainId(uint chainId_) external view returns (bool) {
        return _validChainId(chainId_);
    }

    function exposed_ensureValidClient(address client_) external view {
        _ensureValidClient(client_);
    }

    function exposed_setCanceledOrdersTreasury(address treasury_) external {
        _setCanceledOrdersTreasury(treasury_);
    }

    function exposed_setFailedOrdersTreasury(address treasury_) external {
        _setFailedOrdersTreasury(treasury_);
    }

    function exposed_validPaymentToken(address token_)
        external
        view
        returns (bool)
    {
        return _validPaymentToken(token_);
    }

    function exposed_validateOrderFlags(bytes32 flags_)
        external
        pure
        returns (bool)
    {
        return _validateOrderFlags(flags_);
    }

    function exposed_validStateTransition(
        uint orderId_,
        RedemptionState currentState_,
        RedemptionState newState_
    ) external pure returns (bool) {
        return _validStateTransition(orderId_, currentState_, newState_);
    }

    function exposed_claimPreviouslyUnclaimable(
        address client_,
        address token_,
        address paymentReceiver_
    ) external {
        _claimPreviouslyUnclaimable(client_, token_, paymentReceiver_);
    }

    function exposed_validProjectFee(uint projectFee_)
        external
        pure
        returns (bool)
    {
        return _validProjectFee(projectFee_);
    }

    // Helper functions

    function helper_initiateQueueForPaymentClient(address paymentClient_)
        external
    {
        _queue[paymentClient_].init();
    }
}
