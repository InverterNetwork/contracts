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
    // View Functions

    /// @notice Returns the Everclear spoke contract instance
    /// @return IEverclearSpoke The Everclear contract interface
    function getEverClearSpoke() external view returns (IEverclearSpoke);

    /// @notice Returns the WETH contract instance
    /// @return IWETH The WETH contract interface used for wrapping/unwrapping ETH
    function getWeth() external view returns (IWETH);

    //--------------------------------------------------------------------------
    // External Functions

    /// @notice Retries a previously failed transfer
    /// @param  client_ The payment client address
    /// @param  recipient_ The recipient address
    /// @param  order_ The payment order details
    function retryFailedBridgeTransfer(
        address client_,
        address recipient_,
        IERC20PaymentClientBase_v2.PaymentOrder memory order_
    ) external;
}
