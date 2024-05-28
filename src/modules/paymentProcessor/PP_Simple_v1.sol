// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {
    IPaymentProcessor_v1,
    IERC20PaymentClientBase_v1
} from "src/modules/paymentProcessor/IPaymentProcessor_v1.sol";

// Internal Dependencies
import {Module_v1} from "src/modules/base/Module_v1.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

/**
 * @title   Simple Payment Processor
 *
 * @notice  Manages ERC20 payment processing for modules within the Inverter Network
 *          that are compliant with the {IERC20PaymentClientBase_v1} interface.
 *
 * @dev     Inherits {Module_v1} and implements {IPaymentProcessor_v1} to handle payment
 *          orders from registered modules, ensuring only eligible modules can initiate
 *          payments. Utilizes {SafeERC20} for secure token transfers.
 *
 * @author  Inverter Network
 */
contract PP_Simple_v1 is Module_v1, IPaymentProcessor_v1 {
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(Module_v1)
        returns (bool)
    {
        return interfaceId == type(IPaymentProcessor_v1).interfaceId
            || super.supportsInterface(interfaceId);
    }

    using SafeERC20 for IERC20;

    //--------------------------------------------------------------------------
    // Modifiers

    /// @notice checks that the caller is an active module
    modifier onlyModule() {
        if (!orchestrator().isModule(_msgSender())) {
            revert Module__PaymentProcessor__OnlyCallableByModule();
        }
        _;
    }

    /// @notice checks that the client is calling for itself
    modifier validClient(IERC20PaymentClientBase_v1 client) {
        if (_msgSender() != address(client)) {
            revert Module__PaymentProcessor__CannotCallOnOtherClientsOrders();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Storage

    // Gap for possible future upgrades
    uint[50] private __gap;

    /// @inheritdoc Module_v1
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata,
        bytes memory /*configData*/
    ) external override(Module_v1) initializer {
        __Module_init(orchestrator_, metadata);
    }

    //--------------------------------------------------------------------------
    // IPaymentProcessor_v1 Functions

    /// @inheritdoc IPaymentProcessor_v1
    function token() public view returns (IERC20) {
        return __Module_orchestrator.fundingManager().token();
    }

    /// @inheritdoc IPaymentProcessor_v1
    function processPayments(IERC20PaymentClientBase_v1 client)
        external
        onlyModule
        validClient(client)
    {
        // Collect outstanding orders and their total token amount.
        IERC20PaymentClientBase_v1.PaymentOrder[] memory orders;
        uint totalAmount;
        (orders, totalAmount) = client.collectPaymentOrders();

        //Make sure to let paymentClient know that amount doesnt have to be stored anymore
        client.amountPaid(totalAmount);

        // Cache token.
        IERC20 token_ = token();

        // Transfer tokens from {IERC20PaymentClientBase_v1} to order recipients.
        address recipient;
        uint amount;
        uint len = orders.length;
        for (uint i; i < len; ++i) {
            recipient = orders[i].recipient;
            amount = orders[i].amount;

            token_.safeTransferFrom(address(client), recipient, amount);

            emit TokensReleased(recipient, address(token_), amount);

            emit PaymentOrderProcessed(
                address(client),
                recipient,
                amount,
                orders[i].createdAt,
                orders[i].dueTo
            );
        }
    }

    function cancelRunningPayments(IERC20PaymentClientBase_v1 client)
        external
        view
        onlyModule
        validClient(client)
    {
        //Since we pay out on processing, this function does nothing
        return;
    }
}
