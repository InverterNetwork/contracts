// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {
    IPaymentProcessor_v1,
    IERC20PaymentClientBase_v1
} from "src/modules/paymentProcessor/IPaymentProcessor_v1.sol";

// Internal Dependencies
import {Module_v1} from "src/modules/base/Module_v1.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

/**
 * @title   Simple Payment Processor
 *
 * @notice  Manages ERC20 payment processing for modules within the Inverter Network
 *          that are compliant with the {IERC20PaymentClientBase_v1} interface.
 *
 * @dev     Inherits {Module_v1} and implements {IPaymentProcessor_v1} to handle payment
 *          orders from registered modules, ensuring only eligible modules can initiate
 *          payments. Utilizes {SafeERC20} for secure token transfers.
 *
 * @author  Inverter Network
 */
contract PP_Simple_v1 is Module_v1, IPaymentProcessor_v1 {
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(Module_v1)
        returns (bool)
    {
        return interfaceId == type(IPaymentProcessor_v1).interfaceId
            || super.supportsInterface(interfaceId);
    }

    using SafeERC20 for IERC20;

    //--------------------------------------------------------------------------
    // Modifiers

    /// @notice checks that the caller is an active module
    modifier onlyModule() {
        if (!orchestrator().isModule(_msgSender())) {
            revert Module__PaymentProcessor__OnlyCallableByModule();
        }
        _;
    }

    /// @notice checks that the client is calling for itself
    modifier validClient(IERC20PaymentClientBase_v1 client) {
        if (_msgSender() != address(client)) {
            revert Module__PaymentProcessor__CannotCallOnOtherClientsOrders();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Storage

    /// @notice tracks all payments that could not be made to the paymentReceiver due to any reason
    /// @dev paymentClient => paymentReceiver => unclaimable Amount
    mapping(address => mapping(address => uint)) internal
        unclaimableAmountsForRecipient;

    // Gap for possible future upgrades
    uint[50] private __gap;

    //--------------------------------------------------------------------------
    // Initialization

    /// @inheritdoc Module_v1
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata,
        bytes memory /*configData*/
    ) external override(Module_v1) initializer {
        __Module_init(orchestrator_, metadata);
    }

    //--------------------------------------------------------------------------
    // IPaymentProcessor_v1 Functions

    /// @inheritdoc IPaymentProcessor_v1
    function token() public view returns (IERC20) {
        return __Module_orchestrator.fundingManager().token();
    }

    /// @inheritdoc IPaymentProcessor_v1
    function processPayments(IERC20PaymentClientBase_v1 client)
        external
        onlyModule
        validClient(client)
    {
        // Collect outstanding orders and their total token amount.
        IERC20PaymentClientBase_v1.PaymentOrder[] memory orders;

        (orders,) = client.collectPaymentOrders();

        // Cache token.
        address token_ = address(token());

        // Transfer tokens from {IERC20PaymentClientBase_v1} to order recipients.
        address recipient;
        uint amount;
        uint len = orders.length;
        for (uint i; i < len; ++i) {
            recipient = orders[i].recipient;
            amount = orders[i].amount;

            emit PaymentOrderProcessed(
                address(client),
                recipient,
                amount,
                orders[i].createdAt,
                orders[i].dueTo
            );

            (bool success, bytes memory data) = token_.call(
                abi.encodeWithSelector(
                    IERC20(token_).transferFrom.selector,
                    address(client),
                    recipient,
                    amount
                )
            );

            //If call was success
            if (success && (data.length == 0 || abi.decode(data, (bool)))) {
                emit TokensReleased(recipient, token_, amount);

                //Make sure to let paymentClient know that amount doesnt have to be stored anymore
                client.amountPaid(amount);
            } else {
                emit UnclaimableAmountAdded(address(client), recipient, amount);
                //Adds the walletId to the array of unclaimable wallet ids

                unclaimableAmountsForRecipient[address(client)][recipient] +=
                    amount;
            }
        }
    }

    function cancelRunningPayments(IERC20PaymentClientBase_v1 client)
        external
        view
        onlyModule
        validClient(client)
    {
        //Since we pay out on processing, this function does nothing
        return;
    }

    /// @inheritdoc IPaymentProcessor_v1
    function unclaimable(address client, address paymentReceiver)
        public
        view
        returns (uint amount)
    {
        return unclaimableAmountsForRecipient[client][paymentReceiver];
    }

    /// @inheritdoc IPaymentProcessor_v1
    function claimPreviouslyUnclaimable(address client, address receiver)
        external
    {
        if (unclaimable(client, _msgSender()) == 0) {
            revert Module__PaymentProcessor__NothingToClaim(
                client, _msgSender()
            );
        }

        _claimPreviouslyUnclaimable(client, receiver);
    }

    /// @notice used to claim the unclaimable amount of a particular paymentReceiver for a given payment client
    /// @param client address of the payment client
    /// @param paymentReceiver address of the paymentReceiver for which the unclaimable amount will be claimed
    function _claimPreviouslyUnclaimable(
        address client,
        address paymentReceiver
    ) internal {
        //get amount

        address sender = _msgSender();
        //copy value over
        uint amount = unclaimableAmountsForRecipient[client][sender];
        //Delete the field
        delete unclaimableAmountsForRecipient[client][sender];

        IERC20 _token = token();

        //Call has to succeed otherwise no state change
        _token.safeTransferFrom(client, paymentReceiver, amount);

        emit TokensReleased(paymentReceiver, address(_token), amount);

        //Make sure to let paymentClient know that amount doesnt have to be stored anymore
        IERC20PaymentClientBase_v1(client).amountPaid(amount);
    }
}
