// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IPaymentClient} from "src/interfaces/IPaymentClient.sol";

interface IPaymentProcessor {
    /// @notice Processes all the payments inside a PaymentClient Module.
    /// @dev    It's up to the the implementation to keep up with what has been
    ///         paid out or not.
    /// @param paymentClient A module that implements the PaymentClient Interface
    function processPayments(IPaymentClient paymentClient) external;
}
