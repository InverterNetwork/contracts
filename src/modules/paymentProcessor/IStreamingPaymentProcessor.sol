// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IERC20PaymentClient} from "src/modules/base/mixins/IERC20PaymentClient.sol";
import {IPaymentProcessor} from
    "src/modules/paymentProcessor/IPaymentProcessor.sol";

interface IStreamingPaymentProcessor is IPaymentProcessor {
    //--------------------------------------------------------------------------

    // Structs

    /// @notice This struct is used to store the payment order for a particular contributor by a particular payment client
    /// @dev for _vestingWalletID, valid values will start from 1. 0 is not a valid vestingWalletID.
    /// @param _salary: The total amount that the contributor should eventually get
    /// @param _released: The amount that has been claimed by the contributor till now
    /// @param _start: The start date of the vesting period
    /// @param _dueTo: The ending of the vesting period
    /// @param _vestingWalletID: A unique identifier of a wallet for a specific ERC20PaymentClient and contributor combination
    struct VestingWallet {
        uint _salary;
        uint _released;
        uint _start;
        uint _dueTo;
        uint _vestingWalletID;
    }

    // Events

    /// @notice Emitted when a payment gets processed for execution.
    /// @param recipient The address that will receive the payment.
    /// @param amount The amount of tokens the payment consists of.
    /// @param start Timestamp at which the vesting starts.
    /// @param dueTo Timestamp at which the full amount should be claimable.
    /// @param walletId ID of the payment order that was added
    event StreamingPaymentAdded(
        address indexed ERC20PaymentClient,
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
        address indexed ERC20PaymentClient,
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
    /// @param ERC20PaymentClient The payment client that originated the order.
    /// @param recipient The address that will receive the payment.
    /// @param amount The amount of tokens the payment consists of.
    /// @param createdAt Timestamp at which the order was created.
    /// @param dueTo Timestamp at which the full amount should be payed out/claimable.
    /// @param walletId ID of the payment order that was processed
    event PaymentOrderProcessed(
        address indexed ERC20PaymentClient,
        address indexed recipient,
        uint amount,
        uint createdAt,
        uint dueTo,
        uint walletId
    );

    //--------------------------------------------------------------------------
    // Errors

    /// @notice insufficient tokens in the client to do payments
    error Module__PaymentProcessor__InsufficientTokenBalanceInClient();

    /// @notice the contributor is not owed any money by the ERC20PaymentClient
    error Module__PaymentProcessor__NothingToClaim(
        address ERC20PaymentClient, address contributor
    );

    /// @notice contributor's walletId for the ERC20PaymentClient is not valid
    error Module__PaymentProcessor__InvalidWallet(
        address ERC20PaymentClient, address contributor, uint walletId
    );

    /// @notice contributor's walletId for the ERC20PaymentClient is no longer active
    error Module__PaymentProcessor__InactiveWallet(
        address ERC20PaymentClient, address contributor, uint walletId
    );

    /// @notice the contributor for the given ERC20PaymentClient does not exist (anymore)
    error Module__PaymentProcessor__InvalidContributor(
        address ERC20PaymentClient, address contributor
    );

    //--------------------------------------------------------------------------
    // Functions

    /// @notice claim everything that the ERC20PaymentClient owes to the _msgSender till the current timestamp
    /// @dev This function should be callable if the _msgSender is either an activeContributor or has some unclaimedAmounts
    /// @param client The {IERC20PaymentClient} instance to process all claims from _msgSender
    function claimAll(IERC20PaymentClient client) external;

    /// @notice claim the salary uptil block.timestamp from the client for a payment order with id = walletId by _msgSender
    /// @dev If for a specific walletId, the tokens could not be transferred for some reason, it will added to the unclaimableAmounts
    ///      of the contributor, and the amount would no longer hold any co-relation with the specific walletId of the contributor.
    /// @param client The {IERC20PaymentClient} instance to process the walletId claim from _msgSender
    /// @param walletId The ID of the payment order for which claim is being made
    /// @param retryForUnclaimableAmounts boolean which determines if the function will try to pay the unclaimable amounts from earlier
    ///        along with the vested salary from the payment order with id = walletId
    function claimForSpecificWalletId(
        IERC20PaymentClient client,
        uint walletId,
        bool retryForUnclaimableAmounts
    ) external;

    /// @notice Deletes all payments related to a contributor & leaves unvested tokens in the ERC20PaymentClient.
    /// @dev this function calls _removePayment which goes through all the payment orders for a contributor. For the payment orders
    ///      that are completely vested, their details are deleted in the _claimForSpecificWalletId function and for others it is
    ///      deleted in the _removePayment function only, leaving the unvested tokens as balance of the ERC20PaymentClient itself.
    /// @param client The {IERC20PaymentClient} instance from which we will remove the payments
    /// @param contributor Contributor's address.
    function removeAllContributorPayments(
        IERC20PaymentClient client,
        address contributor
    ) external;

    /// @notice Deletes a specific payment with id = walletId for a contributor & leaves unvested tokens in the ERC20PaymentClient.
    /// @dev the detail of the wallet that is being removed is either deleted in the _claimForSpecificWalletId or later down in this
    ///      function itself depending on the timestamp of when this function was called
    /// @param client The {IERC20PaymentClient} instance from which we will remove the payment
    /// @param contributor address of the contributor whose payment order is to be removed
    /// @param walletId The ID of the contributor's payment order which is to be removed
    /// @param retryForUnclaimableAmounts boolean that determines whether the function would try to return the unclaimableAmounts along
    ///        with the vested amounts from the payment order with id = walletId to the contributor
    function removePaymentForSpecificWalletId(
        IERC20PaymentClient client,
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

    /// @notice see all active payment orders for a ERC20PaymentClient associated with a particular contributor
    /// @dev the contributor must be an active contributor for the particular payment client
    /// @param client Address of the payment client
    /// @param contributor Address of the contributor
    function viewAllPaymentOrders(address client, address contributor)
        external
        view
        returns (VestingWallet[] memory);

    /// @notice tells whether a contributor has any pending payments for a particular client
    /// @dev this function is for convenience and can be easily figured out by other means in the codebase.
    /// @param client Address of the payment client
    /// @param contributor Address of the contributor
    function isActiveContributor(address client, address contributor)
        external
        view
        returns (bool);
}
