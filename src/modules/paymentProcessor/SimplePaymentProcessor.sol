// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

// Internal Dependencies
import {
    IPaymentProcessor,
    IERC20PaymentClient
} from "src/modules/paymentProcessor/IPaymentProcessor.sol";
import {Module} from "src/modules/base/Module.sol";

// Internal Interfaces
import {IOrchestrator} from "src/orchestrator/IOrchestrator.sol";

/**
 * @title SimplePaymentProcessor
 *
 * @dev The SimplePaymentProcessor is a module to process payment orders from other
 *      modules. In order to process a module's payment orders, the module must
 *      implement the {IERC20PaymentClient} interface.
 *
 * @author Inverter Network
 */
contract SimplePaymentProcessor is Module, IPaymentProcessor {
    using SafeERC20 for IERC20;

    //--------------------------------------------------------------------------
    // Modifiers

    /// @notice checks that the caller is an active module
    modifier onlyModule() {
        if (!orchestrator().isModule(_msgSender())) {
            revert Module__PaymentManager__OnlyCallableByModule();
        }
        _;
    }

    /// @notice checks that the client is calling for itself
    modifier validClient(IERC20PaymentClient client) {
        if (_msgSender() != address(client)) {
            revert Module__PaymentManager__CannotCallOnOtherClientsOrders();
        }
        _;
    }

    /// @inheritdoc Module
    function init(
        IOrchestrator orchestrator_,
        Metadata memory metadata,
        bytes memory /*configdata*/
    ) external override(Module) initializer {
        __Module_init(orchestrator_, metadata);
    }

    //--------------------------------------------------------------------------
    // IPaymentProcessor Functions

    /// @inheritdoc IPaymentProcessor
    function token() public view returns (IERC20) {
        return __Module_orchestrator.token();
    }

    /// @inheritdoc IPaymentProcessor
    function processPayments(IERC20PaymentClient client)
        external
        onlyModule
        validClient(client)
    {
        // Collect outstanding orders and their total token amount.
        IERC20PaymentClient.PaymentOrder[] memory orders;
        uint totalAmount;
        (orders, totalAmount) = client.collectPaymentOrders();

        // Cache token.
        IERC20 token_ = token();

        // Transfer tokens from {IERC20PaymentClient} to order recipients.
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

    function cancelRunningPayments(IERC20PaymentClient client)
        external
        onlyModule
        validClient(client)
    {
        //Since we pay out on processing, this function does nothing
        return;
    }
}
