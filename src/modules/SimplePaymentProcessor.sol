// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

// Internal Dependencies
import {
    IPaymentProcessor,
    IPaymentClient
} from "src/modules/IPaymentProcessor.sol";
import {Module} from "src/modules/base/Module.sol";

// Internal Interfaces
import {IProposal} from "src/proposal/IProposal.sol";

/**
 * @title SimplePaymentProcessor
 *
 * @dev The SimplePaymentProcessor is a module to process payment orders from other
 *      modules. In order to process a module's payment orders, the module must
 *      implement the {IPaymentClient} interface.
 *
 * @author byterocket
 */
contract SimplePaymentProcessor is Module, IPaymentProcessor {
    using SafeERC20 for IERC20;

    //--------------------------------------------------------------------------
    // Modifiers

    /// @notice checks that the caller is an active module
    modifier onlyModule() {
        if (!proposal().isModule(_msgSender())) {
            revert Module__PaymentManager__OnlyCallableByModule();
        }
        _;
    }

    /// @notice checks that the client is calling for itself
    modifier validClient(IPaymentClient client) {
        if (_msgSender() != address(client)) {
            revert Module__PaymentManager__CannotCallOnOtherClientsOrders();
        }
        _;
    }

    /// @inheritdoc Module
    function init(
        IProposal proposal_,
        Metadata memory metadata,
        bytes memory /*configdata*/
    ) external override(Module) initializer {
        __Module_init(proposal_, metadata);
    }

    //--------------------------------------------------------------------------
    // IPaymentProcessor Functions

    /// @inheritdoc IPaymentProcessor
    function token() public view returns (IERC20) {
        return __Module_proposal.token();
    }

    /// @inheritdoc IPaymentProcessor
    function processPayments(IPaymentClient client)
        external
        onlyModule
        validClient(client)
    {
        // Collect outstanding orders and their total token amount.
        IPaymentClient.PaymentOrder[] memory orders;
        uint totalAmount;
        (orders, totalAmount) = client.collectPaymentOrders();

        // Cache token.
        IERC20 token_ = token();

        // Transfer tokens from {IPaymentClient} to order recipients.
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

    function cancelRunningPayments(IPaymentClient client)
        external
        onlyModule
        validClient(client)
    {
        //Since we pay out on processing, this function does nothing
        return;
    }
}
