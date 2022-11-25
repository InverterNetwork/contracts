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
 * @title PaymentProcessor
 *
 * @dev The PaymentProcessor is a module to process payment orders from other
 *      modules. In order to process a module's payment orders, the module must
 *      implement the {IPaymentClient} interface.
 *
 * @author byterocket
 */
contract PaymentProcessor is Module, IPaymentProcessor {
    using SafeERC20 for IERC20;

    /// @inheritdoc Module
    function init(
        IProposal proposal_,
        Metadata memory metadata,
        bytes memory /*configdata*/
    ) external override (Module) initializer {
        __Module_init(proposal_, metadata);
    }

    //--------------------------------------------------------------------------
    // IPaymentProcessor Functions

    /// @inheritdoc IPaymentProcessor
    function token() public view returns (IERC20) {
        return __Module_proposal.token();
    }

    /// @inheritdoc IPaymentProcessor
    function processPayments(IPaymentClient client) external {
        // Collect outstanding orders and their total token amount.
        IPaymentClient.PaymentOrder[] memory orders;
        uint totalAmount;
        (orders, totalAmount) = client.collectPaymentOrders();

        // Cache token.
        IERC20 token = token();

        // Transfer tokens from {IPaymentClient} to order recipients.
        address recipient;
        uint amount;
        for (uint i; i < orders.length; i++) {
            recipient = orders[i].recipient;
            amount = orders[i].amount;

            token.safeTransferFrom(address(client), recipient, amount);
        }
    }
}
