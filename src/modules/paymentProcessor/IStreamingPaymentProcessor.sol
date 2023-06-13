// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IPaymentClient} from "src/modules/base/mixins/IPaymentClient.sol";

interface IStreamingPaymentProcessor {
    //--------------------------------------------------------------------------

    // Structs

    /// @notice This struct is used to store the payment order for a particular contributor by a particular payment client
    /// @dev for _streamingWalletID, valid values will start from 1. 0 is not a valid streamingWalletID.
    /// @param _salary: The total amount that the contributor should eventually get
    /// @param _released: The amount that has been claimed by the contributor till now
    /// @param _start: The start date of the vesting period
    /// @param _dueTo: The ending of the vesting period
    /// @param _streamingWalletID: A unique identifier of a wallet for a specific paymentClient and contributor combination
    struct StreamingWallet {
        uint _salary;
        uint _released;
        uint _start;
        uint _dueTo;
        uint _streamingWalletID;
    }

    // Events

    /// @notice Emitted when a payment gets processed for execution.
    /// @param recipient The address that will receive the payment.
    /// @param amount The amount of tokens the payment consists of.
    /// @param start Timestamp at which the vesting starts.
    /// @param dueTo Timestamp at which the full amount should be claimable.
    /// @param walletId ID of the payment order that was added
    event StreamingPaymentAdded(
        address indexed paymentClient,
        address indexed recipient,
        uint amount,
        uint start,
        uint dueTo,
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
    /// @param newSalary The new amount of tokens the payment consists of.
    /// @param newDueTo The new Timestamp at which the full amount should be claimable.
    event PaymentUpdated(address recipient, uint newSalary, uint newDueTo);

    /// @notice Emitted when a running vesting schedule gets updated.
    /// @param recipient The address that will receive the payment.
    /// @param amount The amount of tokens the payment consists of.
    /// @param start Timestamp at which the vesting starts.
    /// @param dueTo Timestamp at which the full amount should be claimable.
    event InvalidStreamingOrderDiscarded(
        address indexed recipient, uint amount, uint start, uint dueTo
    );

    /// @notice Emitted when a payment gets processed for execution.
    /// @param paymentClient The payment client that originated the order.
    /// @param recipient The address that will receive the payment.
    /// @param amount The amount of tokens the payment consists of.
    /// @param createdAt Timestamp at which the order was created.
    /// @param dueTo Timestamp at which the full amount should be payed out/claimable.
    /// @param walletId ID of the payment order that was processed
    event PaymentOrderProcessed(
        address indexed paymentClient,
        address indexed recipient,
        uint amount,
        uint createdAt,
        uint dueTo,
        uint walletId
    );

    /// @notice Emitted when an amount of ERC20 tokens gets sent out of the contract.
    /// @param recipient The address that will receive the payment.
    /// @param amount The amount of tokens the payment consists of.
    event TokensReleased(
        address indexed recipient, address indexed token, uint amount
    );

    /// @notice Emitted when a payment gets processed for execution.
    /// @param paymentClient The payment client that originated the order.
    /// @param recipient The address that will receive the payment.
    /// @param amount The amount of tokens the payment consists of.
    /// @param createdAt Timestamp at which the order was created.
    /// @param dueTo Timestamp at which the full amount should be payed out/claimable.
    event PaymentOrderProcessed(
        address indexed paymentClient,
        address indexed recipient,
        uint amount,
        uint createdAt,
        uint dueTo
    );

    //--------------------------------------------------------------------------
    // Errors

    /// @notice insufficient tokens in the client to do payments
    error Module__PaymentProcessor__InsufficientTokenBalanceInClient();

    /// @notice the contributor is not owed any money by the paymentClient
    error Module__PaymentProcessor__NothingToClaim(
        address paymentClient, address contributor
    );

    /// @notice contributor's walletId for the paymentClient is not valid
    error Module__PaymentProcessor__InvalidWallet(
        address paymentClient, address contributor, uint walletId
    );

    /// @notice contributor's walletId for the paymentClient is no longer active
    error Module__PaymentProcessor__InactiveWallet(
        address paymentClient, address contributor, uint walletId
    );

    /// @notice the contributor for the given paymentClient does not exist (anymore)
    error Module__PaymentProcessor__InvalidContributor(
        address paymentClient, address contributor
    );

    /// @notice invalid caller
    error Module__PaymentManager__OnlyCallableByModule();

    /// @notice a client can only execute on its own orders
    error Module__PaymentManager__CannotCallOnOtherClientsOrders();

    //--------------------------------------------------------------------------
    // Functions

    /// @notice claim everything that the paymentClient owes to the _msgSender till the current timestamp
    /// @dev This function should be callable if the _msgSender is either an activeContributor or has some unclaimedAmounts
    /// @param client The {IPaymentClient} instance to process all claims from _msgSender
    function claimAll(IPaymentClient client) external;

    /// @notice claim the salary uptil block.timestamp from the client for a payment order with id = walletId by _msgSender
    /// @dev If for a specific walletId, the tokens could not be transferred for some reason, it will added to the unclaimableAmounts
    ///      of the contributor, and the amount would no longer hold any co-relation with the specific walletId of the contributor.
    /// @param client The {IPaymentClient} instance to process the walletId claim from _msgSender
    /// @param walletId The ID of the payment order for which claim is being made
    /// @param retryForUnclaimableAmounts boolean which determines if the function will try to pay the unclaimable amounts from earlier
    ///        along with the vested salary from the payment order with id = walletId
    function claimForSpecificWalletId(
        IPaymentClient client,
        uint walletId,
        bool retryForUnclaimableAmounts
    ) external;

    /// @notice processes all payments from an {IPaymentClient} instance.
    /// @dev in the concurrentStreamingPaymentProcessor, a payment client can have multiple payment orders for the same
    ///      contributor and they will be processed separately without being overwritten by this function.
    ///      The maximum number of payment orders that can be associated with a particular contributor by a
    ///      particular paymentClient is (2**256 - 1).
    /// @param client The {IPaymentClient} instance to process its to payments.
    function processPayments(IPaymentClient client) external;

    /// @notice Cancels all unfinished payments from an {IPaymentClient} instance.
    /// @dev this function will try to force-pay the contributors for the salary that has been vested upto the point,
    ///      this function was called. Either the salary goes to the contributor or gets accounted in unclaimableAmounts
    /// @param client The {IPaymentClient} instance for which all unfinished payments will be cancelled.
    function cancelRunningPayments(IPaymentClient client) external;

    /// @notice Deletes all payments related to a contributor & leaves unvested tokens in the PaymentClient.
    /// @dev this function calls _removePayment which goes through all the payment orders for a contributor. For the payment orders
    ///      that are completely vested, their details are deleted in the _claimForSpecificWalletId function and for others it is
    ///      deleted in the _removePayment function only, leaving the unvested tokens as balance of the paymentClient itself.
    /// @param client The {IPaymentClient} instance from which we will remove the payments
    /// @param contributor Contributor's address.
    function removePayment(IPaymentClient client, address contributor)
        external;

    /// @notice Deletes a specific payment with id = walletId for a contributor & leaves unvested tokens in the PaymentClient.
    /// @dev the detail of the wallet that is being removed is either deleted in the _claimForSpecificWalletId or later down in this
    ///      function itself depending on the timestamp of when this function was called
    /// @param client The {IPaymentClient} instance from which we will remove the payment
    /// @param contributor address of the contributor whose payment order is to be removed
    /// @param walletId The ID of the contributor's payment order which is to be removed
    /// @param retryForUnclaimableAmounts boolean that determines whether the function would try to return the unclaimableAmounts along
    ///        with the vested amounts from the payment order with id = walletId to the contributor
    function removePaymentForSpecificWalletId(
        IPaymentClient client,
        address contributor,
        uint walletId,
        bool retryForUnclaimableAmounts
    ) external;

    /// @notice Getter for the start timestamp of a particular payment order with id = walletId associated with a particular contributor
    /// @param client address of the payment client
    /// @param contributor Contributor's address.
    /// @param walletId Id of the wallet for which start is fetched
    function startForSpecificWalletId(
        address client,
        address contributor,
        uint walletId
    ) external view returns (uint);

    /// @notice Getter for the vesting dueTo timestamp of a particular payment order with id = walletId associated with a particular contributor
    /// @param client address of the payment client
    /// @param contributor Contributor's address.
    /// @param walletId Id of the wallet for which dueTo is fetched
    function dueToForSpecificWalletId(
        address client,
        address contributor,
        uint walletId
    ) external view returns (uint);

    /// @notice Getter for the amount of tokens already released for a particular payment order with id = walletId associated with a particular contributor
    /// @param client address of the payment client
    /// @param contributor Contributor's address.
    /// @param walletId Id of the wallet for which released is fetched
    function releasedForSpecificWalletId(
        address client,
        address contributor,
        uint walletId
    ) external view returns (uint);

    /// @notice Calculates the amount of tokens that has already vested for a particular payment order with id = walletId associated with a particular contributor.
    /// @param client address of the payment client
    /// @param contributor Contributor's address.
    /// @param timestamp the time upto which we want the vested amount
    /// @param walletId Id of the wallet for which the vested amount is fetched
    function vestedAmountForSpecificWalletId(
        address client,
        address contributor,
        uint timestamp,
        uint walletId
    ) external view returns (uint);

    /// @notice Getter for the amount of releasable tokens for a particular payment order with id = walletId associated with a particular contributor.
    /// @param client address of the payment client
    /// @param contributor Contributor's address.
    /// @param walletId Id of the wallet for which the releasable amount is fetched
    function releasableForSpecificWalletId(
        address client,
        address contributor,
        uint walletId
    ) external view returns (uint);

    /// @notice Getter for the amount of tokens that could not be claimed.
    /// @param client address of the payment client
    /// @param contributor Contributor's address.
    function unclaimable(address client, address contributor)
        external
        view
        returns (uint);

    /// @notice see all active payment orders for a paymentClient associated with a particular contributor
    /// @dev the contributor must be an active contributor for the particular payment client
    /// @param client Address of the payment client
    /// @param contributor Address of the contributor
    function viewAllPaymentOrders(address client, address contributor)
        external
        view
        returns (StreamingWallet[] memory);

    /// @notice Returns the IERC20 token the payment processor can process.
    function token() external view returns (IERC20);
}
