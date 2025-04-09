// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Interfaces
import {IERC20PaymentClientBase_v2} from
    "@lm/interfaces/IERC20PaymentClientBase_v2.sol";
import {IPaymentProcessor_v2} from
    "src/modules/paymentProcessor/IPaymentProcessor_v2.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

interface IPP_Crosschain_v1 is IPaymentProcessor_v2 {
    /// @notice Thrown when the cross-chain message fails to be delivered
    /// @param sourceChain The chain ID where the message originated
    /// @param destinationChain The chain ID where the message was meant to be delivered
    /// @param messageId The unique identifier of the failed message
    error Module__PP_Crosschain__MessageDeliveryFailed(
        uint sourceChain, uint destinationChain, bytes32 messageId
    );

    /// @notice Thrown when attempting to process a cross-chain payment with invalid parameters
    /// @param paymentClient The address of the payment client
    /// @param paymentId The ID of the payment being processed
    /// @param destinationChain The target chain ID for the payment
    error Module__PP_Crosschain__InvalidPaymentParameters(
        address paymentClient, uint paymentId, uint destinationChain
    );

    /// @notice Thrown when the cross-chain bridge fees exceed the maximum allowed
    /// @param actualFee The actual fee required
    /// @param maxFee The maximum fee allowed
    error Module__PP_Crosschain__BridgeFeeTooHigh(uint actualFee, uint maxFee);
}
