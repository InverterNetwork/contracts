// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Dependencies
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IPaymentProcessor_v1} from "@pp/IPaymentProcessor_v1.sol";
import {IERC20PaymentClientBase_v1} from
    "@lm/interfaces/IERC20PaymentClientBase_v1.sol";
import {IPP_Template_v1} from "./IPP_Template_v1.sol";
import {ERC165Upgradeable, Module_v1} from "src/modules/base/Module_v1.sol";

// External Dependencies
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

/**
 * @title   Inverter Template Payment Processor
 *
 * @notice  Basic template payment processor used as base for developing new payment processors.
 *
 * @dev     This contract is used to showcase a basic setup for a payment processor. The contract showcases the
 *          following:
 *          - Inherit from the Module_v1 contract to enable interaction with the Inverter workflow.
 *          - Use of the IPaymentProcessor_v1 interface to facilitate interaction with a payment client.
 *          - Implement custom interface which has all the public facing functions, errors, events and structs.
 *          - Pre-defined layout for all contract functions, modifiers, state variables etc.
 *          - Use of the ERC165Upgradeable contract to check for interface support.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
 *
 * @author  Inverter Network
 */
contract PP_Template_v1 is IPP_Template_v1, IPaymentProcessor_v1, Module_v1 {
    //--------------------------------------------------------------------------
    // Libraries

    // Add library usage here

    //--------------------------------------------------------------------------
    // ERC165

    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId_)
        public
        view
        virtual
        override(Module_v1)
        returns (bool)
    {
        return interfaceId_ == type(IPP_Template_v1).interfaceId
            || interfaceId_ == type(IPaymentProcessor_v1).interfaceId
            || super.supportsInterface(interfaceId_);
    }

    //--------------------------------------------------------------------------
    // Constants

    // Add constants here

    //--------------------------------------------------------------------------
    // State

    /// @dev    Payout amount multiplier.
    uint internal _payoutAmountMultiplier;

    /// @dev    The number of payment orders.
    uint internal _paymentId;

    //--------------------------------------------------------------------------
    // Modifiers

    /// @dev    Checks that the client is calling for itself.
    modifier validClient(address client_) {
        // modifier logic moved to internal function for contract size reduction
        _validClientModifier(client_);
        _;
    }

    //--------------------------------------------------------------------------
    // Constructor & Init

    /// @inheritdoc Module_v1
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata,
        bytes memory configData
    ) external override(Module_v1) initializer {
        __Module_init(orchestrator_, metadata);

        // Decode module specific init data through use of configData bytes. This value is an example value used to
        // showcase the setters/getters and internal functions/state formating style.
        (uint payoutAmountMultiplier_) = abi.decode(configData, (uint));

        // Set init state.
        _setPayoutAmountMultiplier(payoutAmountMultiplier_);
    }

    //--------------------------------------------------------------------------
    // Public (Getters)

    /// @inheritdoc IPP_Template_v1
    function getPayoutAmountMultiplier()
        external
        view
        returns (uint payoutAmount_)
    {
        return _payoutAmountMultiplier;
    }

    //--------------------------------------------------------------------------
    // Public (Mutation)

    /// @inheritdoc IPaymentProcessor_v1
    function processPayments(IERC20PaymentClientBase_v1 client_)
        external
        validClient(address(client_))
    {
        // The IERC20PaymentClientBase_v1 client should be used to access created payment orders
        // in the Logic Module (LM) implementing the interface. The interface should be referenced to see the different
        // functionalities provided by the ERC20PaymentClientBase_v1.

        // Collect orders from the client
        IERC20PaymentClientBase_v1.PaymentOrder[] memory orders;
        (orders,,) = client_.collectPaymentOrders();

        // Custom logic to proces the payment orders should be implemented below. This template implements
        // a straight forward token transfer using the first order of the payment order array for simplicity.

        // Get payment order details
        address recipient = orders[0].recipient;
        address token_ = orders[0].paymentToken;
        uint amount_ = orders[0].amount * _payoutAmountMultiplier;
        _paymentId = _paymentId + 1;

        // Emit event of the IPaymentProcessor_v1. This is used by Inverter's indexer
        emit PaymentOrderProcessed(
            address(client_),
            orders[0].recipient,
            orders[0].paymentToken,
            amount_,
            0,
            0,
            0
        );

        // Transfer tokens from {IERC20PaymentClientBase_v1} to order recipients.
        // Please note, when processing multiple payment orders then letting the call revert as in this example
        // might not be the best solution. Ways to handle this by implementing the `unclaimable` function can be
        // found in the other Payment Processor (PP) implementations.
        IERC20(token_).transferFrom(address(client_), recipient, amount_);

        // Inform the client about the amount that was released, to keep
        //      the accounting correct.
        client_.amountPaid(token_, amount_);

        // Emit event of the IPaymentProcessor_v1. This is used by Inverter's indexer
        emit TokensReleased(recipient, token_, amount_);
    }

    /// @inheritdoc IPaymentProcessor_v1
    function cancelRunningPayments(IERC20PaymentClientBase_v1 client_)
        external
        view
        validClient(address(client_))
    {
        // This function is used to implement custom logic to cancel running payments. If the nature of
        // processing payments is one of direct processing then this function can be left empty, return nothing.
        return;
    }

    /// @inheritdoc IPaymentProcessor_v1
    function unclaimable(
        address, /*client_*/
        address, /*token_*/
        address /*paymentReceiver_*/
    ) external pure returns (uint amount_) {
        // This function is used to check if there are unclaimable tokens for a specific client, token and payment
        // receiver. As this template only executes one payment order at a time, this function is not utilzed and can
        // return 0.
        return 0;
    }

    /// @inheritdoc IPaymentProcessor_v1
    function claimPreviouslyUnclaimable(
        address, /*client_*/
        address, /*token_*/
        address /*receiver_*/
    ) external pure {
        return;
    }

    /// @inheritdoc IPaymentProcessor_v1
    function validPaymentOrder(
        IERC20PaymentClientBase_v1.PaymentOrder memory order_
    ) external view returns (bool) {
        // This function is used to validate the payment order created on the client side (LM) with the input required by the
        // Payment Processor (PP). The function should return true if the payment order is valid and false if it is not.

        // For this template, only the receiver is validated.
        return _validPaymentReceiver(order_.recipient);
    }

    //--------------------------------------------------------------------------
    // Internal

    /// @dev Internal function to set the new payout amount multiplier.
    /// @param newPayoutAmountMultiplier_ Payout amount multiplier to be set in the state. Cannot be zero.
    function _setPayoutAmountMultiplier(uint newPayoutAmountMultiplier_)
        internal
    {
        if (newPayoutAmountMultiplier_ == 0) {
            revert Module__PP_Template_InvalidAmount();
        }
        emit NewPayoutAmountMultiplierSet(
            _payoutAmountMultiplier, newPayoutAmountMultiplier_
        );
        _payoutAmountMultiplier = newPayoutAmountMultiplier_;
    }

    /// @dev    Validate address input.
    /// @param  addr_ Address to validate.
    /// @return True if address is valid.
    function _validPaymentReceiver(address addr_)
        internal
        view
        returns (bool)
    {
        return !(
            addr_ == address(0) || addr_ == _msgSender()
                || addr_ == address(this) || addr_ == address(orchestrator())
                || addr_ == address(orchestrator().fundingManager().token())
        );
    }

    function _validClientModifier(address client_) internal view {
        if (_msgSender() != client_) {
            revert Module__PP_Template__NotValidClient();
        }
    }

    //--------------------------------------------------------------------------
    // Internal override
}
