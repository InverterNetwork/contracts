// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal
import {IPP_Queue_v1} from "@pp/interfaces/IPP_Queue_v1.sol";
import {IERC20PaymentClientBase_v2} from
    "@lm/interfaces/IERC20PaymentClientBase_v2.sol";

/**
 * @title   Manual Execution Queue Based Payment Processor
 *
 * @notice  A payment processor implementation that extends the base queue system
 *          with manual execution capabilities. This allows for controlled,
 *          manual processing of payment orders in the queue.
 *
 * @dev     This contract inherits from:
 *              - IPP_Queue_v1.
 *          Key features:
 *              - Manual payment execution.
 *              - Inherits FIFO queue management.
 *              - Inherits payment order lifecycle management.
 *          The contract implements manual payment processing through the
 *          executePaymentQueue function.
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
 * @author  Zealynx Security
 */
interface IPP_Queue_ManualExecution_v1 is IPP_Queue_v1 {
    // -------------------------------------------------------------------------
    // Functions

    /// @notice Executes all pending payment orders in the queue as long as
    ///         the payment client has funds to cover the orders.
    /// @dev    If the payment client does not have enough funds, the function
    ///         will stop executing orders.
    function executePaymentQueue(IERC20PaymentClientBase_v2 paymentClient)
        external;
}
