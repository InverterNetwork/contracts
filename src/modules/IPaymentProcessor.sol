// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import {IERC20} from "@oz/token/ERC20/IERC20.sol";

import {IPaymentClient} from "src/modules/mixins/IPaymentClient.sol";

interface IPaymentProcessor {
    /// @notice Processes all payments from an {IPaymentClient} instance.
    /// @dev It's up to the the implementation to keep up with what has been
    ///      paid out or not.
    /// @param client The {IPaymentClient} instance to process its to payments.
    function processPayments(IPaymentClient client) external;

    /// @notice Cancels all unfinished payments from an {IPaymentClient} instance.
    /// @dev It's up to the the implementation to keep up with what has been
    ///      paid out or not.
    /// @param client The {IPaymentClient} instance to process its to payments.
    function cancelRunningPayments(IPaymentClient client) external;

    /// @notice Returns the IERC20 token the payment processor can process.
    function token() external view returns (IERC20);
}
