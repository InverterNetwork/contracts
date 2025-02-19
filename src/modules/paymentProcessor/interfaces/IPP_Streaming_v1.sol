// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Interfaces
import {IERC20PaymentClientBase_v1} from
    "@lm/interfaces/IERC20PaymentClientBase_v1.sol";
import {IPaymentProcessor_v1} from
    "src/modules/paymentProcessor/IPaymentProcessor_v1.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

interface IPP_Streaming_v1 is IPaymentProcessor_v1 {
    //--------------------------------------------------------------------------
    // Structs

    /// @notice This struct is used to store the payment order for a particular paymentReceiver by a
    ///         particular payment client.
    /// @dev	for `_streamId`, valid values will start from 1. 0 is not a valid id.
    /// @param  _paymentToken The address of the token that is being used for the payment.
    /// @param  _streamId A unique identifier of a stream for a specific paymentClient and paymentReceiver combination.
    /// @param  _total The total amount that the paymentReceiver should eventually get.
    /// @param  _released The amount that has been claimed by the paymentReceiver till now.
    /// @param  _start The start date of the streaming period.
    /// @param  _cliff The duration of the cliff period.
    /// @param  _end The ending of the streaming period.
    struct Stream {
        address _paymentToken;
        uint _streamId;
        uint _total;
        uint _released;
        uint _start;
        uint _cliff;
        uint _end;
    }

    //--------------------------------------------------------------------------
    // Events

    /// @notice Emitted when a payment gets processed for execution.
    /// @param  paymentClient The payment client that originated the order.
    /// @param  recipient The address that will receive the payment.
    /// @param  paymentToken The address of the token that is being used for the payment.
    /// @param  streamId ID of the streaming payment order that was added.
    /// @param  amount The amount of tokens the payment consists of.
    /// @param  start The start date of the streaming period.
    /// @param  cliff The duration of the cliff period.
    /// @param  end The ending of the streaming period.
    event StreamingPaymentAdded(
        address indexed paymentClient,
        address indexed recipient,
        address indexed paymentToken,
        uint streamId,
        uint amount,
        uint start,
        uint cliff,
        uint end
    );

    /// @notice Emitted when the stream to an address is removed.
    /// @param  paymentClient The payment client that originated the order.
    /// @param  recipient The address that will stop receiving payment.
    /// @param  streamId ID of the streaming payment order that was removed.
    event StreamingPaymentRemoved(
        address indexed paymentClient, address indexed recipient, uint streamId
    );

    /// @notice Emitted when a running stream schedule gets updated.
    /// @param  recipient The address that will receive the payment.
    /// @param  paymentToken The address of the token that will be used for the payment.
    /// @param  amount The amount of tokens the payment consists of.
    /// @param  start The start date of the streaming period.
    /// @param  cliff The duration of the cliff period.
    /// @param  end The ending of the streaming period.
    event InvalidStreamingOrderDiscarded(
        address indexed recipient,
        address indexed paymentToken,
        uint amount,
        uint start,
        uint cliff,
        uint end
    );

    /// @notice Emitted when a payment was unclaimable due to a token error.
    /// @param  paymentClient The payment client that originated the order.
    /// @param  recipient The address that wshould have received the payment.
    /// @param  paymentToken The address of the token that will be used for the payment.
    /// @param  streamId ID of the streaming payment order that was processed.
    /// @param  amount The amount of tokens that were unclaimable.
    event UnclaimableAmountAdded(
        address indexed paymentClient,
        address recipient,
        address paymentToken,
        uint streamId,
        uint amount
    );

    /// @notice Emitted when an address is removed from the list of active payment receiver, eg because all
    ///         payments have been fulfilled by a client.
    /// @param  paymentClient The address of the payment client.
    /// @param  paymentReceiver The address of the recipient that is removed.
    event PaymentReceiverRemoved(
        address indexed paymentClient, address indexed paymentReceiver
    );

    //--------------------------------------------------------------------------
    // Errors

    /// @notice insufficient tokens in the client to do payments.
    error Module__PP_Streaming__InsufficientTokenBalanceInClient();

    /// @notice paymentReceiver's streamId for the paymentClient is not valid.
    /// @param  paymentClient The payment client that originated the order.
    /// @param  paymentReceiver The address that will receive the payment.
    /// @param  streamId ID of the streaming payment order that was processed.
    error Module__PP_Streaming__InvalidStream(
        address paymentClient, address paymentReceiver, uint streamId
    );

    /// @notice paymentReceiver's streamId for the paymentClient is no longer active.
    /// @param  paymentClient The payment client that originated the order.
    /// @param  paymentReceiver The address that will receive the payment.
    /// @param  streamId ID of the streaming payment order that was processed.
    error Module__PP_Streaming__InactiveStream(
        address paymentClient, address paymentReceiver, uint streamId
    );

    /// @notice the paymentReceiver for the given paymentClient does not exist (anymore).
    /// @param  paymentClient The payment client that originated the order.
    /// @param  paymentReceiver The address that will receive the payment.
    error Module__PP_Streaming__In_validPaymentReceiver(
        address paymentClient, address paymentReceiver
    );

    /// @notice The default start, cliff and end times are invalid.
    /// @param  start The start time.
    /// @param  cliff The cliff duration.
    /// @param  end The end time.
    error Module__PP_Streaming__InvalidDefaultTimes(
        uint start, uint cliff, uint end
    );

    //--------------------------------------------------------------------------
    // Functions
    /// @notice claim everything that the paymentClient owes to the `_msgSender` till the current timestamp.
    /// @dev	This function should be callable if the `_msgSender` is an `activePaymentReceiver`.
    /// @param  client The {IERC20PaymentClientBase_v1} instance address that processes all claims from `_msgSender`.
    function claimAll(address client) external;

    /// @notice claim the total amount up til block.timestamp from the client for a payment order with id = streamId
    ///         by _msgSender.
    /// @dev	If for a specific streamId, the tokens could not be transferred for some reason, it will added
    ///         to the unclaimableAmounts of the `paymentReceiver`, and the amount would no longer hold
    ///         any co-relation with he specific streamId of the `paymentReceiver`.
    /// @param  client The {IERC20PaymentClientBase_v1} instance address that processes the `streamId` claim
    ///               from `_msgSender`.
    /// @param  streamId The ID of the streaming payment order for which claim is being made.
    function claimForSpecificStream(address client, uint streamId) external;

    /// @notice Deletes all payments related to a paymentReceiver & leaves currently streaming tokens in the
    ///         {IERC20PaymentClientBase_v1}.
    /// @dev	this function calls `_removePayment` which goes through all the payment orders for a `paymentReceiver`.
    ///         For the payment orders that are completely streamed, their details are deleted in the
    ///         `_claimForSpecificStrea` function and for others it is deleted in the `_removePayment` function only,
    ///         leaving the currently streaming tokens as balance of the paymentClient itself.
    /// @param  client The {IERC20PaymentClientBase_v1} instance address from which we will remove the payments.
    /// @param  paymentReceiver PaymentReceiver's address.
    function removeAllPaymentReceiverPayments(
        address client,
        address paymentReceiver
    ) external;

    /// @notice Deletes a specific payment with id = streamId for a paymentReceiver & leaves currently streaming
    ///         tokens in the {IERC20PaymentClientBase_v1}.
    /// @dev	the detail of the wallet that is being removed is either deleted in the `_claimForSpecificStream`
    ///         or later down in this function itself depending on the timestamp of when this function was called.
    /// @param  client The {IERC20PaymentClientBase_v1} instance address from which we will remove the payment.
    /// @param  paymentReceiver Address of the paymentReceiver whose payment order is to be removed.
    /// @param  streamId The ID of the paymentReceiver's payment order which is to be removed.
    function removePaymentForSpecificStream(
        address client,
        address paymentReceiver,
        uint streamId
    ) external;

    /// @notice Getter for the start timestamp of a particular payment order with id = streamId associated
    ///         with a particular paymentReceiver.
    /// @param  client address of the payment client.
    /// @param  paymentReceiver PaymentReceiver's address.
    /// @param  streamId Id of the wallet for which start is fetched.
    /// @return start timestamp of the payment order.
    function startForSpecificStream(
        address client,
        address paymentReceiver,
        uint streamId
    ) external view returns (uint);

    /// @notice Getter for the cliff duration of a particular payment order with id = streamId associated
    ///         with a particular paymentReceiver.
    /// @param  client address of the payment client.
    /// @param  paymentReceiver PaymentReceiver's address.
    /// @param  streamId Id of the wallet for which cliff is fetched.
    /// @return cliff duration of the payment order.
    function cliffForSpecificStream(
        address client,
        address paymentReceiver,
        uint streamId
    ) external view returns (uint);

    /// @notice Getter for the stream end timestamp of a particular payment order with id = streamId associated
    ///         with a particular paymentReceiver.
    /// @param  client address of the payment client.
    /// @param  paymentReceiver PaymentReceiver's address.
    /// @param  streamId Id of the wallet for which end is fetched.
    /// @return end timestamp of the payment order.
    function endForSpecificStream(
        address client,
        address paymentReceiver,
        uint streamId
    ) external view returns (uint);

    /// @notice Getter for the amount of tokens already released for a particular payment order
    ///         with id = streamId associated with a particular paymentReceiver.
    /// @param  client address of the payment client.
    /// @param  paymentReceiver PaymentReceiver's address.
    /// @param  streamId Id of the wallet for which released is fetched.
    /// @return released amount of the payment order.
    function releasedForSpecificStream(
        address client,
        address paymentReceiver,
        uint streamId
    ) external view returns (uint);

    /// @notice Calculates the amount of tokens that has already streamed for a particular payment order
    ///         with id = streamId associated with a particular paymentReceiver.
    /// @param  paymentReceiver PaymentReceiver's address.
    /// @param  streamId Id of the wallet for which the streamed amount is fetched.
    /// @param  timestamp the time upto which we want the streamed amount.
    /// @return streamed amount of the stream with id = streamId.
    function streamedAmountForSpecificStream(
        address client,
        address paymentReceiver,
        uint streamId,
        uint timestamp
    ) external view returns (uint);

    /// @notice Getter for the amount of releasable tokens for a particular payment order with id = streamId associated
    ///         with a particular paymentReceiver.
    /// @param  paymentReceiver PaymentReceiver's address.
    /// @param  streamId Id of the wallet for which the releasable amount is fetched.
    /// @return releasable amount of the stream with id = streamId.
    function releasableForSpecificStream(
        address client,
        address paymentReceiver,
        uint streamId
    ) external view returns (uint);

    /// @notice See all active payment orders for a paymentClient associated with a particular paymentReceiver.
    /// @dev	the paymentReceiver must be an active paymentReceiver for the particular payment client.
    /// @param  client Address of the payment client.
    /// @param  paymentReceiver Address of the paymentReceiver.
    /// @return all streams for a particular payment client and payment receiver.
    function viewAllPaymentOrders(address client, address paymentReceiver)
        external
        view
        returns (Stream[] memory);

    /// @notice Tells whether a `paymentReceiver` has any pending payments for a particular client.
    /// @dev	This function is for convenience and can be easily figured out by other means in the codebase.
    /// @param  client Address of the payment client.
    /// @param  paymentReceiver Address of the paymentReceiver.
    /// @return true if the paymentReceiver is active for the payment client.
    function isActivePaymentReceiver(address client, address paymentReceiver)
        external
        view
        returns (bool);
}
