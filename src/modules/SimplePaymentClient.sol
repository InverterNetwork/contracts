// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Dependencies
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Internal Dependencies
import {Types} from "src/common/Types.sol";
import {Module} from "src/modules/base/Module.sol";
import {PaymentClient} from "src/modules/PaymentClient.sol";

contract SimplePaymentClient is PaymentClient, Module {
    using SafeERC20 for IERC20;

    //--------------------------------------------------------------------------
    // Errors
    error __Module__PaymentClient_UnauthorizedProcessor(address _who);

    //--------------------------------------------------------------------------
    // Events

    event PaymentOrderAdded(
        address _recipient, uint _amount, bytes32 _additionalData
    );

    event PaymentOrdersCollected();

    //--------------------------------------------------------------------------
    // Modifiers

    modifier onlyPaymentProcessor() {
        if (_msgSender() != address(__Module_proposal.paymentProcessor())) {
            revert __Module__PaymentClient_UnauthorizedProcessor(_msgSender());
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Storage

    PaymentOrder[] private paymentOrders;
    uint private paymentOrderCounter;

    //--------------------------------------------------------------------------
    // Internal Functions

    /// @notice Adds an open Payment Order to the client, to be picked up by the paymentProcessor
    /// @dev    Implements the virtual function in the PaymentClient contract
    /// @dev    Relay Function that routes the function call via the proposal
    /// @param  _recipient  The recipient of the payment
    /// @param  _amount     The amount to be paid out
    /// @param  _additionalData Additional data to be stored alongside the rest
    function addPaymentOrder(
        address _recipient,
        uint _amount,
        bytes32 _additionalData
    ) internal override {
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

    //--------------------------------------------------------------------------
    // Public Functions

    /// @notice Adds an open Payment Order to the client, to be picked up by the paymentProcessor
    /// @param  _recipient  The recipient of the payment
    /// @param  _amount     The amount to be paid out
    /// @param  _additionalData Additional data to be stored alongside the rest
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

        emit PaymentOrderAdded(_recipient, _amount, _additionalData);
    }

    /// @notice Returns a list of this module's payment orders.
    function viewPaymentOrders()
        external
        view
        returns (PaymentOrder[] memory)
    {
        return paymentOrders;
    }

    /// @notice Returns the amount of existing payment orders
    function getPaymentOrderCount() external view returns (uint) {
        return paymentOrderCounter;
    }

    /// @notice Collects all outstanding payment orders and sends them to the PaymentProcessor, modifying internal state to mark them as completed.
    function collectPaymentOrders()
        external
        onlyPaymentProcessor
        returns (PaymentOrder[] memory)
    {
        /// @question: Doesn't the for loop below do the same as the example without copying? Using safeIncreaseAllowance, if something fails it should revert

        /// @question: Do we want to structure this function also with triggerProposalCallback etc ? It would basically force us to send the PaymentOrders[] around as bytes32  in the call returns and parse them again at the end...

        PaymentOrder[] memory processOrders = paymentOrders;

        // Cache payment token.
        IERC20 token = __Module_proposal.token();

        for (uint i; i < processOrders.length; i++) {
            token.safeIncreaseAllowance(_msgSender(), processOrders[i].amount);
        }

        delete paymentOrders;

        emit PaymentOrdersCollected();
        return processOrders;
    }
}
