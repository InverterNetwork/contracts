// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies
import {Types} from "src/common/Types.sol";
import {Module} from "src/modules/base/Module.sol";

// Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IProposal} from "src/interfaces/IProposal.sol";

//--------------------------------------------------------------------------
// Errors

// @todo declare here

contract Payment is Module {
    //--------------------------------------------------------------------------
    // Storage

    struct Payment {
        //address token;
        uint salary; // per epoch
        uint epochsAmount;
        bool enabled; // @audit rename to paused?
    }

    ;

    // proposalId => contributerAddress => Payment
    mapping(uint => mapping(address => Payment)) public payments;

    address private token;

    //--------------------------------------------------------------------------
    // Events

    event AddPayment(
        uint proposalId, address contributor, uint salary, uint epochsAmount
    );

    event PausePayment(uint proposalId, address contributor, uint salary);

    event Claim(uint proposalId, address contributor, uint availableToClaim);

    //--------------------------------------------------------------------------
    // Modifiers

    modifier onlyOwner(uint proposalId) {
        require(proposals[proposalId].owner == msg.sender, "not proposal owner");
        _;
    }

    modifier onlyContributor(uint proposalId) {
        require(
            payments[proposalId][msg.sender].salary > 0, "no active payments"
        );
        _;
    }

    // @dev make sure proposal exists
    modifier proposalExists(uint proposalId) {
        require(
            proposals[proposalId].initialFunding > 0, "proposal does not exist"
        );
        _;
    }

    // @audit validContributor, validSalary, validEpochs.
    modifier validContributorData(
        address contributor,
        uint salary,
        uint epochsAmount
    ) {
        require(
            payments[proposalId][contributor].salary == 0,
            "payment already added"
        );
        require(contributor != address(0), "invalid contributor address");
        require(salary > 0, "invalid salary");
        require(epochsAmount > 0, "invalid epochsAmount");
        _;
    }

    //--------------------------------------------------------------------------
    // Functions

    // @audit initializer modifier.
    function initialize(IProposal proposal, bytes memory) external {
        __Module_init(proposal);

        // @audit token = proposal.paymentToken();
        // @note Decode params like:
        // (uint a) = abi.decode(data, (uint));
    }

    // @notice Claims any accrued funds which a contributor has earnt
    function claim(uint proposalId) external onlyContributor(proposalId) {
        // TODO implement
        uint availableToClaim;

        emit Claim(proposalId, msg.sender, availableToClaim);
    }

    // @notice Removes/stops a payment of a contributor
    function removePayment(uint proposalId, address contributor)
        external
        onlyOwner(proposalId)
    {
        // @audit idempotent.
        //
        // 1. Delete the current existing payment.
        //      => It's an error if payment is already deleted.
        // 2. Have the payment be deleted after the function executed. <-- This is the way we think!
        //      => It's NOT an error if payment is already deleted.
        //
        // Pattern:
        if (payments[proposalId][contributor].salary != 0) {
            // @todo Emit event.
            delete payments[proposalId][contributor];
        }
    }

    // @notice Pauses a payment of a contributor
    function pausePayment(uint proposalId, address contributor)
        external
        onlyOwner(proposalId)
    {
        // @audit idempotent.
        require(
            payments[proposalId][contributor].salary > 0, "non existing payment"
        );
        require(
            payments[proposalId][contributor].enabled, "payment already paused"
        );
        payments[proposalId][contributor].enabled = false;

        // PaymentPaused
        emit PausePayment(proposalId, contributor, salary);
    }

    /// @notice Returns the existing payments of the contributors
    function listPayments(uint proposalId, address contributor)
        external
        view
        proposalExists(proposalId)
        returns (address, uint, uint)
    {
        return (
            payments[proposalId][contributor].token,
            payments[proposalId][contributor].salary,
            payments[proposalId][contributor].epochsAmount
        );
    }

    /// @notice Adds a new payment containing the details of the monetary flow depending on the module
    function addPayment(
        uint proposalId,
        address contributor,
        //address token,
        uint salary,
        uint epochsAmount
    )
        external
        onlyOwner(proposalId)
        proposalExists(proposalId)
        validContributorData(contributor, salary, epochsAmount)
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
        payments[proposalId][contributor] = Payment(
            //token,    //must be same as in proposal
            salary, //proposal balance must be greater than salary*epochsAmount
            epochsAmount,
            true
        );

        emit AddPayment(proposalId, contributor, salary, epochsAmount);
    }
}
