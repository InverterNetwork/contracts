// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import {MilestoneModule} from "src/modules/Milestone.sol";

import {ProposalMock} from "test/utils/mocks/ProposalMock.sol";


contract MilestoneTest is Test,ProposalMock {//@todo Felix: Properly adapt to the correct Module Implementation
    struct Milestone {
        uint256 identifier;
        uint256 startDate;
        uint256 duration;
        string details; 
        bool submitted;
        bool completed;
    }

    MilestoneModule milestoneMod;

    function setUp() public {
        milestoneMod = new MilestoneModule();
        milestoneMod.initialize(this);
    }

    function getMilestoneFromModule(uint256 id)
        internal
        returns (Milestone memory)
    {
        (
            uint256 identifier,
            uint256 startDate,
            uint256 duration,
            string memory details,
            bool submitted,
            bool completed
        ) = milestoneMod.milestones(id);

        return
            Milestone(
                identifier,
                startDate,
                duration,
                details,
                submitted,
                completed
            );
    }

    function testAdd(
        uint256 identifier,
        uint256 startDate,
        uint256 duration,
        string memory details
    ) public {
        uint256 id = milestoneMod.__Milestone_addMilestone(
            identifier,
            startDate,
            duration,
            details
        );

        Milestone memory milestone = getMilestoneFromModule(id);

        assertTrue(milestone.identifier == identifier);
        assertTrue(milestone.startDate == startDate);
        assertTrue(milestone.duration == duration);
        assertTrue(
            keccak256(bytes(milestone.details)) == keccak256(bytes(details))
        );
        assertTrue(milestone.submitted == false);
        assertTrue(milestone.completed == false);
    }

    function testAdd(
        uint256 newStartDate,
        uint256 newDuration,
        string memory newDetails
    ) public {
        uint256 id = milestoneMod.__Milestone_addMilestone(0, 0, 0, "");

        milestoneMod.__Milestone_changeMilestone(id, newStartDate, newDuration, newDetails);

        Milestone memory milestone = getMilestoneFromModule(id);

        assertTrue(milestone.identifier == 0);
        assertTrue(milestone.startDate == newStartDate);
        assertTrue(milestone.duration == newDuration);
        assertTrue(
            keccak256(bytes(milestone.details)) == keccak256(bytes(newDetails))
        );
        assertTrue(milestone.submitted == false);
        assertTrue(milestone.completed == false);
    }

    function testRemove() public {
        uint256 id = milestoneMod.__Milestone_addMilestone(0, 0, 0, "");
        milestoneMod.__Milestone_removeMilestone(id);
        try milestoneMod.milestones(id) {
            revert();
        } catch {}
    }

    function testSubmit() public {
        uint256 id = milestoneMod.__Milestone_addMilestone(0, 0, 0, "");

        milestoneMod.__Milestone_submitMilestone(id);

        Milestone memory milestone = getMilestoneFromModule(id);
        assertTrue(milestone.submitted == true);
    }

    function testConfirm() public {
        uint256 id = milestoneMod.__Milestone_addMilestone(0, 0, 0, "");

        milestoneMod.__Milestone_submitMilestone(id);
        milestoneMod.__Milestone_confirmMilestone(id);

        Milestone memory milestone = getMilestoneFromModule(id);
        assertTrue(milestone.completed == true);
    }

    function testDecline() public {
        uint256 id = milestoneMod.__Milestone_addMilestone(0, 0, 0, "");

        milestoneMod.__Milestone_submitMilestone(id);
        milestoneMod.__Milestone_declineMilestone(id);

        Milestone memory milestone = getMilestoneFromModule(id);
        assertTrue(milestone.submitted == false);
    }

}
