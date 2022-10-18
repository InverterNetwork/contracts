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
 - in addPayment() use delegatecall to transfer funds from proposal contract.
*/


/**
 * @title Payment manager module implementation #1: Linear vesting curve.
 *
 * @dev The payment module handles the money flow to the contributors
 * (e.g. how many tokens are sent to which contributor at what time).
 *
 * @author byterocket
 */

contract PaymentManager is Module {
    //--------------------------------------------------------------------------
    // Storage

    IERC20 private token;             // invariant
    address private proposal;

    struct VestingWallet {
        uint _salary;
        uint _released;
        uint64 _start;
        uint64 _duration;
        bool _enabled;
    }

    // contributor => Payment
    mapping(address => VestingWallet) private vestings;

    //--------------------------------------------------------------------------
    // Events

    event PaymentAdded(
        address contributor,
        uint salary,
        uint64 start,
        uint64 end
    );
    event PaymentRemoved(address contributor);
    event PaymentPaused(address contributor);
    event PaymentContinued(address contributor);
    event ERC20Released(address indexed token, uint256 amount);

    //--------------------------------------------------------------------------
    // Errors

    /// @notice salary cant be 0.
    error Module__PaymentManager__InvalidSalary();

    /// @notice should start in future, cant be more than 10e18.
    error Module__PaymentManager__InvalidStart();

    /// @notice duration cant overflow, cant be 0.
    error Module__PaymentManager__InvalidDuration();

    //--------------------------------------------------------------------------
    // Modifiers

    modifier validSalary(uint _salary) {
        if(_salary == 0)
            revert Module__PaymentManager__InvalidSalary();
        _;
    }

    modifier validStart(uint _start) {
        if(_start < block.timestamp || _start >= type(uint64).max)
            revert Module__PaymentManager__InvalidStart();
        _;
    }

    modifier validDuration(uint _start, uint _duration){
        if(_start + _duration <= _start || _duration == 0)
            revert Module__PaymentManager__InvalidDuration();
        _;
    }

    //--------------------------------------------------------------------------
    // External Functions

    /// @notice Initialize module, save token and proposal address.
    /// @param proposalInterface Interface of proposal.
    /// @param metadata module metadata.
    /// @param data encoded token and proposal address.
    function initialize(
        IProposal proposalInterface,
        Metadata memory metadata,
        bytes memory data
    )
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

    /// @notice Release the releasable tokens.
    ///         In OZ VestingWallet this method is named release().
    function claim() external {
        if(vestings[msg.sender]._enabled){
            uint256 amount = releasable();
            vestings[msg.sender]._released += amount;

            emit ERC20Released(address(token), amount);

            require(token.transfer(msg.sender, amount),
                "erc20 transfer failed");
        }
    }

    /// @notice Adds a new payment containing the details of the monetary flow
    ///         depending on the module.
    /// @param _contributor Contributor's address.
    /// @param _salary Salary contributor will receive per epoch.
    /// @param _start Start vesting timestamp.
    /// @param _duration Vesting duration timestamp.
    function addPayment(
        address _contributor,
        uint _salary,
        uint64 _start,
        uint64 _duration
    )
        external
        onlyAuthorized // only proposal owner
        validSalary(_salary)
        validStart(_start)
        validDuration(_start, _duration)
    {
        require(validAddress(_contributor), "invalid contributor");

        // @todo Nejc: Verify there's enough tokens in proposal for the payment.
        // @todo Nejc: delegatecall transferFrom proposal to payment module.
        // @todo Nejc: before adding payment make sure contributor is wListed.

        vestings[_contributor] = VestingWallet(
            _salary,
            0,
            _start,
            _duration,
            true
        );

        emit PaymentAdded(_contributor, _salary, _start, _duration);
    }

    /// @notice Deletes a contributors payment and refunds non-released tokens
    ///         to proposal owner.
    /// @param contributor Contributor's address.
    function removePayment(address contributor)
        external
        onlyAuthorized // only proposal owner
    {
        // @noto Nejc: withdraw tokens that were not withdrawn yet.
        uint unclaimedAmount = vestedAmount(uint64(block.timestamp),
            contributor) - released(contributor);
        if(unclaimedAmount > 0) {
            delete vestings[contributor];

            require(token.transfer(msg.sender, unclaimedAmount),
                "erc20 transfer failed");

            emit PaymentRemoved(contributor);
        }
    }

    /// @notice Disable a payment of a contributor.
    /// @param contributor Contributor's address.
    function pausePayment(address contributor)
        external
        onlyAuthorized // only proposal owner
    {
        if(vestings[contributor]._enabled) {
            vestings[contributor]._enabled = false;
            emit PaymentPaused(contributor);
        }
    }

    /// @notice Continue contributors paused payment.
    ///         Tokens from paused period will be immediately claimable.
    /// @param contributor Contributor's address.
    function continuePayment(address contributor)
        external
        onlyAuthorized // only proposal owner
    {
        if(!vestings[contributor]._enabled) {
            vestings[contributor]._enabled = true;
            emit PaymentContinued(contributor);
        }
    }

    //--------------------------------------------------------------------------
    // Public Functions

    /// @notice Returns true if contributors vesting is enabled.
    /// @param contributor Contributor's address.
    function enabled(address contributor) public view returns(bool) {
        return vestings[contributor]._enabled;
    }

    /// @notice Getter for the start timestamp.
    /// @param contributor Contributor's address.
    function start(address contributor) public view returns(uint256) {
        return vestings[contributor]._start;
    }

    /// @notice Getter for the vesting duration.
    /// @param contributor Contributor's address.
    function duration(address contributor) public view returns(uint256) {
        return vestings[contributor]._duration;
    }

    /// @notice Getter for the amount of eth already released
    /// @param contributor Contributor's address.
    function released(address contributor) public view returns(uint256) {
        return vestings[contributor]._released;
    }

    /// @notice Calculates the amount of tokens that has already vested.
    /// @param contributor Contributor's address.
    function vestedAmount(uint64 timestamp, address contributor)
        public
        view
        returns (uint256)
    {
        return _vestingSchedule(vestings[contributor]._salary, timestamp);
    }

    /// @notice Getter for the amount of releasable tokens.
    function releasable() public view returns (uint) {
        return vestedAmount(uint64(block.timestamp), msg.sender) -
            released(msg.sender);
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    /// @notice Virtual implementation of the vesting formula.
    ///         Returns the amount vested, as a function of time,
    ///         for an asset given its total historical allocation.
    /// @param totalAllocation Contributor's allocated vesting amount.
    /// @param timestamp Current block.timestamp
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

    /// @notice validate address input.
    /// @param addr Address to validate.
    /// @return True if address is valid.
    function validAddress(address addr) internal view returns(bool){
        if(addr == address(0) || addr == msg.sender || addr == address(this))
            return false;
        return true;
    }
}
