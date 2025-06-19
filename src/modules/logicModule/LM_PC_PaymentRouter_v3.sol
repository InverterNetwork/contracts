// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IOrchestrator_v2} from
    "src/orchestrator/interfaces/IOrchestrator_v2.sol";
import {IAuthorizer_v2} from "@aut/IAuthorizer_v2.sol";
import {ILM_PC_PaymentRouter_v3} from
    "@lm/interfaces/ILM_PC_PaymentRouter_v3.sol";
import {
    IERC20PaymentClientBase_v3,
    IPaymentProcessor_v3
} from "@lm/abstracts/ERC20PaymentClientBase_v3.sol";

// Internal Dependencies
import {
    ERC20PaymentClientBase_v3,
    Module_v2
} from "@lm/abstracts/ERC20PaymentClientBase_v3.sol";

// External Dependencies
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

/**
 * @title   Inverter Payment Router
 *
 * @notice  This module enables pushing payments directly to the Payment Processor.
 *
 * @dev     Extends {ERC20PaymentClientBase_v3} to integrate payment processing with
 *          bounty management, supporting dynamic additions, updates, and the locking
 *          of bounties. Utilizes roles for managing permissions and maintaining robust
 *          control over bounty operations.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
 *
 * @custom:version  v3.0.0
 *
 * @author  Inverter Network
 */
contract LM_PC_PaymentRouter_v3 is
    ILM_PC_PaymentRouter_v3,
    ERC20PaymentClientBase_v3
{
    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC20PaymentClientBase_v3)
        returns (bool)
    {
        return interfaceId == type(ILM_PC_PaymentRouter_v3).interfaceId
            || super.supportsInterface(interfaceId);
    }

    //--------------------------------------------------------------------------
    // Storage

    uint8 public constant FLAG_START = 1;
    uint8 public constant FLAG_CLIFF = 2;
    uint8 public constant FLAG_END = 3;

    //--------------------------------------------------------------------------
    // Initializer
    function init(
        IOrchestrator_v2 orchestrator_,
        Metadata memory metadata,
        bytes memory /* configData */
    ) external virtual override(Module_v2) initializer {
        __Module_init(orchestrator_, metadata);

        // Set the flags for the PaymentOrders (this module uses 3 flags).
        bytes32 flags;
        flags |= bytes32(1 << FLAG_START);
        flags |= bytes32(1 << FLAG_CLIFF);
        flags |= bytes32(1 << FLAG_END);

        __ERC20PaymentClientBase_v3_init(flags);
    }

    //--------------------------------------------------------------------------
    // Mutating Functions

    /// @inheritdoc ILM_PC_PaymentRouter_v3
    function pushPayment(
        address recipient,
        address paymentToken,
        uint amount,
        uint start,
        uint cliff,
        uint end
    ) public permissioned {
        bytes32 flags;
        bytes32[] memory data;

        {
            bytes32[] memory paymentParameters = new bytes32[](3);
            paymentParameters[0] = bytes32(start == 0 ? block.timestamp : start);
            paymentParameters[1] = bytes32(cliff);
            paymentParameters[2] = bytes32(end == 0 ? block.timestamp : end);

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
            IERC20PaymentClientBase_v3(address(this))
        );
    }

    /// @inheritdoc ILM_PC_PaymentRouter_v3
    function pushPaymentBatched(
        uint8 numOfOrders,
        address[] calldata recipients,
        address[] calldata paymentTokens,
        uint[] calldata amounts,
        uint start,
        uint cliff,
        uint end
    ) public permissioned {
        // Validate all arrays have the same length
        if (
            recipients.length != numOfOrders
                || paymentTokens.length != numOfOrders
                || amounts.length != numOfOrders
        ) {
            revert Module__LM_PC_PaymentRouter_v3__ArrayLengthMismatch();
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
            IERC20PaymentClientBase_v3(address(this))
        );
    }
}
