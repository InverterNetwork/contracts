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
 *          - IPP_Queue_ManualExecution_v1: Implementation interface.
 *          - PP_Queue_v1: Queue based payment processor.
 *
 *          Key features:
 *              - FIFO queue management for payment orders.
 *                Orders are processed in the order they are added to the queue,
 *                first in first out.
 *
 *              - Manual payment execution through queue processing.
 *                Process payments will only add orders to the queue and not
 *                execute them. The executePaymentQueue function will execute
 *                the orders in the queue right away.
 *
 *              - Payment order lifecycle management with state tracking.
 *                The state of orders are tracked and emitted. The states are:
 *                  - PROCESSED: The order has been processed, the collateral has
 *                    been transferred to the recipient.
 *                  - CANCELLED: The order has been cancelled by the queue
 *                    operator.
 *                  - PENDING: The order is still in the queue.
 *                  - FAILED: The order has failed due to the transfer failing
 *                    (blacklisted address).
 *
 * @custom:setup   This module requires the following MANDATORY setup steps:
 *
 *                 1. Configure Queue Operators:
 *                    - Purpose: Queue operators are authorized to cancel payment
 *                               orders in the queue, and claim collateral for
 *                               failed payments.
 *                    - How:     The OrchestratorAdmin (or
 *                               QUEUE_OPERATOR_ROLE_ADMIN if configured) must:
 *                               1. Retrieve the queue operator role identifier.
 *                               2. Grant the role to desired addresses.
 *                    - Example: module.grantModuleRole(
 *                                module.getQueueOperatorRole(),
 *                                operatorAddress
 *                               );
 *
 *                 OPTIONAL setup steps for enhanced administration:
 *
 *                 1. Custom Queue Operator Admin:
 *                    - Purpose: Enables delegation of queue operator management
 *                               to a dedicated admin role instead of relying on
 *                               the OrchestratorAdmin. This allows for more
 *                               granular access control and operational
 *                               flexibility.
 *                    - How:     The OrchestratorAdmin must:
 *                               1. Generate the role IDs for both roles.
 *                               2. Transfer admin rights through the Authorizer.
 *                    - Example: authorizer.transferAdminRole(
 *                               authorizer.generateRoleId(
 *                                 moduleAddress,
 *                                 module.getQueueOperatorRole()
 *                               ),
 *                               authorizer.generateRoleId(
 *                                 moduleAddress,
 *                                 module.getQueueOperatorRoleAdmin()
 *                                )
 *                               );
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
