// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

// Internal Dependencies
import {IPaymentProcessor_v1} from
    "src/modules/paymentProcessor/IPaymentProcessor_v1.sol";
import {IEverclearSpoke} from
    "src/modules/paymentProcessor/interfaces/IEverclear.sol";

// External Dependencies
import {IERC20PaymentClientBase_v2} from
    "@lm/interfaces/IERC20PaymentClientBase_v2.sol";
import {IWETH} from "src/modules/paymentProcessor/interfaces/IWETH.sol";

/// @notice Interface for cross-chain payment processing using Connext protocol
interface IPP_Connext_Crosschain_v1 is IPaymentProcessor_v1 {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Thrown when the provided Time-To-Live (TTL) parameter is invalid
    error Module__PP_Connext_Crosschain__InvalidTTL();

    //--------------------------------------------------------------------------
    // View Functions

    /// @notice Returns the Everclear spoke contract instance
    /// @return The IEverclearSpoke contract interface
    function everClearSpoke() external view returns (IEverclearSpoke);

    /// @notice Returns the WETH contract instance
    /// @return The IWETH contract interface used for wrapping/unwrapping ETH
    function weth() external view returns (IWETH);

    //--------------------------------------------------------------------------
    // External Functions

    /// @notice Process payments for a given client with execution data
    /// @dev This function handles the cross-chain payment processing using Connext
    /// @param client The payment client contract initiating the payment
    /// @param executionData The encoded execution parameters (maxFee, ttl)
    function processPayments(
        IERC20PaymentClientBase_v2 client,
        bytes memory executionData
    ) external;

    /// @notice Get bridge data for a specific payment ID
    /// @dev Used to retrieve information about a cross-chain payment
    /// @param paymentId The ID of the payment to query
    /// @return The bridge data associated with the payment (encoded bytes)
    function getBridgeData(uint paymentId)
        external
        view
        returns (bytes memory);
}
