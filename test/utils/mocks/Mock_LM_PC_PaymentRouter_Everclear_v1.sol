// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

import {LM_PC_PaymentRouter_v2} from
    "src/modules/logicModule/LM_PC_PaymentRouter_v2.sol";
import {PP_Everclear_CrossChain_v1} from
    "src/modules/paymentProcessor/PP_Everclear_CrossChain_v1.sol";
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IModule_v1} from "src/modules/base/IModule_v1.sol";
import {IERC20PaymentClientBase_v2} from
    "src/modules/logicModule/interfaces/IERC20PaymentClientBase_v2.sol";

contract Mock_LM_PC_PaymentRouter_Everclear_v1 is LM_PC_PaymentRouter_v2 {
    // Local constants mirroring PP_Everclear_CrossChain_v1
    uint8 public constant LOCAL_FLAG_MAX_FEE = 4;
    uint8 public constant LOCAL_FLAG_TTL = 5;

    function init(
        IOrchestrator_v1 orchestrator_,
        IModule_v1.Metadata memory metadata,
        bytes memory /* configData */
    ) external override initializer {
        __Module_init(orchestrator_, metadata);

        // Combine standard flags with Everclear-specific flags
        bytes32 combinedFlags = bytes32(
            uint(1 << FLAG_START) | uint(1 << LOCAL_FLAG_MAX_FEE)
                | uint(1 << LOCAL_FLAG_TTL)
        );

        __ERC20PaymentClientBase_v2_init(combinedFlags);
    }

    function pushCrossChainPaymentEverclear(
        address recipient,
        address paymentToken,
        uint amount,
        uint targetChainId,
        uint24 maxFee,
        uint48 ttl
    ) public onlyModuleRole(PAYMENT_PUSHER_ROLE) {
        // Prepare payment parameters array for Everclear-specific data
        bytes32[] memory paymentParamsForEverclear = new bytes32[](3);
        paymentParamsForEverclear[0] = bytes32(block.timestamp); // For FLAG_START
        paymentParamsForEverclear[1] = bytes32(uint(maxFee)); // For LOCAL_FLAG_MAX_FEE
        paymentParamsForEverclear[2] = bytes32(uint(ttl)); // For LOCAL_FLAG_TTL

        // Define the flags for the payment order
        bytes32 crossChainFlags = bytes32(
            uint(1 << FLAG_START) | uint(1 << LOCAL_FLAG_MAX_FEE)
                | uint(1 << LOCAL_FLAG_TTL)
        );

        // Generate the data array using the _assemblePaymentConfig function
        bytes32[] memory data;
        bytes32 assembledFlags; // To capture the flags returned by _assemblePaymentConfig

        // _assemblePaymentConfig is expected to return (bytes32 flags, bytes32[] memory data)
        // It should use the _paymentOrderFlags set during init to interpret paymentParamsForEverclear
        (assembledFlags, data) =
            _assemblePaymentConfig(paymentParamsForEverclear);

        // Ensure the assembledFlags match our intended crossChainFlags
        // This is a sanity check; ideally, _assemblePaymentConfig correctly uses _paymentOrderFlags.
        require(assembledFlags == crossChainFlags, "Flag mismatch");

        // Construct the PaymentOrder struct
        PaymentOrder memory order = PaymentOrder({
            recipient: recipient,
            paymentToken: paymentToken,
            amount: amount,
            originChainId: block.chainid,
            targetChainId: targetChainId,
            flags: crossChainFlags,
            data: data
        });

        // Add the payment order
        _addPaymentOrder(order);

        // Call the payment processor to process the payments
        __Module_orchestrator.paymentProcessor().processPayments(
            IERC20PaymentClientBase_v2(address(this))
        );
    }
}
