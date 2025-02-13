// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies
import {IPaymentProcessor_v1} from
    "src/modules/paymentProcessor/IPaymentProcessor_v1.sol";

/// @notice Interface for cross-chain payment processing functionality
interface IPP_Crosschain_v1 is IPaymentProcessor_v1 {
    // Events
    //--------------------------------------------------------------------------

    /// @notice Emitted when a cross-chain transfer fails to complete
    /// @param client The address initiating the transfer
    /// @param recipient The intended recipient of the transfer
    /// @param executionData The unique identifier for this transfer attempt
    /// @param amount The amount that failed to transfer
    event TransferFailed(
        address indexed client,
        address indexed recipient,
        bytes indexed executionData,
        uint amount
    );

    /// @notice Emitted when a previously failed transfer is attempted again
    /// @param client The address initiating the retry
    /// @param recipient The intended recipient of the transfer
    /// @param oldIntentId The intent ID of the failed transfer
    /// @param newIntentId The new intent ID for this retry attempt
    event FailedTransferRetried(
        address indexed client,
        address indexed recipient,
        bytes32 indexed oldIntentId,
        bytes32 newIntentId
    );

    /// @notice Emitted when a transfer is cancelled by the client or system
    /// @param client The address that initiated the original transfer
    /// @param recipient The intended recipient of the cancelled transfer
    /// @param intentId The unique identifier of the cancelled transfer
    /// @param amount The amount that was intended to be transferred
    event TransferCancelled(
        address indexed client,
        address indexed recipient,
        bytes indexed intentId,
        uint amount
    );

    // Errors
    //--------------------------------------------------------------------------

    /// @notice Thrown when the provided intent ID is invalid or does not exist
    error Module__PP_Crosschain__InvalidIntentId();

    /// @notice Thrown when the unclaimable amount is invalid (e.g., zero or exceeds
    /// limits)
    error Module__PP_Crosschain__InvalidUnclaimableAmount();

    /// @notice Thrown when the payment amount is invalid (e.g., zero or exceeds
    /// limits)
    error Module__PP_Crosschain__InvalidAmount();

    /// @notice Thrown when the cross-chain bridge fees exceed the maximum allowed
    error Module__PP_Crosschain__InvalidBridgeFee();

    /// @notice Thrown when the cross-chain message fails to be delivered
    /// @param sourceChain The chain ID where the message originated
    /// @param destinationChain The chain ID where the message was meant to be
    /// delivered
    /// @param executionData The encoded execution parameters (maxFee, ttl)
    error Module__PP_Crosschain__MessageDeliveryFailed(
        uint sourceChain, uint destinationChain, bytes executionData
    );

    /// @notice Thrown when attempting to process a cross-chain payment with invalid
    /// parameters
    /// @param paymentClient The address of the payment client
    /// @param paymentId The ID of the payment being processed
    /// @param destinationChain The target chain ID for the payment
    error Module__PP_Crosschain__InvalidPaymentParameters(
        address paymentClient, uint paymentId, uint destinationChain
    );
}
