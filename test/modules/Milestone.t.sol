// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import {MilestoneModule} from "../../src/modules/Milestone.sol";

contract MilestoneTest is Test {//@todo Felix: Properly adapt to the correct Module Implementation
    struct Milestone {
        uint256 identifier; //Could go with a name/hash
        uint256 startDate;
        uint256 duration;
        string details; //Could go instead with an ipfs hash or a link
        bool submitted;
        bool completed;
    }

    MilestoneModule milestoneMod;

    function setUp() public {
        milestoneMod = new MilestoneModule();
        milestoneMod.initialize();
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
        uint256 id = milestoneMod.addMilestone(
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
        uint256 id = milestoneMod.addMilestone(0, 0, 0, "");

        milestoneMod.changeMilestone(id, newStartDate, newDuration, newDetails);

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
        uint256 id = milestoneMod.addMilestone(0, 0, 0, "");
        milestoneMod.removeMilestone(id);
        try milestoneMod.milestones(id) {
            revert();
        } catch {}
    }

    function testSubmit() public {
        uint256 id = milestoneMod.addMilestone(0, 0, 0, "");

        milestoneMod.submitMilestone(id);

        Milestone memory milestone = getMilestoneFromModule(id);
        assertTrue(milestone.submitted == true);
    }

    function testConfirm() public {
        uint256 id = milestoneMod.addMilestone(0, 0, 0, "");

        milestoneMod.submitMilestone(id);
        milestoneMod.confirmMilestone(id);

        Milestone memory milestone = getMilestoneFromModule(id);
        assertTrue(milestone.completed == true);
    }

    function testDecline() public {
        uint256 id = milestoneMod.addMilestone(0, 0, 0, "");

        milestoneMod.submitMilestone(id);
        milestoneMod.declineMilestone(id);

        Milestone memory milestone = getMilestoneFromModule(id);
        assertTrue(milestone.submitted == false);
    }

}
