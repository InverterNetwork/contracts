// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies
import {Types} from "src/common/Types.sol";
import {Module} from "src/modules/base/Module.sol";

// Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IProposal} from "src/interfaces/IProposal.sol";

contract Payment is Module {

    //--------------------------------------------------------------------------
    // Storage

    struct Payment {
        uint proposalId;
        address contributor;
        uint salary;            // per epoch
        uint epochsAmount;
        bool enabled;
    };

    // proposalId => contributerAddress => Contributor
    mapping(uint => mapping(address => Payment)) public payments;

    //--------------------------------------------------------------------------
    // Events

    event addPayment(
        uint proposalId,
        address contributor,
        uint salary,
        uint epochsAmount
    );

    //--------------------------------------------------------------------------
    // Modifiers

    modifier onlyOwner(uint proposalId) {
        require(proposals[proposalId].owner == msg.sender, "not proposal owner");
        _;
    }

    modifier onlyContributor(uint proposalId) {
        require(payments[proposalId][msg.sender].salary > 0, "no active payments");
        _;
    }

    // @dev make sure proposal exists
    modifier proposalExists(uint proposalId) {
        require(proposals[proposalId].initialFunding > 0, "proposal does not exist");
        _;
    }

    modifier validContributorData(address contributorAddress, uint salary, uint epochsAmount) {
        require(payments[proposalId][contributor].salary == 0, "payment already added");
        require(contributor != address(0), "invalid contributor address");
        require(salary > 0, "invalid salary");
        require(epochsAmount > 0, "invalid epochsAmount");
        _;
    }

    //--------------------------------------------------------------------------
    // Functions

    function initialize(IProposal proposal, bytes memory) external {
        __Module_init(proposal);

        // @note Decode params like:
        // (uint a) = abi.decode(data, (uint));
    }

    // @notice Claims any accrued funds which a contributor has earnt
    function claim(uint proposalId) external onlyContributor(proposalId) {
        // TODO implement
    }

    // @notice Removes/stops a payment of a contributor
    function removePayment(uint proposalId) external onlyOwner(proposalId) {
        require(payments[proposalId][contributor].salary > 0, "non existing payment");
        payments[proposalId][contributor].enabled = false;
    }

    // @notice Pauses a payment of a contributor
    function pausePayment(uint proposalId) external onlyOwner(proposalId) {
        require(payments[proposalId][contributor].salary > 0, "non existing payment");
        payments[proposalId][contributor].enabled = false;
    }

    /// @notice Returns the existing payments of the contributors
    function listPayments(uint proposalId, address contributorAddress)
        external
        view
        proposalExists(proposalId)
        returns(uint, uint)
    {
        return (payments[proposalId][contributorAddress].salary, payments[proposalId][contributorAddress].epochsAmount);
    }

    /// @notice Adds a new payment containing the details of the monetary flow depending on the module
    function addPayment(uint proposalId, address contributorAddress, uint salary, uint epochsAmount)
        external
        proposalExists(proposalId)
        validContributorData(contributorAddress, salary, epochsAmount)
    {
        // @todo verify there's enough tokens in proposal for the payout.

        // add struct data to mapping
        payments[proposalId][contributorAddress] = Payment(
            proposalId,
            contributorAddress,
            salary,
            epochsAmount,
            true
        );

        emit addPayment(proposalId, contributorAddress, salary, epochsAmount);
    }





}
