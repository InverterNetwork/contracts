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

// External Dependencies
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

/**
 * @title   Inverter Payment Router
 *
 * @notice  This module enables pushing payments directly to the Payment Processor.
 *
 * @dev     Extends {ERC20PaymentClientBase_v1} to integrate payment processing with
 *          bounty management, supporting dynamic additions, updates, and the locking
 *          of bounties. Utilizes roles for managing permissions and maintaining robust
 *          control over bounty operations.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
 *
 * @author  Inverter Network
 */
contract LM_PC_PaymentRouter_v1 is
    ILM_PC_PaymentRouter_v1,
    ERC20PaymentClientBase_v1
{
    /// @inheritdoc ERC165Upgradeable
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

    /// @dev	The role that allows the pushing of payments.
    bytes32 public constant PAYMENT_PUSHER_ROLE = "PAYMENT_PUSHER";

    //--------------------------------------------------------------------------
    // Initializer
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata,
        bytes memory configData
    ) external override(Module_v1) initializer {
        __Module_init(orchestrator_, metadata);

        // Set the flags for the PaymentOrders
        uint8[] memory flags = new uint8[](3); // The Module will use 3 flags
        flags[0] = 1; // start, flag_ID 1
        flags[1] = 2; // cliff, flag_ID 2
        flags[2] = 3; // end, flag_ID 3

        __ERC20PaymentClientBase_v1_init(flags);
    }

    //--------------------------------------------------------------------------
    // Mutating Functions

    /// @inheritdoc ILM_PC_PaymentRouter_v1
    function pushPayment(
        address recipient,
        address paymentToken,
        uint amount,
        uint start,
        uint cliff,
        uint end
    ) public onlyModuleRole(PAYMENT_PUSHER_ROLE) {
        bytes32 flags;
        bytes32[] memory data;

        {
            bytes32[] memory paymentParameters = new bytes32[](3);
            paymentParameters[0] = bytes32(start);
            paymentParameters[1] = bytes32(cliff);
            paymentParameters[2] = bytes32(end);

            (flags, data) = _assemblePaymentConfig(paymentParameters);
        }

        PaymentOrder memory order = PaymentOrder({
            recipient: recipient,
            paymentToken: paymentToken,
            amount: amount,
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: flags,
            data: data
        });

        _addPaymentOrder(order);

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
        uint start,
        uint cliff,
        uint end
    ) public onlyModuleRole(PAYMENT_PUSHER_ROLE) {
        // Validate all arrays have the same length
        if (
            recipients.length != numOfOrders
                || paymentTokens.length != numOfOrders
                || amounts.length != numOfOrders
        ) {
            revert Module__LM_PC_PaymentRouter_v1__ArrayLengthMismatch();
        }

        bytes32 flags;
        bytes32[] memory data;

        {
            bytes32[] memory paymentParameters = new bytes32[](3);
            paymentParameters[0] = bytes32(start);
            paymentParameters[1] = bytes32(cliff);
            paymentParameters[2] = bytes32(end);

            (flags, data) = _assemblePaymentConfig(paymentParameters);
        }

        // Loop through the arrays and add Payments
        for (uint8 i = 0; i < numOfOrders; i++) {
            _addPaymentOrder(
                PaymentOrder({
                    recipient: recipients[i],
                    paymentToken: paymentTokens[i],
                    amount: amounts[i],
                    originChainId: block.chainid,
                    targetChainId: block.chainid,
                    flags: flags,
                    data: data
                })
            );
        }

        // call PaymentProcessor
        __Module_orchestrator.paymentProcessor().processPayments(
            IERC20PaymentClientBase_v1(address(this))
        );
    }
}
