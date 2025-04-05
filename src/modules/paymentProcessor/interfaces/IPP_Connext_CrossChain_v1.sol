// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

// Internal
import {IPaymentProcessor_v1} from
    "src/modules/paymentProcessor/IPaymentProcessor_v1.sol";

// External
import {IERC20PaymentClientBase_v2} from
    "@lm/interfaces/IERC20PaymentClientBase_v2.sol";
import {IWETH} from "src/modules/paymentProcessor/interfaces/IWETH.sol";
import {IEverclearSpoke} from
    "src/modules/paymentProcessor/interfaces/IEverclear.sol";

/**
 * @title   Connext Protocol Integrated Cross-Chain Payment Processor.
 *
 * @notice  A payment processor implementation that enables cross-chain payments
 *          using the Connext protocol. This module processes payment orders created by an Inverter Payment Client
 *          and bridges the payments to the target chain through Connext's infrastructure.
 *
 * @dev     Inherits functionality from:
 *          - IPP_Connext_CrossChain_v1: Implementation interface.
 *          - PP_CrossChain_v1: Cross-chain Payment Processor Base.
 *
 *          Key features:
 *              - Cross-chain payment processing
 *                Enables execution of payment orders across different networks.
 *
 *              - Connext Bridge integration.
 *                Integrates with Connext protocol for secure cross-chain transfers, creating a new intent for each payment order through calling the Everclear Spoke contract.
 *
 *              - Failed bridge transfer retry.
 *                Provides mechanism to retry failed bridge transfers through leveraging the unclaimable amounts and providing a new payment order.
 *
 *              - WETH handling.
 *                Supports native token wrapping/unwrapping for ETH transfers.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to
 *                          our Security Policy at security.inverter.network or
 *                          email us directly!
 *
 * @custom:version  v1.0.0
 *
 * @custom:standard-version v1.0.0
 *
 * @author  33Audits
 */
interface IPP_Connext_CrossChain_v1 {
    //--------------------------------------------------------------------------
    // View Functions

    /// @notice Returns the Everclear spoke contract instance everClearSpoke_.
    /// @return everClearSpoke_ The Everclear contract interface.
    function getEverClearSpoke()
        external
        view
        returns (IEverclearSpoke everClearSpoke_);

    /// @notice Returns the WETH contract instance weth_.
    /// @return weth_ The WETH contract interface used for wrapping/unwrapping ETH.
    function getWeth() external view returns (IWETH weth_);

    //--------------------------------------------------------------------------
    // External Functions

    /// @notice Retries a previously failed transfer.
    /// @param  client_ The payment client address.
    /// @param  recipient_ The recipient address.
    /// @param  order_ The payment order details.
    function retryFailedBridgeTransfer(
        address client_,
        address recipient_,
        IERC20PaymentClientBase_v2.PaymentOrder memory order_
    ) external;
}
