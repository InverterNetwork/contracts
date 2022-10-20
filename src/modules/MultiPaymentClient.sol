// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies
import {Types} from "src/common/Types.sol";
import {Module} from "src/modules/base/Module.sol";
import {IPaymentClient} from "src/interfaces/IPaymentClient.sol";
import {IPaymentProcessor} from "src/interfaces/IPaymentProcessor.sol";

contract MultiPaymentClient is IPaymentClient, Module {
    mapping(address => PaymentOrder[]) private paymentOrders;
    /// @dev tracks the number of PaymentOrders across ALL processors
    uint private paymentOrderCounter;

    /// @notice Returns the list of this payment orders assigned to the caller
    function getPaymentOrders() external view returns (PaymentOrder[] memory) {
        return paymentOrders[_msgSender()];
    }

    /// @notice Returns the list of this payment orders assigned to a specific payment Processor
    function viewPaymentOrders(IPaymentProcessor _who)
        external
        view
        returns (PaymentOrder[] memory)
    {
        return paymentOrders[address(_who)];
    }

    /// @notice Returns the total amount of existing payment orders
    function getPaymentOrderCount() external view returns (uint) {
        return paymentOrderCounter;
    }

    function __MultiPaymentClient_addPaymentOrder(
        address _paymentProcessor,
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

        paymentOrders[_paymentProcessor].push(_new);
        paymentOrderCounter++;
    }

    function addPaymentOrder(
        address _recipient,
        uint _amount,
        bytes32 _additionalData
    ) external onlyAuthorized {
        // if we don't receive a specific processor, we use the default IPayer from the proposal
        // @question: maybe it's better to just declare a default processor on initialization? This way we don't have to inherit Module
        address _processor = address(__Module_proposal.payer);

        _triggerProposalCallback(
            abi.encodeWithSignature(
                "__MultiPaymentClient_addPaymentOrder(address,address, uint, bytes32)",
                _processor,
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
        _triggerProposalCallback(
            abi.encodeWithSignature(
                "__MultiPaymentClient_addPaymentOrder(address,address, uint, bytes32)",
                address(_processor),
                _recipient,
                _amount,
                _additionalData
            ),
            Types.Operation.Call
        );
    }
}
