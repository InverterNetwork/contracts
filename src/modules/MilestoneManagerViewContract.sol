// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import {MilestoneManager} from "src/modules/MilestoneManager.sol";
import {IMilestoneManager} from "src/modules/IMilestoneManager.sol";

abstract contract MilestoneManagerViewContract is IMilestoneManager {
    //--------------------------------------------------------------------------
    // Constants

    /// @dev Marks the beginning of the list.
    /// @dev Unrealistic to have that many milestones.
    uint internal constant _SENTINEL = type(uint).max;

    /// @dev Marks the last element of the list.
    /// @dev Always links back to the _SENTINEL.
    uint internal _last;

    /// @dev Marks the maximum amount of contributors per milestone.
    /// @dev Setting a reasonable limit prevents running into 'out of gas' issues with the generated payment order array
    uint internal constant MAXIMUM_CONTRIBUTORS = 50;

    //--------------------------------------------------------------------------
    // Storage

    /// @dev Value for what the next id will be.
    uint internal _nextId;

    /// @dev Registry mapping milestone ids to Milestone structs.
    mapping(uint => Milestone) internal _milestoneRegistry;

    /// @dev List of milestone id's.
    mapping(uint => uint) internal _milestones;

    /// @dev Counter for number of milestone id's in the _milestones list.
    uint internal _milestoneCounter;

    /// @dev The current active milestone's id.
    /// @dev Uses _SENTINEL to indicate no current active milestone.
    uint internal _activeMilestone;

    /// @dev The current minimum time gap between the updating and staring of a milestone
    /// @dev The default value will be 3 days. Can be updated by authorized addresses.
    uint internal _milestoneUpdateTimelock;

    /// @dev Marks the precision we will use for the salary percentages. Represents what counts as "100%".
    /// @dev Value is 100_000_000 since it allows for 1$ precision in a 1.000.000$ budget.
    uint internal SALARY_PRECISION;

    /// @dev Defines what part of the Budget gets taken as fee at the start of a Milestone.
    /// @dev defined as a value relative to the SALARY_PRECISION
    uint internal FEE_PCT;

    /// @dev Treasury address to send the fees to.
    address internal FEE_TREASURY;

    //--------------------------------------------------------------------------
    // Public View Functions

    /// @inheritdoc IMilestoneManager
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

    /// @inheritdoc IMilestoneManager
    function listMilestoneIds() public view returns (uint[] memory) {
        uint[] memory result = new uint256[](_milestoneCounter);

        // Populate result array.
        uint index;
        uint elem = _milestones[_SENTINEL];
        while (elem != _SENTINEL) {
            result[index] = elem;
            elem = _milestones[elem];
            index++;
        }

        return result;
    }

    /// @inheritdoc IMilestoneManager
    function getActiveMilestoneId() external view returns (uint milestoneId) {
        if (!hasActiveMilestone()) {
            revert Module__MilestoneManager__NoActiveMilestone();
        }

        return _activeMilestone;
    }

    /// @inheritdoc IMilestoneManager
    function hasActiveMilestone() public view returns (bool) {
        if (!isExistingMilestoneId(_activeMilestone)) {
            return false;
        }

        Milestone memory m = _milestoneRegistry[_activeMilestone];

        // Milestone active if not completed and already started but duration
        // not yet over.
        uint startTimestamp = m.startTimestamp;
        return !m.completed && startTimestamp != 0
            && startTimestamp + m.duration >= block.timestamp;
    }

    /// @inheritdoc IMilestoneManager
    function isNextMilestoneActivatable() public view returns (bool) {
        // Return false if next milestone does not exist.
        uint next = _milestones[_activeMilestone];
        if (!isExistingMilestoneId(next)) {
            return false;
        }

        if (
            block.timestamp - _milestoneRegistry[next].lastUpdatedTimestamp
                < _milestoneUpdateTimelock
        ) {
            return false;
        }

        // Return false if Milestone has already been started
        if (_milestoneRegistry[next].startTimestamp != 0) {
            return false;
        }

        // Return true if current active milestone does not exist.
        if (!isExistingMilestoneId(_activeMilestone)) {
            return true;
        }

        Milestone memory m = _milestoneRegistry[_activeMilestone];

        // Milestone is activatable if current milestone started and its
        // duration exceeded.
        return m.startTimestamp + m.duration < block.timestamp;
    }

    /// @inheritdoc IMilestoneManager
    function isExistingMilestoneId(uint id) public view returns (bool) {
        return id != _SENTINEL && _milestones[id] != 0;
    }

    /// @inheritdoc IMilestoneManager
    function getPreviousMilestoneId(uint id)
        external
        view
        returns (uint prevId)
    {
        if (!isExistingMilestoneId(id)) {
            revert Module__MilestoneManager__InvalidMilestoneId();
        }
        uint[] memory milestoneIds = listMilestoneIds();

        uint len = milestoneIds.length;
        for (uint i; i < len; ++i) {
            if (milestoneIds[i] == id) {
                return i != 0 ? milestoneIds[i - 1] : _SENTINEL;
            }
        }
    }

    /// @inheritdoc IMilestoneManager
    function isContributor(uint milestoneId, address who)
        public
        view
        returns (bool)
    {
        Contributor[] memory contribs =
            getMilestoneInformation(milestoneId).contributors;

        uint len = contribs.length;
        for (uint i; i < len; ++i) {
            if (contribs[i].addr == who) {
                return true;
            }
        }
        return false;
    }

    /// @inheritdoc IMilestoneManager
    function getSalaryPrecision() public view returns (uint) {
        return SALARY_PRECISION;
    }

    function getFeePct() public view returns (uint) {
        return FEE_PCT;
    }

    /// @inheritdoc IMilestoneManager
    function getMaximumContributors() public pure returns (uint) {
        return MAXIMUM_CONTRIBUTORS;
    }

    function getMilestoneUpdateTimelock() public view returns (uint) {
        return _milestoneUpdateTimelock;
    }
}

}