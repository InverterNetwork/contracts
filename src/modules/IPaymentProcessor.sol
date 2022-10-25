// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IPaymentClient} from "src/modules/IPaymentClient.sol";

interface IPaymentProcessor {
    /// @notice Processes all payments from an {IPaymentClient} instance.
    /// @dev It's up to the the implementation to keep up with what has been
    ///      paid out or not.
    /// @param client The {IPaymentClient} instance to process its to payments.
    function processPayments(IPaymentClient client) external;
}
