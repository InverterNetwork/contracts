// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Interfaces
import {IERC20PaymentClientBase_v1} from
    "@lm/interfaces/IERC20PaymentClientBase_v1.sol";
import {IPaymentProcessor_v1} from
    "src/modules/paymentProcessor/IPaymentProcessor_v1.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

interface IPP_Simple_v1 is IPaymentProcessor_v1 {
    //--------------------------------------------------------------------------
    // Events

    /// @notice Emitted when a payment gets processed for execution.
    /// @param  paymentClient The payment client that originated the order.
    /// @param  recipient The address that will receive the payment.
    /// @param  paymentToken The address of the token that is being used for the payment.
    /// @param  amount The amount of tokens the payment consists of.
    event PaymentOrderAdded(
        address indexed paymentClient,
        address indexed recipient,
        address indexed paymentToken,
        uint amount
    );
}
