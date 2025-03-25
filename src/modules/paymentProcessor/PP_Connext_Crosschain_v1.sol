// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// External
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IWETH} from "@pp/interfaces/IWETH.sol";
import {IEverclearSpoke} from "@pp/interfaces/IEverclear.sol";
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

// Internal
import {IPaymentProcessor_v1} from "@pp/IPaymentProcessor_v1.sol";
import {CrossChainBase_v1} from "@pp/abstracts/CrossChainBase_v1.sol";
import {ICrossChainBase_v1} from "@pp/interfaces/ICrossChainBase_v1.sol";
import {IPP_Connext_CrossChain_v1} from
    "@pp/interfaces/IPP_Connext_CrossChain_v1.sol";
import {IERC20PaymentClientBase_v2} from
    "@lm/interfaces/IERC20PaymentClientBase_v2.sol";
import {PP_CrossChain_v1} from "@pp/abstracts/PP_CrossChain_v1.sol";
import {Module_v1} from "src/modules/base/Module_v1.sol";

/**
 * @title   Connext Cross-Chain Payment Processor
 *
 * @notice  A payment processor implementation that enables cross-chain payments
 *          using the Connext protocol. This module processes payment orders from
 *          payment clients and bridges them to their target chains through
 *          Connext's infrastructure.
 *
 * @dev     Inherits functionality from:
 *          - IPP_Connext_CrossChain_v1: Implementation interface
 *          - IPaymentProcessor_v1: Base payment processor functionality
 *          - ICrossChainBase_v1: Cross-chain operations base
 *
 *          Key features:
 *              - Cross-chain payment processing
 *                Enables payments to be sent across different networks
 *
 *              - Bridge integration
 *                Integrates with Everclear protocol for secure cross-chain transfers
 *
 *              - Failed transfer recovery
 *                Provides mechanism to retry failed bridge transfers
 *
 *              - WETH handling
 *                Supports native token wrapping/unwrapping for ETH transfers
 *
 * @custom:setup    This module requires the following MANDATORY setup steps:
 *
 *                  1. Initialize with Correct Parameters:
 *                     - Purpose: The module needs proper configuration of
 *                               Everclear spoke and WETH contract addresses
 *                     - How:     Pass the correct addresses during initialization
 *                     - Example: module.init(
 *                                 orchestrator,
 *                                 metadata,
 *                                 abi.encode(everClearSpoke, wethAddress)
 *                               );
 *
 *                  2. Payment Client Authorization:
 *                     - Purpose: Only authorized payment clients should be able
 *                               to process payments through this module
 *                     - How:     The payment client must be added through the
 *                               orchestrator's module management system
 *                     - Example: orchestrator.initiateAddModule(clientAddress);
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to
 *                          our Security Policy at security.inverter.network or
 *                          email us directly!
 *
 * @custom:version  v1.0.0
 *
 * @custom:standard-version v1.0.0
 *
 * @author  33Audits
 */
contract PP_Connext_CrossChain_v1 is
    IPP_Connext_CrossChain_v1,
    PP_CrossChain_v1
{
    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId_)
        public
        view
        virtual
        override(PP_CrossChain_v1)
        returns (bool)
    {
        return interfaceId_ == type(IPP_Connext_CrossChain_v1).interfaceId
            || interfaceId_ == type(IPaymentProcessor_v1).interfaceId
            || super.supportsInterface(interfaceId_);
    }
    // -------------------------------------------------------------------------
    // Constants

    /// @notice Payment order flag for the Everclear max fee.
    uint8 public constant FLAG_MAX_FEE = 4;
    /// @notice Payment order flag for the Everclear TTL.
    uint8 public constant FLAG_TTL = 5;

    // -------------------------------------------------------------------------
    // State Variables

    /// @notice The Everclear spoke contract address.
    IEverclearSpoke internal _everClearSpoke;
    /// @notice The WETH contract address.
    IWETH internal _weth;

    // -------------------------------------------------------------------------
    // Initialization Function

    /// @notice The module's initializer function.
    /// @dev    CAN be overridden by downstream contract.
    /// @dev    MUST call `__Module_init()`.
    /// @param  orchestrator_ The orchestrator contract.
    /// @param  metadata_ The metadata of the module.
    /// @param  configData_ The config data of the module, comprised of:
    ///     - address: everClearSpoke_: The Everclear spoke contract address for
    ///       cross-chain message passing
    ///     - address: weth_: The WETH contract address for native token wrapping
    ///       and unwrapping operations
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata_,
        bytes memory configData_
    ) external override(Module_v1) initializer {
        __Module_init(orchestrator_, metadata_);
        (address everClearSpoke_, address weth_) =
            abi.decode(configData_, (address, address));

        _everClearSpoke = IEverclearSpoke(everClearSpoke_);
        _weth = IWETH(weth_);
    }

    // -------------------------------------------------------------------------
    // View Functions

    /// @inheritdoc IPP_Connext_CrossChain_v1
    function getEverClearSpoke()
        external
        view
        returns (IEverclearSpoke everClearSpoke_)
    {
        return _everClearSpoke;
    }

    /// @inheritdoc IPP_Connext_CrossChain_v1
    function getWeth() external view returns (IWETH weth_) {
        return _weth;
    }

    /// @inheritdoc ICrossChainBase_v1
    function getBridgeData(uint paymentId_)
        public
        view
        override(CrossChainBase_v1)
        returns (bytes memory)
    {
        return _bridgeData[paymentId_];
    }

    // -------------------------------------------------------------------------
    // External Functions

    /// @inheritdoc IPaymentProcessor_v1
    function processPayments(IERC20PaymentClientBase_v2 client_)
        external
        onlyModule
        validClient(address(client_))
    {
        // Get the payment orders from the payment client.
        IERC20PaymentClientBase_v2.PaymentOrder[] memory orders;
        (orders,,) = client_.collectPaymentOrders();

        // Process each payment order.
        for (uint i = 0; i < orders.length; i++) {
            if (!_validPaymentOrder(orders[i])) {
                revert
                    IERC20PaymentClientBase_v2
                    .Module__ERC20PaymentClientBase__InvalidPaymentOrder();
            }
            // Transfer the token for the order from the payment client into
            // the payment processor.
            _transferTokenAndApproveToBridge(orders[i], address(client_));
            // Execute the bridge transfer.
            bytes memory bridgeData = _executeBridgeTransfer(orders[i]);
            // Bridge data in the Everclear implementation is the intent ID.

            // If a non-zero intent ID is returned.
            if (bytes32(bridgeData) != bytes32(0)) {
                // Emit the Payment Processor's PaymentOrderProcessed event.
                emit PaymentOrderProcessed(
                    address(client_),
                    orders[i].recipient,
                    orders[i].paymentToken,
                    orders[i].amount,
                    orders[i].originChainId,
                    orders[i].targetChainId,
                    orders[i].flags,
                    orders[i].data
                );
                emit PaymentIdAssigned(_paymentId, bytes32(bridgeData));

                // Store the intent ID for the payment order.
                _bridgeData[_paymentId] = bridgeData;
                _paymentId++;
            } else {
                // Handle failed transfer.
                _unclaimableAmountsForRecipient[address(client_)][orders[i]
                    .paymentToken][orders[i].recipient] += orders[i].amount;
                emit BridgeTransferFailed(
                    address(client_),
                    orders[i].recipient,
                    orders[i].paymentToken,
                    orders[i].amount,
                    orders[i].originChainId,
                    orders[i].targetChainId,
                    orders[i].flags,
                    orders[i].data
                );
            }
        }
    }

    /// @inheritdoc IPP_Connext_CrossChain_v1
    function retryFailedBridgeTransfer(
        address client_,
        address recipient_,
        IERC20PaymentClientBase_v2.PaymentOrder memory order_
    ) external {
        uint unclaimableAmount =
            unclaimable(client_, order_.paymentToken, recipient_);

        // Validate that receipient has an unclaimable amount and the order
        // amount provided is not greater than the unclaimable amount.
        if (unclaimableAmount == 0 || order_.amount > unclaimableAmount) {
            revert Module__PP_CrossChain__InvalidUnclaimableAmount();
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
            revert Module__PP_CrossChain__MessageDeliveryFailed(
                order_.originChainId,
                order_.targetChainId,
                order_.flags,
                order_.data
            );
        }
        // Store the intent ID for the payment order.
        _bridgeData[_paymentId] = bridgeData;
        _paymentId++;

        emit PaymentOrderProcessed(
            address(client_),
            recipient_,
            order_.paymentToken,
            order_.amount,
            order_.originChainId,
            order_.targetChainId,
            order_.flags,
            order_.data
        );
    }

    /// @inheritdoc IPaymentProcessor_v1
    function validPaymentOrder(
        IERC20PaymentClientBase_v2.PaymentOrder memory order_
    ) external virtual returns (bool valid_) {
        return _validPaymentOrder(order_);
    }

    // -------------------------------------------------------------------------
    // Internal Functions

    /// @notice Validates the payment order.
    /// @param  order_ The payment order to validate.
    /// @return valid_ True if the payment order is valid, false otherwise.
    function _validPaymentOrder(
        IERC20PaymentClientBase_v2.PaymentOrder memory order_
    ) internal virtual returns (bool valid_) {
        valid_ = _validPaymentReceiver(order_.recipient)
            && _validPaymentToken(order_.paymentToken) && _validTotal(order_.amount)
            && _validateOriginAndTargetChainId(
                order_.originChainId, order_.targetChainId
            ) && _validateFlagsAndData(order_.flags, order_.data);

        (uint48 maxFee, uint48 ttl) =
            _getEverclearMaxFeeAndTTL(order_.flags, order_.data);
        bool validParams = maxFee > 0 && ttl > 0;

        return validParams && valid_;
    }

    /// @notice Execute the cross-chain bridge transfer.
    /// @param  order_ The payment order containing transfer details.
    /// @return intentId_ Data returned by the bridge implementation.
    function _executeBridgeTransfer(
        IERC20PaymentClientBase_v2.PaymentOrder memory order_
    ) internal override(CrossChainBase_v1) returns (bytes memory intentId_) {
        bytes32 intentId = _createCrossChainIntent(order_);
        return abi.encode(intentId);
    }

    /// @notice Transfer the token for the payment order into the payment processor.
    /// @dev    The tokens must be transferred to the payment processor first because
    ///         the bridge contract will later call this contract to execute the
    ///         cross-chain transfer.
    /// @param  order_ The payment order details.
    /// @param  client_ The payment client address.
    function _transferTokenAndApproveToBridge(
        IERC20PaymentClientBase_v2.PaymentOrder memory order_,
        address client_
    ) internal {
        IERC20(order_.paymentToken).transferFrom(
            client_, address(this), order_.amount
        );
        // Update the amount paid on the payment client side.
        IERC20PaymentClientBase_v2(client_).amountPaid(
            order_.paymentToken, order_.amount
        );

        IERC20(order_.paymentToken).approve(
            address(_everClearSpoke), order_.amount
        );
    }

    /// @notice Creates a new cross-chain intent for payment transfer.
    /// @param  order_ The payment order details.
    /// @return intentId_ ID of the created intent.
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
            maxFee,
            ttl,
            ""
        );
    }

    /// @notice Gets the Everclear max fee and TTL from the flags and data.
    /// @param  flags_ The flags to get the max fee and TTL from.
    /// @param  data_ The data to get the max fee and TTL from.
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

    /// @notice Validates the target chain ID.
    /// @param  targetChainId_ The target chain ID to validate.
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
