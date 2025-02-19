// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

// External Imports
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {Module_v1} from "src/modules/base/Module_v1.sol";

// Internal Imports
import {CrossChainBase_v1} from
    "src/modules/paymentProcessor/abstracts/CrossChainBase_v1.sol";
import {ICrossChainBase_v1} from
    "src/modules/paymentProcessor/interfaces/ICrosschainBase_v1.sol";
import {IPP_Connext_Crosschain_v1} from
    "src/modules/paymentProcessor/interfaces/IPP_Connext_Crosschain_v1.sol";
import {IERC20PaymentClientBase_v2} from
    "@lm/interfaces/IERC20PaymentClientBase_v2.sol";
import {PP_Crosschain_v1} from
    "src/modules/paymentProcessor/abstracts/PP_Crosschain_v1.sol";
import {IWETH} from "src/modules/paymentProcessor/interfaces/IWETH.sol";
import {IEverclearSpoke} from
    "src/modules/paymentProcessor/interfaces/IEverclear.sol";
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";

/**
 * @title   Connext Cross-chain Payment Processor
 *
 * @notice  Specialized payment processor implementation for handling cross-chain payments via Connext protocol.
 *
 * @dev     This contract extends PP_Crosschain_v1 and provides:
 *          - Integration with Connext's EverClear protocol for secure cross-chain transfers
 *          - Native token handling through WETH wrapper
 *          - Robust payment order processing and validation
 *          - Failed transfer handling with retry and cancellation mechanisms
 *          - Bridge-specific transfer logic implementation
 *          - Support for Base network (chainId: 8453)
 *          - Comprehensive transfer state tracking
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
 *
 * @author  Inverter Network
 * @custom:version 1.0.0
 * @custom:standard-version 1.0.0
 */
contract PP_Connext_Crosschain_v1 is PP_Crosschain_v1 {
    // Storage Variables
    IEverclearSpoke public everClearSpoke;
    IWETH public weth;

    /// @dev Tracks all details for all payment orders of a paymentReceiver for a specific paymentClient.
    ///      paymentClient => paymentReceiver => paymentId => intentId.
    mapping(
        address paymentClient
            => mapping(
                address recipient => mapping(uint paymentId => bytes32 intentId)
            )
    ) public processedIntentId;

    /// @dev    Tracks all payments that could not be made to the paymentReceiver due to any reason.
    /// @dev	paymentClient => token address => paymentReceiver => unclaimable Amount.
    mapping(
        address paymentClient
            => mapping(
                address token => mapping(address recipient => uint amount)
            )
    ) internal unclaimableAmountsForRecipient;

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the payment processor module
     * @param orchestrator_ The orchestrator contract address
     * @param metadata Module metadata
     * @param configData ABI encoded configuration data (everClearSpoke and WETH addresses)
     */
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata,
        bytes memory configData
    ) external override(Module_v1) initializer {
        __Module_init(orchestrator_, metadata);
        (address everClearSpoke_, address weth_) =
            abi.decode(configData, (address, address));

        everClearSpoke = IEverclearSpoke(everClearSpoke_);
        weth = IWETH(weth_);
    }

    // External Mutating Functions
    /**
     * @notice Processes multiple payment orders through the bridge
     * @param client The payment client contract interface
     * @param executionData Additional data needed for execution (encoded maxFee and TTL)
     */
    function processPayments(
        IERC20PaymentClientBase_v2 client,
        bytes memory executionData
    ) external {
        IERC20PaymentClientBase_v2.PaymentOrder[] memory orders;
        (orders,,) = client.collectPaymentOrders();
        address clientAddress = address(client);
        for (uint i = 0; i < orders.length; i++) {
            bytes memory bridgeData =
                _executeBridgeTransfer(orders[i], executionData);

            if (bytes32(bridgeData) != bytes32(0)) {
                // Handle successful transfer
                _bridgeData[_paymentId] = bridgeData;
                emit PaymentOrderProcessed(
                    clientAddress,
                    orders[i].recipient,
                    orders[i].paymentToken,
                    orders[i].amount,
                    orders[i].originChainId,
                    orders[i].targetChainId,
                    orders[i].flags,
                    orders[i].data
                );
                _paymentId++;
                processedIntentId[address(client)][orders[i].recipient][_paymentId]
                = bytes32(bridgeData);
            } else {
                // Handle failed transfer
                unclaimableAmountsForRecipient[clientAddress][orders[i]
                    .paymentToken][orders[i].recipient] += orders[i].amount;
                emit TransferFailed(
                    clientAddress,
                    orders[i].recipient,
                    executionData,
                    orders[i].amount
                );
            }
            client.amountPaid(orders[i].paymentToken, orders[i].amount);
        }
    }

    /**
     * @notice Retries a previously failed transfer
     * @param client The payment client address
     * @param recipient The recipient address
     * @param order The payment order details
     * @param executionData Old execution data that failed
     * @param newExecutionData New execution data for retry
     */
    function retryFailedTransfer(
        address client,
        address recipient,
        bytes memory executionData,
        bytes memory newExecutionData,
        IERC20PaymentClientBase_v2.PaymentOrder memory order
    ) external validClient(client) {
        //unclaimable amount should not be 0 if the transfer has failed
        uint unclaimableAmount =
            unclaimable(client, order.paymentToken, recipient);
        if (unclaimableAmount == 0 || order.amount > unclaimableAmount) {
            revert Module__PP_Crosschain__InvalidUnclaimableAmount();
        }
        unclaimableAmountsForRecipient[client][order.paymentToken][recipient] -=
            order.amount;

        bytes32 newIntentId =
            _createCrossChainIntent(order, newExecutionData, false);
        if (newIntentId == bytes32(0)) {
            revert Module__PP_Crosschain__MessageDeliveryFailed(
                8453, 8453, executionData
            );
        }

        processedIntentId[client][recipient][_paymentId] = newIntentId;
    }

    // @notice Claim the unclaimable amount of a particular `paymentReceiver` for a given payment client.
    // @dev This function is used to claim the unclaimable amount of a particular `paymentReceiver` for a given payment client.
    // @param client address of the payment client.
    // @param token address of the payment token.
    // @param receiver address of the paymentReceiver for which the unclaimable amount will be claimed.
    function claimPreviouslyUnclaimable(
        address client,
        address token,
        address receiver
    ) external virtual override {
        if (unclaimable(client, token, _msgSender()) == 0) {
            revert Module__PaymentProcessor__NothingToClaim(
                client, _msgSender()
            );
        }

        _claimPreviouslyUnclaimable(client, token, receiver);
    }

    // View Functions
    /**
     * @notice Retrieves the bridge data for a specific payment ID
     * @param paymentId The unique identifier of the payment
     * @return The bridge data associated with the payment
     */
    function getBridgeData(uint paymentId)
        public
        view
        override
        returns (bytes memory)
    {
        return _bridgeData[paymentId];
    }

    // @notice Returns the unclaimable amount of a particular `paymentReceiver` for a given payment client.
    // @dev This function is used to return the unclaimable amount of a particular `paymentReceiver` for a given payment client.
    // @param client address of the payment client.
    // @param token address of the payment token.
    // @param paymentReceiver address of the paymentReceiver for which the unclaimable amount will be returned.
    function unclaimable(address client, address token, address paymentReceiver)
        public
        view
        virtual
        override
        returns (uint amount)
    {
        return unclaimableAmountsForRecipient[client][token][paymentReceiver];
    }
    // Overridden Internal Functions

    /// @notice used to claim the unclaimable amount of a particular `paymentReceiver` for a given payment client.
    /// @param  client address of the payment client.
    /// @param  token address of the payment token.
    /// @param  paymentReceiver address of the paymentReceiver for which the unclaimable amount will be claimed.
    function _claimPreviouslyUnclaimable(
        address client,
        address token,
        address paymentReceiver
    ) internal {
        address sender = _msgSender();
        uint amount = unclaimableAmountsForRecipient[client][token][sender];
        delete unclaimableAmountsForRecipient[client][token][sender];

        IERC20(token).transfer(paymentReceiver, amount);
        emit TokensReleased(paymentReceiver, address(token), amount);
    }

    /**
     * @dev Execute the cross-chain bridge transfer
     * @param order The payment order containing transfer details
     * @param executionData Additional execution parameters
     * @return bridgeData Data returned by the bridge implementation
     */
    function _executeBridgeTransfer(
        IERC20PaymentClientBase_v2.PaymentOrder memory order,
        bytes memory executionData
    ) internal override returns (bytes memory) {
        bytes32 _intentId = _createCrossChainIntent(order, executionData, true);
        return abi.encode(_intentId);
    }

    // Internal Helper Functions
    /**
     * @dev Creates a new cross-chain intent for payment transfer
     * @param order The payment order details
     * @param executionData Additional execution parameters
     * @param transferFromRecipient Whether to transfer from the recipient
     * @return The ID of the created intent
     */
    function _createCrossChainIntent(
        IERC20PaymentClientBase_v2.PaymentOrder memory order,
        bytes memory executionData,
        bool transferFromRecipient
    ) internal returns (bytes32) {
        _validateOrder(order);

        if (executionData.length == 0) {
            revert
                ICrossChainBase_v1
                .Module__CrossChainBase_InvalidExecutionData();
        }
        (uint maxFee, uint ttl) = abi.decode(executionData, (uint, uint));
        if (ttl == 0) {
            revert
                IPP_Connext_Crosschain_v1
                .Module__PP_Connext_Crosschain__InvalidTTL();
        }
        if (transferFromRecipient) {
            IERC20(order.paymentToken).transferFrom(
                order.recipient, address(this), order.amount
            );
            IERC20(order.paymentToken).approve(
                address(everClearSpoke), order.amount
            );
        }

        uint32[] memory destinations = new uint32[](1);
        destinations[0] = 8453;

        return everClearSpoke.newIntent(
            destinations,
            order.recipient,
            order.paymentToken,
            address(weth),
            order.amount,
            uint24(maxFee),
            uint48(ttl),
            ""
        );
    }

    /**
     * @dev Validates a payment order
     * @param order The payment order to validate
     */
    function _validateOrder(
        IERC20PaymentClientBase_v2.PaymentOrder memory order
    ) internal pure {
        if (order.amount == 0) {
            revert ICrossChainBase_v1.Module__CrossChainBase__InvalidAmount();
        }
        if (order.recipient == address(0)) {
            revert ICrossChainBase_v1.Module__CrossChainBase__InvalidRecipient();
        }
    }
}
