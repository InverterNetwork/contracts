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

    /// @notice Returns the list of this module's payment orders.
    function getPaymentOrders() external view returns (PaymentOrder[] memory);

    /// @notice Adds a payment order to the client using the proposal's default payment processor
    function addPaymentOrder(
        address _recipient,
        uint _amount,
        bytes32 _additionalData
    ) external;

    /// @notice Adds a payment order to the client, specifying which processor should handle payout
    function addPaymentOrder(
        IPaymentProcessor assignedPaymentProcessor,
        address _recipient,
        uint _amount,
        bytes32 _additionalData
    ) external;
}
