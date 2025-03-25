// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal
import {IPaymentProcessor_v1} from "@pp/IPaymentProcessor_v1.sol";

/**
 * @title   Cross-chain Payment Processor Base Contract
 *
 * @notice  Abstract base contract for implementing cross-chain payment processing functionality.
 *
 * @dev     This contract serves as the base for cross-chain payment processors and provides:
 *          - Extension of CrossChainBase_v1 for cross-chain functionality
 *          - Implementation of IPP_CrossChain_v1 interface
 *          - Core payment validation logic
 *          - Basic security checks for payment processing
 *          - Abstract functions for bridge-specific implementations
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
 *
 * @author  33Audits
 *
 * @custom:version 1.0.0
 *
 * @custom:standard-version 1.0.0
 */
interface IPP_CrossChain_v1 is IPaymentProcessor_v1 {
    // Events
    //--------------------------------------------------------------------------

    /// @notice Emitted when a cross-chain transfer fails to complete.
    /// @param  client_ The address initiating the transfer.
    /// @param  recipient_ The intended recipient of the transfer.
    /// @param  amount_ The amount that failed to transfer.
    /// @param  flags_ The flags for this transfer attempt.
    /// @param  data_ The data for this transfer attempt.
    event BridgeTransferFailed(
        address indexed client_,
        address indexed recipient_,
        address indexed paymentToken_,
        uint amount_,
        uint originChainId_,
        uint targetChainId_,
        bytes32 flags_,
        bytes32[] data_
    );

    /// @notice Emitted when a payment ID is assigned.
    /// @param  paymentId_ The payment ID.
    /// @param  data_ The data for this transfer attempt.
    event PaymentIdAssigned(uint indexed paymentId_, bytes32 indexed data_);

    // Errors
    //--------------------------------------------------------------------------

    /// @notice Thrown when the unclaimable amount is invalid (e.g., zero or exceeds
    ///         limits).
    error Module__PP_CrossChain__InvalidUnclaimableAmount();

    /// @notice Thrown when the cross-chain message fails to be delivered.
    /// @param  sourceChain The chain ID where the message originated.
    /// @param  destinationChain The chain ID where the message was meant to be
    ///         delivered.
    /// @param  flags The flags for this transfer attempt.
    /// @param  data The data for this transfer attempt.
    error Module__PP_CrossChain__MessageDeliveryFailed(
        uint sourceChain, uint destinationChain, bytes32 flags, bytes32[] data
    );

    // -------------------------------------------------------------------------
    // View Functions

    /// @notice Get the current payment ID.
    /// @return paymentId_ The current payment ID.
    function getPaymentId() external view returns (uint paymentId_);
}
