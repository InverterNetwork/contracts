// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// External
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

// Internal
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IPaymentProcessor_v2} from "@pp/IPaymentProcessor_v2.sol";
import {IERC20PaymentClientBase_v3} from
    "@lm/interfaces/IERC20PaymentClientBase_v3.sol";
import {IPP_Queue_v1} from "@pp/interfaces/IPP_Queue_v1.sol";
import {Module_v2} from "src/modules/base/Module_v2.sol";
import {LinkedIdList} from "src/modules/lib/LinkedIdList.sol";

/**
 * @title   Queue Based Payment Processor
 *
 * @notice  A payment processor implementation that manages payment orders
 *          through a FIFO queue system. It supports automated execution of
 *          payments within the processPayments function.
 *
 * @dev     This contract inherits from:
 *          - IPP_Queue_v1: Implementation interface.
 *          - IPaymentProcessor_v2: Payment processor interface.
 *          - Module_v2: Base module functionality.
 *
 *          Key features:
 *              - FIFO queue management for payment orders.
 *                Orders are processed in the order they are added to the queue,
 *                first in first out.
 *
 *              - Automated payment execution through queue processing.
 *                The processPayments function will add orders to the queue and
 *                execute the orders right away.
 *
 *              - Payment order lifecycle management with state tracking.
 *                The state of orders are tracked and emitted. The states are:
 *                  - PROCESSED: The order has been processed, the collateral has
 *                    been transferred to the recipient.
 *                  - CANCELLED: The order has been cancelled by the queue
 *                    operator.
 *                  - PENDING: The order is still in the queue.
 *                  - FAILED: The order has failed due to the transfer failing
 *                    (blacklisted address).
 *
 * @custom:setup   OPTIONAL setup steps for enhanced administration:
 *
 *                 1. Configure Queue Operators:
 *                    - Purpose: Queue operators are authorized to cancel payment
 *                               orders in the queue, and claim collateral for
 *                               failed payments.
 *                    - How:     The OrchestratorAdmin must:
 *                                1. Create a Queue operator role
 *                                2. Add access permission for the
 *                                   claimPreviouslyUnclaimableToTreasury() and
 *                                   cancelPaymentOrderThroughQueueId()
 *                                   functions to the Queue operator role.
 *                                3. Grant the role to desired addresses.
 *                    - Example: authorizer.createRole();
 *                               authorizer.addAccessPermission();
 *                               authorizer.grantRole();
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
 * @author  Zealynx Security
 */
contract PP_Queue_v1 is IPP_Queue_v1, Module_v2 {
    // -------------------------------------------------------------------------
    // Libraries

    using SafeERC20 for IERC20;
    using LinkedIdList for LinkedIdList.List;

    // -------------------------------------------------------------------------
    // ERC165

    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId_)
        public
        view
        virtual
        override(Module_v2)
        returns (bool supported_)
    {
        return interfaceId_ == type(IPP_Queue_v1).interfaceId
            || interfaceId_ == type(IPaymentProcessor_v2).interfaceId
            || super.supportsInterface(interfaceId_);
    }

    // -------------------------------------------------------------------------
    // Constants

    /// @notice    Flag position in the flags byte.
    uint8 internal constant FLAG_ORDER_ID = 0;

    /// @notice BPS value.
    uint internal constant BPS = 10_000;

    // ---------------------------------------------------------------------
    // Storage

    /// @notice Queue of payment orders per client.
    mapping(address client => LinkedIdList.List queue) internal _queue;

    /// @notice Payment orders.
    mapping(address client => mapping(uint orderId => QueuedOrder order))
        internal _orders;

    /// @notice Current order ID per client.
    mapping(address client => uint currentOrderId) internal _currentOrderId;

    /// @notice Tracks all payments that could not be made to the
    ///         paymentReceiver.
    mapping(
        address client
            => mapping(
                address token
                    => mapping(address receiver => uint unclaimableAmount)
            )
    ) internal _unclaimableAmountsForRecipient;

    /// @notice Treasury address which receives the collateral of canceled orders.
    address internal _cancelledOrdersTreasury;

    /// @notice Treasury address which receives the collateral of failed orders.
    address internal _failedOrdersTreasury;

    /// @notice Maximum number of orders that can be processed in a single
    ///         queue execution to prevent gas limit issues.
    uint internal _maxOrdersPerExecution;

    /// @dev    Gap for possible future upgrades.
    uint[50] private __gap;

    // -------------------------------------------------------------------------
    // Modifiers

    /// @dev    Checks that the calling client is valid.
    modifier clientIsValid(address client_) {
        _ensureValidClient(client_);
        _;
    }

    /// @dev    Checks that the caller is an active module.
    modifier onlyModule() {
        if (!orchestrator().isModule(_msgSender())) {
            revert Module__PaymentProcessor__OnlyCallableByModule();
        }
        _;
    }

    // -------------------------------------------------------------------------
    // Initialization Function

    /// @notice The module's initializer function.
    /// @dev	CAN be overridden by downstream contract.
    /// @dev	MUST call `__Module_init()`.
    /// @param orchestrator_ The orchestrator contract.
    /// @param metadata_ The metadata of the module.
    /// @param configData_ The config data of the module, comprised of:
    ///     - address: cancelledOrdersTreasury: The treasury address which
    ///       receives collateral from cancelled orders.
    ///     - address: failedOrdersTreasury: The treasury address which
    ///       receives collateral from failed orders.
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata_,
        bytes memory configData_
    ) external override(Module_v2) initializer {
        __Module_init(orchestrator_, metadata_);
        // Decode config data.
        (address cancelledOrdersTreasury_, address failedOrdersTreasury_) =
            abi.decode(configData_, (address, address));

        _setCanceledOrdersTreasury(cancelledOrdersTreasury_);
        _setFailedOrdersTreasury(failedOrdersTreasury_);

        // Default value for max orders per execution to ensure not to run out of gas.
        _maxOrdersPerExecution = 30;
    }

    //--------------------------------------------------------------------------
    // Public View Functions

    /// @inheritdoc IPP_Queue_v1
    function getMaxOrdersPerExecution()
        external
        view
        virtual
        returns (uint maxOrdersPerExecution_)
    {
        return _maxOrdersPerExecution;
    }

    /// @inheritdoc IPP_Queue_v1
    function getCanceledOrdersTreasury()
        external
        view
        virtual
        returns (address treasury_)
    {
        treasury_ = _cancelledOrdersTreasury;
    }

    /// @inheritdoc IPP_Queue_v1
    function getFailedOrdersTreasury()
        external
        view
        virtual
        returns (address treasury_)
    {
        treasury_ = _failedOrdersTreasury;
    }

    /// @inheritdoc IPP_Queue_v1
    function getOrder(uint orderId_, IERC20PaymentClientBase_v3 client_)
        external
        view
        virtual
        returns (QueuedOrder memory order_)
    {
        if (!_orderExists(orderId_, client_)) {
            revert Module__PP_Queue_InvalidOrderId(address(client_), orderId_);
        }
        order_ = _orders[address(client_)][orderId_];
    }

    /// @inheritdoc IPP_Queue_v1
    function getOrderQueue(address client_)
        external
        view
        virtual
        returns (uint[] memory queue_)
    {
        // If queue is empty, return empty array.
        if (_queue[client_].length() == 0) {
            return new uint[](0);
        }

        uint[] memory queue = new uint[](_queue[client_].length());
        uint index_;

        for (
            uint id = _queue[client_].getNextId(LinkedIdList._SENTINEL);
            id != LinkedIdList._SENTINEL;
            id = _queue[client_].getNextId(id)
        ) {
            queue[index_++] = id;
        }

        queue_ = queue;
    }

    /// @inheritdoc IPP_Queue_v1
    function getQueueHead(address client_)
        external
        view
        virtual
        returns (uint head_)
    {
        // Check if queue is initialized by checking if sentinel position exists
        if (_queue[client_].list[LinkedIdList._SENTINEL] == 0) {
            revert Module__PP_Queue_QueueOperationFailed(client_);
        }
        head_ = _queue[client_].getNextId(LinkedIdList._SENTINEL);
    }

    /// @inheritdoc IPP_Queue_v1
    function getQueueTail(address client_)
        external
        view
        virtual
        returns (uint tail_)
    {
        tail_ = _queue[client_].lastId();
    }

    /// @inheritdoc IPP_Queue_v1
    function getQueueSizeForClient(address client_)
        external
        view
        virtual
        returns (uint size_)
    {
        size_ = _queue[client_].length();
    }

    /// @inheritdoc IPaymentProcessor_v2
    function unclaimable(
        address client_,
        address token_,
        address paymentReceiver_
    ) public view virtual returns (uint amount_) {
        amount_ =
            _unclaimableAmountsForRecipient[client_][token_][paymentReceiver_];
    }

    /// @inheritdoc IPaymentProcessor_v2
    function validPaymentOrder(
        IERC20PaymentClientBase_v3.PaymentOrder memory order_
    ) external view virtual returns (bool isValid_) {
        return _validPaymentOrder(order_);
    }

    //--------------------------------------------------------------------------
    // Public Mutating Functions

    /// @inheritdoc IPP_Queue_v1
    function setMaxOrdersPerExecution(uint maxOrdersPerExecution_)
        external
        virtual
        permissioned
    {
        if (maxOrdersPerExecution_ == 0) {
            revert Module__PP_Queue_ZeroAmount();
        }
        _maxOrdersPerExecution = maxOrdersPerExecution_;
    }

    /// @inheritdoc IPP_Queue_v1
    function setCanceledOrdersTreasury(address treasury_)
        external
        virtual
        permissioned
    {
        _setCanceledOrdersTreasury(treasury_);
    }

    /// @inheritdoc IPP_Queue_v1
    function setFailedOrdersTreasury(address treasury_) external permissioned {
        _setFailedOrdersTreasury(treasury_);
    }

    /// @inheritdoc IPaymentProcessor_v2
    function processPayments(IERC20PaymentClientBase_v3 client_)
        external
        virtual
        clientIsValid(address(client_))
        onlyModule
    {
        // Collect outstanding orders and their total token amount.
        IERC20PaymentClientBase_v3.PaymentOrder[] memory orders;

        (orders,,) = client_.collectPaymentOrders();

        uint orderLength = orders.length;
        for (uint i; i < orderLength; ++i) {
            // Add order to order queue
            _addPaymentOrderToQueue(orders[i], address(client_));
        }
        // Execute Order Queue.
        _executePaymentQueue(address(client_));
    }

    /// @inheritdoc IPaymentProcessor_v2
    function cancelRunningPayments(IERC20PaymentClientBase_v3 client_)
        external
        view
        virtual
        clientIsValid(address(client_))
    {
        return;
    }

    /// @inheritdoc IPaymentProcessor_v2
    function claimPreviouslyUnclaimable(
        address client_,
        address token_,
        address receiver_
    ) external virtual {
        if (unclaimable(client_, token_, _msgSender()) == 0) {
            revert Module__PaymentProcessor__NothingToClaim(client_, receiver_);
        }

        _claimPreviouslyUnclaimable(client_, token_, receiver_);
    }

    /// @inheritdoc IPP_Queue_v1
    function claimPreviouslyUnclaimableToTreasury(
        address client_,
        address token_,
        address receiver_
    ) external virtual permissioned {
        if (unclaimable(client_, token_, receiver_) == 0) {
            revert Module__PaymentProcessor__NothingToClaim(client_, receiver_);
        }
        // Get amount to claim.
        uint amount =
            _unclaimableAmountsForRecipient[client_][token_][receiver_];
        // Delete the field.
        delete _unclaimableAmountsForRecipient[client_][token_][receiver_];

        // Transfer amount to treasury. Call has to succeed otherwise no state
        // change.
        IERC20(token_).safeTransferFrom(
            address(this), _failedOrdersTreasury, amount
        );

        emit TokensReleased(receiver_, address(token_), amount);
        emit UnclaimableAmountClaimedToTreasury(
            receiver_, _failedOrdersTreasury, amount, _msgSender()
        );
    }

    /// @inheritdoc IPP_Queue_v1
    function cancelPaymentOrderThroughQueueId(
        uint orderId_,
        IERC20PaymentClientBase_v3 client_
    ) external virtual permissioned returns (bool success_) {
        // Validate that the order exists for the given queue ID and client.
        if (!_orderExists(orderId_, client_)) {
            revert Module__PP_Queue_InvalidOrderId(address(client_), orderId_);
        }

        // Get the order to be cancelled
        QueuedOrder storage order = _orders[address(client_)][orderId_];

        // Check if the order is in a valid state for cancellation (must be PENDING).
        if (order.state_ != RedemptionState.PENDING) {
            revert Module__PP_Queue_InvalidState();
        }

        // Check if the client has enough balance to cancel the order, otherwise revert.
        if (
            IERC20(order.order_.paymentToken).balanceOf(order.client_)
                < order.order_.amount
        ) {
            revert Module__PP_Queue_InvalidAmount(order.order_.amount);
        }

        // Update the order state to CANCELLED.
        _updateOrderState(orderId_, address(client_), RedemptionState.CANCELLED);

        // Remove the cancelled order from the queue.
        _removeFromQueue(orderId_, address(client_));

        // Try to transfer the amount to the treasury.
        success_ = _tryPaymentTransfer(
            order.order_.paymentToken,
            order.client_,
            _cancelledOrdersTreasury,
            order.order_.amount,
            false // don't collect protocol fee when cancelling order
        );
        if (!success_) {
            // If tranfer to the treasury fails than this would mean that the treasury
            // is blacklisted, which shouldn't happen.
            revert Module_PP_Queue_PaymentFailed(
                order.client_,
                _cancelledOrdersTreasury,
                order.order_.paymentToken,
                order.order_.amount
            );
        }
    }

    // -------------------------------------------------------------------------
    // Internal Functions

    ///	@notice	Processes the next payment order in the queue.
    ///	@return	success_ True if a payment was processed.
    function _processNextOrder(address client_)
        internal
        virtual
        returns (bool success_)
    {
        uint firstId = _queue[client_].getNextId(LinkedIdList._SENTINEL);
        if (firstId == LinkedIdList._SENTINEL) {
            return false;
        }

        QueuedOrder storage order = _orders[client_][firstId];

        // Skip if order is not in PENDING state.
        if (order.state_ != RedemptionState.PENDING) {
            revert Module__PP_Queue_InvalidState();
        }

        // Check token balance and allowance.
        if (
            !_validTokenBalance(
                order.order_.paymentToken, order.client_, order.order_.amount
            )
        ) {
            return false;
        }

        // Execute payment transfer
        _executePaymentTransfer(firstId, order);
        // return true as payment has been processed
        return true;
    }

    /// @notice	Executes the actual payment transfer for an order. It sets
    ///         the order state to PROCESSED if the transfer succeeds, otherwise
    ///         if the transfer fails it sets the order state to FAILED. In both
    ///         cases the order is removed from the queue.
    /// @param	orderId_ The ID of the order to process.
    /// @param	order_ The order to process.
    function _executePaymentTransfer(uint orderId_, QueuedOrder memory order_)
        internal
        virtual
    {
        // Try to transfer payment from client to recipient
        bool success_ = _tryPaymentTransfer(
            order_.order_.paymentToken,
            order_.client_,
            order_.order_.recipient,
            order_.order_.amount,
            true // collect protocol fee when processing order
        );

        // Update order state based on transfer success
        if (success_) {
            _updateOrderState(
                orderId_, address(order_.client_), RedemptionState.PROCESSED
            );
        } else {
            _updateOrderState(
                orderId_, address(order_.client_), RedemptionState.FAILED
            );
        }

        // Remove processed order from queue
        _removeFromQueue(orderId_, address(order_.client_));
    }

    /// @notice	This function does a low lever call to transfer
    ///         funds to prevent reverts. Instead it will return a
    ///         boolean value indicating whether the transfer was
    ///         successful.
    /// @param	token_ The token address.
    /// @param	client_ The client address.
    /// @param	recipient_ The recipient address.
    /// @param	amount_ The amount to transfer.
    /// @return	success_ True if the transfer was successful.
    function _lowLevelTransfer(
        address token_,
        address client_,
        address recipient_,
        uint amount_
    ) internal virtual returns (bool success_) {
        // Make a low-level call to the token contract to execute transferFrom
        (bool success, bytes memory data) = token_.call(
            abi.encodeWithSelector(
                IERC20(token_).transferFrom.selector,
                client_,
                recipient_,
                amount_
            )
        );

        // Check if transfer was successful:
        // 1. Call must succeed
        // 2. Return data must either be empty or decode to true
        // 3. Token must be a contract (have code)
        if (
            success && (data.length == 0 || abi.decode(data, (bool)))
                && token_.code.length != 0
        ) {
            return true;
        }
        return false;
    }

    /// @notice  This function tries to transfer funds from client to recipient.
    ///          If the transfer fails, then the funds are transferred to this
    ///          module and made accesible for the recipient to claim through the
    ///          the unclaimable amounts.
    /// @param	token_ The token address.
    /// @param	client_ The client address.
    /// @param	recipient_ The recipient address.
    /// @param	amount_ The amount to transfer.
    /// @param	collectProtocolFee_ Whether to collect the protocol fee.
    /// @return	success_ True if the transfer was successful.
    function _tryPaymentTransfer(
        address token_,
        address client_,
        address recipient_,
        uint amount_,
        bool collectProtocolFee_
    ) internal virtual returns (bool success_) {
        // Get the protocol fee amount, net amount and treasury address to sent the fee.
        (uint protocolFeeAmount, uint netAmount, address treasury_) =
        _getProtocolFeeDetails(
            amount_,
            bytes4(keccak256(bytes("processPayments(address)"))),
            collectProtocolFee_
        );

        // Try direct transfer to recipient
        (bool success) =
            _lowLevelTransfer(token_, client_, recipient_, netAmount);

        if (success) {
            // Emit event for releasing tokens from the payment client to
            // the recipient.
            emit TokensReleased(recipient_, token_, netAmount);
            success_ = true;

            if (protocolFeeAmount > 0) {
                // Transfer fee amount to protocol treasury.
                IERC20(token_).safeTransferFrom(
                    client_, treasury_, protocolFeeAmount
                );
                // Emit event for releasing tokens from the payment client to
                // the protocol treasury.
                emit TokensReleased(treasury_, token_, protocolFeeAmount);
                // Emit event for protocol fee transfer
                emit ProtocolFeeTransferred(
                    token_, treasury_, protocolFeeAmount
                );
            }
        } else {
            // If direct transfer failed, try transferring to this module
            (success) =
                _lowLevelTransfer(token_, client_, address(this), amount_);

            if (!success) {
                // If tranfer to this module fails than this would mean that this module
                // is blacklisted, which shouldn't happen.
                revert Module_PP_Queue_PaymentFailed(
                    client_, recipient_, token_, amount_
                );
            }
            _addToUnclaimableAmount(client_, token_, recipient_, amount_);

            emit UnclaimableAmountAdded(client_, token_, recipient_, amount_);

            success_ = false;
        }

        // Update client accounting
        IERC20PaymentClientBase_v3(client_).amountPaid(token_, amount_);
    }

    /// @notice	Executes all pending orders in the queue.
    /// @dev    This function is only callable by the client.
    /// @param  client_ The client address.
    function _executePaymentQueue(address client_)
        internal
        virtual
        clientIsValid(client_)
    {
        uint firstId = _queue[client_].getNextId(LinkedIdList._SENTINEL);
        if (firstId == LinkedIdList._SENTINEL) {
            revert Module__PP_Queue_EmptyQueue();
        }

        uint processedCount;
        while (
            _processNextOrder(client_)
                && processedCount < _maxOrdersPerExecution
        ) {
            ++processedCount;
        }

        emit PaymentQueueExecuted(_msgSender(), client_, processedCount);
    }

    /// @notice	Adds a payment order to the queue.
    /// @param	order_ The payment order to add.
    /// @param  client_ The client paying for the order.
    /// @return	queueId_ The ID of the added order.
    function _addPaymentOrderToQueue(
        IERC20PaymentClientBase_v3.PaymentOrder memory order_,
        address client_
    ) internal virtual returns (uint queueId_) {
        if (!_validPaymentOrder(order_)) {
            revert Module__PP_Queue_QueueOperationFailed(client_);
        }

        // Get queue ID from flags and data, or generate new one
        queueId_ = _getPaymentQueueId(order_.flags, order_.data);

        // Create new order
        _orders[client_][queueId_] = QueuedOrder({
            order_: order_,
            state_: RedemptionState.PENDING,
            orderId_: queueId_,
            timestamp_: block.timestamp,
            client_: client_
        });

        // Initialize the queue if it's the first order
        if (_queue[client_].length() == 0) {
            _queue[client_].init();
        }

        // Add to linked list
        _queue[client_].addId(queueId_);

        // Update current order ID
        _currentOrderId[client_] = queueId_;

        emit PaymentOrderQueued(
            queueId_,
            order_.recipient,
            order_.paymentToken,
            client_,
            order_.amount,
            uint(order_.flags)
        );
    }

    /// @notice	Removes an order from the queue.
    /// @param	orderId_ ID of the order to remove.
    /// @param	client_ The client address.
    function _removeFromQueue(uint orderId_, address client_)
        internal
        virtual
    {
        uint prevId = _queue[client_].getPreviousId(orderId_);
        _queue[client_].removeId(prevId, orderId_);
    }

    /// @notice Validates token balance and allowance for a payment.
    /// @param  token_ Token to check.
    /// @param  client_ Client address.
    /// @param  amount_ Amount to check.
    /// @return valid_ True if balance and allowance are sufficient.
    function _validTokenBalance(address token_, address client_, uint amount_)
        internal
        view
        virtual
        returns (bool valid_)
    {
        IERC20 token = IERC20(token_);
        return token.balanceOf(client_) >= amount_
            && token.allowance(client_, address(this)) >= amount_;
    }

    /// @notice	Used to claim the unclaimable amount of a particular
    ///         paymentReceiver for a given payment client.
    /// @param	client_ Address of the payment client.
    /// @param	token_ Address of the payment token.
    /// @param	paymentReceiver_ Address of the paymentReceiver for which
    ///         the unclaimable amount will be claimed.
    function _claimPreviouslyUnclaimable(
        address client_,
        address token_,
        address paymentReceiver_
    ) internal virtual {
        // Copy value over.
        uint amount =
            _unclaimableAmountsForRecipient[client_][token_][paymentReceiver_];
        // Delete the field.
        delete _unclaimableAmountsForRecipient[client_][token_][paymentReceiver_];

        // Call has to succeed otherwise no state change.
        IERC20(token_).safeTransferFrom(address(this), paymentReceiver_, amount);

        emit TokensReleased(paymentReceiver_, address(token_), amount);
    }

    /// @notice Validates if a queue ID is valid.
    /// @dev    Queue ID must equal to the current order ID + 1 for the client
    ///         and greater than 0 (we start from 1).
    /// @param  queueId_ The queue ID to validate.
    /// @param  client_ The payment client address.
    /// @return isValid_ Returns true if the queue ID is valid.
    function _validQueueId(uint queueId_, address client_)
        internal
        view
        virtual
        returns (bool isValid_)
    {
        // Queue ID must equal to the current order ID + 1 for the client
        // and greater than 0 (we start from 1).
        return queueId_ > 0 && queueId_ == _currentOrderId[client_] + 1;
    }

    /// @notice Gets payment queue ID from flags and data.
    /// @param  flags_ The payment order flags.
    /// @param  data_ Additional payment order data.
    /// @return queueId_ The queue ID from the data or a newly generated one.
    function _getPaymentQueueId(bytes32 flags_, bytes32[] memory data_)
        internal
        view
        virtual
        returns (uint queueId_)
    {
        // Check if orderID flag is set (bit 0)
        bool hasOrderId = uint(flags_) & (1 << FLAG_ORDER_ID) != 0;

        // If flag is set and data is provided, use that ID
        if (hasOrderId && data_.length > FLAG_ORDER_ID) {
            queueId_ = uint(data_[FLAG_ORDER_ID]);
        }
    }

    /// @notice Validate total input amount.
    /// @dev    Amount must be greater than 0.
    /// @param  amount_ Amount to validate.
    /// @return valid_ True if uint is valid.
    function _validTotalAmount(uint amount_)
        internal
        pure
        virtual
        returns (bool valid_)
    {
        return amount_ != 0;
    }

    /// @notice Validate whether the address is a valid payment receiver.
    /// @param  receiver_ Address to validate.
    /// @return validPaymentReceiver_ True if address is valid.
    function _validPaymentReceiver(address receiver_)
        internal
        view
        virtual
        returns (bool validPaymentReceiver_)
    {
        return !(
            receiver_ == address(0) || receiver_ == _msgSender()
                || receiver_ == address(this)
                || receiver_ == address(orchestrator())
                || receiver_ == address(orchestrator().fundingManager().token())
        );
    }

    /// @notice Validates the chain ID.
    /// @dev    The chain ID must match the current chain ID.
    /// @param  chainId_ The chain ID to validate.
    /// @return valid_ True if the chain ID matches the current chain ID.
    function _validChainId(uint chainId_)
        internal
        view
        virtual
        returns (bool valid_)
    {
        return chainId_ == block.chainid;
    }

    /// @notice Validates the payment token.
    /// @param  token_ Token address to validate.
    /// @return valid_ True if token is valid.
    function _validPaymentToken(address token_)
        internal
        view
        virtual
        returns (bool valid_)
    {
        if (token_ == address(0)) {
            return false;
        }

        // Try to call balanceOf to verify it's an ERC20
        try IERC20(token_).balanceOf(address(this)) returns (uint) {
            return true;
        } catch {
            return false;
        }
    }

    /// @notice Validates a payment order.
    /// @param  order_ The order to validate.
    /// @return valid_ True if the order is valid.
    function _validPaymentOrder(
        IERC20PaymentClientBase_v3.PaymentOrder memory order_
    ) internal view virtual returns (bool valid_) {
        // Extract queue ID from order data.
        uint queueId_ = _getPaymentQueueId(order_.flags, order_.data);

        // Validate payment receiver, amount and queue ID.
        return _validPaymentReceiver(order_.recipient)
            && _validTotalAmount(order_.amount)
            && _validQueueId(queueId_, address(msg.sender))
            && _validPaymentToken(order_.paymentToken)
            && _validChainId(order_.originChainId)
            && _validChainId(order_.targetChainId)
            && _validateFlagsAndData(order_.flags, order_.data);
    }

    /// @notice Validates a state transition.
    /// @param  orderId_ ID of the order.
    /// @param  currentState_ Current state of the order.
    /// @param  newState_ New state to transition to.
    /// @return valid_ True if the transition is valid.
    function _validStateTransition(
        uint orderId_,
        RedemptionState currentState_,
        RedemptionState newState_
    ) internal pure virtual returns (bool valid_) {
        // Can't transition from completed or cancelled.
        if (
            currentState_ == RedemptionState.PROCESSED
                || currentState_ == RedemptionState.CANCELLED
        ) {
            revert Module__PP_Queue_InvalidStateTransition(
                orderId_, currentState_, newState_
            );
        }

        // Can only transition to completed or cancelled from processing.
        if (
            newState_ == RedemptionState.PROCESSED
                || newState_ == RedemptionState.CANCELLED
        ) {
            if (currentState_ != RedemptionState.PENDING) {
                revert Module__PP_Queue_InvalidStateTransition(
                    orderId_, currentState_, newState_
                );
            }
        }

        return true;
    }

    /// @notice Updates the state of a payment order.
    /// @param  orderId_ ID of the order to update.
    /// @param  state_ New state of the order.
    /// @param  client_ The client address.
    function _updateOrderState(
        uint orderId_,
        address client_,
        RedemptionState state_
    ) internal virtual {
        QueuedOrder storage order = _orders[client_][orderId_];
        _validStateTransition(orderId_, order.state_, state_);
        order.state_ = state_;
        emit PaymentOrderStateChanged(
            orderId_, state_, order.client_, _msgSender()
        );
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
        for (uint8 i; i < 8; ++i) {
            if (flagsValue & (1 << i) != 0) {
                requiredDataLength++;
            }
        }

        return data_.length == requiredDataLength
            && (flagsValue & (1 << FLAG_ORDER_ID)) != 0;
    }

    /// @notice Internal function to check whether the client is valid.
    /// @param  client_ Address to validate.
    function _ensureValidClient(address client_) internal view virtual {
        if (client_ != _msgSender()) {
            revert Module__PP_Queue_OnlyCallableByClient();
        }
    }

    /// @notice Adds to the unclaimable amount for a specific payment.
    /// @param  client_ The client address.
    /// @param  token_ The token address.
    /// @param  receiver_ The receiver address.
    /// @param  amount_ The amount to add.
    function _addToUnclaimableAmount(
        address client_,
        address token_,
        address receiver_,
        uint amount_
    ) internal virtual {
        _unclaimableAmountsForRecipient[client_][token_][receiver_] += amount_;
    }

    /// @notice Checks if an order exists.
    /// @param  orderId_ ID of the order to check.
    /// @param  client_ Address of the client.
    /// @return exists_ True if the order exists.
    function _orderExists(uint orderId_, IERC20PaymentClientBase_v3 client_)
        internal
        view
        virtual
        returns (bool exists_)
    {
        QueuedOrder storage order = _orders[address(client_)][orderId_];
        return order.client_ == address(client_) && order.timestamp_ != 0;
    }

    function _setCanceledOrdersTreasury(address treasury_) internal virtual {
        if (treasury_ == address(0) || treasury_ == address(this)) {
            revert Module__PP_Queue_InvalidTreasuryAddress(treasury_);
        }
        _cancelledOrdersTreasury = treasury_;
    }

    function _setFailedOrdersTreasury(address treasury_) internal virtual {
        if (treasury_ == address(0) || treasury_ == address(this)) {
            revert Module__PP_Queue_InvalidTreasuryAddress(treasury_);
        }
        _failedOrdersTreasury = treasury_;
    }

    /// @notice Calculates the protocol fee amount, net amount and identifies the
    ///         treasury address for a given function.
    /// @dev    Given the collectProtocolFee flag is true, retrieves the fee
    ///         percentage and treasury address for the specified function
    ///         selector, then calculates the actual fee amount based on the
    ///         provided total amount. If the flag is false, it returns 0 for
    ///         the fee amount and net amount is equal to total amount.
    /// @param  totalAmount_ The base amount on which to calculate the fee.
    /// @param  functionSelector_ The function selector used to look up the
    ///         appropriate fee data.
    /// @param  collectProtocolFee_ Whether to collect the protocol fee.
    /// @return feeAmount_ The calculated protocol fee amount.
    /// @return netAmount_ The net amount after deducting the protocol fee.
    /// @return treasury_ The treasury address where the fee should be sent.
    function _getProtocolFeeDetails(
        uint totalAmount_,
        bytes4 functionSelector_,
        bool collectProtocolFee_
    )
        internal
        view
        virtual
        returns (uint feeAmount_, uint netAmount_, address treasury_)
    {
        // If protocol fee is not collected, return 0 fee amount and
        // net amount equal to total amount.
        if (!collectProtocolFee_) {
            return (0, totalAmount_, address(0));
        }

        // Get the fee percentage and treasury address for the specified function selector.
        (uint protocolFeePercentage, address treasuryAddress_) =
            _getFeeManagerCollateralFeeData(functionSelector_);
        treasury_ = treasuryAddress_;

        // Revert if the fee percentage is greater than or equal to the BPS.
        if (protocolFeePercentage >= BPS) {
            revert Module__PP_Queue_FeeAmountToHigh(protocolFeePercentage);
        }

        // Calculate protocol fee amount if applicable
        if (protocolFeePercentage > 0) {
            feeAmount_ = totalAmount_ * protocolFeePercentage / BPS;
        }

        // Calculate the net amount after deducting the protocol fee.
        netAmount_ = totalAmount_ - feeAmount_;
    }
}
