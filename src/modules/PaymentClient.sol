// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies
import {IPaymentClient} from "src/modules/IPaymentClient.sol";

abstract contract PaymentClient is IPaymentClient {
    /// @notice Adds an open Payment Order to the client, to be picked up by the paymentProcessor
    /// @param  _recipient  The recipient of the payment
    /// @param  _amount     The amount to be paid out
    /// @param  _additionalData Additional data to be stored alongside the rest
    function addPaymentOrder(
        address _recipient,
        uint _amount,
        bytes32 _additionalData
    ) internal virtual;
}
