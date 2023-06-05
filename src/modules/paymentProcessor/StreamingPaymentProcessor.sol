// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

// Internal Dependencies
import {
    IPaymentProcessor,
    IPaymentClient
} from "src/modules/paymentProcessor/IPaymentProcessor.sol";

import {Module} from "src/modules/base/Module.sol";
import {ERC20} from "@oz/token/ERC20/ERC20.sol";

// Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IProposal} from "src/proposal/IProposal.sol";

/**
 * @title Payment processor module implementation #2: Linear vesting curve.
 *
 * @dev The payment module handles the money flow to the contributors
 * (e.g. how many tokens are sent to which contributor at what time).
 *
 * @author byterocket
 */

contract StreamingPaymentProcessor is Module, IPaymentProcessor {
    //--------------------------------------------------------------------------
    // Storage

    /// @notice This struct is used to store the payment order for a particular contributor by a particular payment client
    /// @dev for _streamingWalletID, valid values will start from 1. 0 is not a valid streamingWalletID.
    /// @param _salary: The total amount that the contributor should eventually get
    /// @param _released: The amount that has been claimed by the contributor till now
    /// @param _start: The start date of the vesting period
    /// @param _duration: The length of the vesting period
    /// @param _streamingWalletID: A unique identifier of a wallet for a specific paymentClient and contributor combination
    struct StreamingWallet {
        uint _salary;
        uint _released;
        uint _start;
        uint _duration;
        uint _streamingWalletID;
    }

    /// @notice tracks whether a specific contributor is active in a paymentClient
    /// @dev paymentClient => contributor => isActive(bool)
    mapping(address => mapping(address => bool)) public isActiveContributor;

    /// @notice provides a unique id for new payment orders added for a specific client & contributor combo
    /// @dev paymentClient => contributor => walletId(uint256)
    mapping(address => mapping(address => uint)) public numContributorWallets;

    /// @notice tracks all vesting details for all payment orders of a contributor for a specific paymentClient
    /// @dev paymentClient => contributor => streamingWalletID => Wallet
    mapping(address => mapping(address => mapping(uint => StreamingWallet)))
        private vestings;

    /// @notice tracks all payments that could not be made to the contributor due to any reason
    /// @dev paymentClient => contributor => unclaimableAmount
    mapping(address => mapping(address => uint)) private unclaimableAmounts;

    /// @notice list of addresses with open payment Orders per paymentClient
    /// @dev paymentClient => listOfContributors(address[]). Duplicates are not allowed.
    mapping(address => address[]) private activePayments;

    /// @notice list of walletIDs of all payment orders of a particular contributor for a particular paymentClient
    /// @dev client => contributor => arrayOfWalletIdsWithPendingPayment(uint256[])
    mapping(address => mapping(address => uint[])) private
        activeContributorPayments;

    //--------------------------------------------------------------------------
    // Events

    /// @notice Emitted when a payment gets processed for execution.
    /// @param recipient The address that will receive the payment.
    /// @param amount The amount of tokens the payment consists of.
    /// @param start Timestamp at which the vesting starts.
    /// @param duration Timestamp at which the full amount should be claimable.
    /// @param walletId ID of the payment order that was added
    event StreamingPaymentAdded(
        address indexed paymentClient,
        address indexed recipient,
        uint amount,
        uint start,
        uint duration,
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
    /// @param newDuration Number of blocks over which the amount will vest.
    event PaymentUpdated(address recipient, uint newSalary, uint newDuration);

    /// @notice Emitted when a running vesting schedule gets updated.
    /// @param recipient The address that will receive the payment.
    /// @param amount The amount of tokens the payment consists of.
    /// @param start Timestamp at which the vesting starts.
    /// @param duration Number of blocks over which the amount will vest
    event InvalidStreamingOrderDiscarded(
        address indexed recipient, uint amount, uint start, uint duration
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

    //--------------------------------------------------------------------------
    // Modifiers

    /// @notice checks that the caller is an active module
    modifier onlyModule() {
        if (!proposal().isModule(_msgSender())) {
            revert Module__PaymentManager__OnlyCallableByModule();
        }
        _;
    }

    /// @notice checks that the client is calling for itself
    modifier validClient(IPaymentClient client) {
        if (_msgSender() != address(client)) {
            revert Module__PaymentManager__CannotCallOnOtherClientsOrders();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // External Functions

    /// @inheritdoc Module
    function init(
        IProposal proposal_,
        Metadata memory metadata,
        bytes memory /*configdata*/
    ) external override(Module) initializer {
        __Module_init(proposal_, metadata);
    }

    /// @notice used to claim everything that the paymentClient owes to the _msgSender till the current timestamp
    /// @dev This function should be callable if the _msgSender is either an activeContributor or has some unclaimedAmounts
    /// @param client The {IPaymentClient} instance to process all claims from _msgSender
    function claimAll(IPaymentClient client) external {
        if (
            !(
                isActiveContributor[address(client)][_msgSender()]
                    || unclaimable(address(client), _msgSender()) > 0
            )
        ) {
            revert Module__PaymentProcessor__NothingToClaim(
                address(client), _msgSender()
            );
        }

        _claimAll(address(client), _msgSender());
    }

    /// @notice used to claim the salary uptil block.timestamp from the client for a payment order with id = walletId by _msgSender
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
    ) external {
        if (
            !isActiveContributor[address(client)][_msgSender()]
                || (walletId > numContributorWallets[address(client)][_msgSender()])
        ) {
            revert Module__PaymentProcessor__InvalidWallet(
                address(client), _msgSender(), walletId
            );
        }

        if (
            _verifyActiveWalletId(address(client), _msgSender(), walletId)
                == type(uint).max
        ) {
            revert Module__PaymentProcessor__InactiveWallet(
                address(client), _msgSender(), walletId
            );
        }

        _claimForSpecificWalletId(
            address(client), _msgSender(), walletId, retryForUnclaimableAmounts
        );
    }

    /// @notice processes all payments from an {IPaymentClient} instance.
    /// @dev in the concurrentStreamingPaymentProcessor, a payment client can have multiple payment orders for the same
    ///      contributor and they will be processed separately without being overwritten by this function.
    ///      The maximum number of payment orders that can be associated with a particular contributor by a
    ///      particular paymentClient is (2**256 - 1).
    /// @param client The {IPaymentClient} instance to process its to payments.
    function processPayments(IPaymentClient client)
        external
        onlyModule
        validClient(client)
    {
        //We check if there are any new paymentOrders, without processing them
        if (client.paymentOrders().length > 0) {
            // Collect outstanding orders and their total token amount.
            IPaymentClient.PaymentOrder[] memory orders;
            uint totalAmount;
            (orders, totalAmount) = client.collectPaymentOrders();

            if (token().balanceOf(address(client)) < totalAmount) {
                revert
                    Module__PaymentProcessor__InsufficientTokenBalanceInClient();
            }

            // Generate Streaming Payments for all orders
            address _recipient;
            uint _amount;
            uint _start;
            uint _duration;
            uint _walletId;

            uint numOrders = orders.length;

            for (uint i; i < numOrders;) {
                _recipient = orders[i].recipient;
                _amount = orders[i].amount;
                _start = orders[i].createdAt;
                _duration = (orders[i].dueTo - _start);

                // We can't increase the value of numContributorWallets here, as it is possible that in the next
                // _addPayment step, this wallet is not actually added. So, we will increment the value of this
                // mapping there only, and for the same reason we cannot set the isActiveContributor mapping
                // to true here.
                _walletId =
                    numContributorWallets[address(client)][_recipient] + 1;

                _addPayment(
                    address(client),
                    _recipient,
                    _amount,
                    _start,
                    _duration,
                    _walletId
                );

                emit PaymentOrderProcessed(
                    address(client),
                    _recipient,
                    _amount,
                    _start,
                    _duration,
                    _walletId
                );

                unchecked {
                    ++i;
                }
            }
        }
    }

    /// @notice Cancels all unfinished payments from an {IPaymentClient} instance.
    /// @dev this function will try to force-pay the contributors for the salary that has been vested upto the point,
    ///      this function was called. Either the salary goes to the contributor or gets accounted in unclaimableAmounts
    /// @param client The {IPaymentClient} instance for which all unfinished payments will be cancelled.
    function cancelRunningPayments(IPaymentClient client)
        external
        onlyModule
        validClient(client)
    {
        _cancelRunningOrders(address(client));
    }

    /// @notice Deletes all payments related to a contributor & leaves unvested tokens in the PaymentClient.
    /// @dev this function calls _removePayment which goes through all the payment orders for a contributor. For the payment orders
    ///      that are completely vested, their details are deleted in the _claimForSpecificWalletId function and for others it is
    ///      deleted in the _removePayment function only, leaving the unvested tokens as balance of the paymentClient itself.
    /// @param client The {IPaymentClient} instance from which we will remove the payments
    /// @param contributor Contributor's address.
    function removePayment(IPaymentClient client, address contributor)
        external
        onlyAuthorized
    {
        if (
            _findAddressInActivePayments(address(client), contributor)
                == type(uint).max
        ) {
            revert Module__PaymentProcessor__InvalidContributor(
                address(client), contributor
            );
        }
        _removePayment(address(client), contributor);
    }

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
    ) external onlyAuthorized {
        // First, we **claim** the vested funds from this specific walletId
        _claimForSpecificWalletId(
            address(client), contributor, walletId, retryForUnclaimableAmounts
        );

        // Now, we need to check when this function was called to determine if we need to delete the details pertaining to this wallet or not
        uint startContributor =
            startForSpecificWalletId(address(client), contributor, walletId);
        uint durationContributor =
            durationForSpecificWalletId(address(client), contributor, walletId);

        if (block.timestamp < startContributor + durationContributor) {
            // deletes activeContributorPayments
            _removePaymentForSpecificWalletId(
                address(client), contributor, walletId
            );

            // deletes vesting information
            _removeVestingInformationForSpecificWalletId(
                address(client), contributor, walletId
            );

            // deletes activePayments & isActiveContributor if it was the contributor's last paymentOrder
            if (
                activeContributorPayments[address(client)][contributor].length
                    == 0
            ) {
                isActiveContributor[address(client)][contributor] = false;
                _removeContributorFromActivePayments(
                    address(client), contributor
                );
            }
        }
    }

    //--------------------------------------------------------------------------
    // Public Functions

    /// @notice Getter for the start timestamp of a particular payment order with id = walletId associated with a particular contributor
    /// @param client address of the payment client
    /// @param contributor Contributor's address.
    /// @param walletId Id of the wallet for which start is fetched
    function startForSpecificWalletId(
        address client,
        address contributor,
        uint walletId
    ) public view returns (uint) {
        return vestings[client][contributor][walletId]._start;
    }

    /// @notice Getter for the vesting duration of a particular payment order with id = walletId associated with a particular contributor
    /// @param client address of the payment client
    /// @param contributor Contributor's address.
    /// @param walletId Id of the wallet for which duration is fetched
    function durationForSpecificWalletId(
        address client,
        address contributor,
        uint walletId
    ) public view returns (uint) {
        return vestings[client][contributor][walletId]._duration;
    }

    /// @notice Getter for the amount of tokens already released for a particular payment order with id = walletId associated with a particular contributor
    /// @param client address of the payment client
    /// @param contributor Contributor's address.
    /// @param walletId Id of the wallet for which released is fetched
    function releasedForSpecificWalletId(
        address client,
        address contributor,
        uint walletId
    ) public view returns (uint) {
        return vestings[client][contributor][walletId]._released;
    }

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
    ) public view returns (uint) {
        return _vestingScheduleForSpecificWalletId(
            client, contributor, timestamp, walletId
        );
    }

    /// @notice Getter for the amount of releasable tokens for a particular payment order with id = walletId associated with a particular contributor.
    /// @param client address of the payment client
    /// @param contributor Contributor's address.
    /// @param walletId Id of the wallet for which the releasable amount is fetched
    function releasableForSpecificWalletId(
        address client,
        address contributor,
        uint walletId
    ) public view returns (uint) {
        return vestedAmountForSpecificWalletId(
            client, contributor, block.timestamp, walletId
        ) - releasedForSpecificWalletId(client, contributor, walletId);
    }

    /// @notice Getter for the amount of tokens that could not be claimed.
    /// @param client address of the payment client
    /// @param contributor Contributor's address.
    function unclaimable(address client, address contributor)
        public
        view
        returns (uint)
    {
        return unclaimableAmounts[client][contributor];
    }

    /// @notice Returns the token used by the proposal to pay salaries to the contributors
    function token() public view returns (IERC20) {
        return this.proposal().token();
    }

    /// @notice used to see all active payment orders for a paymentClient associated with a particular contributor
    /// @dev the contributor must be an active contributor for the particular payment client
    /// @param client Address of the payment client
    /// @param contributor Address of the contributor
    function viewAllPaymentOrders(address client, address contributor)
        public
        view
        returns (StreamingWallet[] memory)
    {
        if (!(isActiveContributor[client][contributor])) {
            revert Module__PaymentProcessor__InvalidContributor(
                client, contributor
            );
        }

        uint[] memory contributorWalletsArray =
            activeContributorPayments[client][contributor];
        uint contributorWalletsArrayLength = contributorWalletsArray.length;

        uint index;
        StreamingWallet[] memory contributorStreamingWallets =
            new StreamingWallet[](contributorWalletsArrayLength);

        for (index; index < contributorWalletsArrayLength;) {
            contributorStreamingWallets[index] =
                vestings[client][contributor][contributorWalletsArray[index]];

            unchecked {
                ++index;
            }
        }

        return contributorStreamingWallets;
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    /// @notice used to find whether a particular contributor has pending payments with a client
    /// @dev This function returns the first instance of the contributor address in the activePayments[client] array, but that
    ///      is completely fine as the activePayments[client] array does not allow duplicates.
    /// @param client address of the payment client
    /// @param contributor address of the contributor
    /// @return the index of the contributor in the activePayments[client] array. Returns type(uint256).max otherwise.
    function _findAddressInActivePayments(address client, address contributor)
        internal
        view
        returns (uint)
    {
        address[] memory contribSearchArray = activePayments[client];

        uint length = activePayments[client].length;
        for (uint i; i < length;) {
            if (contribSearchArray[i] == contributor) {
                return i;
            }
            unchecked {
                ++i;
            }
        }
        return type(uint).max;
    }

    /// @notice used to find whether a particular payment order associated with a contributor and paymentClient with id = walletId is active or not
    /// @dev active means that the particular payment order is still to be paid out/claimed. This function returns the first instance of the walletId
    ///      in the activeContributorPayments[client][contributor] array, but that is fine as the array does not allow duplicates.
    /// @param client address of the payment client
    /// @param contributor address of the contributor
    /// @param walletId ID of the payment order that needs to be searched
    /// @return the index of the contributor in the activeContributorPayments[client][contributor] array. Returns type(uint256).max otherwise.
    function _verifyActiveWalletId(
        address client,
        address contributor,
        uint walletId
    ) internal view returns (uint) {
        uint[] memory contributorWalletsArray =
            activeContributorPayments[client][contributor];
        uint contributorWalletsArrayLength = contributorWalletsArray.length;

        uint index;
        for (index; index < contributorWalletsArrayLength;) {
            if (contributorWalletsArray[index] == walletId) {
                return index;
            }
            unchecked {
                ++index;
            }
        }

        return type(uint).max;
    }

    /// @notice used to cancel all unfinished payments from the client
    /// @dev all active payment orders of all active contributors associated with the client, are iterated through and
    ///      their details are deleted
    /// @param client address of the payment client
    function _cancelRunningOrders(address client) internal {
        address[] memory contributors = activePayments[client];
        uint contributorsLength = contributors.length;

        uint index;
        for (index; index < contributorsLength;) {
            _removePayment(client, contributors[index]);

            unchecked {
                ++index;
            }
        }
    }

    /// @notice Deletes all payments related to a contributor & leaves unvested tokens in the PaymentClient.
    /// @dev this function calls _removePayment which goes through all the payment orders for a contributor. For the payment orders
    ///      that are completely vested, their details are deleted in the _claimForSpecificWalletId function and for others it is
    ///      deleted in the _removePayment function only, leaving the unvested tokens as balance of the paymentClient itself.
    /// @param client address of the payment client
    /// @param contributor address of the contributor
    function _removePayment(address client, address contributor) internal {
        uint[] memory contributorWalletsArray =
            activeContributorPayments[client][contributor];
        uint contributorWalletsArrayLength = contributorWalletsArray.length;

        uint index;
        uint startContributor;
        uint durationContributor;
        uint walletId;
        for (index; index < contributorWalletsArrayLength;) {
            walletId = contributorWalletsArray[index];
            _claimForSpecificWalletId(client, contributor, walletId, true);

            startContributor =
                startForSpecificWalletId(client, contributor, walletId);
            durationContributor =
                durationForSpecificWalletId(client, contributor, walletId);

            if (block.timestamp < startContributor + durationContributor) {
                _removePaymentForSpecificWalletId(client, contributor, walletId);

                _removeVestingInformationForSpecificWalletId(
                    client, contributor, walletId
                );

                if (activeContributorPayments[client][contributor].length == 0)
                {
                    isActiveContributor[client][contributor] = false;
                    _removeContributorFromActivePayments(client, contributor);
                }

                emit StreamingPaymentRemoved(client, contributor, walletId);
            }

            unchecked {
                ++index;
            }
        }
    }

    /// @notice used to remove the payment order with id = walletId from the activeContributorPayments[client][contributor] array.
    /// @dev This function simply removes a particular payment order from the earlier mentioned array. The implications of removing a payment order
    ///      from this array have to be handled outside of this function, such as checking whether the contributor is still active or not, etc.
    /// @param client Address of the payment client
    /// @param contributor Address of the contributor
    /// @param walletId Id of the payment order that needs to be removed
    function _removePaymentForSpecificWalletId(
        address client,
        address contributor,
        uint walletId
    ) internal {
        uint walletIdIndex =
            _verifyActiveWalletId(client, contributor, walletId);

        if (walletIdIndex == type(uint).max) {
            revert Module__PaymentProcessor__InactiveWallet(
                address(client), _msgSender(), walletId
            );
        }

        activeContributorPayments[client][contributor][walletIdIndex] =
        activeContributorPayments[client][contributor][activeContributorPayments[client][contributor]
            .length - 1];

        activeContributorPayments[client][contributor].pop();
    }

    /// @notice used to remove the vesting info of the payment order with id = walletId.
    /// @dev This function simply removes the vesting details of a particular payment order. The implications of removing the vesting info of
    ///      payment order have to be handled outside of this function.
    /// @param client Address of the payment client
    /// @param contributor Address of the contributor
    /// @param walletId Id of the payment order whose vesting information needs to be removed
    function _removeVestingInformationForSpecificWalletId(
        address client,
        address contributor,
        uint walletId
    ) internal {
        delete vestings[client][contributor][walletId];
    }

    /// @notice used to remove a contributor as one of the beneficiaries of the payment client
    /// @dev this function will be called when all the payment orders of a payment client associated with a particular contributor has been fulfilled.
    ///      Also signals that the contributor is no longer an active contributor according to the payment client
    /// @param client address of the payment client
    /// @param contributor address of the contributor
    function _removeContributorFromActivePayments(
        address client,
        address contributor
    ) internal {
        // Find the contributor's index in the array of activePayments mapping.
        uint contributorIndex =
            _findAddressInActivePayments(client, contributor);

        if (contributorIndex == type(uint).max) {
            revert Module__PaymentProcessor__InvalidContributor(
                client, contributor
            );
        }

        // Replace the element to be deleted with the last element of the array
        uint contributorsLength = activePayments[client].length;
        activePayments[client][contributorIndex] =
            activePayments[client][contributorsLength - 1];

        // pop the last element of the array
        activePayments[client].pop();
    }

    /// @notice Adds a new payment containing the details of the monetary flow
    ///         depending on the module.
    /// @dev This function can handle multiple payment orders associated with a particular contributor for the same payment client
    ///      without overriding the earlier ones. The maximum payment orders for a contributor MUST BE capped at (2**256-1).
    /// @param _contributor Contributor's address.
    /// @param _salary Salary contributor will receive per epoch.
    /// @param _start Start vesting timestamp.
    /// @param _duration Streaming duration timestamp.
    /// @param _walletId ID of the new wallet of the a particular contributor being added
    function _addPayment(
        address client,
        address _contributor,
        uint _salary,
        uint _start,
        uint _duration,
        uint _walletId
    ) internal {
        if (
            !validAddress(_contributor) || !validSalary(_salary)
                || !validStart(_start) || !validDuration(_duration)
        ) {
            emit InvalidStreamingOrderDiscarded(
                _contributor, _salary, _start, _duration
            );
        } else {
            ++numContributorWallets[client][_contributor];
            isActiveContributor[client][_contributor] = true;

            vestings[client][_contributor][_walletId] =
                StreamingWallet(_salary, 0, _start, _duration, _walletId);

            // We do not want activePayments[client] to have duplicate contributor entries
            // So we avoid pushing the _contributor to activePayments[client] if it already exists
            if (
                _findAddressInActivePayments(client, _contributor)
                    == type(uint).max
            ) {
                activePayments[client].push(_contributor);
            }

            activeContributorPayments[client][_contributor].push(_walletId);

            emit StreamingPaymentAdded(
                client, _contributor, _salary, _start, _duration, _walletId
            );
        }
    }

    /// @notice used to claim all the payment orders associated with a particular contributor for a given payment client
    /// @dev Calls the _claimForSpecificWalletId function for all the active wallets of a particular contributor for the
    ///      given payment client. Depending on the time this function is called, the vested payments are transferred to the
    ///      contributor or accounted in unclaimableAmounts.
    ///      For payment orders that are fully vested, their details are deleted and changes are made to the state of the contract accordingly.
    /// @param client address of the payment client
    /// @param contributor address of the contributor for which every payment order will be claimed
    function _claimAll(address client, address contributor) internal {
        uint[] memory contributorWalletsArray =
            activeContributorPayments[client][contributor];
        uint contributorWalletsArrayLength = contributorWalletsArray.length;

        uint index;
        for (index; index < contributorWalletsArrayLength;) {
            _claimForSpecificWalletId(
                client, contributor, contributorWalletsArray[index], true
            );

            unchecked {
                ++index;
            }
        }
    }

    /// @notice used to claim the payment order of a particular contributor for a given payment client with id = walletId
    /// @dev Depending on the time this function is called, the vested payments are transferred to the contributor or accounted in unclaimableAmounts.
    ///      For payment orders that are fully vested, their details are deleted and changes are made to the state of the contract accordingly.
    /// @param client address of the payment client
    /// @param contributor address of the contributor for which every payment order will be claimed
    /// @param walletId ID of the payment order that is to be claimed
    /// @param retryForUnclaimableAmounts boolean which determines if the function will try to pay the unclaimable amounts from earlier
    ///        along with the vested salary from the payment order with id = walletId
    function _claimForSpecificWalletId(
        address client,
        address contributor,
        uint walletId,
        bool retryForUnclaimableAmounts
    ) internal {
        uint amount =
            releasableForSpecificWalletId(client, contributor, walletId);
        vestings[client][contributor][walletId]._released += amount;

        if (
            retryForUnclaimableAmounts
                && unclaimableAmounts[client][contributor] > 0
        ) {
            amount += unclaimable(client, contributor);
            delete unclaimableAmounts[client][contributor];
        }

        address _token = address(token());

        (bool success, bytes memory data) = _token.call(
            abi.encodeWithSelector(
                IERC20(_token).transferFrom.selector,
                client,
                contributor,
                amount
            )
        );

        if (success && (data.length == 0 || abi.decode(data, (bool)))) {
            emit TokensReleased(contributor, _token, amount);
        } else {
            unclaimableAmounts[client][contributor] += amount;
        }

        uint startContributor =
            startForSpecificWalletId(client, contributor, walletId);
        uint durationContributor =
            durationForSpecificWalletId(client, contributor, walletId);

        // This if conditional block represents that nothing more remains to be vested from the specific walletId
        if (block.timestamp >= startContributor + durationContributor) {
            // 1. remove walletId from the activeContributorPayments mapping
            _removePaymentForSpecificWalletId(client, contributor, walletId);

            // 2. delete the vesting information for this specific walletId
            _removeVestingInformationForSpecificWalletId(
                client, contributor, walletId
            );

            // 3. activePayments and isActive would be updated if this was the last wallet that was associated with the contributor was claimed.
            //    This would also mean that, it is possible for a contributor to be inactive and still have money owed to them (unclaimableAmounts)
            if (activeContributorPayments[client][contributor].length == 0) {
                isActiveContributor[client][contributor] = false;
                _removeContributorFromActivePayments(client, contributor);
            }

            // Note We do not need to update unclaimableAmounts, as it is already done earlier depending on the `transferFrom` call.
            // Note Also, we do not need to update numContributorWallets, as claiming completely from a wallet does not affect this mapping.

            emit StreamingPaymentRemoved(client, contributor, walletId);
        }
    }

    /// @notice Virtual implementation of the vesting formula.
    ///         Returns the amount vested, as a function of time,
    ///         for an asset given its total historical allocation.
    /// @param contributor The contributor to check on.
    /// @param timestamp Current block.timestamp
    /// @param walletId ID of a particular contributor's wallet whose vesting schedule needs to be checked
    function _vestingScheduleForSpecificWalletId(
        address client,
        address contributor,
        uint timestamp,
        uint walletId
    ) internal view virtual returns (uint) {
        uint totalAllocation = vestings[client][contributor][walletId]._salary;
        uint startContributor =
            startForSpecificWalletId(client, contributor, walletId);
        uint durationContributor =
            durationForSpecificWalletId(client, contributor, walletId);

        if (timestamp < startContributor) {
            return 0;
        } else if (timestamp >= startContributor + durationContributor) {
            return totalAllocation;
        } else {
            return (totalAllocation * (timestamp - startContributor))
                / durationContributor;
        }
    }

    /// @notice validate address input.
    /// @param addr Address to validate.
    /// @return True if address is valid.
    function validAddress(address addr) internal view returns (bool) {
        return !(
            addr == address(0) || addr == _msgSender() || addr == address(this)
                || addr == address(proposal())
        );
    }

    /// @notice validate uint salary input.
    /// @param _salary uint to validate.
    /// @return True if uint is valid.
    function validSalary(uint _salary) internal pure returns (bool) {
        return !(_salary == 0);
    }

    /// @notice validate uint start input.
    /// @param _start uint to validate.
    /// @return True if uint is valid.
    function validStart(uint _start) internal view returns (bool) {
        return !(_start < block.timestamp || _start >= type(uint).max);
    }

    /// @notice validate uint duration input.
    /// @param _duration uint to validate.
    /// @return True if duration is valid.
    function validDuration(uint _duration) internal pure returns (bool) {
        return !(_duration == 0);
    }
}
