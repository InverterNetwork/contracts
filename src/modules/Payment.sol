// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies
import {Types} from "src/common/Types.sol";
import {Module} from "src/modules/base/Module.sol";
import {ERC20} from "@oz/token/ERC20/ERC20.sol";

// Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IProposal} from "src/interfaces/IProposal.sol";


contract Payment is Module {
    //--------------------------------------------------------------------------
    // Storage

    ERC20 private token;

    struct Payment {
        uint salary; // per epoch
        uint epochsAmount;
        bool enabled; // @audit rename to paused?
    }

    // contributerAddress => Payment
    mapping(address => Payment) public payments;

    //address private token;

    //--------------------------------------------------------------------------
    // Events

    event PaymentAdded(address contributor, uint salary, uint epochsAmount);

    event PaymentRemoved(address contributor, uint salary, uint epochsAmount);

    event EnablePaymentToggled(address contributor, uint salary, bool paymentEnabled);

    event PaymentClaimed(address contributor, uint availableToClaim);

    //--------------------------------------------------------------------------
    // Errors

    // @todo declare here

    //--------------------------------------------------------------------------
    // Modifiers

    modifier validContributor(address contributor) {
        require(contributor != address(0), "invalid contributor address");
        require(contributor != address(this), "invalid contributor address");
        require(contributor != msg.sender, "invalid contributor address");
        _;
    }

    modifier validSalary(address contributor, uint salary) {
      require(payments[contributor].salary == 0,
          "payment already added");
      require(salary > 0, "invalid salary");
      _;
    }

    modifier validEpochsAmount(uint epochsAmount) {
        require(epochsAmount > 0, "invalid epochs amount");
        _;
    }

    modifier hasActivePayments() {
        require(
            payments[msg.sender].salary > 0, "no active payments"
        );
        _;
    }

    //--------------------------------------------------------------------------
    // Functions

    // @audit initializer modifier.
    function initialize(IProposal proposal, bytes memory data) external initializer {
        __Module_init(proposal);

        address _token = abi.decode(data, (address));
        require(_token != address(0), "invalid token address");
        require(_token != msg.sender, "invalid token address");
        token = ERC20(_token);
    }

    // @notice Claims any accrued funds which a contributor has earnt
    function claim() external hasActivePayments() {
        // TODO implement
        uint availableToClaim;

        emit PaymentClaimed(msg.sender, availableToClaim);
    }

    // @notice Removes/stops a payment of a contributor
    function removePayment(address contributor)
        external
        onlyAuthorized() // only proposal owner
    {
        if (payments[contributor].salary != 0) {
            uint _salary = payments[contributor].salary;
            uint _epochsAmount = payments[contributor].epochsAmount;

            delete payments[contributor];

            emit PaymentRemoved(contributor, _salary, _epochsAmount);
        }
    }

    // @notice Enable/Disable a payment of a contributor
    // @param contributor Contributor's address
    function toggleEnablePayment(address contributor)
        external
        onlyAuthorized() // only proposal owner
    {
        payments[contributor].enabled = !payments[contributor].enabled;

        emit EnablePaymentToggled(
            contributor,
            payments[contributor].salary,
            payments[contributor].enabled
        );
    }

    /// NOTE we may want a method that returns all the contributor addresses
    /// @notice Returns the existing payments of the contributors
    function listPayments(address contributor)
        external
        view
        returns (uint, uint)
    {
        return (
            payments[contributor].salary,
            payments[contributor].epochsAmount
        );
    }

    /// @notice Adds a new payment containing the details of the monetary flow depending on the module
    function addPayment(
        address contributor,
        uint salary,
        uint epochsAmount
    )
        external
        onlyAuthorized() // only proposal owner
        validContributor(contributor)
        validSalary(contributor, salary)
        validEpochsAmount(epochsAmount)
    {
        // - mp: Define token in proposal, fetchable via `paymentToken()`.
        // - `addPayment()` fetch token from address(proposal) to address(this).
        // - Make functions idempotent.
        // - Use `onlyAuthorized` modifier.
        // - Refactor modifiers to only have single arguments, e.g. `validSalary`, `validEpochs`.
        // - Rename evetns to past term, e.g. `PaymentClaimed`, `PaymentPaused`.

        // Somewhere else: (A sends X tokens to proposal => token.balanceOf(proposal) == X)
        // Payment:
        // function addPayment {
        //   token.transferFrom(proposal, address(this), amount);
        // }

        // @todo verify there's enough tokens in proposal for the payment.

        // @todo make sure token address is the same as defined in proposal

        // add struct data to mapping
        payments[contributor] = Payment(
            salary,
            epochsAmount,
            true
        );

        emit PaymentAdded(contributor, salary, epochsAmount);
    }
}
