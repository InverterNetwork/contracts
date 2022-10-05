// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import {MilestoneModule} from "src/modules/Milestone.sol";

import {ProposalMock} from "test/utils/mocks//proposal/ProposalMock.sol";
import {AuthorizerMock} from "test/utils/mocks/AuthorizerMock.sol";

contract MilestoneTest is
    Test,
    ProposalMock
{
    struct Milestone {
        string title;
        uint256 startDate;
        string details;
        bool submitted;
        bool completed;
        bool removed;
    }

    MilestoneModule milestoneMod;
    AuthorizerMock authorizerMock = new AuthorizerMock();

    //--------------------------------------------------------------------------------
    // SETUP

    constructor() ProposalMock(authorizerMock) {}

    function setUp() public {
        milestoneMod = new MilestoneModule();
        milestoneMod.initialize(this);

        address[] memory modules = new address[](1);
        modules[0] = address(milestoneMod);

        ProposalMock(this).initModules(modules);
    }

    //--------------------------------------------------------------------------------
    // HELPER FUNCTIONS

    function getMilestoneFromModule(uint256 id)
        internal
        returns (Milestone memory)
    {
        (
            string memory title,
            uint256 startDate,
            string memory details,
            bool submitted,
            bool completed,
            bool removed
        ) = milestoneMod.milestones(id);

        return
            Milestone(title, startDate, details, submitted, completed, removed);
    }

    //--------------------------------------------------------------------------------
    // TEST MODIFIER

    //--------------------------------------------------------------------------------
    // TEST REACH-AROUND

    function testReachAroundAdd(
        string memory title,
        uint256 startDate,
        string memory details
    ) public {
        vm.assume(bytes(title).length != 0);
        vm.assume(bytes(details).length != 0);
        authorizerMock.setAllAuthorized(true);

        //Used to check current id
        uint256 id;

        //Add
        vm.expectCall(
            address(milestoneMod),
            abi.encodeCall(
                milestoneMod.__Milestone_addMilestone,
                (title, startDate, details)
            )
        );
        id = milestoneMod.addMilestone(title, startDate, details);
        assertTrue(id==0);
        
        //Change
        vm.expectCall(
            address(milestoneMod),
            abi.encodeCall(
                milestoneMod.__Milestone_changeMilestone,
                (id, startDate, details)
            )
        );
        milestoneMod.changeMilestone(id, startDate, details);

        //Remove
        id = milestoneMod.addMilestone(title, startDate, details);
        vm.expectCall(
            address(milestoneMod),
            abi.encodeCall(milestoneMod.__Milestone_removeMilestone, (id))
        );
        milestoneMod.removeMilestone(id);

        //Submit
        id = milestoneMod.addMilestone(title, startDate, details);
        vm.expectCall(
            address(milestoneMod),
            abi.encodeCall(milestoneMod.__Milestone_submitMilestone, (id))
        );
        milestoneMod.submitMilestone(id);

        //Confirm
        id = milestoneMod.addMilestone(title, startDate, details);
        milestoneMod.submitMilestone(id);

        vm.expectCall(
            address(milestoneMod),
            abi.encodeCall(milestoneMod.__Milestone_confirmMilestone, (id))
        );
        milestoneMod.confirmMilestone(id);

        //Decline
        id = milestoneMod.addMilestone(title, startDate, details);
        milestoneMod.submitMilestone(id);
        vm.expectCall(
            address(milestoneMod),
            abi.encodeCall(milestoneMod.__Milestone_declineMilestone, (id))
        );
        milestoneMod.declineMilestone(id);
    }

    //@todo Add Seperator
    //@todo test if modifiers are in place //https://github.com/byterocket/kolektivo-contracts/blob/main/test/reserve/OnlyOwner.t.sol#L8

    //--------------------------------------------------------------------------------
    // TEST MAIN
    function testAdd(
        string memory title,
        uint256 startDate,
        string memory details
    ) public {
        vm.assume(bytes(title).length != 0);
        vm.assume(bytes(details).length != 0);

        uint256 id = milestoneMod.__Milestone_addMilestone(
            title,
            startDate,
            details
        );

        Milestone memory milestone = getMilestoneFromModule(id);

        assertTrue(
            keccak256(bytes(milestone.title)) == keccak256(bytes(title))
        );
        assertTrue(milestone.startDate == startDate);
        assertTrue(
            keccak256(bytes(milestone.details)) == keccak256(bytes(details))
        );
        assertTrue(milestone.submitted == false);
        assertTrue(milestone.completed == false);
        assertTrue(milestone.removed == false);
    }

    function testAddMultiple() public {
        uint256 realId;
        for (uint256 supposedId = 0; supposedId < 3; supposedId++) {
            //@note is 3 enough? Should this even be tested?
            realId = milestoneMod.__Milestone_addMilestone(" ", 0, " ");
            assertTrue(realId == supposedId);
        }
    }

    function testChange(uint256 newStartDate, string memory newDetails) public {
        vm.assume(bytes(newDetails).length != 0);
        uint256 id = milestoneMod.__Milestone_addMilestone(" ", 0, " ");

        milestoneMod.__Milestone_changeMilestone(id, newStartDate, newDetails);

        Milestone memory milestone = getMilestoneFromModule(id);

        assertTrue(keccak256(bytes(milestone.title)) == keccak256(bytes(" ")));
        assertTrue(milestone.startDate == newStartDate);
        assertTrue(
            keccak256(bytes(milestone.details)) == keccak256(bytes(newDetails))
        );
        assertTrue(milestone.submitted == false);
        assertTrue(milestone.completed == false);
        assertTrue(milestone.removed == false);
    }

    function testRemove() public {
        uint256 id = milestoneMod.__Milestone_addMilestone(" ", 0, " ");
        milestoneMod.__Milestone_removeMilestone(id);

        Milestone memory milestone = getMilestoneFromModule(id);
        assertTrue(milestone.removed == true);
    }

    function testSubmit() public {
        uint256 id = milestoneMod.__Milestone_addMilestone(" ", 0, " ");

        milestoneMod.__Milestone_submitMilestone(id);

        Milestone memory milestone = getMilestoneFromModule(id);
        assertTrue(milestone.submitted == true);
        assertTrue(milestone.removed == false);
    }

    function testConfirm() public {
        uint256 id = milestoneMod.__Milestone_addMilestone(" ", 0, " ");

        milestoneMod.__Milestone_submitMilestone(id);
        milestoneMod.__Milestone_confirmMilestone(id);

        Milestone memory milestone = getMilestoneFromModule(id);
        assertTrue(milestone.completed == true);
        assertTrue(milestone.removed == false);
    }

    function testDecline() public {
        uint256 id = milestoneMod.__Milestone_addMilestone(" ", 0, " ");

        milestoneMod.__Milestone_submitMilestone(id);
        milestoneMod.__Milestone_declineMilestone(id);

        Milestone memory milestone = getMilestoneFromModule(id);
        assertTrue(milestone.submitted == false);
        assertTrue(milestone.removed == false);
    }
}
