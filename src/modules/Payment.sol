// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies
import {Types} from "src/common/Types.sol";
import {Module} from "src/modules/base/Module.sol";
import {ERC20} from "@oz/token/ERC20/ERC20.sol";

// Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IProposal} from "src/interfaces/IProposal.sol";


/*** @todo Nejc:
 - replace require syntax with errors
*/


/**
 * @title Payment module
 *
 * @dev The payment module handles the money flow to the contributors
 * (e.g. how many tokens are sent to which contributor at what time).
 *
 * @author byterocket
 */


contract Payment is Module {
    //--------------------------------------------------------------------------
    // Storage

    IERC20 private token;             // invariant
    address private proposal;

    struct VestingWallet {
        uint _salary;
        uint _released;
        uint64 _start;
        uint64 _duration;
        bool enabled;
    }

    // contributor => Payment
    mapping(address => VestingWallet) private vestings;

    //--------------------------------------------------------------------------
    // Events

    event ERC20Released(address indexed token, uint256 amount);

    event PaymentAdded(
        address contributor,
        uint salary,
        uint64 start,
        uint64 end
    );

    // event PaymentRemoved(address contributor, uint salary, uint epochsAmount);
    //
    // event EnablePaymentToggled(address contributor, uint salary, bool enabled);
    //
    // event PaymentClaimed(address contributor, uint availableToClaim);



    //--------------------------------------------------------------------------
    // Errors

    // @todo Nejc: Declare here.

    //--------------------------------------------------------------------------
    // Modifiers

    modifier validContributor(address contributor) {
        require(contributor != address(0), "invalid contributor address");
        require(contributor != address(this), "invalid contributor address");
        require(contributor != msg.sender, "invalid contributor address");
        require(vestings[contributor]._salary == 0, "payment already added");
        _;
    }

    modifier validSalary(uint salary) {
        require(salary > 0, "invalid salary");
        _;
    }

    modifier validEpochsAmount(uint epochsAmount) {
        require(epochsAmount > 0, "invalid epochs amount");
        _;
    }

    modifier hasActivePayments() {
        require(vestings[msg.sender]._salary > 0, "no active payments");
        _;
    }

    //--------------------------------------------------------------------------
    // External View Functions

    function start(address contributor) public view virtual returns(uint256) {
        return vestings[contributor]._start;
    }

    function duration(address contributor) public view virtual returns(uint256) {
        return vestings[contributor]._duration;
    }

    function released(address contributor) public view virtual returns(uint256) {
        return vestings[contributor]._released;
    }

    function vestedAmount(uint64 timestamp) public view virtual returns (uint256) {
        return _vestingSchedule(token.balanceOf(
            address(this)) + released(msg.sender), timestamp);
    }

    function releasable() public view virtual returns (uint) {
        return vestedAmount(uint64(block.timestamp)) - released(msg.sender);
    }

    function release() public virtual {
        uint256 amount = releasable();
        vestings[msg.sender]._released += amount;
        emit ERC20Released(address(token), amount);
        // @todo Nejc: check transfer return value / use safeTransfer
        token.transfer(msg.sender, amount);
    }

    function _vestingSchedule(uint256 totalAllocation, uint64 timestamp)
        internal
        view
        virtual
        returns (uint256)
    {
        if (timestamp < start(msg.sender)) {
            return 0;
        } else if (timestamp > start(msg.sender) + duration(msg.sender)) {
            return totalAllocation;
        } else {
            return (totalAllocation * (timestamp - start(msg.sender))) /
                duration(msg.sender);
        }
    }

    /// @notice Initialize module, save token and proposal address.
    /// @param proposalInterface Interface of proposal.
    /// @param data encoded token and proposal address.
    function initialize(
        IProposal proposalInterface,
        Metadata memory metadata,
        bytes memory data)
        external
        initializer
    {
        __Module_init(proposalInterface, metadata);

        (address _token, address _proposal) =
            abi.decode(data, (address, address));

        require(validAddress(_token), "invalid token address");
        require(validAddress(_proposal), "invalid proposal address");

        token = IERC20(_token);
        proposal = _proposal;
    }

    /// @notice Adds a new payment containing the details of the monetary flow
    ///         depending on the module.
    /// @param contributor Contributor's address.
    /// @param salary Salary contributor will receive per epoch.
    /// PARAM epochsAmount Amount of epochs to receive the salary for.
    function addPayment(
        address contributor,
        uint salary,
        uint64 start,
        uint64 duration
        //uint epochsAmount
    )
        external
        // onlyAuthorized() // only proposal owner
        // validContributor(contributor)
        // validSalary(salary)

        //validEpochsAmount(epochsAmount)
        // @todo Nejc: add modifiers for input validation
    {
        // INPUTS VALIDATION
        // require(start + duration > start, "duration overflow");
        // require(start > block.timestamp, "should start in future");
        // require(duration > 0, "duration cant be 0");
        //require(vestings[contributor] == address(0), "already has a vesting");

        // @todo Nejc: Verify there's enough tokens in proposal for the payment.
        // @todo Nejc transferFrom proposal to payment module.
        // @todo Nejc: before adding payment make sure contributor is wListed.

        vestings[msg.sender] = VestingWallet(
            salary, 0, start, duration, true
        );

        emit PaymentAdded(contributor, salary, start, duration);
    }

    // @notice Returns address of vesting contract per contributor.
    // function getVesting(address contributor) external view returns(address) {
    //     return vestings[contributor];
    // }

    /// @notice Removes/stops a payment of a contributor.
    /// @param contributor Contributor's address.
    // function removePayment(address contributor)
    //     external
    //     onlyAuthorized() // only proposal owner
    // {
    //     if (payments[contributor].salary != 0) {
    //         uint _salary = payments[contributor].salary;
    //         uint _epochsAmount = payments[contributor].epochsAmount;
    //
    //         delete payments[contributor];
    //
    //         emit PaymentRemoved(contributor, _salary, _epochsAmount);
    //     }
    // }
    //
    // /// @notice Enable/Disable a payment of a contributor.
    // /// @param contributor Contributor's address.
    // function toggleEnablePayment(address contributor)
    //     external
    //     onlyAuthorized() // only proposal owner
    // {
    //     payments[contributor].enabled = !payments[contributor].enabled;
    //
    //     emit EnablePaymentToggled(
    //         contributor,
    //         payments[contributor].salary,
    //         payments[contributor].enabled
    //     );
    // }
    //
    // /// Note we may want a method that returns all contributor addresses.
    // /// @notice Returns the existing payments of the contributors.
    // /// @param contributor Contributor's address.
    // /// @return salary Salary contributor will receive per epoch.
    // /// @return epochsAmount Amount of epochs to receive the salary for.
    // function listPayments(address contributor)
    //     external
    //     view
    //     returns (uint, uint)
    // {
    //     return (
    //         payments[contributor].salary,
    //         payments[contributor].epochsAmount
    //     );
    // }

    //--------------------------------------------------------------------------
    // Internal Functions

    /// @notice validate address input.
    /// @param addr Address to validate.
    /// @return True if address is valid.
    function validAddress(address addr) internal view returns(bool){
        if(addr == address(0) || addr == msg.sender || addr == address(this))
            return false;
        return true;
    }
}
