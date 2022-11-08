// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Dependencies
import {ERC20} from "@oz/token/ERC20/ERC20.sol";

// Internal Dependencies
import {Types} from "src/common/Types.sol";
import {Module, ContextUpgradeable} from "src/modules/base/Module.sol";

// Internal Libraries
import {LibString} from "src/common/LibString.sol";

// Internal Interfaces
import {IMilestoneManager} from "src/modules/IMilestoneManager.sol";
import {IProposal} from "src/proposal/IProposal.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

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
        if (!__Module_proposal.isContributor(_msgSender())) {
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
        if (!isExistingMilestoneId(id)) {
            revert Module__MilestoneManager__InvalidMilestoneId();
        }
        _;
    }

    modifier onlyConsecutiveMilestones(uint prevId, uint id) {
        if (_milestones[prevId] != id) {
            revert Module__MilestoneManager__MilestonesNotConsecutive();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Constants

    /// @dev Unrealistic to have that many milestones.
    uint internal constant _SENTINEL = type(uint).max;

    //--------------------------------------------------------------------------
    // Storage

    mapping(uint => Milestone) private _milestoneRegistry;

    mapping(uint => uint) private _milestones;

    uint private _milestoneCounter;

    uint private _activeMilestone;

    //--------------------------------------------------------------------------
    // Initialization

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

    function getMilestoneInformation(uint id)
        public
        view
        returns (Milestone memory)
    {
        if (!isExistingMilestoneId(id)) {
            revert Module__MilestoneManager__InvalidMilestoneId();
        }

        return _milestoneRegistry[id];
    }

    function listMilestoneIds() external view returns (uint[] memory) {
        uint[] memory result = new uint[](_milestoneCounter);

        // Populate result array.
        uint index = 0;
        uint elem = _milestones[_SENTINEL];
        while (elem != _SENTINEL) {
            result[index] = elem;
            elem = _milestones[elem];
            index++;
        }

        return result;
    }

    function getActiveMilestoneId() public view returns (uint id) {
        if (!hasActiveMilestone()) {
            revert Module__MilestoneManager__NoActiveMilestone();
        }

        return _activeMilestone;
    }

    function hasActiveMilestone() public view returns (bool) {
        if (!isExistingMilestoneId(_activeMilestone)) {
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

        return isExistingMilestoneId(next);
    }

    function isExistingMilestoneId(uint id) public view returns (bool) {
        return id != _SENTINEL && _milestones[id] != 0;
    }

    //--------------------------------------------------------------------------
    // Milestone API Functions

    /// @inheritdoc IMilestoneManager
    function addMilestone(
        uint duration,
        uint budget,
        string memory title,
        string memory details
    )
        external
        onlyAuthorized
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

        emit MilestoneAdded(id, duration, budget, title, details);

        return id;
    }

    /// @inheritdoc IMilestoneManager
    function removeMilestone(uint prevId, uint id)
        external
        onlyAuthorized
        validId(id)
        onlyConsecutiveMilestones(prevId, id)
    {
        Milestone storage m = _milestoneRegistry[id];

        // Not removeable if milestone started already.
        if (m.startTimestamp != 0) {
            revert Module__MilestoneManager__MilestoneNotRemovable();
        }

        // Remove milestone instance from registry.
        delete _milestoneRegistry[id];

        // Remove milestone's id from list and decrease counter.
        _milestones[prevId] = _milestones[id];
        delete _milestones[id];
        _milestoneCounter--;

        emit MilestoneRemoved(id);
    }

    /// @inheritdoc IMilestoneManager
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

        if (!isNextMilestoneActivateable()) {
            revert Module__MilestoneManager__MilestoneNotActivateable();
        }

        // Get next milestone's id and update _activeMilestone.
        uint id = _milestones[_activeMilestone];
        _activeMilestone = id;

        // Mark milestone as started, i.e. set its startTimestamp.
        _milestoneRegistry[id].startTimestamp = block.timestamp;


        address[] memory contributors = __Module_proposal.listContributors();
        // @dev token should be declared in globaly if used in other functions
        IERC20 token = __Module_proposal.token();
        uint payout = _milestoneRegistry[_activeMilestone].budget * 1000
            / contributors.length * 1000;

        for(uint i; i < contributors.length; i++){
            token.safeTransfer(contributors[i], payout);
        }
    }

    /// @inheritdoc IMilestoneManager
    function updateMilestone(
        uint id,
        uint duration,
        uint budget,
        string memory details
    ) external onlyAuthorized validId(id) validDetails(details) {
        Milestone storage m = _milestoneRegistry[id];

        // Not updateable if milestone started already.
        if (m.startTimestamp != 0) {
            revert Module__MilestoneManager__MilestoneNotUpdateable();
        }

        // @todo mp: Gas optimize.
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

    /// @inheritdoc IMilestoneManager
    function submitMilestone(uint id) external onlyContributor validId(id) {
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

    /// @inheritdoc IMilestoneManager
    function confirmMilestone(uint id) external onlyAuthorized validId(id) {
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

    /// @inheritdoc IMilestoneManager
    function declineMilestone(uint id) external onlyAuthorized validId(id) {
        Milestone storage m = _milestoneRegistry[id];

        // Not declineable if milestone not submitted yet or already completed.
        if (!m.submitted || m.completed) {
            revert Module__MilestoneManager__MilestoneNotDeclineable();
        }

        // Declining a milestone marks it as not submitted again.
        m.submitted = false;
        emit MilestoneDeclined(id);
    }
}
