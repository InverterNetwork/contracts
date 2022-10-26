// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies
import {Types} from "src/common/Types.sol";
import {Module} from "src/modules/base/Module.sol";

// Internal Libraries
import {LibString} from "src/common/LibString.sol";

// Internal Interfaces
import {IMilestoneManager} from "src/modules/IMilestoneManager.sol";
import {IProposal} from "src/proposal/IProposal.sol";

/**
 * @title Milestone Module
 *
 * @dev @todo felix: Add contract documentation
 *
 * @author byterocket
 */
contract MilestoneManager is IMilestoneManager, Module {
    using LibString for string;

    //--------------------------------------------------------------------------
    // Modifiers

    modifier onlyContributor() {
        // @todo mp, felix: Use _msgSender().
        if (!__Module_proposal.isActiveContributor(msg.sender)) {
            revert Module__MilestoneManager__OnlyCallableByContributor();
        }
        _;
    }

    modifier validDuration(uint duration) {
        if (duration == 0) {
            revert Module__MilestoneManager__InvalidDuration();
        }
        _;
    }

    modifier validBudget(uint budget) {
        // @todo mp, marvin, nuggan: No constraints for a milestone budget?
        _;
    }

    modifier validTitle(string memory title) {
        if (title.isEmpty()) {
            revert Module__MilestoneManager__InvalidTitle();
        }
        _;
    }

    modifier validDetails(string memory details) {
        if (details.isEmpty()) {
            revert Module__MilestoneManager__InvalidDetails();
        }
        _;
    }

    modifier validId(uint id) {
        if (!isExistingMilestone(id)) {
            revert Module__MilestoneManager__InvalidMilestoneId();
        }
        _;
    }

    modifier onlyConsecutiveMilestones(uint prevId, uint id) {
        if (_milestones[prevId] != id) {
            revert("Not consecutive milestones");
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Constants

    /// @dev Unrealistic to have that many milestones.
    uint internal constant _SENTINEL = type(uint).max;

    //----------------------------------
    // Proposal Callback Function Signatures

    string private constant _FUNC_ADD_MILESTONE =
        "__Milestone_addMilestone(string,uint256,string)";

    string private constant _FUNC_UPDATE_MILESTONE_DETAILS =
        "__Milestone_updateMilestoneDetails(uint256,string)";

    string private constant _FUNC_UPDATE_MILESTONE_START_DATE =
        "__Milestone_updateMilestoneStartDate(uint256,uint256)";

    string private constant _FUNC_REMOVE_MILESTONE =
        "__Milestone_removeMilestone(uint256)";

    string private constant _FUNC_SUBMIT_MILESTONE =
        "__Milestone_submitMilestone(uint256)";

    string private constant _FUNC_CONFIRM_MILESTONE =
        "__Milestone_confirmMilestone(uint256)";

    string private constant _FUNC_DECLINE_MILESTONE =
        "__Milestone_declineMilestone(uint256)";

    //--------------------------------------------------------------------------
    // Storage

    mapping(uint => Milestone) internal _milestoneRegistry;

    mapping(uint => uint) internal _milestones;

    uint internal _milestoneCounter;

    uint internal _activeMilestone;

    //--------------------------------------------------------------------------
    // Initialization

    constructor() {}

    /// @inheritdoc Module
    function init(
        IProposal proposal_,
        Metadata memory metadata,
        bytes memory /*configdata*/
    ) external override (Module) initializer {
        __Module_init(proposal_, metadata);

        // Set up sentinel to signal empty list of milestones.
        _milestones[_SENTINEL] = _SENTINEL;

        // Set _activeMilestone to sentinel as otherwise the 0th milestone would
        // be interpreted as active.
        _activeMilestone = _SENTINEL;
    }

    //--------------------------------------------------------------------------
    // Public View Functions

    function getMilestone(uint id) public view returns (Milestone memory) {
        if (!isExistingMilestone(id)) {
            revert("Milestone does not exist");
        }

        return _milestoneRegistry[id];
    }

    function getAllMilestoneIds() external view returns (uint[] memory) {
        uint[] memory array = new uint[](_milestoneCounter);

        uint index = 0;
        uint id = _milestones[_SENTINEL];
        while (id != _SENTINEL) {
            array[index] = id;
            id = _milestones[id];
            index++;
        }

        return array;
    }

    function getActiveMilestoneId() public view returns (uint id) {
        if (!hasActiveMilestone()) {
            revert("No milestone currently active");
        }

        return _activeMilestone;
    }

    function hasActiveMilestone() public view returns (bool) {
        if (!isExistingMilestone(_activeMilestone)) {
            return false;
        }

        Milestone storage m = _milestoneRegistry[_activeMilestone];

        return m.completed && m.startTimestamp + m.duration < block.timestamp;
    }

    function isNextMilestoneActivateable() public view returns (bool) {
        if (hasActiveMilestone()) {
            return false;
        }

        uint next = _milestones[_activeMilestone];

        return isExistingMilestone(next);
    }

    function isExistingMilestone(uint id) public view returns (bool) {
        return id != _SENTINEL && _milestones[id] != 0;
    }

    //--------------------------------------------------------------------------
    // Milestone API Functions

    /// @inheritdoc IMilestoneManager
    function addMilestone(
        string memory title,
        uint startDate,
        string memory details
    ) external onlyAuthorized returns (uint) {
        bool ok;
        bytes memory returnData;

        (ok, returnData) = _triggerProposalCallback(
            abi.encodeWithSignature(
                _FUNC_ADD_MILESTONE, title, startDate, details
            ),
            Types.Operation.Call
        );

        if (!ok) {
            revert Module_ProposalCallbackFailed(_FUNC_ADD_MILESTONE);
        }

        // Decode returnData into milestone id and return it.
        return abi.decode(returnData, (uint));
    }

    /// @inheritdoc IMilestoneManager
    function removeMilestone(uint id) external onlyAuthorized {
        bool ok;

        (ok, /*returnData*/ ) = _triggerProposalCallback(
            abi.encodeWithSignature(_FUNC_REMOVE_MILESTONE, id),
            Types.Operation.Call
        );

        if (!ok) {
            revert Module_ProposalCallbackFailed(_FUNC_REMOVE_MILESTONE);
        }
    }

    function startNextMilestone() external onlyAuthorized {
        // Pre conditions:
        // - preMilestone confirmed
        // - preMilestone duration ended

        // Payment handling:
        // - Payment for this milestone starts now
        // - Need to make sure tokens exist!
        //   - Fetch tokens from proposal to address(this) (?)
        //   - Payment Order
        //      - Implement PaymentClient interface
        //      - Create PaymentOrder

        // Milestone handling:
        // - milestone starts now
    }

    /// @inheritdoc IMilestoneManager
    function updateMilestoneDetails(uint id, string memory details)
        external
        onlyAuthorized
    {
        bool ok;

        (ok, /*returnData*/ ) = _triggerProposalCallback(
            abi.encodeWithSignature(_FUNC_UPDATE_MILESTONE_DETAILS, id, details),
            Types.Operation.Call
        );

        if (!ok) {
            revert Module_ProposalCallbackFailed(_FUNC_UPDATE_MILESTONE_DETAILS);
        }
    }

    /// @inheritdoc IMilestoneManager
    function updateMilestoneStartDate(uint id, uint startDate)
        external
        onlyAuthorized
    {
        bool ok;

        (ok, /*returnData*/ ) = _triggerProposalCallback(
            abi.encodeWithSignature(
                _FUNC_UPDATE_MILESTONE_START_DATE, id, startDate
            ),
            Types.Operation.Call
        );

        if (!ok) {
            revert Module_ProposalCallbackFailed(
                _FUNC_UPDATE_MILESTONE_START_DATE
            );
        }
    }

    /// @inheritdoc IMilestoneManager
    function submitMilestone(uint id) external onlyContributor {
        bool ok;

        (ok, /*returnData*/ ) = _triggerProposalCallback(
            abi.encodeWithSignature(_FUNC_SUBMIT_MILESTONE, id),
            Types.Operation.Call
        );

        if (!ok) {
            revert Module_ProposalCallbackFailed(_FUNC_SUBMIT_MILESTONE);
        }
    }

    /// @inheritdoc IMilestoneManager
    function confirmMilestone(uint id) external onlyAuthorized {
        bool ok;

        (ok, /*returnData*/ ) = _triggerProposalCallback(
            abi.encodeWithSignature(_FUNC_CONFIRM_MILESTONE, id),
            Types.Operation.Call
        );

        if (!ok) {
            revert Module_ProposalCallbackFailed(_FUNC_CONFIRM_MILESTONE);
        }
    }

    /// @inheritdoc IMilestoneManager
    function declineMilestone(uint id) external onlyAuthorized {
        bool ok;

        (ok, /*returnData*/ ) = _triggerProposalCallback(
            abi.encodeWithSignature(_FUNC_DECLINE_MILESTONE, id),
            Types.Operation.Call
        );

        if (!ok) {
            revert Module_ProposalCallbackFailed(_FUNC_DECLINE_MILESTONE);
        }
    }

    //--------------------------------------------------------------------------
    // Proposal Callback Functions

    function __Milestone_addMilestone(
        uint duration,
        uint budget,
        string memory title,
        string memory details
    )
        external
        onlyProposal
        validDuration(duration)
        validBudget(budget)
        validTitle(title)
        validDetails(details)
        returns (uint)
    {
        // Increase counter and cache result.
        // Note that ids therefore start at 1.
        uint id = ++_milestoneCounter;

        // Add milestone's id to list.
        _milestones[id] = _milestones[_SENTINEL];
        _milestones[_SENTINEL] = id;

        // Add milestone instance to registry.
        _milestoneRegistry[id] = Milestone({
            duration: duration,
            budget: budget,
            title: title,
            details: details,
            startTimestamp: 0,
            submitted: false,
            completed: false
        });

        // Emit event.
        emit MilestoneAdded(id, duration, budget, title, details);

        return id;
    }

    function __Milestone_removeMilestone(uint prevId, uint id)
        external
        onlyProposal
        validId(id)
        onlyConsecutiveMilestones(prevId, id)
    {
        Milestone storage m = _milestoneRegistry[id];

        // Not removeable if milestone started already.
        if (m.startTimestamp != 0) {
            revert Module__MilestoneManager__MilestoneNotRemovable();
        }

        // Delete milestone instance from registry.
        delete _milestoneRegistry[id];

        // Remove milestone's id from list and decrease counter.
        _milestones[prevId] = _milestones[id];
        delete _milestones[id];
        _milestoneCounter--;

        emit MilestoneRemoved(id);
    }

    function __Milestone_startNextMilestone() external onlyProposal {
        if (!isNextMilestoneActivateable()) {
            revert("Milestone not activateable");
        }

        // Get next milestone's id and update _activeMilestone.
        uint id = _milestones[_activeMilestone];
        _activeMilestone = id;

        // Mark milestone as started, i.e. set its startTimestamp.
        _milestoneRegistry[id].startTimestamp = block.timestamp;

        // @todo Initiate payment order.
        //       Make sure token exists.
    }

    function __Milestone_updateMilestone(
        uint id,
        uint duration,
        uint budget,
        string memory details
    )
        external
        onlyProposal
        validId(id)
        validDuration(duration)
        validBudget(budget)
        validDetails(details)
    {
        Milestone storage m = _milestoneRegistry[id];

        // Not updateable if milestone started already.
        if (m.startTimestamp != 0) {
            revert Module__MilestoneManager__MilestoneNotUpdateable();
        }

        bool durationUpdated = m.duration != duration;
        bool budgetUpdated = m.budget != budget;
        bool detailsUpdated = m.details.equals(details);

        if (durationUpdated || budgetUpdated || detailsUpdated) {
            m.duration = duration;
            m.budget = budget;
            m.details = details;
            emit MilestoneUpdated(id, duration, budget, details);
        }
    }

    function __Milestone_submitMilestone(uint id)
        external
        onlyProposal
        validId(id)
    {
        Milestone storage m = _milestoneRegistry[id];

        // Not submitable if milestone not started yet or already completed.
        if (m.startTimestamp == 0 || m.completed) {
            revert Module__MilestoneManager__MilestoneNotSubmitable();
        }

        if (!m.submitted) {
            m.submitted = true;
            emit MilestoneSubmitted(id);
        }
    }

    function __Milestone_confirmMilestone(uint id)
        external
        onlyProposal
        validId(id)
    {
        Milestone storage m = _milestoneRegistry[id];

        // Not confirmable if milestone not submitted yet.
        if (!m.submitted) {
            revert Module__MilestoneManager__MilestoneNotConfirmable();
        }

        if (!m.completed) {
            m.completed = true;
            emit MilestoneConfirmed(id);
        }
    }

    function __Milestone_declineMilestone(uint id)
        external
        onlyProposal
        validId(id)
    {
        Milestone storage m = _milestoneRegistry[id];

        // Not declineable if milestone not submitted yet or already completed.
        if (!m.submitted || m.completed) {
            revert Module__MilestoneManager__MilestoneNotDeclineable();
        }

        // Declining a milestone marks it as non-submitted again.
        m.submitted = false;
        emit MilestoneDeclined(id);
    }
}
