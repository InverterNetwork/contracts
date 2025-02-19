// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal
import {IPaymentProcessor_v1} from "@pp/IPaymentProcessor_v1.sol";

/// @notice Interface for cross-chain payment processing functionality
interface IPP_Crosschain_v1 is IPaymentProcessor_v1 {
    // Events
    //--------------------------------------------------------------------------

    /// @notice Emitted when a cross-chain transfer fails to complete
    /// @param client The address initiating the transfer
    /// @param recipient The intended recipient of the transfer
    /// @param amount The amount that failed to transfer
    /// @param flags The flags for this transfer attempt
    /// @param data The data for this transfer attempt
    event BridgeTransferFailed(
        address indexed client,
        address indexed recipient,
        uint amount,
        bytes32 flags,
        bytes32[] data
    );

    // Errors
    //--------------------------------------------------------------------------

    /// @notice Thrown when the unclaimable amount is invalid (e.g., zero or exceeds
    /// limits)
    error Module__PP_Crosschain__InvalidUnclaimableAmount();

    /// @notice Thrown when the cross-chain message fails to be delivered
    /// @param sourceChain The chain ID where the message originated
    /// @param destinationChain The chain ID where the message was meant to be
    /// delivered
    /// @param flags The flags for this transfer attempt
    /// @param data The data for this transfer attempt
    error Module__PP_Crosschain__MessageDeliveryFailed(
        uint sourceChain, uint destinationChain, bytes32 flags, bytes32[] data
    );

    // -------------------------------------------------------------------------
    // View Functions

    /// @notice Get the current payment ID
    /// @return paymentId_ The current payment ID
    function getPaymentId() external view returns (uint paymentId_);
}
