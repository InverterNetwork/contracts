// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

// Internal Dependencies
import {
    IPaymentProcessor,
    IPaymentClient
} from "src/modules/IPaymentProcessor.sol";
import {Types} from "src/common/Types.sol";
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

contract VestingPaymentProcessor is Module, IPaymentProcessor {
    //--------------------------------------------------------------------------
    // Storage

    struct VestingWallet {
        uint _salary;
        uint _released;
        uint _start;
        uint _duration;
    }

    // paymentClient => contributor => Payment
    mapping(address => mapping(address => VestingWallet)) private vestings;
    // paymentClient => contributor => unclaimableAmount
    mapping(address => mapping(address => uint)) private unclaimableAmounts;

    /// @notice list of addresses with open payment Orders per paymentClient
    mapping(address => address[]) private activePayments;

    //--------------------------------------------------------------------------
    // Events

    /// @notice Emitted when a payment gets processed for execution.
    /// @param recipient The address that will receive the payment.
    /// @param amount The amount of tokens the payment consists of.
    /// @param start Timestamp at which the vesting starts.
    /// @param duration Timestamp at which the full amount should be claimable.
    event VestingPaymentAdded(
        address indexed paymentClient,
        address indexed recipient,
        uint amount,
        uint start,
        uint duration
    );

    /// @notice Emitted when the vesting to an address is removed.
    /// @param recipient The address that will stop receiving payment.
    event VestingPaymentRemoved(
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
    event InvalidVestingOrderDiscarded(
        address indexed recipient, uint amount, uint start, uint duration
    );

    //--------------------------------------------------------------------------
    // Errors

    /// @notice insufficient tokens in the client to do payments
    error Module__PaymentManager__InsufficientTokenBalanceInClient();

    /// @notice invalid caller
    error Module__PaymentManager__OnlyCallableByModule();

    //--------------------------------------------------------------------------
    // Modifiers

    modifier onlyModule() {
        if (!proposal().isModule(_msgSender())) {
            revert Module__PaymentManager__OnlyCallableByModule();
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

    /// @notice Release the releasable tokens.
    ///         In OZ VestingWallet this method is named release().
    function claim(IPaymentClient client) external {
        _claim(address(client), _msgSender());
    }

    /// @inheritdoc IPaymentProcessor
    function processPayments(IPaymentClient client) external onlyModule {
        //We check if there are any new paymentOrders, without processing them
        if (client.paymentOrders().length > 0) {
            // If there are, we remove all payments that would be overwritten
            // Doing it at the start ensures that collectPaymentOrders will always start from a blank slate concerning balances/allowances.
            _cancelRunningOrders(client);

            // Collect outstanding orders and their total token amount.
            IPaymentClient.PaymentOrder[] memory orders;
            uint totalAmount;
            (orders, totalAmount) = client.collectPaymentOrders();

            if (token().balanceOf(address(client)) < totalAmount) {
                revert Module__PaymentManager__InsufficientTokenBalanceInClient(
                );
            }

            // Generate Vesting Payments for all orders
            address _recipient;
            uint _amount;
            uint _start;
            uint _duration;
            for (uint i; i < orders.length; i++) {
                _recipient = orders[i].recipient;
                _amount = orders[i].amount;
                _start = orders[i].createdAt;
                _duration = (orders[i].dueTo - _start);

                _addPayment(
                    address(client), _recipient, _amount, _start, _duration
                );

                emit PaymentOrderProcessed(
                    address(client), _recipient, _amount, _start, _duration
                );
            }
        }
    }

    function cancelRunningPayments(IPaymentClient client)
        external
        onlyAuthorized
    {
        _cancelRunningOrders(client);
    }

    function _cancelRunningOrders(IPaymentClient client) internal {
        //IPaymentClient.PaymentOrder[] memory orders;
        //orders = client.paymentOrders();
        address[] memory _activePayments = activePayments[address(client)];

        address _recipient;
        for (uint i; i < _activePayments.length; ++i) {
            _recipient = _activePayments[i];

            _removePayment(address(client), _recipient);
        }
    }

    /// @notice Deletes a contributors payment and leaves non-released tokens
    ///         in the PaymentClient.
    /// @param contributor Contributor's address.
    function removePayment(IPaymentClient client, address contributor)
        external
        onlyAuthorized
    {
        _removePayment(address(client), contributor);
    }

    //--------------------------------------------------------------------------
    // Public Functions

    /// @notice Getter for the start timestamp.
    /// @param contributor Contributor's address.
    function start(address client, address contributor)
        public
        view
        returns (uint)
    {
        return vestings[client][contributor]._start;
    }

    /// @notice Getter for the vesting duration.
    /// @param contributor Contributor's address.
    function duration(address client, address contributor)
        public
        view
        returns (uint)
    {
        return vestings[client][contributor]._duration;
    }

    /// @notice Getter for the amount of eth already released
    /// @param contributor Contributor's address.
    function released(address client, address contributor)
        public
        view
        returns (uint)
    {
        return vestings[client][contributor]._released;
    }

    /// @notice Calculates the amount of tokens that has already vested.
    /// @param contributor Contributor's address.
    function vestedAmount(address client, address contributor, uint timestamp)
        public
        view
        returns (uint)
    {
        return _vestingSchedule(client, contributor, timestamp);
    }

    /// @notice Getter for the amount of releasable tokens.
    function releasable(address client, address contributor)
        public
        view
        returns (uint)
    {
        return vestedAmount(client, contributor, uint(block.timestamp))
            - released(client, contributor);
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

    function findAddressInActivePayments(address client, address contributor)
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

    function _removePayment(address client, address contributor) internal {
        //we claim the earned funds for the contributor.
        _claim(client, contributor);

        //we remove the payment from the activePayments array
        uint contribIndex = findAddressInActivePayments(client, contributor);

        if (contribIndex != type(uint).max) {
            // Move the last element into the place to delete
            activePayments[client][contribIndex] =
                activePayments[client][activePayments[client].length - 1];
            // Remove the last element
            activePayments[client].pop();

            delete vestings[client][contributor];

            emit VestingPaymentRemoved(client, contributor);
        }

        /// Note that all unvested funds remain in the PaymentClient, where they will be accounted for in future payment orders.
    }

    /// @notice Adds a new payment containing the details of the monetary flow
    ///         depending on the module.
    /// @param _contributor Contributor's address.
    /// @param _salary Salary contributor will receive per epoch.
    /// @param _start Start vesting timestamp.
    /// @param _duration Vesting duration timestamp.
    function _addPayment(
        address client,
        address _contributor,
        uint _salary,
        uint _start,
        uint _duration
    ) internal {
        if (
            !validAddress(_contributor) || !validSalary(_salary)
                || !validStart(_start) || !validDuration(_start, _duration)
        ) {
            emit InvalidVestingOrderDiscarded(
                _contributor, _salary, _start, _duration
            );
        } else {
            vestings[client][_contributor] =
                VestingWallet(_salary, 0, _start, _duration);

            uint contribIndex =
                findAddressInActivePayments(client, _contributor);
            if (contribIndex == type(uint).max) {
                activePayments[client].push(_contributor);
            }

            emit VestingPaymentAdded(
                client, _contributor, _salary, _start, _duration
            );
        }
    }

    function _claim(address client, address beneficiary) internal {
        uint amount = releasable(client, beneficiary);
        vestings[client][beneficiary]._released += amount;

        //if beneficiary has unclaimable tokens from before, add it to releasable amount
        if (unclaimableAmounts[client][beneficiary] > 0) {
            amount += unclaimable(client, beneficiary);
            delete unclaimableAmounts[client][beneficiary];
        }

        // we claim the earned funds for the contributor.
        address _token = address(token());
        (bool success, bytes memory data) = address(_token).call(
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
            // if transfer fails, store amount to unclaimableAmounts.
            unclaimableAmounts[client][beneficiary] += amount;
        }
    }

    /// @notice Virtual implementation of the vesting formula.
    ///         Returns the amount vested, as a function of time,
    ///         for an asset given its total historical allocation.
    /// @param contributor The contributor to check on.
    /// @param timestamp Current block.timestamp
    function _vestingSchedule(
        address client,
        address contributor,
        uint timestamp
    ) internal view virtual returns (uint) {
        uint totalAllocation = vestings[client][contributor]._salary;
        uint startContributor = start(client, contributor);
        uint durationContributor = duration(client, contributor);

        if (timestamp < startContributor) {
            return 0;
        } else if (timestamp > startContributor + durationContributor) {
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

    function validSalary(uint _salary) internal view returns (bool) {
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

    function validDuration(uint _start, uint _duration)
        internal
        view
        returns (bool)
    {
        if (_duration == 0) {
            return false;
        }
        return true;
    }
}
