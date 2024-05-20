// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IAuthorizer_v1} from "@aut/IAuthorizer_v1.sol";
import {ILM_PC_PaymentRouter_v1} from
    "@lm/interfaces/ILM_PC_PaymentRouter_v1.sol";
import {
    IERC20PaymentClientBase_v1,
    IPaymentProcessor_v1
} from "@lm/abstracts/ERC20PaymentClientBase_v1.sol";

// Internal Dependencies
import {
    ERC20PaymentClientBase_v1,
    Module_v1
} from "@lm/abstracts/ERC20PaymentClientBase_v1.sol";

// Internal Libraries

// External Libraries

// NOTE: Development halted until the payment processor can handle multiple tokens,  and not only the native orchestrator one

/**
 * @title   Payment Router
 *
 * @notice  Tis module is a stopgap solution to enable pushing payments to the Payment Processor.
 *
 *
 * @dev     Extends {ERC20PaymentClientBase_v1} to integrate payment processing with
 *          bounty management, supporting dynamic additions, updates, and the locking
 *          of bounties. Utilizes roles for managing permissions and maintaining robust
 *          control over bounty operations.
 *
 * @author  Inverter Network
 */
contract LM_PC_PaymentRouter_v1 is
    ILM_PC_PaymentRouter_v1,
    ERC20PaymentClientBase_v1
{
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC20PaymentClientBase_v1)
        returns (bool)
    {
        return interfaceId == type(ILM_PC_PaymentRouter_v1).interfaceId
            || super.supportsInterface(interfaceId);
    }

    //--------------------------------------------------------------------------
    // Storage

    // Payment Pusher Role
    bytes32 public constant PAYMENT_PUSHER_ROLE = "PAYMENT_PUSHER";

    /// @inheritdoc ILM_PC_PaymentRouter_v1
    function pushPayment(
        address recipient,
        address paymentToken,
        uint amount,
        uint dueTo
    ) public onlyModuleRole(PAYMENT_PUSHER_ROLE) {
        _addPaymentOrder(
            PaymentOrder(
                recipient, paymentToken, amount, block.timestamp, dueTo
            )
        );

        // call PaymentProcessor
        __Module_orchestrator.paymentProcessor().processPayments(
            IERC20PaymentClientBase_v1(address(this))
        );
    }

    /// @inheritdoc ILM_PC_PaymentRouter_v1
    function pushPaymentBatched(
        uint8 numOfOrders,
        address[] calldata recipients,
        address[] calldata paymentTokens,
        uint[] calldata amounts,
        uint[] calldata dueTos
    ) public onlyModuleRole(PAYMENT_PUSHER_ROLE) {
        // Validate all arrays have the same length
        if (
            recipients.length != numOfOrders
                || paymentTokens.length != numOfOrders
                || amounts.length != numOfOrders || dueTos.length != numOfOrders
        ) {
            revert Module__ERC20PaymentClientBase__ArrayLengthMismatch();
        }

        // Loop through the arrays and add Payments
        for (uint8 i = 0; i < numOfOrders; i++) {
            _addPaymentOrder(
                PaymentOrder(
                    recipients[i],
                    paymentTokens[i],
                    amounts[i],
                    block.timestamp,
                    dueTos[i]
                )
            );
        }

        // call PaymentProcessor
        __Module_orchestrator.paymentProcessor().processPayments(
            IERC20PaymentClientBase_v1(address(this))
        );
    }
}
