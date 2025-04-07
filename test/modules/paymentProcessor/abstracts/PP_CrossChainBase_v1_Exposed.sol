// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal
import {PP_CrossChainBase_v1} from "@pp/abstracts/PP_CrossChainBase_v1.sol";
import {IERC20PaymentClientBase_v2} from
    "@lm/interfaces/IERC20PaymentClientBase_v2.sol";
import {IPaymentProcessor_v1} from "@pp/IPaymentProcessor_v1.sol";

contract PP_CrossChainBase_v1_Exposed is PP_CrossChainBase_v1 {
    // ============================================================================
    // Implement interface and abstract functions

    function processPayments(IERC20PaymentClientBase_v2 client) external {}

    function validPaymentOrder(
        IERC20PaymentClientBase_v2.PaymentOrder memory order
    ) external returns (bool valid_) {
        return true;
    }

    function _executeBridgeTransfer(
        IERC20PaymentClientBase_v2.PaymentOrder memory order
    ) internal override returns (bytes memory) {
        return "";
    }

    // ============================================================================
    // Exposed functions

    function exposed_validPaymentToken(address token) external returns (bool) {
        return _validPaymentToken(token);
    }

    function exposed_validTotal(uint total) external view returns (bool) {
        return _validTotal(total);
    }

    function exposed_validPaymentReceiver(address receiver)
        external
        returns (bool)
    {
        return _validPaymentReceiver(receiver);
    }

    function exposed_claimPreviouslyUnclaimable(
        address client,
        address token,
        address receiver
    ) external {
        _claimPreviouslyUnclaimable(client, token, receiver);
    }

    function exposed_executeBridgeTransfer(
        IERC20PaymentClientBase_v2.PaymentOrder memory order
    ) external payable returns (bytes memory) {
        return _executeBridgeTransfer(order);
    }

    // ============================================================================
    // Helper functions

    function helper_setBridgeData(bytes memory data, uint paymentId) external {
        _bridgeData[paymentId] = data;
    }

    function helper_setPaymentId(uint paymentId) external {
        _paymentId = paymentId;
    }

    function helper_setUnclaimableAmount(
        address client,
        address token,
        address paymentReceiver,
        uint amount
    ) external {
        _unclaimableAmountsForRecipient[client][token][paymentReceiver] = amount;
    }
}
