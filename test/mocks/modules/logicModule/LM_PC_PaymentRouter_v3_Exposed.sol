// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies
import {LM_PC_PaymentRouter_v3} from "@lm/LM_PC_PaymentRouter_v3.sol";

contract LM_PC_PaymentRouter_v3_Exposed is LM_PC_PaymentRouter_v3 {
    //--------------------------------------------------------------------------
    // Internal Functions

    function direct__assemblePaymentConfig(bytes32[] memory data)
        external
        view
        returns (bytes32, bytes32[] memory)
    {
        return _assemblePaymentConfig(data);
    }
}
