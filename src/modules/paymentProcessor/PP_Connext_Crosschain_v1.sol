// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

// External Imports
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {Module_v1} from "src/modules/base/Module_v1.sol";

// Internal Imports
import {IPaymentProcessor_v1} from "@pp/IPaymentProcessor_v1.sol";
import {CrossChainBase_v1} from "@pp/abstracts/CrossChainBase_v1.sol";
import {ICrossChainBase_v1} from "@pp/interfaces/ICrosschainBase_v1.sol";
import {IPP_Connext_Crosschain_v1} from
    "@pp/interfaces/IPP_Connext_Crosschain_v1.sol";
import {IERC20PaymentClientBase_v2} from
    "@lm/interfaces/IERC20PaymentClientBase_v2.sol";
import {PP_Crosschain_v1} from "@pp/abstracts/PP_Crosschain_v1.sol";
import {IWETH} from "@pp/interfaces/IWETH.sol";
import {IEverclearSpoke} from "@pp/interfaces/IEverclear.sol";
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
 *
 * @custom:version 1.0.0
 *
 * @custom:standard-version 1.0.0
 */
contract PP_Connext_Crosschain_v1 is
    IPP_Connext_Crosschain_v1,
    PP_Crosschain_v1
{
    // -------------------------------------------------------------------------
    // Constants

    /// @notice Payment order flag for the Everclear max fee.
    uint8 private constant FLAG_MAX_FEE = 4;
    /// @notice Payment order flag for the Everclear TTL.
    uint8 private constant FLAG_TTL = 5;

    // -------------------------------------------------------------------------
    // State Variables

    /// @notice The Everclear spoke contract address.
    IEverclearSpoke internal _everClearSpoke;
    /// @notice The WETH contract address.
    IWETH internal _weth;

    /// @notice Tracks all details for all payment orders of a paymentReceiver for a specific paymentClient.
    /// @dev    paymentClient => paymentReceiver => paymentId => intentId.
    mapping(
        address paymentClient
            => mapping(
                address recipient => mapping(uint paymentId => bytes32 intentId)
            )
    ) internal _processedIntentId;

    // -------------------------------------------------------------------------
    // Initialization Function

    /**
     * @notice Initializes the payment processor module
     * @param orchestrator_ The orchestrator contract address
     * @param metadata Module metadata
     * @param configData ABI encoded configuration data (_everClearSpoke and WETH addresses)
     */
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata,
        bytes memory configData
    ) external override(Module_v1) initializer {
        __Module_init(orchestrator_, metadata);
        (address everClearSpoke_, address weth_) =
            abi.decode(configData, (address, address));

        _everClearSpoke = IEverclearSpoke(everClearSpoke_);
        _weth = IWETH(weth_);
    }

    // -------------------------------------------------------------------------
    // View Functions

    /// @inheritdoc IPP_Connext_Crosschain_v1
    function getEverClearSpoke() external view returns (IEverclearSpoke) {
        return _everClearSpoke;
    }

    /// @inheritdoc IPP_Connext_Crosschain_v1
    function getWeth() external view returns (IWETH) {
        return _weth;
    }

    /// @inheritdoc IPP_Connext_Crosschain_v1
    function getProcessedIntentId(
        address paymentClient,
        address recipient,
        uint paymentId
    ) external view returns (bytes32) {
        return _processedIntentId[paymentClient][recipient][paymentId];
    }

    /// @inheritdoc ICrossChainBase_v1
    function getBridgeData(uint paymentId)
        public
        view
        override(CrossChainBase_v1)
        returns (bytes memory)
    {
        return _bridgeData[paymentId]; // @note how is this different than the mapping in the getter above?
    }

    // -------------------------------------------------------------------------
    // External Functions

    /// @inheritdoc IPaymentProcessor_v1
    function processPayments(IERC20PaymentClientBase_v2 client) external {
        // Get the payment orders from the payment client.
        IERC20PaymentClientBase_v2.PaymentOrder[] memory orders;
        (orders,,) = client.collectPaymentOrders();

        // Process each payment order.
        for (uint i = 0; i < orders.length; i++) {
            if (!_validPaymentOrder(orders[i])) {
                revert
                    IERC20PaymentClientBase_v2
                    .Module__ERC20PaymentClientBase__InvalidPaymentOrder();
            }
            // Transfer the token for the order from the payment client into
            // the payment processor.
            _transferTokenAndApproveToBridge(orders[i], address(client));
            // Execute the bridge transfer.
            bytes memory bridgeData = _executeBridgeTransfer(orders[i]);
            // Bridge data in the Everclear implementation is the intent ID.

            // If a non-zero intent ID is returned.
            if (bytes32(bridgeData) != bytes32(0)) {
                // Store intent ID in the bridge data.
                _bridgeData[_paymentId] = bridgeData;

                // Emit the Payment Processor's PaymentOrderProcessed event.
                emit PaymentOrderProcessed(
                    address(client),
                    orders[i].recipient,
                    orders[i].paymentToken,
                    orders[i].amount,
                    orders[i].originChainId,
                    orders[i].targetChainId,
                    orders[i].flags,
                    orders[i].data
                );
                // @note how does the end user know the payment ID if needed to retrive the intendId later?
                // @note Also why increment here, but using the value below again to store the intent ID?
                _paymentId++;

                // Store the intent ID for the payment order.
                _processedIntentId[address(client)][orders[i].recipient][_paymentId]
                = bytes32(bridgeData);
            } else {
                // Handle failed transfer.
                _unclaimableAmountsForRecipient[address(client)][orders[i]
                    .paymentToken][orders[i].recipient] += orders[i].amount;
                emit BridgeTransferFailed(
                    address(client),
                    orders[i].recipient,
                    orders[i].amount,
                    orders[i].flags,
                    orders[i].data
                );
            }

            // Update the amount paid on the payment client side.
            client.amountPaid(orders[i].paymentToken, orders[i].amount);
        }
    }

    /// @inheritdoc IPP_Connext_Crosschain_v1
    function retryFailedBridgeTransfer(
        address client_,
        address recipient_,
        IERC20PaymentClientBase_v2.PaymentOrder memory order_
    ) external validClient(client_) {
        // @note should this function call be restricted to only the payment client?

        uint unclaimableAmount =
            unclaimable(client_, order_.paymentToken, recipient_);

        // Validate that receipient has an unclaimable amount and the order
        // amount provided is not greater than the unclaimable amount.
        if (unclaimableAmount == 0 || order_.amount > unclaimableAmount) {
            revert Module__PP_Crosschain__InvalidUnclaimableAmount();
        }

        // Subtract the order amount from the unclaimable amount.
        _unclaimableAmountsForRecipient[client_][order_.paymentToken][recipient_]
        -= order_.amount;

        // Delete the unclaimable amount mapping entry if the amount is 0.
        if (
            _unclaimableAmountsForRecipient[client_][order_.paymentToken][recipient_]
                == 0
        ) {
            delete _unclaimableAmountsForRecipient[client_][order_.paymentToken][recipient_];
        }

        // Execute the bridge transfer.
        bytes memory bridgeData = _executeBridgeTransfer(order_);

        // If a zero intent ID is returned, revert.
        if (bytes32(bridgeData) == bytes32(0)) {
            revert Module__PP_Crosschain__MessageDeliveryFailed(
                order_.originChainId,
                order_.targetChainId,
                order_.flags,
                order_.data
            );
        }

        // Store the intent ID for the payment order.
        _processedIntentId[client_][recipient_][_paymentId] =
            bytes32(bridgeData);
        // @note should we increment the payment ID here?
    }

    /// @inheritdoc IPaymentProcessor_v1
    function validPaymentOrder(
        IERC20PaymentClientBase_v2.PaymentOrder memory order
    ) external virtual returns (bool valid_) {
        return _validPaymentOrder(order);
    }

    // -------------------------------------------------------------------------
    // Internal Functions

    /// @notice Validates the payment order.
    /// @param order The payment order to validate.
    /// @return valid_ True if the payment order is valid, false otherwise.
    function _validPaymentOrder(
        IERC20PaymentClientBase_v2.PaymentOrder memory order
    ) internal virtual returns (bool valid_) {
        valid_ = _validPaymentReceiver(order.recipient)
            && _validPaymentToken(order.paymentToken) && _validTotal(order.amount)
            && _validateOriginAndTargetChainId(
                order.originChainId, order.targetChainId
            ) && _validateFlagsAndData(order.flags, order.data);

        ( /* maxFee */ , uint48 ttl) =
            _getEverclearMaxFeeAndTTL(order.flags, order.data);
        return ttl > 0 && valid_;
    }

    /// @dev Execute the cross-chain bridge transfer
    /// @param order The payment order containing transfer details
    /// @return bridgeData Data returned by the bridge implementation
    function _executeBridgeTransfer(
        IERC20PaymentClientBase_v2.PaymentOrder memory order
    ) internal override(CrossChainBase_v1) returns (bytes memory) {
        bytes32 _intentId = _createCrossChainIntent(order);
        return abi.encode(_intentId);
    }

    /// @notice Transfer the token for the payment order into the payment processor.
    /// @dev    The tokens must be transferred to the payment processor first because
    ///         the bridge contract will later call this contract to execute the
    ///         cross-chain transfer.
    /// @param order_ The payment order details.
    /// @param client_ The payment client address.
    function _transferTokenAndApproveToBridge(
        IERC20PaymentClientBase_v2.PaymentOrder memory order_,
        address client_
    ) internal {
        IERC20(order_.paymentToken).transferFrom(
            client_, address(this), order_.amount
        );
        IERC20(order_.paymentToken).approve(
            address(_everClearSpoke), order_.amount
        );
    }

    /// @dev Creates a new cross-chain intent for payment transfer
    /// @param order_ The payment order details
    /// @return intentId_ ID of the created intent
    function _createCrossChainIntent(
        IERC20PaymentClientBase_v2.PaymentOrder memory order_
    ) internal returns (bytes32 intentId_) {
        // Get the max fee and TTL from the flags and data.
        (uint24 maxFee, uint48 ttl) =
            _getEverclearMaxFeeAndTTL(order_.flags, order_.data);

        uint32[] memory destinations = new uint32[](1);
        destinations[0] = uint32(order_.targetChainId);

        return _everClearSpoke.newIntent(
            destinations,
            order_.recipient,
            order_.paymentToken,
            address(_weth),
            order_.amount,
            maxFee, // @todo validate if maxFee has to be > 0. If so, add check to validatePaymentOrder
            ttl,
            "" // @note is calldata always empty? What could it be used for?
        );
    }

    /// @notice Gets the Everclear max fee and TTL from the flags and data.
    /// @param flags_ The flags to get the max fee and TTL from.
    /// @param data_ The data to get the max fee and TTL from.
    /// @return maxFee_ The max fee.
    /// @return ttl_ The TTL.
    function _getEverclearMaxFeeAndTTL(bytes32 flags_, bytes32[] memory data_)
        internal
        view
        virtual
        returns (uint24 maxFee_, uint48 ttl_)
    {
        maxFee_ = uint24(uint(data_[FLAG_MAX_FEE]));
        ttl_ = uint48(uint(data_[FLAG_TTL]));
    }

    /// @notice Validates the target chain ID
    /// @param targetChainId_ The target chain ID to validate
    function _validateOriginAndTargetChainId(
        uint originChainId_,
        uint targetChainId_
    ) internal view virtual returns (bool valid_) {
        return
            targetChainId_ != block.chainid && originChainId_ == block.chainid;
    }

    /// @notice Validates flags and corresponding data array.
    /// @param  flags_ The flags to validate.
    /// @param  data_ The data array to validate.
    function _validateFlagsAndData(bytes32 flags_, bytes32[] memory data_)
        internal
        pure
        virtual
        returns (bool valid_)
    {
        uint flagsValue = uint(flags_);
        uint requiredDataLength = 0;

        // Count how many flags are set.
        for (uint8 i; i <= 8; ++i) {
            // @note why set 8 as max flag? If we know we only need 4 flags, why not set 4?
            if (flagsValue & (1 << i) != 0) {
                requiredDataLength++;
            }
        }

        return data_.length == requiredDataLength
            && (flagsValue & (1 << FLAG_MAX_FEE)) != 0
            && (flagsValue & (1 << FLAG_TTL)) != 0;
    }

    /// @dev    Gap for possible future upgrades.
    uint[50] private __gap;
}
