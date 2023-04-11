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

    // contributor => Payment
    mapping(address => VestingWallet) private vestings;
    // contributor => unclaimableAmount
    mapping(address => uint) private unclaimableAmounts;

    //--------------------------------------------------------------------------
    // Events

    /// @notice Emitted when a payment gets processed for execution.
    /// @param recipient The address that will receive the payment.
    /// @param amount The amount of tokens the payment consists of.
    /// @param start Timestamp at which the vesting starts.
    /// @param duration Number of blocks over which the amount will vest
    event VestingPaymentAdded(
        address indexed recipient, uint amount, uint start, uint duration
    );

    /// @notice Emitted when the vesting to an address is removed.
    /// @param recipient The address that will stop receiving payment.
    event VestingPaymentRemoved(address indexed recipient);

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

    //--------------------------------------------------------------------------
    // Modifiers

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
        _claim(client, _msgSender());
    }

    /// @inheritdoc IPaymentProcessor
    function processPayments(IPaymentClient client) external {
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

                _addPayment(_recipient, _amount, _start, _duration);

                emit PaymentOrderProcessed(
                    _recipient, _amount, _start, _duration
                );
            }
        }
    }

    function cancelRunningPayments(IPaymentClient client)
        external
        onlyAuthorizedOrOwner
    {
        _cancelRunningOrders(client);
    }

    function _cancelRunningOrders(IPaymentClient client) internal {
        IPaymentClient.PaymentOrder[] memory orders;
        orders = client.paymentOrders();

        address _recipient;
        for (uint i; i < orders.length; i++) {
            _recipient = orders[i].recipient;

            //check if running payment order exists. If it does, remove it
            if (start(_recipient) != 0) {
                _removePayment(client, _recipient);
            }
        }
    }

    /// @notice Deletes a contributors payment and leaves non-released tokens
    ///         in the PaymentClient.
    /// @param contributor Contributor's address.
    function removePayment(IPaymentClient client, address contributor)
        external
        onlyAuthorized
    {
        _removePayment(client, contributor);
    }

    //--------------------------------------------------------------------------
    // Public Functions

    /// @notice Getter for the start timestamp.
    /// @param contributor Contributor's address.
    function start(address contributor) public view returns (uint) {
        return vestings[contributor]._start;
    }

    /// @notice Getter for the vesting duration.
    /// @param contributor Contributor's address.
    function duration(address contributor) public view returns (uint) {
        return vestings[contributor]._duration;
    }

    /// @notice Getter for the amount of eth already released
    /// @param contributor Contributor's address.
    function released(address contributor) public view returns (uint) {
        return vestings[contributor]._released;
    }

    /// @notice Calculates the amount of tokens that has already vested.
    /// @param contributor Contributor's address.
    function vestedAmount(address contributor, uint timestamp)
        public
        view
        returns (uint)
    {
        return _vestingSchedule(contributor, timestamp);
    }

    /// @notice Getter for the amount of releasable tokens.
    function releasable(address contributor) public view returns (uint) {
        return vestedAmount(contributor, uint(block.timestamp))
            - released(contributor);
    }

    /// @notice Getter for the amount of tokens that could not be claimed.
    function unclaimable(address contributor) public view returns (uint) {
        return unclaimableAmounts[contributor];
    }

    function token() public view returns (IERC20) {
        return this.proposal().token();
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    function _removePayment(IPaymentClient client, address contributor)
        internal
    {
        //we claim the earned funds for the contributor.
        _claim(client, contributor);

        //all unvested funds remain in the PaymentClient, where they will be accounted for in future payment orders.

        delete vestings[contributor];

        emit VestingPaymentRemoved(contributor);
    }

    /// @notice Adds a new payment containing the details of the monetary flow
    ///         depending on the module.
    /// @param _contributor Contributor's address.
    /// @param _salary Salary contributor will receive per epoch.
    /// @param _start Start vesting timestamp.
    /// @param _duration Vesting duration timestamp.
    function _addPayment(
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
            vestings[_contributor] =
                VestingWallet(_salary, 0, _start, _duration);

            emit VestingPaymentAdded(_contributor, _salary, _start, _duration);
        }
    }

    function _claim(IPaymentClient client, address beneficiary) internal {
        uint amount = releasable(beneficiary);
        vestings[beneficiary]._released += amount;

        //if beneficiary has unclaimable tokens from before, add it to releasable amount
        if (unclaimableAmounts[beneficiary] > 0) {
            amount += unclaimable(beneficiary);
            delete unclaimableAmounts[beneficiary];
        }

        // we claim the earned funds for the contributor.
        try token().transferFrom(address(client), beneficiary, amount) {
            emit TokensReleased(beneficiary, address(token()), amount);
            // if transfer fails, move amount to unclaimableAmounts.
        } catch {
            unclaimableAmounts[beneficiary] += amount;
        }
    }

    /// @notice Virtual implementation of the vesting formula.
    ///         Returns the amount vested, as a function of time,
    ///         for an asset given its total historical allocation.
    /// @param contributor The contributor to check on.
    /// @param timestamp Current block.timestamp
    function _vestingSchedule(address contributor, uint timestamp)
        internal
        view
        virtual
        returns (uint)
    {
        uint totalAllocation = vestings[contributor]._salary;
        uint startContributor = start(contributor);
        uint durationContributor = duration(contributor);

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
