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
 * @title   Connext Cross-Chain Payment Processor
 *
 * @notice  A payment processor implementation that enables cross-chain payments
 *          using the Connext protocol. This module processes payment orders from
 *          payment clients and bridges them to their target chains through
 *          Connext's infrastructure.
 *
 * @dev     Inherits functionality from:
 *          - IPP_Connext_CrossChain_v1: Implementation interface
 *          - IPaymentProcessor_v1: Base payment processor functionality
 *          - ICrossChainBase_v1: Cross-chain operations base
 *
 *          Key features:
 *              - Cross-chain payment processing
 *                Enables payments to be sent across different networks
 *
 *              - Bridge integration
 *                Integrates with Everclear protocol for secure cross-chain transfers
 *
 *              - Failed transfer recovery
 *                Provides mechanism to retry failed bridge transfers
 *
 *              - WETH handling
 *                Supports native token wrapping/unwrapping for ETH transfers
 *
 * @custom:setup    This module requires the following MANDATORY setup steps:
 *
 *                  1. Initialize with Correct Parameters:
 *                     - Purpose: The module needs proper configuration of
 *                               Everclear spoke and WETH contract addresses
 *                     - How:     Pass the correct addresses during initialization
 *                     - Example: module.init(
 *                                 orchestrator,
 *                                 metadata,
 *                                 abi.encode(everClearSpoke, wethAddress)
 *                               );
 *
 *                  2. Payment Client Authorization:
 *                     - Purpose: Only authorized payment clients should be able
 *                               to process payments through this module
 *                     - How:     The payment client must be added through the
 *                               orchestrator's module management system
 *                     - Example: orchestrator.initiateAddModule(clientAddress);
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
interface IPP_Connext_CrossChain_v1 is IPaymentProcessor_v1 {
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
