// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IPaymentProcessor_v1} from "@pp/IPaymentProcessor_v1.sol";
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
 *              - PP_Queue_v1.
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
            || interfaceId_ == type(IPaymentProcessor_v1).interfaceId
            || super.supportsInterface(interfaceId_);
    }

    // -------------------------------------------------------------------------
    // Public

    /// @inheritdoc IPaymentProcessor_v1
    function processPayments(IERC20PaymentClientBase_v2 client_)
        external
        virtual
        override(PP_Queue_v1, IPaymentProcessor_v1)
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
        clientIsValid(address(client_))
        onlyModule
    {
        _executePaymentQueue(address(client_));
    }

    /// @dev    Gap for possible future upgrades.
    uint[50] private __gap;
}
