// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

// Internal Dependencies
import {
    IPaymentProcessor,
    IPaymentClient
} from "src/modules/IPaymentProcessor.sol";

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

contract ConcurrentStreamingPaymentProcessor is Module, IPaymentProcessor {
    //--------------------------------------------------------------------------
    // Storage

    // **_streamingWalletID**: Valid values will start from 1. 0 is not a valid streamingWalletID.
    struct StreamingWallet {
        uint _salary;
        uint _released;
        uint _start;
        uint _duration;
        uint _streamingWalletID;
    }

    mapping(address => mapping(address => bool)) public isActiveContributor;
    mapping(address => mapping(address => uint256)) public numContributorWallets;

    // paymentClient => contributor => streamingWalletID => Wallet
    mapping(address => mapping(address => mapping(uint256 => StreamingWallet))) private vestings;

    // paymentClient => contributor => unclaimableAmount
    mapping(address => mapping(address => uint)) private unclaimableAmounts;

    /// @notice list of addresses with open payment Orders per paymentClient
    mapping(address => address[]) private activePayments;

    /// @notice client => contributor => arrayOfWalletIdsWithPendingPayment
    mapping(address => mapping(address => uint256[])) private activeContributorPayments;

    //--------------------------------------------------------------------------
    // Events

    /// @notice Emitted when a payment gets processed for execution.
    /// @param recipient The address that will receive the payment.
    /// @param amount The amount of tokens the payment consists of.
    /// @param start Timestamp at which the vesting starts.
    /// @param duration Timestamp at which the full amount should be claimable.
    event StreamingPaymentAdded(
        address indexed paymentClient,
        address indexed recipient,
        uint amount,
        uint start,
        uint duration
    );

    /// @notice Emitted when the vesting to an address is removed.
    /// @param recipient The address that will stop receiving payment.
    event StreamingPaymentRemoved(
        address indexed paymentClient, address indexed recipient
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

    //--------------------------------------------------------------------------
    // Errors

    /// @notice insufficient tokens in the client to do payments
    error Module__PaymentManager__InsufficientTokenBalanceInClient();

    /// @notice the contributor is not owed any money by the paymentClient
    error Module__PaymentManager__NothingToClaim(address paymentClient, address contributor);

    /// @notice contributor's walletId for the paymentClient is not valid 
    error Module__PaymentManager__InvalidWallet(address paymentClient, address contributor, uint256 walletId);

    /// @notice contributor's walletId for the paymentClient is no longer active
    error Module__PaymentManager__InactiveWallet(address paymentClient, address contributor, uint256 walletId);

    /// @notice the contributor for the given paymentClient does not exist (anymore)
    error Module__PaymentManager__InvalidContributor(address paymentClient, address contributor);

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

    /// @dev This function should be callable if the _msgSender is either an activeContributor or has some unclaimedAmounts
    function claimAll(IPaymentClient client) external {
        if(!(isActiveContributor[address(client)][_msgSender()] || unclaimable(address(client), _msgSender()) > 0)) {
            revert Module__PaymentManager__NothingToClaim(address(client), _msgSender());
        }

        _claimAll(address(client), _msgSender());
    }

    /// @dev If for a specific walletId, the tokens could not be transferred for some reason, it will added to the unclaimableAmounts
    ///      of the contributor, and the amount would no longer hold any co-relation with the specific walletId of the contributor.
    function claimForSpecificWalletId(IPaymentClient client, uint256 walletId, bool retryForUnclaimableAmounts) external {
        if(!isActiveContributor[address(client)][_msgSender()] || (walletId > numContributorWallets[address(client)][_msgSender()])) {
            revert Module__PaymentManager__InvalidWallet(address(client), _msgSender(), walletId);
        }

        if(_verifyActiveWalletId(address(client), _msgSender(), walletId) == type(uint256).max) {
            revert Module__PaymentManager__InactiveWallet(address(client), _msgSender(), walletId);
        }

        _claimForSpecificWalletId(address(client), _msgSender(), walletId, retryForUnclaimableAmounts);
    }

    /// @inheritdoc IPaymentProcessor
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
                revert Module__PaymentManager__InsufficientTokenBalanceInClient();
            }
            
            // Generate Streaming Payments for all orders
            address _recipient;
            uint _amount;
            uint _start;
            uint _duration;
            uint _walletId;

            for (uint i; i < orders.length; i++) {
                _recipient = orders[i].recipient;
                _amount = orders[i].amount;
                _start = orders[i].createdAt;
                _duration = (orders[i].dueTo - _start);

                // We can't increase the value of numContributorWallets here, as it is possible that in the next
                // _addPayment step, this wallet is not actually added. So, we will increment the value of this 
                // mapping there only, and for the same reason we cannot set the isActiveContributor mapping 
                // to true here.
                _walletId = numContributorWallets[address(client)][_recipient] + 1;

                _addPayment(
                    address(client), _recipient, _amount, _start, _duration, _walletId
                );

                emit PaymentOrderProcessed(
                    address(client), _recipient, _amount, _start, _duration
                );
            }
        }
    }

    /// @inheritdoc IPaymentProcessor
    function cancelRunningPayments(IPaymentClient client)
        external
        onlyModule
        validClient(client)
    {
        _cancelRunningOrders(address(client));
    }

    /// @notice Deletes a contributors payment and leaves non-released tokens
    ///         in the PaymentClient.
    /// @param contributor Contributor's address.
    function removePayment(IPaymentClient client, address contributor)
        external
        onlyAuthorized
    {
        if(_findAddressInActivePayments(address(client), contributor) == type(uint256).max) {
            revert Module__PaymentManager__InvalidContributor(address(client), contributor);
        }
        _removePayment(address(client), contributor);
    }

    // @todo add relevant event emissions
    function removePaymentForSpecificWalletId(
        IPaymentClient client, 
        address contributor, 
        uint256 walletId,
        bool retryForUnclaimableAmounts
    ) external onlyAuthorized {
        // We need to make sure that this function updates these following storage variables
        // 1. activePayments               [X]
        // 2. activeContributorPayments    [X]
        // 3. unclaimableAmounts           [X]
        // 4. vestings                     [X]
        // 5. isActiveContributor          [X]
        // 6. numContributorWallets        ~NA~

        // First, we **claim** the vested funds from this specific walletId
        _claimForSpecificWalletId(address(client), contributor, walletId, retryForUnclaimableAmounts);
        // This function will take care of: unclaimableAmounts

        // And in the case that the current block.timestamp >= vesting timestamp of walletId, then the following are also taken care of:
        // activePayments, activeContributorPayments, vestings, isActiveContributor, numContributorWallets

        // So, we need to check when this function was called to determine if we need to modify the other mappings or not
        uint startContributor = startForSpecificWalletId(address(client), contributor, walletId);
        uint durationContributor = durationForSpecificWalletId(address(client), contributor, walletId);

        if(block.timestamp < startContributor + durationContributor) {
            // handles activeContributorPayments
            _removePaymentForSpecificWalletId(address(client), contributor, walletId);

            // handles vesting information
            _removeVestingInformationForSpecificWalletId(address(client), contributor, walletId);

            // handles activePayments and isActiveContributor if required
            if(activeContributorPayments[address(client)][contributor].length == 0) {
                isActiveContributor[address(client)][contributor] = false;
                _removeContributorFromActivePayments(address(client), contributor);
            }
        }
    }

    //--------------------------------------------------------------------------
    // Public Functions

    /// @notice Getter for the start timestamp.
    /// @param contributor Contributor's address.
    function startForSpecificWalletId(address client, address contributor, uint256 walletId)
        public
        view
        returns (uint)
    {
        return vestings[client][contributor][walletId]._start;
    }

    /// @notice Getter for the vesting duration.
    /// @param contributor Contributor's address.
    function durationForSpecificWalletId(address client, address contributor, uint256 walletId)
        public
        view
        returns (uint)
    {
        return vestings[client][contributor][walletId]._duration;
    }

    /// @notice Getter for the amount of eth already released
    /// @param contributor Contributor's address.
    function releasedForSpecificWalletId(address client, address contributor, uint256 walletId)
        public
        view
        returns (uint)
    {
        return vestings[client][contributor][walletId]._released;
    }

    /// @notice Calculates the amount of tokens that has already vested.
    /// @param contributor Contributor's address.
    function vestedAmountForSpecificWalletId(address client, address contributor, uint timestamp, uint walletId)
        public
        view
        returns (uint)
    {
        return _vestingScheduleForSpecificWalletId(client, contributor, timestamp, walletId);
    }

    /// @notice Getter for the amount of releasable tokens.
    function releasableForSpecificWalletId(address client, address contributor, uint256 walletId)
        public
        view
        returns (uint)
    {
        return 
            vestedAmountForSpecificWalletId(client, contributor, block.timestamp, walletId)
            - releasedForSpecificWalletId(client, contributor, walletId);
    }

    /// @notice Getter for the amount of tokens that could not be claimed.
    function unclaimable(address client, address contributor)
        public
        view
        returns (uint)
    {
        return unclaimableAmounts[client][contributor];
    }

    function token() public view returns (IERC20) {
        return this.proposal().token();
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    function _findAddressInActivePayments(address client, address contributor)
        internal
        view
        returns (uint)
    {
        address[] memory contribSearchArray = activePayments[client];

        uint length = activePayments[client].length;
        for (uint i; i < length; i++) {
            if (contribSearchArray[i] == contributor) {
                return i;
            }
        }
        return type(uint).max;
    }

    function _verifyActiveWalletId(address client, address contributor, uint256 walletId) internal view returns(uint256) {
        uint256[] memory contributorWalletsArray = activeContributorPayments[client][contributor];
        uint256 contributorWalletsArrayLength = contributorWalletsArray.length;

        uint index;
        for(index; index < contributorWalletsArrayLength; ) {
            if(contributorWalletsArray[index] == walletId) {
                return index;
            }
            unchecked {
                ++index;
            }
        }

        return type(uint256).max;
    } 

    function _cancelRunningOrders(address client) internal {
        address[] memory contributors = activePayments[client];
        uint256 contributorsLength = contributors.length;
        
        uint index;
        for (index; index < contributorsLength; ) {
            _removePayment(client, contributors[index]);

            unchecked {
                ++index;
            }
        }
    }

    function _removePayment(address client, address contributor) internal {
        uint256[] memory contributorWalletsArray = activeContributorPayments[client][contributor];
        uint256 contributorWalletsArrayLength = contributorWalletsArray.length;

        uint256 index;
        uint256 startContributor;
        uint256 durationContributor;
        uint256 walletId;
        for(index; index < contributorWalletsArrayLength; ) {
            walletId = contributorWalletsArray[index];
            _claimForSpecificWalletId(client, contributor, walletId, true);

            startContributor = startForSpecificWalletId(client, contributor, walletId);
            durationContributor = durationForSpecificWalletId(client, contributor, walletId);

            if(block.timestamp < startContributor + durationContributor) {
                _removePaymentForSpecificWalletId(client, contributor, walletId);

                _removeVestingInformationForSpecificWalletId(client, contributor, walletId);

                if(activeContributorPayments[client][contributor].length == 0) {
                    isActiveContributor[client][contributor] = false;
                    _removeContributorFromActivePayments(client, contributor);
                }
            }

            unchecked {
                ++index;
            }
        }
    }

    // @todo add relevant event emissions
    function _removePaymentForSpecificWalletId(
        address client, 
        address contributor, 
        uint256 walletId
    ) internal {
        uint256 walletIdIndex = _verifyActiveWalletId(client, contributor, walletId);

        if(walletIdIndex == type(uint256).max) {
            revert Module__PaymentManager__InactiveWallet(address(client), _msgSender(), walletId);
        }

        activeContributorPayments[client][contributor][walletIdIndex] = activeContributorPayments[client][contributor][activeContributorPayments[client][contributor].length - 1];

        activeContributorPayments[client][contributor].pop();
    }

    // @todo add relevant event emission
    function _removeVestingInformationForSpecificWalletId(
        address client, 
        address contributor, 
        uint256 walletId
    ) internal  {
        delete vestings[client][contributor][walletId];
    }

    // @todo add relevant event emissions
    function _removeContributorFromActivePayments(
        address client,
        address contributor
    ) internal {
        // Find the contributor's index in the array of activePayments mapping.
        uint contributorIndex = _findAddressInActivePayments(client, contributor);

        if(contributorIndex == type(uint256).max) {
            revert Module__PaymentManager__InvalidContributor(client, contributor);
        }

        // Replace the element to be deleted with the last element of the array
        uint256 contributorsLength = activePayments[client].length; 
        activePayments[client][contributorIndex] = activePayments[client][contributorsLength - 1];

        // pop the last element of the array
        activePayments[client].pop();
    }

    /// @notice Adds a new payment containing the details of the monetary flow
    ///         depending on the module.
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
            !validAddress(_contributor) || !validSalary(_salary) || !validStart(_start) || !validDuration(_duration)
        ) {
            emit InvalidStreamingOrderDiscarded ( _contributor, _salary, _start, _duration);
        } else {
            ++numContributorWallets[client][_contributor];
            isActiveContributor[client][_contributor] = true;

            vestings[client][_contributor][_walletId] =
                StreamingWallet(_salary, 0, _start, _duration, _walletId);

            // We do not want activePayments[client] to have duplicate contributor entries
            // So we avoid pushing the _contributor to activePayments[client] if it already exists
            if(_findAddressInActivePayments(client, _contributor) == type(uint256).max) {
                activePayments[client].push(_contributor);
            }

            activeContributorPayments[client][_contributor].push(_walletId);

            emit StreamingPaymentAdded(
                client, _contributor, _salary, _start, _duration
            );
        }
    }

    function _claimAll(address client, address contributor) internal {
        uint256[] memory contributorWalletsArray = activeContributorPayments[client][contributor];
        uint256 contributorWalletsArrayLength = contributorWalletsArray.length;

        uint256 index;
        for(index; index < contributorWalletsArrayLength; ) {
            _claimForSpecificWalletId(client, contributor, contributorWalletsArray[index], true);
            
            unchecked {
                ++index;
            }
        }
    }

    function _claimForSpecificWalletId(address client, address beneficiary, uint256 walletId, bool retryForUnclaimableAmounts) internal {
        uint amount = releasableForSpecificWalletId(client, beneficiary, walletId);
        vestings[client][beneficiary][walletId]._released += amount;

        if(retryForUnclaimableAmounts && unclaimableAmounts[client][beneficiary] > 0) {
            amount += unclaimable(client, beneficiary);
            delete unclaimableAmounts[client][beneficiary];
        }

        address _token = address(token());

        (bool success, bytes memory data) = _token.call(
            abi.encodeWithSelector(
                IERC20(_token).transferFrom.selector,
                client,
                beneficiary,
                amount
            )
        );

        if (success && (data.length == 0 || abi.decode(data, (bool)))) {
            emit TokensReleased(beneficiary, _token, amount);
        } else {
            unclaimableAmounts[client][beneficiary] += amount;
        }

        uint startContributor = startForSpecificWalletId(client, beneficiary, walletId);
        uint durationContributor = durationForSpecificWalletId(client, beneficiary, walletId);

        // This if conditional block represents that nothing more remains to be vested from the specific walletId
        if(block.timestamp >= startContributor + durationContributor) {
            // 1. remove walletId from the activeContributorPayments mapping
            _removePaymentForSpecificWalletId(client, beneficiary, walletId);

            // 2. delete the vesting information for this specific walletId
            _removeVestingInformationForSpecificWalletId(client, beneficiary, walletId);

            // 3. activePayments and isActive would be updated if this was the last wallet that was associated with the contributor was claimed.
            //    This would also mean that, it is possible for a contributor to be inactive and still have money owed to them (unclaimableAmounts)
            if(activeContributorPayments[client][beneficiary].length == 0) {
                isActiveContributor[client][beneficiary] = false;
                _removeContributorFromActivePayments(client, beneficiary);
            }

            // Note We do not need to update unclaimableAmounts, as it is already done earlier depending on the `transferFrom` call.
            // Note Also, we do not need to update numContributorWallets, as claiming completely from a wallet does not affect this mapping.
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
        uint startContributor = startForSpecificWalletId(client, contributor, walletId);
        uint durationContributor = durationForSpecificWalletId(client, contributor, walletId);

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
        if (
            addr == address(0) || addr == _msgSender() || addr == address(this)
                || addr == address(proposal())
        ) {
            return false;
        }
        return true;
    }

    function validSalary(uint _salary) internal pure returns (bool) {
        if (_salary == 0) {
            return false;
        }
        return true;
    }

    function validStart(uint _start) internal view returns (bool) {
        if (_start < block.timestamp || _start >= type(uint).max) {
            return false;
        }
        return true;
    }

    function validDuration(uint _duration) internal pure returns (bool) {
        if (_duration == 0) {
            return false;
        }
        return true;
    }
}