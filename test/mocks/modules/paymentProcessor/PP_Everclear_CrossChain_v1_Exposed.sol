pragma solidity 0.8.23;

// Internal
import {PP_Everclear_CrossChain_v1} from "@pp/PP_Everclear_CrossChain_v1.sol";
import {IERC20PaymentClientBase_v3} from
    "@lm/interfaces/IERC20PaymentClientBase_v3.sol";
import {IEverclear} from "@pp/interfaces/IEverclear.sol";
// External
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

contract PP_Everclear_CrossChain_v1_Exposed is PP_Everclear_CrossChain_v1 {
    // Expose internal _executeBridgeTransfer function
    function exposed_executeBridgeTransfer(
        IERC20PaymentClientBase_v3.PaymentOrder memory order
    ) external {
        _executeBridgeTransfer(order);
    }

    function exposed_validPaymentOrder(
        IERC20PaymentClientBase_v3.PaymentOrder memory order
    ) external returns (bool) {
        return _validPaymentOrder(order);
    }

    function exposed_transferTokenAndApproveToBridge(
        IERC20PaymentClientBase_v3.PaymentOrder memory order,
        address client
    ) external {
        _transferTokenAndApproveToBridge(order, client);
    }

    // Expose internal xcall function
    function exposed_createCrossChainIntent(
        IERC20PaymentClientBase_v3.PaymentOrder memory order
    ) external returns (bytes32 intentId_, IEverclear.Intent memory intent_) {
        return _createCrossChainIntent(order);
    }

    function exposed_unclaimable(
        address client,
        address recipient,
        address token
    ) external view returns (uint) {
        return _unclaimableAmountsForRecipient[client][token][recipient];
    }

    function exposed_getEverclearMaxFeeAndTTL(
        bytes32 flags,
        bytes32[] memory data
    ) external pure returns (uint24 maxFee_, uint48 ttl_) {
        return _getEverclearMaxFeeAndTTL(flags, data);
    }

    function exposed_validateOriginAndTargetChainId(
        uint originChainId,
        uint targetChainId
    ) external view returns (bool) {
        return _validateOriginAndTargetChainId(originChainId, targetChainId);
    }

    function exposed_validateFlagsAndData(bytes32 flags, bytes32[] memory data)
        external
        pure
        returns (bool)
    {
        return _validateFlagsAndData(flags, data);
    }

    function exposed_processSuccessfulBridgeTransfer(
        IERC20PaymentClientBase_v3.PaymentOrder memory order_,
        address client_,
        bytes32 intentId_,
        IEverclear.Intent memory intent_
    ) external {
        _processSuccessfulBridgeTransfer(order_, client_, intentId_, intent_);
    }

    function exposed_processFailedBridgeTransfer(
        IERC20PaymentClientBase_v3.PaymentOrder memory order_,
        address client_
    ) external {
        _processFailedBridgeTransfer(order_, client_);
    }

    // =========================================================================
    // Helper functions

    function helper_setIntentIdToIntent(
        bytes32 intentId,
        IEverclear.Intent memory intent
    ) external {
        _intentIdToIntent[intentId] = IEverclear.Intent(
            intent.initiator,
            intent.receiver,
            intent.inputAsset,
            intent.outputAsset,
            intent.maxFee,
            intent.origin,
            intent.nonce,
            intent.timestamp,
            intent.ttl,
            intent.amount,
            intent.destinations,
            intent.data
        );
    }
}
