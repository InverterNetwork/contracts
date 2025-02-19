// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies

// External Dependencies
import {IERC20PaymentClientBase_v2} from
    "@lm/interfaces/IERC20PaymentClientBase_v2.sol";

/// @title ICrossChainBase_v1
/// @notice Base interface for cross-chain payment processing functionality
interface ICrossChainBase_v1 {
    /// @notice Struct to hold cross-chain message data
    /// @param messageId Unique identifier for the cross-chain message
    /// @param sourceChain Address or identifier of the source chain
    /// @param targetChain Address or identifier of the target chain
    /// @param payload The encoded data being sent across chains
    /// @param executed Boolean flag indicating if the message has been processed
    struct CrossChainMessage {
        uint messageId;
        address sourceChain;
        address targetChain;
        bytes payload;
        bool executed;
    }

    //--------------------------------------------------------------------------
    // Events

    /// @notice Emitted when a bridge transfer is executed
    /// @param bridgeData The encoded data of the bridge transfer
    event BridgeTransferExecuted(bytes indexed bridgeData);

    //--------------------------------------------------------------------------
    // Errors

    /// @notice Thrown when attempting to process a transfer with zero amount
    error Module__CrossChainBase__InvalidAmount();

    /// @notice Thrown when an unauthorized client attempts to interact with the contract
    error Module__CrossChainBase__NotValidClient();

    /// @notice Thrown when attempting to execute a message that has already been processed
    error Module__CrossChainBase_MessageAlreadyExecuted();

    /// @notice Thrown when the cross-chain message fails verification
    error Module__CrossChainBase_MessageVerificationFailed();

    /// @notice Thrown when the provided execution data is malformed or invalid
    error Module__CrossChainBase_InvalidExecutionData();

    /// @notice Thrown when the recipient address is invalid or not allowed
    error Module__CrossChainBase__InvalidRecipient();
}
