// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {
    IPP_Streaming_v1,
    IPaymentProcessor_v1,
    IERC20PaymentClientBase_v1
} from "@pp/interfaces/IPP_Streaming_v1.sol";

// Internal Dependencies
import {Module_v1} from "src/modules/base/Module_v1.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// External Dependencies
import {ERC20} from "@oz/token/ERC20/ERC20.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

/**
 * @title   Linear Streaming Payment Processor
 *
 * @notice  Manages continuous and linear streaming payment streams within the Inverter
 *          Network, allowing multiple concurrent streams per recipient. Provides tools
 *          to claim streamed amounts and manage payment schedules dynamically.
 *
 * @dev     Supports complex payment interactions including streaming based on time for
 *          multiple clients and recipients, integrated with error handling for
 *          payments and managing active streaming schedules and their cancellations.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
 *
 * @author  Inverter Network
 */
contract PP_Streaming_v1 is Module_v1, IPP_Streaming_v1 {
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(Module_v1)
        returns (bool)
    {
        return interfaceId == type(IPP_Streaming_v1).interfaceId
            || interfaceId == type(IPaymentProcessor_v1).interfaceId
            || super.supportsInterface(interfaceId);
    }

    using SafeERC20 for IERC20;

    //--------------------------------------------------------------------------
    // Storage

    /// @notice provides a unique id for new payment orders added for a specific client & paymentReceiver combo
    /// @dev paymentClient => paymentReceiver => streamId(uint)
    mapping(address => mapping(address => uint)) public numStreams;

    /// @notice tracks all stream details for all payment orders of a paymentReceiver for a specific paymentClient
    /// @dev paymentClient => paymentReceiver => streamId => Wallet
    mapping(address => mapping(address => mapping(uint => Stream))) private
        streams;

    /// @notice tracks all streams for payments that could not be made to the paymentReceiver due to any reason
    /// @dev paymentClient => token address => paymentReceiver => streamId array
    mapping(address => mapping(address => mapping(address => uint[]))) internal
        unclaimableStreams;

    /// @notice tracks all payments that could not be made to the paymentReceiver due to any reason
    /// @dev paymentClient => token address =>  paymentReceiver => streamId => unclaimable Amount
    mapping(
        address => mapping(address => mapping(address => mapping(uint => uint)))
    ) internal unclaimableAmountsForStream;

    /// @notice list of addresses with open payment Orders per paymentClient
    /// @dev paymentClient => listOfPaymentReceivers(address[]). Duplicates are not allowed.
    mapping(address => address[]) private activePaymentReceivers;

    /// @notice list of streamIds of all payment orders of a particular paymentReceiver for a particular paymentClient
    /// @dev client => paymentReceiver => arrayOfStreamIdsWithPendingPayment(uint[])
    mapping(address => mapping(address => uint[])) private activeStreams;

    // Storage gap for future upgrades
    uint[50] private __gap;

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
    modifier validClient(address client) {
        if (_msgSender() != client) {
            revert Module__PaymentProcessor__CannotCallOnOtherClientsOrders();
        }
        _;
    }

    modifier activePaymentReceiver(address client, address paymentReceiver) {
        if (activeStreams[client][paymentReceiver].length == 0) {
            revert Module__PP_Streaming__InvalidPaymentReceiver(
                client, paymentReceiver
            );
        }
        _;
    }

    //--------------------------------------------------------------------------
    // External Functions

    /// @inheritdoc Module_v1
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata,
        bytes memory /*configData*/
    ) external override(Module_v1) initializer {
        __Module_init(orchestrator_, metadata);
    }

    /// @inheritdoc IPP_Streaming_v1
    function claimAll(address client) external {
        if (activeStreams[client][_msgSender()].length == 0) {
            revert Module__PaymentProcessor__NothingToClaim(
                client, _msgSender()
            );
        }

        _claimAll(client, _msgSender());
    }

    /// @inheritdoc IPaymentProcessor_v1
    function claimPreviouslyUnclaimable(
        address client,
        address token,
        address receiver
    ) external {
        if (unclaimable(client, token, _msgSender()) == 0) {
            revert Module__PaymentProcessor__NothingToClaim(
                client, _msgSender()
            );
        }

        _claimPreviouslyUnclaimable(client, token, receiver);
    }

    /// @inheritdoc IPP_Streaming_v1
    function claimForSpecificStream(address client, uint streamId) external {
        if (
            activeStreams[client][_msgSender()].length == 0
                || streamId > numStreams[client][_msgSender()]
        ) {
            revert Module__PP_Streaming__InvalidStream(
                client, _msgSender(), streamId
            );
        }

        if (_findActiveStream(client, _msgSender(), streamId) == type(uint).max)
        {
            revert Module__PP_Streaming__InactiveStream(
                client, _msgSender(), streamId
            );
        }

        _claimForSpecificStream(client, _msgSender(), streamId);
    }

    /// @inheritdoc IPaymentProcessor_v1
    function processPayments(IERC20PaymentClientBase_v1 client)
        external
        onlyModule
        validClient(address(client))
    {
        // We check if there are any new paymentOrders, without processing them
        if (client.paymentOrders().length > 0) {
            // Collect outstanding orders and their total token amount.
            IERC20PaymentClientBase_v1.PaymentOrder[] memory orders;
            address[] memory tokens;
            uint[] memory totalAmounts;
            (orders, tokens, totalAmounts) = client.collectPaymentOrders();
            for (uint i = 0; i < tokens.length; i++) {
                if (
                    IERC20(tokens[i]).balanceOf(address(client))
                        < totalAmounts[i]
                ) {
                    revert
                        Module__PP_Streaming__InsufficientTokenBalanceInClient();
                }
            }

            // Generate Streaming Payments for all orders
            address _recipient;
            address _token;
            uint _streamId;
            uint _amount;
            uint _start;
            uint _cliff;
            uint _end;

            uint numOrders = orders.length;

            for (uint i; i < numOrders;) {
                _recipient = orders[i].recipient;
                _token = orders[i].paymentToken;
                _streamId = numStreams[address(client)][_recipient] + 1;
                _amount = orders[i].amount;
                _start = orders[i].start;
                _cliff = orders[i].cliff;
                _end = orders[i].end;

                _addPayment(
                    address(client),
                    _recipient,
                    _token,
                    _streamId,
                    _amount,
                    _start,
                    _cliff,
                    _end
                );

                emit PaymentOrderProcessed(
                    address(client),
                    _recipient,
                    _token,
                    _streamId,
                    _amount,
                    _start,
                    _cliff,
                    _end
                );

                unchecked {
                    ++i;
                }
            }
        }
    }

    /// @inheritdoc IPaymentProcessor_v1
    function cancelRunningPayments(IERC20PaymentClientBase_v1 client)
        external
        onlyModule
        validClient(address(client))
    {
        _cancelRunningOrders(address(client));
    }

    /// @inheritdoc IPP_Streaming_v1
    function removeAllPaymentReceiverPayments(
        address client,
        address paymentReceiver
    ) external onlyOrchestratorAdmin {
        if (
            _findAddressInActiveStreams(client, paymentReceiver)
                == type(uint).max
        ) {
            revert Module__PP_Streaming__InvalidPaymentReceiver(
                client, paymentReceiver
            );
        }
        _removePayment(client, paymentReceiver);
    }

    /// @inheritdoc IPP_Streaming_v1
    function removePaymentForSpecificStream(
        address client,
        address paymentReceiver,
        uint streamId
    ) external onlyOrchestratorAdmin {
        // First, we give the streamed funds from this specific streamId to the beneficiary
        _claimForSpecificStream(client, paymentReceiver, streamId);

        // Now, we need to check when this function was called to determine if we need to delete the details pertaining to this stream or not
        // We will delete the payment order in question, if it hasn't already reached the end of its duration.
        if (
            block.timestamp
                < endForSpecificStream(client, paymentReceiver, streamId)
        ) {
            _afterClaimCleanup(client, paymentReceiver, streamId);
        }
    }

    //--------------------------------------------------------------------------
    // Public Functions

    /// @inheritdoc IPP_Streaming_v1
    function isActivePaymentReceiver(address client, address paymentReceiver)
        public
        view
        returns (bool)
    {
        return activeStreams[client][paymentReceiver].length > 0;
    }

    /// @inheritdoc IPP_Streaming_v1
    function startForSpecificStream(
        address client,
        address paymentReceiver,
        uint streamId
    ) public view returns (uint) {
        return streams[client][paymentReceiver][streamId]._start;
    }

    /// @inheritdoc IPP_Streaming_v1
    function cliffForSpecificStream(
        address client,
        address paymentReceiver,
        uint streamId
    ) public view returns (uint) {
        return streams[client][paymentReceiver][streamId]._cliff;
    }

    /// @inheritdoc IPP_Streaming_v1
    function endForSpecificStream(
        address client,
        address paymentReceiver,
        uint streamId
    ) public view returns (uint) {
        return streams[client][paymentReceiver][streamId]._end;
    }

    /// @inheritdoc IPP_Streaming_v1
    function releasedForSpecificStream(
        address client,
        address paymentReceiver,
        uint streamId
    ) public view returns (uint) {
        return streams[client][paymentReceiver][streamId]._released;
    }

    /// @inheritdoc IPP_Streaming_v1
    function streamedAmountForSpecificStream(
        address client,
        address paymentReceiver,
        uint streamId,
        uint timestamp
    ) public view returns (uint) {
        return _streamAmountForSpecificStream(
            client, paymentReceiver, streamId, timestamp
        );
    }

    /// @inheritdoc IPP_Streaming_v1
    function releasableForSpecificStream(
        address client,
        address paymentReceiver,
        uint streamId
    ) public view returns (uint) {
        return streamedAmountForSpecificStream(
            client, paymentReceiver, streamId, block.timestamp
        ) - releasedForSpecificStream(client, paymentReceiver, streamId);
    }

    /// @inheritdoc IPaymentProcessor_v1
    function unclaimable(address client, address token, address paymentReceiver)
        public
        view
        returns (uint amount)
    {
        uint[] memory ids = unclaimableStreams[client][token][paymentReceiver];
        uint length = ids.length;

        if (length == 0) {
            return 0;
        }

        for (uint i = 0; i < length; i++) {
            amount += unclaimableAmountsForStream[client][token][paymentReceiver][ids[i]];
        }
    }

    /// @inheritdoc IPP_Streaming_v1
    function viewAllPaymentOrders(address client, address paymentReceiver)
        external
        view
        activePaymentReceiver(client, paymentReceiver)
        returns (Stream[] memory)
    {
        uint[] memory streamIdsArray = activeStreams[client][paymentReceiver];
        uint streamIdsArrayLength = streamIdsArray.length;

        uint index;
        Stream[] memory paymentReceiverStreams =
            new Stream[](streamIdsArrayLength);

        for (index; index < streamIdsArrayLength;) {
            paymentReceiverStreams[index] =
                streams[client][paymentReceiver][streamIdsArray[index]];

            unchecked {
                ++index;
            }
        }

        return paymentReceiverStreams;
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    /// @notice common set of steps to be taken after everything has been claimed from a specific stream
    /// @param client address of the payment client
    /// @param paymentReceiver address of the paymentReceiver
    /// @param streamId ID of the stream that was fully claimed
    function _afterClaimCleanup(
        address client,
        address paymentReceiver,
        uint streamId
    ) internal {
        // 1. remove streamId from the activeStreams mapping
        _removePaymentForSpecificStream(client, paymentReceiver, streamId);

        // 2. delete the stream information for this specific streamId
        _removeStreamInformationForSpecificStream(
            client, paymentReceiver, streamId
        );

        // 3. activePaymentReceivers and isActive would be updated if this was the last stream that was associated with the paymentReceiver was claimed.
        //    This would also mean that, it is possible for a paymentReceiver to be inactive and still have money owed to them (unclaimableAmounts)
        if (activeStreams[client][paymentReceiver].length == 0) {
            _removePaymentReceiverFromActiveStreams(client, paymentReceiver);
        }

        // Note We do not need to update unclaimableAmounts, as it is already done earlier depending on the `transferFrom` call.
        // Note Also, we do not need to update numStreams, as claiming completely from a stream does not affect this mapping.

        // 4. emit an event broadcasting that a particular payment has been removed
        emit StreamingPaymentRemoved(client, paymentReceiver, streamId);
    }

    /// @notice used to find whether a particular paymentReceiver has pending payments with a client
    /// @dev This function returns the first instance of the paymentReceiver address in the activePaymentReceivers[client] array, but that
    ///      is completely fine as the activePaymentReceivers[client] array does not allow duplicates.
    /// @param client address of the payment client
    /// @param paymentReceiver address of the paymentReceiver
    /// @return the index of the paymentReceiver in the activePaymentReceivers[client] array. Returns type(uint256).max otherwise.
    function _findAddressInActiveStreams(
        address client,
        address paymentReceiver
    ) internal view returns (uint) {
        address[] memory receiverSearchArray = activePaymentReceivers[client];

        uint length = activePaymentReceivers[client].length;
        for (uint i; i < length;) {
            if (receiverSearchArray[i] == paymentReceiver) {
                return i;
            }
            unchecked {
                ++i;
            }
        }
        return type(uint).max;
    }

    /// @notice used to find whether a particular payment order associated with a paymentReceiver and paymentClient with id = streamId is active or not
    /// @dev active means that the particular payment order is still to be paid out/claimed. This function returns the first instance of the streamId
    ///      in the activeStreams[client][paymentReceiver] array, but that is fine as the array does not allow duplicates.
    /// @param client address of the payment client
    /// @param paymentReceiver address of the paymentReceiver
    /// @param streamId ID of the payment order that needs to be searched
    /// @return the index of the paymentReceiver in the activeStreams[client][paymentReceiver] array. Returns type(uint256).max otherwise.
    function _findActiveStream(
        address client,
        address paymentReceiver,
        uint streamId
    ) internal view returns (uint) {
        uint[] memory streamIdsArray = activeStreams[client][paymentReceiver];
        uint streamIdsArrayLength = streamIdsArray.length;

        uint index;
        for (index; index < streamIdsArrayLength;) {
            if (streamIdsArray[index] == streamId) {
                return index;
            }
            unchecked {
                ++index;
            }
        }

        return type(uint).max;
    }

    /// @notice used to cancel all unfinished payments from the client
    /// @dev all active payment orders of all active paymentReceivers associated with the client, are iterated through and
    ///      their details are deleted
    /// @param client address of the payment client
    function _cancelRunningOrders(address client) internal {
        address[] memory paymentReceivers = activePaymentReceivers[client];
        uint paymentReceiversLength = paymentReceivers.length;

        uint index;
        for (index; index < paymentReceiversLength;) {
            _removePayment(client, paymentReceivers[index]);

            unchecked {
                ++index;
            }
        }
    }

    /// @notice Deletes all payments related to a paymentReceiver & leaves currently streaming tokens in the ERC20PaymentClientBase_v1.
    /// @dev this function calls _removePayment which goes through all the payment orders for a paymentReceiver. For the payment orders
    ///      that are completely streamed, their details are deleted in the _claimForSpecificStream function and for others it is
    ///      deleted in the _removePayment function only, leaving the currently streaming tokens as balance of the paymentClient itself.
    /// @param client address of the payment client
    /// @param paymentReceiver address of the paymentReceiver
    function _removePayment(address client, address paymentReceiver) internal {
        uint[] memory streamIdsArray = activeStreams[client][paymentReceiver];
        uint streamIdsArrayLength = streamIdsArray.length;

        uint index;
        uint streamId;
        for (index; index < streamIdsArrayLength;) {
            streamId = streamIdsArray[index];
            _claimForSpecificStream(client, paymentReceiver, streamId);

            // If the paymentOrder being removed was already past its duration, then it would have been removed in the earlier _claimForSpecificStream call
            // Otherwise, we would remove that paymentOrder in the following lines.
            if (
                block.timestamp
                    < endForSpecificStream(client, paymentReceiver, streamId)
            ) {
                _afterClaimCleanup(client, paymentReceiver, streamId);
            }

            unchecked {
                ++index;
            }
        }
    }

    /// @notice used to remove the payment order with id = streamId from the activeStreams[client][paymentReceiver] array.
    /// @dev This function simply removes a particular payment order from the earlier mentioned array. The implications of removing a payment order
    ///      from this array have to be handled outside of this function, such as checking whether the paymentReceiver is still active or not, etc.
    /// @param client Address of the payment client
    /// @param paymentReceiver Address of the paymentReceiver
    /// @param streamId Id of the payment order that needs to be removed
    function _removePaymentForSpecificStream(
        address client,
        address paymentReceiver,
        uint streamId
    ) internal {
        uint streamIdIndex =
            _findActiveStream(client, paymentReceiver, streamId);

        if (streamIdIndex == type(uint).max) {
            revert Module__PP_Streaming__InactiveStream(
                address(client), _msgSender(), streamId
            );
        }

        address _token =
            streams[client][paymentReceiver][streamId]._paymentToken;
        uint remainingReleasable = streams[client][paymentReceiver][streamId] // The total amount
            ._total - streams[client][paymentReceiver][streamId]._released; // Minus what has already been "released"

        // In case there is still something to be released
        if (remainingReleasable > 0) {
            // Let PaymentClient know that the amount is not needed to be stored anymore

            IERC20PaymentClientBase_v1(client).amountPaid(
                _token, remainingReleasable
            );
        }

        // Standard deletion process.
        // Unordered removal of PaymentReceiver payment with streamId StreamIdIndex
        // Move the last element to the index which is to be deleted and then pop the last element of the array.
        activeStreams[client][paymentReceiver][streamIdIndex] = activeStreams[client][paymentReceiver][activeStreams[client][paymentReceiver]
            .length - 1];

        activeStreams[client][paymentReceiver].pop();
    }

    /// @notice used to remove the stream info of the payment order with id = streamId.
    /// @dev This function simply removes the stream details of a particular payment order. The implications of removing the stream info of
    ///      payment order have to be handled outside of this function.
    /// @param client Address of the payment client
    /// @param paymentReceiver Address of the paymentReceiver
    /// @param streamId Id of the payment order whose stream information needs to be removed
    function _removeStreamInformationForSpecificStream(
        address client,
        address paymentReceiver,
        uint streamId
    ) internal {
        delete streams[client][paymentReceiver][streamId];
    }

    /// @notice used to remove a paymentReceiver as one of the beneficiaries of the payment client
    /// @dev this function will be called when all the payment orders of a payment client associated with a particular paymentReceiver has been fulfilled.
    ///      Also signals that the paymentReceiver is no longer an active paymentReceiver according to the payment client
    /// @param client address of the payment client
    /// @param paymentReceiver address of the paymentReceiver
    function _removePaymentReceiverFromActiveStreams(
        address client,
        address paymentReceiver
    ) internal {
        // Find the paymentReceiver's index in the array of activePaymentReceivers mapping.
        uint paymentReceiverIndex =
            _findAddressInActiveStreams(client, paymentReceiver);

        if (paymentReceiverIndex == type(uint).max) {
            revert Module__PP_Streaming__InvalidPaymentReceiver(
                client, paymentReceiver
            );
        }

        // Replace the element to be deleted with the last element of the array
        uint paymentReceiversLength = activePaymentReceivers[client].length;
        activePaymentReceivers[client][paymentReceiverIndex] =
            activePaymentReceivers[client][paymentReceiversLength - 1];

        // pop the last element of the array
        activePaymentReceivers[client].pop();
    }

    /// @notice Adds a new payment containing the details of the monetary flow
    ///         depending on the module.
    /// @dev This function can handle multiple payment orders associated with a particular paymentReceiver for the same payment client
    ///      without overriding the earlier ones. The maximum payment orders for a paymentReceiver MUST BE capped at (2**256-1).
    /// @param _paymentReceiver PaymentReceiver's address.
    /// @param _total Total amount the paymentReceiver will receive per epoch.
    /// @param _start Streaming start timestamp.
    /// @param _cliff The duration of the cliff period.
    /// @param _end Streaming end timestamp.
    /// @param _streamId ID of the new stream of the a particular paymentReceiver being added
    function _addPayment(
        address client,
        address _paymentReceiver,
        address _token,
        uint _streamId,
        uint _total,
        uint _start,
        uint _cliff,
        uint _end
    ) internal {
        ++numStreams[client][_paymentReceiver];
        if (
            !validPaymentReceiver(_paymentReceiver) || !validTotal(_total)
                || !validTimes(_start, _cliff, _end) || !validPaymentToken(_token)
        ) {
            emit InvalidStreamingOrderDiscarded(
                _paymentReceiver, _token, _total, _start, _cliff, _end
            );
        } else {
            streams[client][_paymentReceiver][_streamId] =
                Stream(_token, _streamId, _total, 0, _start, _cliff, _end);

            // We do not want activePaymentReceivers[client] to have duplicate paymentReceiver entries
            // So we avoid pushing the _paymentReceiver to activePaymentReceivers[client] if it already exists
            if (
                _findAddressInActiveStreams(client, _paymentReceiver)
                    == type(uint).max
            ) {
                activePaymentReceivers[client].push(_paymentReceiver);
            }

            activeStreams[client][_paymentReceiver].push(_streamId);

            emit StreamingPaymentAdded(
                client,
                _paymentReceiver,
                _token,
                _streamId,
                _total,
                _start,
                _cliff,
                _end
            );
        }
    }

    /// @notice used to claim all the payment orders associated with a particular paymentReceiver for a given payment client
    /// @dev Calls the _claimForSpecificStream function for all the active streams of a particular paymentReceiver for the
    ///      given payment client. Depending on the time this function is called, the steamed payments are transferred to the
    ///      paymentReceiver.
    ///      For payment orders that are fully steamed, their details are deleted and changes are made to the state of the contract accordingly.
    /// @param client address of the payment client
    /// @param paymentReceiver address of the paymentReceiver for which every payment order will be claimed
    function _claimAll(address client, address paymentReceiver) internal {
        uint[] memory streamIdsArray = activeStreams[client][paymentReceiver];
        uint streamIdsArrayLength = streamIdsArray.length;

        uint index;
        for (index; index < streamIdsArrayLength;) {
            _claimForSpecificStream(
                client, paymentReceiver, streamIdsArray[index]
            );

            unchecked {
                ++index;
            }
        }
    }

    /// @notice used to claim the payment order of a particular paymentReceiver for a given payment client with id = streamId
    /// @dev Depending on the time this function is called, the steamed payments are transferred to the paymentReceiver or accounted in unclaimableAmounts.
    ///      For payment orders that are fully steamed, their details are deleted and changes are made to the state of the contract accordingly.
    /// @param client address of the payment client
    /// @param paymentReceiver address of the paymentReceiver for which every payment order will be claimed
    /// @param streamId ID of the payment order that is to be claimed
    function _claimForSpecificStream(
        address client,
        address paymentReceiver,
        uint streamId
    ) internal {
        uint amount =
            releasableForSpecificStream(client, paymentReceiver, streamId);

        streams[client][paymentReceiver][streamId]._released += amount;

        address _token =
            streams[client][paymentReceiver][streamId]._paymentToken;

        (bool success, bytes memory data) = _token.call(
            abi.encodeWithSelector(
                IERC20(_token).transferFrom.selector,
                client,
                paymentReceiver,
                amount
            )
        );

        if (success && (data.length == 0 || abi.decode(data, (bool)))) {
            emit TokensReleased(paymentReceiver, _token, amount);

            // Make sure to let paymentClient know that amount doesnt have to be stored anymore
            IERC20PaymentClientBase_v1(client).amountPaid(
                address(_token), amount
            );
        } else {
            emit UnclaimableAmountAdded(
                client, paymentReceiver, address(_token), streamId, amount
            );
            // Adds the streamId to the array of unclaimable stream ids

            uint[] memory ids =
                unclaimableStreams[client][_token][paymentReceiver];
            bool containsId = false;

            for (uint i = 0; i < ids.length; i++) {
                if (streamId == ids[i]) {
                    containsId = true;
                    break;
                }
            }
            // If it doesnt contain id than add it to array
            if (!containsId) {
                unclaimableStreams[client][_token][paymentReceiver].push(
                    streamId
                );
            }

            unclaimableAmountsForStream[client][_token][paymentReceiver][streamId]
            += amount;
        }

        // This if conditional block represents that nothing more remains to be steamed from the specific streamId
        if (
            block.timestamp
                >= endForSpecificStream(client, paymentReceiver, streamId)
        ) {
            _afterClaimCleanup(client, paymentReceiver, streamId);
        }
    }

    /// @notice used to claim the unclaimable amount of a particular paymentReceiver for a given payment client
    /// @dev assumes that the streamId array is not empty
    /// @param client address of the payment client
    /// @param client address of the payment token
    /// @param paymentReceiver address of the paymentReceiver for which the unclaimable amount will be claimed
    function _claimPreviouslyUnclaimable(
        address client,
        address token,
        address paymentReceiver
    ) internal {
        // get amount
        uint amount;

        address sender = _msgSender();
        uint[] memory ids = unclaimableStreams[client][token][sender];
        uint length = ids.length;

        for (uint i = 0; i < length; i++) {
            // Add the unclaimable amount of each id to the current amount
            amount += unclaimableAmountsForStream[client][token][sender][ids[i]];
            // Delete value of stream id
            delete unclaimableAmountsForStream[client][token][sender][ids[i]];
        }
        // As all of the stream ids should have been claimed we can delete the stream id array
        delete unclaimableStreams[client][token][sender];

        // Call has to succeed otherwise no state change
        IERC20(token).safeTransferFrom(client, paymentReceiver, amount);

        emit TokensReleased(paymentReceiver, address(token), amount);

        // Make sure to let paymentClient know that amount doesnt have to be stored anymore
        IERC20PaymentClientBase_v1(client).amountPaid(address(token), amount);
    }

    /// @notice Virtual implementation of the stream formula.
    ///         Returns the amount steamed, as a function of time,
    ///         for an asset given its total historical allocation.
    /// @param paymentReceiver The paymentReceiver to check on.
    /// @param streamId ID of a particular paymentReceiver's stream whose stream schedule needs to be checked
    /// @param timestamp the time upto which we want the steamed amount
    function _streamAmountForSpecificStream(
        address client,
        address paymentReceiver,
        uint streamId,
        uint timestamp
    ) internal view virtual returns (uint) {
        uint total = streams[client][paymentReceiver][streamId]._total;
        uint start = startForSpecificStream(client, paymentReceiver, streamId);
        uint end = endForSpecificStream(client, paymentReceiver, streamId);

        if (
            timestamp
                < (
                    start
                        + cliffForSpecificStream(client, paymentReceiver, streamId)
                )
        ) {
            // if current time is smaller than starting date plus
            // optional cliff duration, return 0
            return 0;
        } else if (timestamp >= end) {
            return total;
        } else {
            // here the cliff is not applied, as it is just delaying
            // the start of the release, not the vesting part itself
            return (total * (timestamp - start)) / (end - start);
        }
    }

    /// @notice validate address input.
    /// @param addr Address to validate.
    /// @return True if address is valid.
    function validPaymentReceiver(address addr) internal view returns (bool) {
        return !(
            addr == address(0) || addr == _msgSender() || addr == address(this)
                || addr == address(orchestrator())
                || addr == address(orchestrator().fundingManager().token())
        );
    }

    /// @notice validate uint total amount input.
    /// @param _total uint to validate.
    /// @return True if uint is valid.
    function validTotal(uint _total) internal pure returns (bool) {
        return !(_total == 0);
    }

    /// @notice validate uint start input.
    /// @param _start uint to validate.
    /// @param _cliff uint to validate.
    /// @param _end uint to validate.
    /// @return True if uint is valid.
    function validTimes(uint _start, uint _cliff, uint _end)
        internal
        pure
        returns (bool)
    {
        // _start + _cliff should be less or equal to _end
        // this already implies that _start is not greater than _end
        return _start + _cliff <= _end;
    }

    /// @notice validate payment token input.
    /// @param _token Address of the token to validate.
    /// @return True if address is valid.
    function validPaymentToken(address _token) internal view returns (bool) {
        // Only a basic sanity check, the corresponding module should ensure it's sending an ERC20.
        return !(
            _token == address(0) || _token == _msgSender()
                || _token == address(this) || _token == address(orchestrator())
        );
    }
}
