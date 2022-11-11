// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

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

contract PaymentProcessor is Module, IPaymentProcessor {
    using SafeERC20 for IERC20;

    /// @dev The payment token.
    /// @dev Cache to save multiple `__Module_proposal.token()` calls.
    IERC20 internal _token;

    /// @inheritdoc Module
    function init(
        IProposal proposal_,
        Metadata memory metadata,
        bytes memory /*configdata*/
    ) external override(Module) initializer {
        __Module_init(proposal_, metadata);

        // Cache the proposal's token.
        _token = proposal_.token();
    }

    //--------------------------------------------------------------------------
    // State

    /// @inheritdoc IPaymentProcessor
    function processPayments(IPaymentClient client) external {
        // Collect outstanding orders and their total token amount.
        IPaymentClient.PaymentOrder[] memory orders;
        uint totalAmount;
        (orders, totalAmount) = client.collectPaymentOrders();

        // Transfer tokens from {IPaymentClient} to order recipients.
        address recipient;
        uint amount;
        for (uint i; i < orders.length; i++) {
            recipient = orders[i].recipient;
            amount = orders[i].amount;

            _token.safeTransferFrom(address(client), recipient, amount);
        }
    }
}
