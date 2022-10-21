// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies
import {IPaymentProcessor} from "src/interfaces/IPaymentProcessor.sol";

interface IPaymentClient {
    struct PaymentOrder {
        bytes32 id; // Unique ID based on hash
        uint amount;
        address recipient;
        uint date; // Creation timestamp
        bytes32 additionalData; // Additional info for stuff like streaming, vesting etc
    }

    /// @notice Returns the list outstanding payment orders.
    function viewPaymentOrders()
        external
        view
        returns (PaymentOrder[] memory);

    /// @notice Collects all outstanding payment orders, modifying internal state to mark them as completed.
    function collectPaymentOrders() external returns (PaymentOrder[] memory);
}
