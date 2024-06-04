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
 * @notice  Manages continuous and linear vesting payment streams within the Inverter
 *          Network, allowing multiple concurrent vestings per recipient. Provides tools
 *          to claim vested amounts and manage payment schedules dynamically.
 *
 * @dev     Supports complex payment interactions including vesting based on time for
 *          multiple clients and recipients, integrated with error handling for
 *          payments and managing active vesting schedules and their cancellations.
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
    /// @dev paymentClient => paymentReceiver => walletId(uint)
    mapping(address => mapping(address => uint)) public numVestingWallets;

    /// @notice tracks all vesting details for all payment orders of a paymentReceiver for a specific paymentClient
    /// @dev paymentClient => paymentReceiver => vestingWalletID => Wallet
    mapping(address => mapping(address => mapping(uint => VestingWallet)))
        private vestings;

    /// @notice tracks all walletIds for payments that could not be made to the paymentReceiver due to any reason
    /// @dev paymentClient => paymentReceiver => walletId array
    mapping(address => mapping(address => uint[])) internal unclaimableWalletIds;

    /// @notice tracks all payments that could not be made to the paymentReceiver due to any reason
    /// @dev paymentClient => paymentReceiver => vestingWalletID => unclaimable Amount
    mapping(address => mapping(address => mapping(uint => uint))) internal
        unclaimableAmountsForWalletId;

    /// @notice list of addresses with open payment Orders per paymentClient
    /// @dev paymentClient => listOfPaymentReceivers(address[]). Duplicates are not allowed.
    mapping(address => address[]) private activePaymentReceivers;

    /// @notice list of walletIDs of all payment orders of a particular paymentReceiver for a particular paymentClient
    /// @dev client => paymentReceiver => arrayOfWalletIdsWithPendingPayment(uint[])
    mapping(address => mapping(address => uint[])) private activeVestingWallets;

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
        if (activeVestingWallets[client][paymentReceiver].length == 0) {
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
        if (activeVestingWallets[client][_msgSender()].length == 0) {
            revert Module__PaymentProcessor__NothingToClaim(
                client, _msgSender()
            );
        }

        _claimAll(client, _msgSender());
    }

    /// @inheritdoc IPP_Streaming_v1
    function claimPreviouslyUnclaimable(address client, address receiver)
        external
    {
        if (unclaimable(client, _msgSender()) == 0) {
            revert Module__PaymentProcessor__NothingToClaim(
                client, _msgSender()
            );
        }

        _claimPreviouslyUnclaimable(client, receiver);
    }

    /// @inheritdoc IPP_Streaming_v1
    function claimForSpecificWalletId(address client, uint walletId) external {
        if (
            activeVestingWallets[client][_msgSender()].length == 0
                || walletId > numVestingWallets[client][_msgSender()]
        ) {
            revert Module__PP_Streaming__InvalidWallet(
                client, _msgSender(), walletId
            );
        }

        if (
            _findActiveWalletId(client, _msgSender(), walletId)
                == type(uint).max
        ) {
            revert Module__PP_Streaming__InactiveWallet(
                client, _msgSender(), walletId
            );
        }

        _claimForSpecificWalletId(client, _msgSender(), walletId);
    }

    /// @inheritdoc IPaymentProcessor_v1
    function processPayments(IERC20PaymentClientBase_v1 client)
        external
        onlyModule
        validClient(address(client))
    {
        //We check if there are any new paymentOrders, without processing them
        if (client.paymentOrders().length > 0) {
            // Collect outstanding orders and their total token amount.
            IERC20PaymentClientBase_v1.PaymentOrder[] memory orders;
            uint totalAmount;
            (orders, totalAmount) = client.collectPaymentOrders();

            if (token().balanceOf(address(client)) < totalAmount) {
                revert Module__PP_Streaming__InsufficientTokenBalanceInClient();
            }

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
                _walletId = numVestingWallets[address(client)][_recipient] + 1;

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
    ) external onlyOrchestratorOwner {
        if (
            _findAddressInActiveVestings(client, paymentReceiver)
                == type(uint).max
        ) {
            revert Module__PP_Streaming__InvalidPaymentReceiver(
                client, paymentReceiver
            );
        }
        _removePayment(client, paymentReceiver);
    }

    /// @inheritdoc IPP_Streaming_v1
    function removePaymentForSpecificWalletId(
        address client,
        address paymentReceiver,
        uint walletId
    ) external onlyOrchestratorOwner {
        // First, we give the vested funds from this specific walletId to the beneficiary
        _claimForSpecificWalletId(client, paymentReceiver, walletId);

        // Now, we need to check when this function was called to determine if we need to delete the details pertaining to this wallet or not
        // We will delete the payment order in question, if it hasn't already reached the end of its duration.
        if (
            block.timestamp
                < dueToForSpecificWalletId(client, paymentReceiver, walletId)
        ) {
            _afterClaimCleanup(client, paymentReceiver, walletId);
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
        return activeVestingWallets[client][paymentReceiver].length > 0;
    }

    /// @inheritdoc IPP_Streaming_v1
    function startForSpecificWalletId(
        address client,
        address paymentReceiver,
        uint walletId
    ) public view returns (uint) {
        return vestings[client][paymentReceiver][walletId]._start;
    }

    /// @inheritdoc IPP_Streaming_v1
    function dueToForSpecificWalletId(
        address client,
        address paymentReceiver,
        uint walletId
    ) public view returns (uint) {
        return vestings[client][paymentReceiver][walletId]._dueTo;
    }

    /// @inheritdoc IPP_Streaming_v1
    function releasedForSpecificWalletId(
        address client,
        address paymentReceiver,
        uint walletId
    ) public view returns (uint) {
        return vestings[client][paymentReceiver][walletId]._released;
    }

    /// @inheritdoc IPP_Streaming_v1
    function vestedAmountForSpecificWalletId(
        address client,
        address paymentReceiver,
        uint timestamp,
        uint walletId
    ) public view returns (uint) {
        return _vestingAmountForSpecificWalletId(
            client, paymentReceiver, timestamp, walletId
        );
    }

    /// @inheritdoc IPP_Streaming_v1
    function releasableForSpecificWalletId(
        address client,
        address paymentReceiver,
        uint walletId
    ) public view returns (uint) {
        return vestedAmountForSpecificWalletId(
            client, paymentReceiver, block.timestamp, walletId
        ) - releasedForSpecificWalletId(client, paymentReceiver, walletId);
    }

    /// @inheritdoc IPP_Streaming_v1
    function unclaimable(address client, address paymentReceiver)
        public
        view
        returns (uint amount)
    {
        uint[] memory ids = unclaimableWalletIds[client][paymentReceiver];
        uint length = ids.length;

        if (length == 0) {
            return 0;
        }

        for (uint i = 0; i < length; i++) {
            amount +=
                unclaimableAmountsForWalletId[client][paymentReceiver][ids[i]];
        }
    }

    /// @inheritdoc IPaymentProcessor_v1
    function token() public view returns (IERC20) {
        return this.orchestrator().fundingManager().token();
    }

    /// @inheritdoc IPP_Streaming_v1
    function viewAllPaymentOrders(address client, address paymentReceiver)
        external
        view
        activePaymentReceiver(client, paymentReceiver)
        returns (VestingWallet[] memory)
    {
        uint[] memory vestingWalletsArray =
            activeVestingWallets[client][paymentReceiver];
        uint vestingWalletsArrayLength = vestingWalletsArray.length;

        uint index;
        VestingWallet[] memory paymentReceiverVestingWallets =
            new VestingWallet[](vestingWalletsArrayLength);

        for (index; index < vestingWalletsArrayLength;) {
            paymentReceiverVestingWallets[index] =
                vestings[client][paymentReceiver][vestingWalletsArray[index]];

            unchecked {
                ++index;
            }
        }

        return paymentReceiverVestingWallets;
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    /// @notice common set of steps to be taken after everything has been claimed from a specific wallet
    /// @param client address of the payment client
    /// @param paymentReceiver address of the paymentReceiver
    /// @param walletId ID of the wallet that was fully claimed
    function _afterClaimCleanup(
        address client,
        address paymentReceiver,
        uint walletId
    ) internal {
        // 1. remove walletId from the activeVestingWallets mapping
        _removePaymentForSpecificWalletId(client, paymentReceiver, walletId);

        // 2. delete the vesting information for this specific walletId
        _removeVestingInformationForSpecificWalletId(
            client, paymentReceiver, walletId
        );

        // 3. activePaymentReceivers and isActive would be updated if this was the last wallet that was associated with the paymentReceiver was claimed.
        //    This would also mean that, it is possible for a paymentReceiver to be inactive and still have money owed to them (unclaimableAmounts)
        if (activeVestingWallets[client][paymentReceiver].length == 0) {
            _removePaymentReceiverFromActiveVestings(client, paymentReceiver);
        }

        // Note We do not need to update unclaimableAmounts, as it is already done earlier depending on the `transferFrom` call.
        // Note Also, we do not need to update numVestingWallets, as claiming completely from a wallet does not affect this mapping.

        // 4. emit an event broadcasting that a particular payment has been removed
        emit StreamingPaymentRemoved(client, paymentReceiver, walletId);
    }

    /// @notice used to find whether a particular paymentReceiver has pending payments with a client
    /// @dev This function returns the first instance of the paymentReceiver address in the activePaymentReceivers[client] array, but that
    ///      is completely fine as the activePaymentReceivers[client] array does not allow duplicates.
    /// @param client address of the payment client
    /// @param paymentReceiver address of the paymentReceiver
    /// @return the index of the paymentReceiver in the activePaymentReceivers[client] array. Returns type(uint256).max otherwise.
    function _findAddressInActiveVestings(
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

    /// @notice used to find whether a particular payment order associated with a paymentReceiver and paymentClient with id = walletId is active or not
    /// @dev active means that the particular payment order is still to be paid out/claimed. This function returns the first instance of the walletId
    ///      in the activeVestingWallets[client][paymentReceiver] array, but that is fine as the array does not allow duplicates.
    /// @param client address of the payment client
    /// @param paymentReceiver address of the paymentReceiver
    /// @param walletId ID of the payment order that needs to be searched
    /// @return the index of the paymentReceiver in the activeVestingWallets[client][paymentReceiver] array. Returns type(uint256).max otherwise.
    function _findActiveWalletId(
        address client,
        address paymentReceiver,
        uint walletId
    ) internal view returns (uint) {
        uint[] memory vestingWalletsArray =
            activeVestingWallets[client][paymentReceiver];
        uint vestingWalletsArrayLength = vestingWalletsArray.length;

        uint index;
        for (index; index < vestingWalletsArrayLength;) {
            if (vestingWalletsArray[index] == walletId) {
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

    /// @notice Deletes all payments related to a paymentReceiver & leaves unvested tokens in the ERC20PaymentClientBase_v1.
    /// @dev this function calls _removePayment which goes through all the payment orders for a paymentReceiver. For the payment orders
    ///      that are completely vested, their details are deleted in the _claimForSpecificWalletId function and for others it is
    ///      deleted in the _removePayment function only, leaving the unvested tokens as balance of the paymentClient itself.
    /// @param client address of the payment client
    /// @param paymentReceiver address of the paymentReceiver
    function _removePayment(address client, address paymentReceiver) internal {
        uint[] memory vestingWalletsArray =
            activeVestingWallets[client][paymentReceiver];
        uint vestingWalletsArrayLength = vestingWalletsArray.length;

        uint index;
        uint walletId;
        for (index; index < vestingWalletsArrayLength;) {
            walletId = vestingWalletsArray[index];
            _claimForSpecificWalletId(client, paymentReceiver, walletId);

            // If the paymentOrder being removed was already past its duration, then it would have been removed in the earlier _claimForSpecificWalletId call
            // Otherwise, we would remove that paymentOrder in the following lines.
            if (
                block.timestamp
                    < dueToForSpecificWalletId(client, paymentReceiver, walletId)
            ) {
                _afterClaimCleanup(client, paymentReceiver, walletId);
            }

            unchecked {
                ++index;
            }
        }
    }

    /// @notice used to remove the payment order with id = walletId from the activeVestingWallets[client][paymentReceiver] array.
    /// @dev This function simply removes a particular payment order from the earlier mentioned array. The implications of removing a payment order
    ///      from this array have to be handled outside of this function, such as checking whether the paymentReceiver is still active or not, etc.
    /// @param client Address of the payment client
    /// @param paymentReceiver Address of the paymentReceiver
    /// @param walletId Id of the payment order that needs to be removed
    function _removePaymentForSpecificWalletId(
        address client,
        address paymentReceiver,
        uint walletId
    ) internal {
        uint walletIdIndex =
            _findActiveWalletId(client, paymentReceiver, walletId);

        if (walletIdIndex == type(uint).max) {
            revert Module__PP_Streaming__InactiveWallet(
                address(client), _msgSender(), walletId
            );
        }

        uint remainingReleasable = vestings[client][paymentReceiver][walletId] //The whole salary
            ._salary - vestings[client][paymentReceiver][walletId]._released; //Minus what has already been "released"

        //In case there is still something to be released
        if (remainingReleasable > 0) {
            //Let PaymentClient know that the amount is not needed to be stored anymore

            IERC20PaymentClientBase_v1(client).amountPaid(remainingReleasable);
        }

        // Standard deletion process.
        // Unordered removal of PaymentReceiver payment with walletId WalletIdIndex
        // Move the last element to the index which is to be deleted and then pop the last element of the array.
        activeVestingWallets[client][paymentReceiver][walletIdIndex] =
        activeVestingWallets[client][paymentReceiver][activeVestingWallets[client][paymentReceiver]
            .length - 1];

        activeVestingWallets[client][paymentReceiver].pop();
    }

    /// @notice used to remove the vesting info of the payment order with id = walletId.
    /// @dev This function simply removes the vesting details of a particular payment order. The implications of removing the vesting info of
    ///      payment order have to be handled outside of this function.
    /// @param client Address of the payment client
    /// @param paymentReceiver Address of the paymentReceiver
    /// @param walletId Id of the payment order whose vesting information needs to be removed
    function _removeVestingInformationForSpecificWalletId(
        address client,
        address paymentReceiver,
        uint walletId
    ) internal {
        delete vestings[client][paymentReceiver][walletId];
    }

    /// @notice used to remove a paymentReceiver as one of the beneficiaries of the payment client
    /// @dev this function will be called when all the payment orders of a payment client associated with a particular paymentReceiver has been fulfilled.
    ///      Also signals that the paymentReceiver is no longer an active paymentReceiver according to the payment client
    /// @param client address of the payment client
    /// @param paymentReceiver address of the paymentReceiver
    function _removePaymentReceiverFromActiveVestings(
        address client,
        address paymentReceiver
    ) internal {
        // Find the paymentReceiver's index in the array of activePaymentReceivers mapping.
        uint paymentReceiverIndex =
            _findAddressInActiveVestings(client, paymentReceiver);

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
    /// @param _salary Salary paymentReceiver will receive per epoch.
    /// @param _start Start vesting timestamp.
    /// @param _dueTo Streaming dueTo timestamp.
    /// @param _walletId ID of the new wallet of the a particular paymentReceiver being added
    function _addPayment(
        address client,
        address _paymentReceiver,
        uint _salary,
        uint _start,
        uint _dueTo,
        uint _walletId
    ) internal {
        ++numVestingWallets[client][_paymentReceiver];
        if (
            !validAddress(_paymentReceiver) || !validSalary(_salary)
                || !validStart(_start)
        ) {
            emit InvalidStreamingOrderDiscarded(
                _paymentReceiver, _salary, _start, _dueTo
            );
        } else {
            vestings[client][_paymentReceiver][_walletId] =
                VestingWallet(_salary, 0, _start, _dueTo, _walletId);

            // We do not want activePaymentReceivers[client] to have duplicate paymentReceiver entries
            // So we avoid pushing the _paymentReceiver to activePaymentReceivers[client] if it already exists
            if (
                _findAddressInActiveVestings(client, _paymentReceiver)
                    == type(uint).max
            ) {
                activePaymentReceivers[client].push(_paymentReceiver);
            }

            activeVestingWallets[client][_paymentReceiver].push(_walletId);

            emit StreamingPaymentAdded(
                client, _paymentReceiver, _salary, _start, _dueTo, _walletId
            );
        }
    }

    /// @notice used to claim all the payment orders associated with a particular paymentReceiver for a given payment client
    /// @dev Calls the _claimForSpecificWalletId function for all the active wallets of a particular paymentReceiver for the
    ///      given payment client. Depending on the time this function is called, the vested payments are transferred to the
    ///      paymentReceiver.
    ///      For payment orders that are fully vested, their details are deleted and changes are made to the state of the contract accordingly.
    /// @param client address of the payment client
    /// @param paymentReceiver address of the paymentReceiver for which every payment order will be claimed
    function _claimAll(address client, address paymentReceiver) internal {
        uint[] memory vestingWalletsArray =
            activeVestingWallets[client][paymentReceiver];
        uint vestingWalletsArrayLength = vestingWalletsArray.length;

        uint index;
        for (index; index < vestingWalletsArrayLength;) {
            _claimForSpecificWalletId(
                client, paymentReceiver, vestingWalletsArray[index]
            );

            unchecked {
                ++index;
            }
        }
    }

    /// @notice used to claim the payment order of a particular paymentReceiver for a given payment client with id = walletId
    /// @dev Depending on the time this function is called, the vested payments are transferred to the paymentReceiver or accounted in unclaimableAmounts.
    ///      For payment orders that are fully vested, their details are deleted and changes are made to the state of the contract accordingly.
    /// @param client address of the payment client
    /// @param paymentReceiver address of the paymentReceiver for which every payment order will be claimed
    /// @param walletId ID of the payment order that is to be claimed
    function _claimForSpecificWalletId(
        address client,
        address paymentReceiver,
        uint walletId
    ) internal {
        uint amount =
            releasableForSpecificWalletId(client, paymentReceiver, walletId);

        vestings[client][paymentReceiver][walletId]._released += amount;

        address _token = address(token());

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

            //Make sure to let paymentClient know that amount doesnt have to be stored anymore
            IERC20PaymentClientBase_v1(client).amountPaid(amount);
        } else {
            emit UnclaimableAmountAdded(
                client, paymentReceiver, walletId, amount
            );
            //Adds the walletId to the array of unclaimable wallet ids

            uint[] memory ids = unclaimableWalletIds[client][paymentReceiver];
            bool containsId = false;

            for (uint i = 0; i < ids.length; i++) {
                if (walletId == ids[i]) {
                    containsId = true;
                    break;
                }
            }
            //If it doesnt contain id than add it to array
            if (!containsId) {
                unclaimableWalletIds[client][paymentReceiver].push(walletId);
            }

            unclaimableAmountsForWalletId[client][paymentReceiver][walletId] +=
                amount;
        }

        uint dueToPaymentReceiver =
            dueToForSpecificWalletId(client, paymentReceiver, walletId);

        // This if conditional block represents that nothing more remains to be vested from the specific walletId
        if (block.timestamp >= dueToPaymentReceiver) {
            _afterClaimCleanup(client, paymentReceiver, walletId);
        }
    }

    /// @notice used to claim the unclaimable amount of a particular paymentReceiver for a given payment client
    /// @dev assumes that the walletId array is not empty
    /// @param client address of the payment client
    /// @param paymentReceiver address of the paymentReceiver for which the unclaimable amount will be claimed
    function _claimPreviouslyUnclaimable(
        address client,
        address paymentReceiver
    ) internal {
        //get amount

        uint amount;

        address sender = _msgSender();
        uint[] memory ids = unclaimableWalletIds[client][sender];
        uint length = ids.length;

        for (uint i = 0; i < length; i++) {
            //Add the unclaimable amount of each id to the current amount
            amount += unclaimableAmountsForWalletId[client][sender][ids[i]];
            //Delete value of wallet id
            delete unclaimableAmountsForWalletId[client][sender][ids[i]];
        }
        //As all of the wallet ids should have been claimed we can delete the wallet id array
        delete unclaimableWalletIds[client][sender];

        IERC20 _token = token();

        //Call has to succeed otherwise no state change
        _token.safeTransferFrom(client, paymentReceiver, amount);

        emit TokensReleased(paymentReceiver, address(_token), amount);

        //Make sure to let paymentClient know that amount doesnt have to be stored anymore
        IERC20PaymentClientBase_v1(client).amountPaid(amount);
    }

    /// @notice Virtual implementation of the vesting formula.
    ///         Returns the amount vested, as a function of time,
    ///         for an asset given its total historical allocation.
    /// @param paymentReceiver The paymentReceiver to check on.
    /// @param timestamp the time upto which we want the vested amount
    /// @param walletId ID of a particular paymentReceiver's wallet whose vesting schedule needs to be checked
    function _vestingAmountForSpecificWalletId(
        address client,
        address paymentReceiver,
        uint timestamp,
        uint walletId
    ) internal view virtual returns (uint) {
        uint totalAllocation =
            vestings[client][paymentReceiver][walletId]._salary;
        uint startPaymentReceiver =
            startForSpecificWalletId(client, paymentReceiver, walletId);
        uint dueToPaymentReceiver =
            dueToForSpecificWalletId(client, paymentReceiver, walletId);

        if (timestamp < startPaymentReceiver) {
            return 0;
        } else if (timestamp >= dueToPaymentReceiver) {
            return totalAllocation;
        } else {
            return (totalAllocation * (timestamp - startPaymentReceiver))
                / (dueToPaymentReceiver - startPaymentReceiver);
        }
    }

    /// @notice validate address input.
    /// @param addr Address to validate.
    /// @return True if address is valid.
    function validAddress(address addr) internal view returns (bool) {
        return !(
            addr == address(0) || addr == _msgSender() || addr == address(this)
                || addr == address(orchestrator())
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
