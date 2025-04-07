pragma solidity 0.8.23;

// Internal
import {PP_Everclear_CrossChain_v1} from
    "src/modules/paymentProcessor/PP_Everclear_CrossChain_v1.sol";
import {IERC20PaymentClientBase_v2} from
    "@lm/interfaces/IERC20PaymentClientBase_v2.sol";
// External
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

contract PP_Everclear_CrossChain_v1_Exposed is PP_Everclear_CrossChain_v1 {
    // Expose internal _executeBridgeTransfer function
    function exposed_executeBridgeTransfer(
        IERC20PaymentClientBase_v2.PaymentOrder memory order
    ) external {
        _executeBridgeTransfer(order);
    }

    function exposed_validPaymentOrder(
        IERC20PaymentClientBase_v2.PaymentOrder memory order
    ) external returns (bool) {
        return _validPaymentOrder(order);
    }

    function exposed_transferTokenAndApproveToBridge(
        IERC20PaymentClientBase_v2.PaymentOrder memory order,
        address client
    ) external {
        return _transferTokenAndApproveToBridge(order, client);
    }

    // Expose internal xcall function
    function exposed_createCrossChainIntent(
        IERC20PaymentClientBase_v2.PaymentOrder memory order
    ) external returns (bytes32) {
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
    ) external view returns (uint24 maxFee_, uint48 ttl_) {
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
        view
        returns (bool)
    {
        return _validateFlagsAndData(flags, data);
    }
}
