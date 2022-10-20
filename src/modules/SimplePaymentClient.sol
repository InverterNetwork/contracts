// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies
import {Types} from "src/common/Types.sol";
import {Module} from "src/modules/base/Module.sol";
import {IPaymentClient} from "src/interfaces/IPaymentClient.sol";
import {IPaymentProcessor} from "src/interfaces/IPaymentProcessor.sol";

contract SimplePaymentClient is IPaymentClient, Module {
    PaymentOrder[] private paymentOrders;
    uint private paymentOrderCounter;

    /// @notice Returns the list of this module's payment orders.
    function getPaymentOrders() external view returns (PaymentOrder[] memory) {
        return paymentOrders;
    }

    /// @notice Returns the amount of existing payment orders
    function getPaymentOrderCount() external view returns (uint) {
        return paymentOrderCounter;
    }

    function __PaymentClient_addPaymentOrder(
        address _recipient,
        uint _amount,
        bytes32 _additionalData
    ) external onlyProposal {
        //get date
        uint _date = block.timestamp;
        // create hash.
        /// @dev Encoding the paymentCount with the address of this module should ensure ID uniqueness accross all modules managed by the same PaymentProcessor.
        bytes32 _id =
            keccak256(abi.encodePacked(paymentOrderCounter, address(this)));

        PaymentOrder memory _new = PaymentOrder({
            id: _id,
            amount: _amount,
            recipient: _recipient,
            date: _date,
            additionalData: _additionalData
        });

        paymentOrders.push(_new);
        paymentOrderCounter++;
    }

    function addPaymentOrder(
        address _recipient,
        uint _amount,
        bytes32 _additionalData
    ) external onlyAuthorized {
        _triggerProposalCallback(
            abi.encodeWithSignature(
                "__PaymentClient_addPaymentOrder(address, uint, bytes32)",
                _recipient,
                _amount,
                _additionalData
            ),
            Types.Operation.Call
        );
    }

    function addPaymentOrder(
        IPaymentProcessor _processor,
        address _recipient,
        uint _amount,
        bytes32 _additionalData
    ) external onlyAuthorized {
        // Since this is a simple paymentProcessor, we discard the first argument and inform the user.
        // TODO emit event

        _triggerProposalCallback(
            abi.encodeWithSignature(
                "__PaymentClient_addPaymentOrder(address, uint, bytes32)",
                _recipient,
                _amount,
                _additionalData
            ),
            Types.Operation.Call
        );
    }
}
