// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal
import {IPaymentProcessor_v1} from "@pp/IPaymentProcessor_v1.sol";

/**
 * @title   Cross-chain Payment Processor Base Contract.
 *
 * @notice  Abstract base contract for implementing cross-chain payment
 *          processing functionality.
 *
 * @dev     Inherits functionality from:
 *          - IPP_CrossChainBase_v1: Implementation interface.
 *          - IPaymentProcessor_v1: Payment processor interface.
 *          - Module_v1: Base module functionality.
 *
 *          Key features:
 *              - Bridge Data Management
 *                Stores and retrieves bridge-specific data for each bridge operation.
 *
 *              - Payment ID tracking.
 *                Tracks the payment ID for each cross-chain payment.
 *
 *              - Enforces interface implementation.
 *                Abstract bridge transfer function enforcing custom implementation in inheriting contracts.
 *
 *              - Unclaimable amounts tracking.
 *                Provides functionality to claim unclaimable amounts
 *                (failed bridge transfers) for each payment client, token,
 *                and recipient to the current chain.
 *
 *              - Base cross-chain payment validation.
 *                Implements basic validation checks for cross-chain payments.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to
 *                          our Security Policy at security.inverter.network or
 *                          email us directly!
 *
 * @custom:version 1.0.0
 *
 * @custom:standard-version 1.0.0
 *
 * @author  33Audits
 */
interface IPP_CrossChainBase_v1 is IPaymentProcessor_v1 {
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
    /// @param  intentId_ The intent ID.
    /// @param  recipient_ The recipient of the payment.
    /// @param  client_ The payment client that initiated the payment.
    /// @param  paymentToken_ The token which has been bridged.
    /// @param  amount_ The amount of tokens that have been bridged.
    /// @param  originChainId_ The chain id of the origin chain.
    /// @param  targetChainId_ The chain id of the target chain.
    event BridgeTransferCompleted(
        uint indexed paymentId_,
        bytes32 indexed intentId_,
        address indexed recipient_,
        address client_,
        address paymentToken_,
        uint amount_,
        uint originChainId_,
        uint targetChainId_,
        bytes32 flags_,
        bytes32[] data_
    );

    // Errors
    //--------------------------------------------------------------------------

    /// @notice Thrown when the unclaimable amount is invalid (e.g., zero or exceeds
    ///         limits).
    error Module__PP_CrossChain__InvalidUnclaimableAmount();

    /// @notice Thrown when maxFee or ttl is invalid.
    error Module__PP_CrossChain__InvalidMaxFeeOrTTL();

    // -------------------------------------------------------------------------
    // View Functions

    /// @notice Get the bridge data for a given payment ID.
    /// @param  paymentId_ The ID of the payment to get the bridge data for.
    /// @return bridgeData_ The bridge data for the given payment ID.
    function getBridgeDataByPaymentId(uint paymentId_)
        external
        view
        returns (bytes memory bridgeData_);

    /// @notice Get the current payment ID.
    /// @return paymentId_ The current payment ID.
    function getPaymentId() external view returns (uint paymentId_);
}
