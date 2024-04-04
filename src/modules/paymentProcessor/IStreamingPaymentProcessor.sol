// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IERC20PaymentClient} from
    "src/modules/logicModule/paymentClient/IERC20PaymentClient.sol";
import {IPaymentProcessor} from
    "src/modules/paymentProcessor/IPaymentProcessor.sol";

interface IStreamingPaymentProcessor is IPaymentProcessor {
    //--------------------------------------------------------------------------

    // Structs

    /// @notice This struct is used to store the payment order for a particular paymentReceiver by a particular payment client
    /// @dev for _vestingWalletID, valid values will start from 1. 0 is not a valid vestingWalletID.
    /// @param _salary The total amount that the paymentReceiver should eventually get
    /// @param _released The amount that has been claimed by the paymentReceiver till now
    /// @param _start The start date of the vesting period
    /// @param _cliff The duration of the cliff.
    /// @param _end The ending of the vesting period
    /// @param _vestingWalletID A unique identifier of a wallet for a specific paymentClient and paymentReceiver combination
    struct VestingWallet {
        uint _salary;
        uint _released;
        uint _start;
        uint _cliff;
        uint _end;
        uint _vestingWalletID;
    }

    //--------------------------------------------------------------------------
    // Events

    /// @notice Emitted when a payment gets processed for execution.
    /// @param recipient The address that will receive the payment.
    /// @param amount The amount of tokens the payment consists of.
    /// @param start Timestamp at which the vesting starts.
    /// @param cliff The duration of the cliff.
    /// @param end Timestamp at which the full amount should be claimable.
    /// @param walletId ID of the payment order that was added
    event StreamingPaymentAdded(
        address indexed paymentClient,
        address indexed recipient,
        uint amount,
        uint start,
        uint cliff,
        uint end,
        uint walletId
    );

    /// @notice Emitted when the vesting to an address is removed.
    /// @param recipient The address that will stop receiving payment.
    /// @param walletId ID of the payment order removed
    event StreamingPaymentRemoved(
        address indexed paymentClient,
        address indexed recipient,
        uint indexed walletId
    );

    /// @notice Emitted when a running vesting schedule gets updated.
    /// @param recipient The address that will receive the payment.
    /// @param amount The amount of tokens the payment consists of.
    /// @param start Timestamp at which the vesting starts.
    /// @param cliff The duration of the cliff.
    /// @param end Timestamp at which the full amount should be claimable.
    event InvalidStreamingOrderDiscarded(
        address indexed recipient, uint amount, uint start, uint cliff, uint end
    );

    /// @notice Emitted when a payment gets processed for execution.
    /// @param paymentClient The payment client that originated the order.
    /// @param recipient The address that will receive the payment.
    /// @param amount The amount of tokens the payment consists of.
    /// @param createdAt Timestamp at which the order was created.
    /// @param cliff The duration of the cliff.
    /// @param end Timestamp at which the full amount should be payed out/claimable.
    /// @param walletId ID of the payment order that was processed
    event PaymentOrderProcessed(
        address indexed paymentClient,
        address indexed recipient,
        uint amount,
        uint createdAt,
        uint cliff,
        uint end,
        uint walletId
    );

    //--------------------------------------------------------------------------
    // Errors

    /// @notice insufficient tokens in the client to do payments
    error Module__PaymentProcessor__InsufficientTokenBalanceInClient();

    /// @notice the paymentReceiver is not owed any money by the paymentClient
    error Module__PaymentProcessor__NothingToClaim(
        address paymentClient, address paymentReceiver
    );

    /// @notice paymentReceiver's walletId for the paymentClient is not valid
    error Module__PaymentProcessor__InvalidWallet(
        address paymentClient, address paymentReceiver, uint walletId
    );

    /// @notice paymentReceiver's walletId for the paymentClient is no longer active
    error Module__PaymentProcessor__InactiveWallet(
        address paymentClient, address paymentReceiver, uint walletId
    );

    /// @notice the paymentReceiver for the given paymentClient does not exist (anymore)
    error Module__PaymentProcessor__InvalidPaymentReceiver(
        address paymentClient, address paymentReceiver
    );

    //--------------------------------------------------------------------------
    // Functions

    /// @notice claim everything that the paymentClient owes to the _msgSender till the current timestamp
    /// @dev This function should be callable if the _msgSender is either an activePaymentReceiver or has some unclaimedAmounts
    /// @param client The IERC20PaymentClient instance address that processes all claims from _msgSender
    function claimAll(address client) external;

    /// @notice claim the salary uptil block.timestamp from the client for a payment order with id = walletId by _msgSender
    /// @dev If for a specific walletId, the tokens could not be transferred for some reason, it will added to the unclaimableAmounts
    ///      of the paymentReceiver, and the amount would no longer hold any co-relation with the specific walletId of the paymentReceiver.
    /// @param client The {IERC20PaymentClient} instance address that processes the walletId claim from _msgSender
    /// @param walletId The ID of the payment order for which claim is being made
    /// @param retryForUnclaimableAmounts boolean which determines if the function will try to pay the unclaimable amounts from earlier
    ///        along with the vested salary from the payment order with id = walletId
    function claimForSpecificWalletId(
        address client,
        uint walletId,
        bool retryForUnclaimableAmounts
    ) external;

    /// @notice Deletes all payments related to a paymentReceiver & leaves unvested tokens in the ERC20PaymentClient.
    /// @dev this function calls _removePayment which goes through all the payment orders for a paymentReceiver. For the payment orders
    ///      that are completely vested, their details are deleted in the _claimForSpecificWalletId function and for others it is
    ///      deleted in the _removePayment function only, leaving the unvested tokens as balance of the paymentClient itself.
    /// @param client The {IERC20PaymentClient} instance address from which we will remove the payments
    /// @param paymentReceiver PaymentReceiver's address.
    function removeAllPaymentReceiverPayments(
        address client,
        address paymentReceiver
    ) external;

    /// @notice Deletes a specific payment with id = walletId for a paymentReceiver & leaves unvested tokens in the ERC20PaymentClient.
    /// @dev the detail of the wallet that is being removed is either deleted in the _claimForSpecificWalletId or later down in this
    ///      function itself depending on the timestamp of when this function was called
    /// @param client The {IERC20PaymentClient} instance address from which we will remove the payment
    /// @param paymentReceiver address of the paymentReceiver whose payment order is to be removed
    /// @param walletId The ID of the paymentReceiver's payment order which is to be removed
    /// @param retryForUnclaimableAmounts boolean that determines whether the function would try to return the unclaimableAmounts along
    ///        with the vested amounts from the payment order with id = walletId to the paymentReceiver
    function removePaymentForSpecificWalletId(
        address client,
        address paymentReceiver,
        uint walletId,
        bool retryForUnclaimableAmounts
    ) external;

    /// @notice Getter for the start timestamp of a particular payment order with id = walletId associated with a particular paymentReceiver
    /// @param client address of the payment client
    /// @param paymentReceiver PaymentReceiver's address.
    /// @param walletId Id of the wallet for which start is fetched
    function startForSpecificWalletId(
        address client,
        address paymentReceiver,
        uint walletId
    ) external view returns (uint);

    /// @notice Getter for the vesting end timestamp of a particular payment order with id = walletId associated with a particular paymentReceiver
    /// @param client address of the payment client
    /// @param paymentReceiver PaymentReceiver's address.
    /// @param walletId Id of the wallet for which end is fetched
    function endForSpecificWalletId(
        address client,
        address paymentReceiver,
        uint walletId
    ) external view returns (uint);

    /// @notice Getter for the amount of tokens already released for a particular payment order with id = walletId associated with a particular paymentReceiver
    /// @param client address of the payment client
    /// @param paymentReceiver PaymentReceiver's address.
    /// @param walletId Id of the wallet for which released is fetched
    function releasedForSpecificWalletId(
        address client,
        address paymentReceiver,
        uint walletId
    ) external view returns (uint);

    /// @notice Calculates the amount of tokens that has already vested for a particular payment order with id = walletId associated with a particular paymentReceiver.
    /// @param client address of the payment client
    /// @param paymentReceiver PaymentReceiver's address.
    /// @param timestamp the time upto which we want the vested amount
    /// @param walletId Id of the wallet for which the vested amount is fetched
    function vestedAmountForSpecificWalletId(
        address client,
        address paymentReceiver,
        uint timestamp,
        uint walletId
    ) external view returns (uint);

    /// @notice Getter for the amount of releasable tokens for a particular payment order with id = walletId associated with a particular paymentReceiver.
    /// @param client address of the payment client
    /// @param paymentReceiver PaymentReceiver's address.
    /// @param walletId Id of the wallet for which the releasable amount is fetched
    function releasableForSpecificWalletId(
        address client,
        address paymentReceiver,
        uint walletId
    ) external view returns (uint);

    /// @notice Getter for the amount of tokens that could not be claimed.
    /// @param client address of the payment client
    /// @param paymentReceiver PaymentReceiver's address.
    function unclaimable(address client, address paymentReceiver)
        external
        view
        returns (uint);

    /// @notice see all active payment orders for a paymentClient associated with a particular paymentReceiver
    /// @dev the paymentReceiver must be an active paymentReceiver for the particular payment client
    /// @param client Address of the payment client
    /// @param paymentReceiver Address of the paymentReceiver
    function viewAllPaymentOrders(address client, address paymentReceiver)
        external
        view
        returns (VestingWallet[] memory);

    /// @notice tells whether a paymentReceiver has any pending payments for a particular client
    /// @dev this function is for convenience and can be easily figured out by other means in the codebase.
    /// @param client Address of the payment client
    /// @param paymentReceiver Address of the paymentReceiver
    function isActivePaymentReceiver(address client, address paymentReceiver)
        external
        view
        returns (bool);
}
