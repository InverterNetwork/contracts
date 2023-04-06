// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

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

    event PaymentAdded(address contributor, uint salary, uint start, uint end);
    event PaymentRemoved(address contributor);

    event PaymentUpdated(address contributor, uint newSalary, uint newEndDate);
    event ERC20Released(address indexed token, uint amount);

    //--------------------------------------------------------------------------
    // Errors

    /// @notice salary cannot be 0.
    error Module__PaymentManager__InvalidSalary();

    /// @notice should start in future, cant be more than 10e18.
    error Module__PaymentManager__InvalidStart();

    /// @notice duration cant overflow, cant be 0.
    error Module__PaymentManager__InvalidDuration();

    /// @notice invalid token address
    error Module__PaymentManager__InvalidToken();

    /// @notice invalid proposal address
    error Module__PaymentManager__InvalidProposal();

    /// @notice invalid contributor address
    error Module__PaymentManager__InvalidContributor();

    /// @notice insufficient tokens in the client to do payments
    error Module__PaymentManager__InsufficientTokenBalanceInClient();

    //--------------------------------------------------------------------------
    // Modifiers

    modifier validSalary(uint _salary) {
        if (_salary == 0) {
            revert Module__PaymentManager__InvalidSalary();
        }
        _;
    }

    modifier validStart(uint _start) {
        if (_start < block.timestamp || _start >= type(uint).max) {
            revert Module__PaymentManager__InvalidStart();
        }
        _;
    }

    modifier validDuration(uint _start, uint _duration) {
        if (_duration == 0) {
            revert Module__PaymentManager__InvalidDuration();
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

        emit PaymentRemoved(contributor);
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
    )
        internal
        validSalary(_salary)
        validStart(_start)
        validDuration(_start, _duration)
    {
        if (!validAddress(_contributor)) {
            revert Module__PaymentManager__InvalidContributor();
        }

        vestings[_contributor] = VestingWallet(_salary, 0, _start, _duration);

        emit PaymentAdded(_contributor, _salary, _start, _duration);
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
            emit ERC20Released(address(token()), amount);
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

        if (timestamp < start(contributor)) {
            return 0;
        } else if (timestamp > start(contributor) + duration(contributor)) {
            return totalAllocation;
        } else {
            return (totalAllocation * (timestamp - start(contributor)))
                / duration(contributor);
        }
    }

    /// @notice validate address input.
    /// @param addr Address to validate.
    /// @return True if address is valid.
    function validAddress(address addr) internal view returns (bool) {
        if (addr == address(0) || addr == _msgSender() || addr == address(this))
        {
            return false;
        }
        return true;
    }
}
