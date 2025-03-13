// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

// Internal
import {CrossChainBase_v1} from
    "src/modules/paymentProcessor/abstracts/CrossChainBase_v1.sol";
import {IERC20PaymentClientBase_v2} from
    "@lm/interfaces/IERC20PaymentClientBase_v2.sol";

contract CrossChainBase_v1_Exposed is CrossChainBase_v1 {
    function _executeBridgeTransfer(
        IERC20PaymentClientBase_v2.PaymentOrder memory order
    ) internal pure override returns (bytes memory) {
        return "";
    }

    function getBridgeData(uint paymentId)
        public
        pure
        override
        returns (bytes memory)
    {
        return "";
    }

    function exposed_executeBridgeTransfer(
        IERC20PaymentClientBase_v2.PaymentOrder memory order
    ) external payable returns (bytes memory) {
        return _executeBridgeTransfer(order);
    }
}
