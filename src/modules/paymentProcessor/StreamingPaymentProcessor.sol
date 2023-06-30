// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

// Internal Dependencies
import {
    IStreamingPaymentProcessor,
    IPaymentClient
} from "src/modules/paymentProcessor/IStreamingPaymentProcessor.sol";

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
 * Concurrent streaming allows for several active vestings per destination address.
 *
 * @author Inverter Network
 */

contract StreamingPaymentProcessor is Module, IStreamingPaymentProcessor {
    //--------------------------------------------------------------------------
    // Storage

    /// @notice tracks whether a specific contributor is active in a paymentClient
    /// @dev paymentClient => contributor => isActive(bool)
    mapping(address => mapping(address => bool)) public isActiveContributor;

    /// @notice provides a unique id for new payment orders added for a specific client & contributor combo
    /// @dev paymentClient => contributor => walletId(uint)
    mapping(address => mapping(address => uint)) public numStreamingWallets;

    /// @notice tracks all vesting details for all payment orders of a contributor for a specific paymentClient
    /// @dev paymentClient => contributor => streamingWalletID => Wallet
    mapping(address => mapping(address => mapping(uint => StreamingWallet)))
        private vestings;

    /// @notice tracks all payments that could not be made to the contributor due to any reason
    /// @dev paymentClient => contributor => unclaimableAmount
    mapping(address => mapping(address => uint)) private unclaimableAmounts;

    /// @notice list of addresses with open payment Orders per paymentClient
    /// @dev paymentClient => listOfContributors(address[]). Duplicates are not allowed.
    mapping(address => address[]) private activeContributors;

    /// @notice list of walletIDs of all payment orders of a particular contributor for a particular paymentClient
    /// @dev client => contributor => arrayOfWalletIdsWithPendingPayment(uint[])
    mapping(address => mapping(address => uint[])) private
        activeContributorPayments;

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

    modifier activeContributor(address client, address contributor) {
        if (!(isActiveContributor[client][contributor])) {
            revert Module__PaymentProcessor__InvalidContributor(
                client, contributor
            );
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

    /// @inheritdoc IStreamingPaymentProcessor
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

    /// @inheritdoc IStreamingPaymentProcessor
    function claimForSpecificWalletId(
        IPaymentClient client,
        uint walletId,
        bool retryForUnclaimableAmounts
    ) external {
        if (
            !isActiveContributor[address(client)][_msgSender()]
                || (walletId > numStreamingWallets[address(client)][_msgSender()])
        ) {
            revert Module__PaymentProcessor__InvalidWallet(
                address(client), _msgSender(), walletId
            );
        }

        if (
            _findActiveWalletId(address(client), _msgSender(), walletId)
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

    /// @inheritdoc IStreamingPaymentProcessor
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

            // Generate Streaming Payments for all orders
            address _recipient;
            uint _amount;
            uint _start;
            uint _dueTo;
            uint _walletId;

            uint numOrders = orders.length;

            for (uint i; i < numOrders;) {
                _recipient = orders[i].recipient;
                _amount = orders[i].amount;
                _start = orders[i].createdAt;
                _dueTo = orders[i].dueTo;
                _walletId = numStreamingWallets[address(client)][_recipient] + 1;

                _addPayment(
                    address(client),
                    _recipient,
                    _amount,
                    _start,
                    _dueTo,
                    _walletId
                );

                emit PaymentOrderProcessed(
                    address(client),
                    _recipient,
                    _amount,
                    _start,
                    _dueTo,
                    _walletId
                );

                unchecked {
                    ++i;
                }
            }
        }
    }

    /// @inheritdoc IStreamingPaymentProcessor
    function cancelRunningPayments(IPaymentClient client)
        external
        onlyModule
        validClient(client)
    {
        _cancelRunningOrders(address(client));
    }

    /// @inheritdoc IStreamingPaymentProcessor
    function removeAllPaymentForContributor(
        IPaymentClient client,
        address contributor
    ) external onlyAuthorized {
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

    /// @inheritdoc IStreamingPaymentProcessor
    function removePaymentForSpecificWalletId(
        IPaymentClient client,
        address contributor,
        uint walletId,
        bool retryForUnclaimableAmounts
    ) external onlyAuthorized {
        // First, we give the vested funds from this specific walletId to the beneficiary
        _claimForSpecificWalletId(
            address(client), contributor, walletId, retryForUnclaimableAmounts
        );

        // Now, we need to check when this function was called to determine if we need to delete the details pertaining to this wallet or not
        // We will delete the payment order in question, if it hasn't already reached the end of its duration.
        if (
            block.timestamp
                < dueToForSpecificWalletId(address(client), contributor, walletId)
        ) {
            _afterClaimCleanup(address(client), contributor, walletId);
        }
    }

    //--------------------------------------------------------------------------
    // Public Functions

    /// @inheritdoc IStreamingPaymentProcessor
    function startForSpecificWalletId(
        address client,
        address contributor,
        uint walletId
    ) public view returns (uint) {
        return vestings[client][contributor][walletId]._start;
    }

    /// @inheritdoc IStreamingPaymentProcessor
    function dueToForSpecificWalletId(
        address client,
        address contributor,
        uint walletId
    ) public view returns (uint) {
        return vestings[client][contributor][walletId]._dueTo;
    }

    /// @inheritdoc IStreamingPaymentProcessor
    function releasedForSpecificWalletId(
        address client,
        address contributor,
        uint walletId
    ) public view returns (uint) {
        return vestings[client][contributor][walletId]._released;
    }

    /// @inheritdoc IStreamingPaymentProcessor
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

    /// @inheritdoc IStreamingPaymentProcessor
    function releasableForSpecificWalletId(
        address client,
        address contributor,
        uint walletId
    ) public view returns (uint) {
        return vestedAmountForSpecificWalletId(
            client, contributor, block.timestamp, walletId
        ) - releasedForSpecificWalletId(client, contributor, walletId);
    }

    /// @inheritdoc IStreamingPaymentProcessor
    function unclaimable(address client, address contributor)
        public
        view
        returns (uint)
    {
        return unclaimableAmounts[client][contributor];
    }

    /// @inheritdoc IStreamingPaymentProcessor
    function token() public view returns (IERC20) {
        return this.proposal().token();
    }

    /// @inheritdoc IStreamingPaymentProcessor
    function viewAllPaymentOrders(address client, address contributor)
        external
        view
        activeContributor(client, contributor)
        returns (StreamingWallet[] memory)
    {
        uint[] memory streamingWalletsArray =
            activeContributorPayments[client][contributor];
        uint streamingWalletsArrayLength = streamingWalletsArray.length;

        uint index;
        StreamingWallet[] memory contributorStreamingWallets =
            new StreamingWallet[](streamingWalletsArrayLength);

        for (index; index < streamingWalletsArrayLength;) {
            contributorStreamingWallets[index] =
                vestings[client][contributor][streamingWalletsArray[index]];

            unchecked {
                ++index;
            }
        }

        return contributorStreamingWallets;
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    /// @notice common set of steps to be taken after everything has been claimed from a specific wallet
    /// @param client address of the payment client
    /// @param contributor address of the contributor
    /// @param walletId ID of the wallet that was fully claimed
    function _afterClaimCleanup(
        address client,
        address contributor,
        uint walletId
    ) internal {
        // 1. remove walletId from the activeContributorPayments mapping
        _removePaymentForSpecificWalletId(client, contributor, walletId);

        // 2. delete the vesting information for this specific walletId
        _removeVestingInformationForSpecificWalletId(
            client, contributor, walletId
        );

        // 3. activeContributors and isActive would be updated if this was the last wallet that was associated with the contributor was claimed.
        //    This would also mean that, it is possible for a contributor to be inactive and still have money owed to them (unclaimableAmounts)
        if (activeContributorPayments[client][contributor].length == 0) {
            isActiveContributor[client][contributor] = false;
            _removeContributorFromActivePayments(client, contributor);
        }

        // Note We do not need to update unclaimableAmounts, as it is already done earlier depending on the `transferFrom` call.
        // Note Also, we do not need to update numStreamingWallets, as claiming completely from a wallet does not affect this mapping.

        // 4. emit an event broadcasting that a particular payment has been removed
        emit StreamingPaymentRemoved(client, contributor, walletId);
    }

    /// @notice used to find whether a particular contributor has pending payments with a client
    /// @dev This function returns the first instance of the contributor address in the activeContributors[client] array, but that
    ///      is completely fine as the activeContributors[client] array does not allow duplicates.
    /// @param client address of the payment client
    /// @param contributor address of the contributor
    /// @return the index of the contributor in the activeContributors[client] array. Returns type(uint256).max otherwise.
    function _findAddressInActivePayments(address client, address contributor)
        internal
        view
        returns (uint)
    {
        address[] memory contribSearchArray = activeContributors[client];

        uint length = activeContributors[client].length;
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
    function _findActiveWalletId(
        address client,
        address contributor,
        uint walletId
    ) internal view returns (uint) {
        uint[] memory streamingWalletsArray =
            activeContributorPayments[client][contributor];
        uint streamingWalletsArrayLength = streamingWalletsArray.length;

        uint index;
        for (index; index < streamingWalletsArrayLength;) {
            if (streamingWalletsArray[index] == walletId) {
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
        address[] memory contributors = activeContributors[client];
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
        uint[] memory streamingWalletsArray =
            activeContributorPayments[client][contributor];
        uint streamingWalletsArrayLength = streamingWalletsArray.length;

        uint index;
        uint walletId;
        for (index; index < streamingWalletsArrayLength;) {
            walletId = streamingWalletsArray[index];
            _claimForSpecificWalletId(client, contributor, walletId, true);

            // If the paymentOrder being removed was already past its duration, then it would have been removed in the earlier _claimForSpecificWalletId call
            // Otherwise, we would remove that paymentOrder in the following lines.
            if (
                block.timestamp
                    < dueToForSpecificWalletId(client, contributor, walletId)
            ) {
                _afterClaimCleanup(client, contributor, walletId);
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
        uint walletIdIndex = _findActiveWalletId(client, contributor, walletId);

        if (walletIdIndex == type(uint).max) {
            revert Module__PaymentProcessor__InactiveWallet(
                address(client), _msgSender(), walletId
            );
        }

        // Standard deletion process.
        // Unordered removal of Contributor payment with walletId WalletIdIndex
        // Move the last element to the index which is to be deleted and then pop the last element of the array.
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
        // Find the contributor's index in the array of activeContributors mapping.
        uint contributorIndex =
            _findAddressInActivePayments(client, contributor);

        if (contributorIndex == type(uint).max) {
            revert Module__PaymentProcessor__InvalidContributor(
                client, contributor
            );
        }

        // Replace the element to be deleted with the last element of the array
        uint contributorsLength = activeContributors[client].length;
        activeContributors[client][contributorIndex] =
            activeContributors[client][contributorsLength - 1];

        // pop the last element of the array
        activeContributors[client].pop();
    }

    /// @notice Adds a new payment containing the details of the monetary flow
    ///         depending on the module.
    /// @dev This function can handle multiple payment orders associated with a particular contributor for the same payment client
    ///      without overriding the earlier ones. The maximum payment orders for a contributor MUST BE capped at (2**256-1).
    /// @param _contributor Contributor's address.
    /// @param _salary Salary contributor will receive per epoch.
    /// @param _start Start vesting timestamp.
    /// @param _dueTo Streaming dueTo timestamp.
    /// @param _walletId ID of the new wallet of the a particular contributor being added
    function _addPayment(
        address client,
        address _contributor,
        uint _salary,
        uint _start,
        uint _dueTo,
        uint _walletId
    ) internal {
        if (
            !validAddress(_contributor) || !validSalary(_salary)
                || !validStart(_start)
        ) {
            emit InvalidStreamingOrderDiscarded(
                _contributor, _salary, _start, _dueTo
            );
        } else {
            ++numStreamingWallets[client][_contributor];
            isActiveContributor[client][_contributor] = true;

            vestings[client][_contributor][_walletId] =
                StreamingWallet(_salary, 0, _start, _dueTo, _walletId);

            // We do not want activeContributors[client] to have duplicate contributor entries
            // So we avoid pushing the _contributor to activeContributors[client] if it already exists
            if (
                _findAddressInActivePayments(client, _contributor)
                    == type(uint).max
            ) {
                activeContributors[client].push(_contributor);
            }

            activeContributorPayments[client][_contributor].push(_walletId);

            emit StreamingPaymentAdded(
                client, _contributor, _salary, _start, _dueTo, _walletId
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
        uint[] memory streamingWalletsArray =
            activeContributorPayments[client][contributor];
        uint streamingWalletsArrayLength = streamingWalletsArray.length;

        uint index;
        for (index; index < streamingWalletsArrayLength;) {
            _claimForSpecificWalletId(
                client, contributor, streamingWalletsArray[index], true
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

        uint dueToContributor =
            dueToForSpecificWalletId(client, contributor, walletId);

        // This if conditional block represents that nothing more remains to be vested from the specific walletId
        if (block.timestamp >= dueToContributor) {
            _afterClaimCleanup(client, contributor, walletId);
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
        uint dueToContributor =
            dueToForSpecificWalletId(client, contributor, walletId);

        if (timestamp < startContributor) {
            return 0;
        } else if (timestamp >= dueToContributor) {
            return totalAllocation;
        } else {
            return (totalAllocation * (timestamp - startContributor))
                / (dueToContributor - startContributor);
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
}
