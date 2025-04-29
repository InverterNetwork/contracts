// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IPaymentProcessor_v2} from "@pp/IPaymentProcessor_v2.sol";
import {IERC20PaymentClientBase_v2} from
    "@lm/interfaces/IERC20PaymentClientBase_v2.sol";
import {IPP_Queue_v1} from "@pp/interfaces/IPP_Queue_v1.sol";
import {IPP_Queue_ManualExecution_v1} from
    "@pp/interfaces/IPP_Queue_ManualExecution_v1.sol";
import {ERC165Upgradeable, Module_v1} from "src/modules/base/Module_v1.sol";
import {PP_Queue_v1} from "@pp/PP_Queue_v1.sol";

// External
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

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
contract PP_Queue_ManualExecution_v1 is
    IPP_Queue_ManualExecution_v1,
    PP_Queue_v1
{
    // -------------------------------------------------------------------------
    // ERC165

    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId_)
        public
        view
        virtual
        override(PP_Queue_v1)
        returns (bool)
    {
        return interfaceId_ == type(IPP_Queue_ManualExecution_v1).interfaceId
            || interfaceId_ == type(IPaymentProcessor_v2).interfaceId
            || super.supportsInterface(interfaceId_);
    }

    // -------------------------------------------------------------------------
    // Storage

    /// @dev    Gap for possible future upgrades.
    uint[50] private __gap;

    // -------------------------------------------------------------------------
    // Public Mutating Functions

    /// @inheritdoc IPaymentProcessor_v2
    function processPayments(IERC20PaymentClientBase_v2 client_)
        external
        virtual
        override(PP_Queue_v1, IPaymentProcessor_v2)
        clientIsValid(address(client_))
        onlyModule
    {
        // Collect outstanding orders and their total token amount.
        IERC20PaymentClientBase_v2.PaymentOrder[] memory orders;

        (orders,,) = client_.collectPaymentOrders();

        uint orderLength = orders.length;
        for (uint i; i < orderLength; ++i) {
            // Add order to order queue.
            _addPaymentOrderToQueue(orders[i], address(client_));
        }
    }

    /// @inheritdoc IPP_Queue_ManualExecution_v1
    function executePaymentQueue(IERC20PaymentClientBase_v2 client_)
        external
        virtual
        onlyModule
    {
        _executePaymentQueue(address(client_));
    }
}
