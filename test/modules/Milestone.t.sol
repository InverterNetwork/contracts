// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import {MilestoneModule} from "src/modules/Milestone.sol";
import {IModule} from "src/interfaces/IModule.sol";

import {ProposalMock} from "test/utils/mocks/proposal/ProposalMock.sol";
import {AuthorizerMock} from "test/utils/mocks/AuthorizerMock.sol";

contract MilestoneTest is Test, ProposalMock {
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
        view
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

    function testContributorAccess(address accessor) public {
        uint256 id = milestoneMod.nextNewMilestoneId();
        milestoneMod.__Milestone_addMilestone(id, " ", 0, " ");

        vm.expectRevert(MilestoneModule.OnlyCallableByContributor.selector);
        vm.prank(accessor);
        milestoneMod.submitMilestone(id);

        authorizerMock.setIsAuthorized(address(this), true);

        milestoneMod.grantMilestoneContributorRole(accessor);

        vm.prank(accessor);
        milestoneMod.submitMilestone(id);
    }

    function testValidTitle(string memory title) public {
        if ((bytes(title)).length == 0) {
            vm.expectRevert(MilestoneModule.InvalidTitle.selector);
        }
        milestoneMod.__Milestone_addMilestone(0, title, 0, " ");
    }

    function testValidStartDate(uint256 startDate) public {
        /* if(startDate == 0){
            vm.expectRevert(MilestoneModule.InvalidStartDate.selector);
        }
        milestoneMod.__Milestone_addMilestone(" ", startDate, " "); */
    }

    function testValidDetails(string memory details) public {
        if ((bytes(details)).length == 0) {
            vm.expectRevert(MilestoneModule.InvalidDetails.selector);
        }
        milestoneMod.__Milestone_addMilestone(0, " ", 0, details);
    }

    function testValidId(uint256 id) public {
        milestoneMod.__Milestone_addMilestone(0, " ", 0, " ");
        if (id >= milestoneMod.nextNewMilestoneId()) {
            vm.expectRevert(MilestoneModule.InvalidMilestoneId.selector);
        }
        milestoneMod.__Milestone_removeMilestone(id);
    }

    function testNewMilestoneIdAvailable(uint256 id) public {
        uint256 nextId;
        for (uint256 i = 0; i < 10; i++) {
            nextId = milestoneMod.nextNewMilestoneId();
            milestoneMod.__Milestone_addMilestone(nextId, " ", 0, " ");
        }
        if (id > milestoneMod.nextNewMilestoneId()) {
            vm.expectRevert(
                MilestoneModule.NewMilestoneIdNotYetAvailable.selector
            );
        }
        milestoneMod.__Milestone_addMilestone(id, " ", 0, " ");
    }

    function testSubmitted(uint256 id) public {
        vm.assume(id <= 1);

        //Not Submitted
        uint256 idOfNotSubmitted = milestoneMod.nextNewMilestoneId();
        milestoneMod.__Milestone_addMilestone(idOfNotSubmitted, " ", 0, " ");

        //Submitted
        uint256 idOfSubmitted = milestoneMod.nextNewMilestoneId();
        milestoneMod.__Milestone_addMilestone(idOfSubmitted, " ", 0, " ");
        milestoneMod.__Milestone_submitMilestone(idOfSubmitted);

        if (id == idOfNotSubmitted) {
            vm.expectRevert(MilestoneModule.MilestoneNotSubmitted.selector);
        }

        milestoneMod.__Milestone_confirmMilestone(id);
    }

    function testNotCompleted(uint256 id) public {
        vm.assume(id <= 1);

        //Submitted
        uint256 idOfSubmitted = milestoneMod.nextNewMilestoneId();
        milestoneMod.__Milestone_addMilestone(idOfSubmitted, " ", 0, " ");
        milestoneMod.__Milestone_submitMilestone(idOfSubmitted);

        //Completed
        uint256 idOfCompleted = milestoneMod.nextNewMilestoneId();
        milestoneMod.__Milestone_addMilestone(idOfCompleted, " ", 0, " ");
        milestoneMod.__Milestone_submitMilestone(idOfCompleted);
        milestoneMod.__Milestone_confirmMilestone(idOfCompleted);

        if (id == idOfCompleted) {
            vm.expectRevert(MilestoneModule.MilestoneAlreadyCompleted.selector);
        }

        milestoneMod.__Milestone_declineMilestone(id);
    }

    function testNotRemoved(uint256 id) public {
        vm.assume(id <= 1);

        //Not Removed
        uint256 idOfNotRemoved = milestoneMod.nextNewMilestoneId();
        milestoneMod.__Milestone_addMilestone(idOfNotRemoved, " ", 0, " ");

        //Submitted
        uint256 idOfRemoved = milestoneMod.nextNewMilestoneId();
        milestoneMod.__Milestone_addMilestone(idOfRemoved, " ", 0, " ");
        milestoneMod.__Milestone_removeMilestone(idOfRemoved);

        if (id == idOfRemoved) {
            vm.expectRevert(MilestoneModule.MilestoneRemoved.selector);
        }
        milestoneMod.__Milestone_changeStartDate(id, 0);
    }

    function testModifierInPosition() public {
        //--------------------------------------------------------------------------------
        //Setup

        //Give necessary rights
        authorizerMock.setIsAuthorized(address(this), true);
        milestoneMod.grantMilestoneContributorRole(address(this));

        uint256 id = milestoneMod.nextNewMilestoneId();
        milestoneMod.__Milestone_addMilestone(id, " ", 0, " ");

        uint256 removedId = milestoneMod.nextNewMilestoneId();
        milestoneMod.__Milestone_addMilestone(removedId, " ", 0, " ");
        milestoneMod.__Milestone_removeMilestone(removedId);

        uint256 completedId = milestoneMod.nextNewMilestoneId();
        milestoneMod.__Milestone_addMilestone(completedId, " ", 0, " ");
        milestoneMod.__Milestone_submitMilestone(completedId);
        milestoneMod.__Milestone_confirmMilestone(completedId);

        uint256 invalidId = milestoneMod.nextNewMilestoneId()+1;

        //Take nessesary rights
        milestoneMod.revokeMilestoneContributorRole(address(this));
        authorizerMock.setIsAuthorized(address(this), false);

        //--------------------------------------------------------------------------------
        //initialize

        //initializer
        //This checks if Module init is called and therfor guarantees that onlyInitializing Modifier is working,
        //Which confirms if the initializer modifier is used
        assertTrue(address(milestoneMod.proposal()) != address(0));

        //--------------------------------------------------------------------------------
        //__Milestone_addMilestone

        //OnlyProposal
        vm.expectRevert(IModule.Module__OnlyCallableByProposal.selector);
        vm.prank(address(0));
        milestoneMod.__Milestone_addMilestone(0, " ", 0, " ");

        //newMilestoneIdAvailable
        vm.expectRevert(MilestoneModule.NewMilestoneIdNotYetAvailable.selector);
        milestoneMod.__Milestone_addMilestone(invalidId, " ", 0, " ");

        //validTitle
        vm.expectRevert(MilestoneModule.InvalidTitle.selector);
        milestoneMod.__Milestone_addMilestone(0, "", 0, " ");

        /*//validStartDate
        vm.expectRevert(MilestoneModule.InvalidStartDate.selector);//@note as long as ValidStartDate has no checks no Implmentation needed
        milestoneMod.__Milestone_addMilestone(
            "",
            0,
            " "
        ); */

        //validDetails
        vm.expectRevert(MilestoneModule.InvalidDetails.selector);
        milestoneMod.__Milestone_addMilestone(0, " ", 0, "");

        //--------------------------------------------------------------------------------
        //addMilestone

        //onlyAuthorized
        vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
        vm.prank(address(0));
        milestoneMod.addMilestone(0, " ", 0, " ");

        //--------------------------------------------------------------------------------
        //__Milestone_changeDetails

        //OnlyProposal
        vm.expectRevert(IModule.Module__OnlyCallableByProposal.selector);
        vm.prank(address(0));
        milestoneMod.__Milestone_changeDetails(id, " ");

        //validId
        vm.expectRevert(MilestoneModule.InvalidMilestoneId.selector);
        milestoneMod.__Milestone_changeDetails(invalidId, " ");

        //notRemoved
        vm.expectRevert(MilestoneModule.MilestoneRemoved.selector);
        milestoneMod.__Milestone_changeDetails(removedId, " ");

        //validDetails
        vm.expectRevert(MilestoneModule.InvalidDetails.selector);
        milestoneMod.__Milestone_changeDetails(id, "");

        //--------------------------------------------------------------------------------
        //changeDetails

        //onlyAuthorized
        vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
        vm.prank(address(0));
        milestoneMod.changeDetails(id, " ");

        //--------------------------------------------------------------------------------
        //__Milestone_changeStartDate

        //OnlyProposal
        vm.expectRevert(IModule.Module__OnlyCallableByProposal.selector);
        vm.prank(address(0));
        milestoneMod.__Milestone_changeStartDate(id, 0);

        //validId
        vm.expectRevert(MilestoneModule.InvalidMilestoneId.selector);
        milestoneMod.__Milestone_changeStartDate(invalidId, 0);

        //notRemoved
        vm.expectRevert(MilestoneModule.MilestoneRemoved.selector);
        milestoneMod.__Milestone_changeStartDate(removedId, 0);

        /*//validStartDate
        vm.expectRevert(MilestoneModule.InvalidStartDate.selector);//@note as long as ValidStartDate has no checks no Implmentation needed
        milestoneMod.__Milestone_changeStartDate(
            "",
            0,
            " "
        ); */

        //--------------------------------------------------------------------------------
        //changeStartDate

        //onlyAuthorized
        vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
        vm.prank(address(0));
        milestoneMod.changeStartDate(id, 0);

        //--------------------------------------------------------------------------------
        //__Milestone_removeMilestone

        //OnlyProposal
        vm.expectRevert(IModule.Module__OnlyCallableByProposal.selector);
        vm.prank(address(0));
        milestoneMod.__Milestone_removeMilestone(id);

        //validId
        vm.expectRevert(MilestoneModule.InvalidMilestoneId.selector);
        milestoneMod.__Milestone_removeMilestone(invalidId);

        //notCompleted
        vm.expectRevert(MilestoneModule.MilestoneAlreadyCompleted.selector);
        milestoneMod.__Milestone_removeMilestone(completedId);

        //--------------------------------------------------------------------------------
        //removeMilestone

        //onlyAuthorized
        vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
        vm.prank(address(0));
        milestoneMod.removeMilestone(id);

        //--------------------------------------------------------------------------------
        //__Milestone_submitMilestone

        //OnlyProposal
        vm.expectRevert(IModule.Module__OnlyCallableByProposal.selector);
        vm.prank(address(0));
        milestoneMod.__Milestone_submitMilestone(id);

        //validId
        vm.expectRevert(MilestoneModule.InvalidMilestoneId.selector);
        milestoneMod.__Milestone_submitMilestone(invalidId);

        //notRemoved
        vm.expectRevert(MilestoneModule.MilestoneRemoved.selector);
        milestoneMod.__Milestone_submitMilestone(removedId);

        //--------------------------------------------------------------------------------
        //submitMilestone

        //contributorAccess
        vm.expectRevert(MilestoneModule.OnlyCallableByContributor.selector);
        vm.prank(address(0));
        milestoneMod.submitMilestone(id);

        //--------------------------------------------------------------------------------
        //__Milestone_confirmMilestone

        //OnlyProposal
        vm.expectRevert(IModule.Module__OnlyCallableByProposal.selector);
        vm.prank(address(0));
        milestoneMod.__Milestone_confirmMilestone(id);

        //validId
        vm.expectRevert(MilestoneModule.InvalidMilestoneId.selector);
        milestoneMod.__Milestone_confirmMilestone(invalidId);

        //notRemoved
        vm.expectRevert(MilestoneModule.MilestoneRemoved.selector);
        milestoneMod.__Milestone_confirmMilestone(removedId);

        //submitted
        vm.expectRevert(MilestoneModule.MilestoneNotSubmitted.selector);
        milestoneMod.__Milestone_confirmMilestone(id);

        //--------------------------------------------------------------------------------
        //confirmMilestone

        //onlyAuthorized
        vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
        vm.prank(address(0));
        milestoneMod.confirmMilestone(id);

        //--------------------------------------------------------------------------------
        //__Milestone_declineMilestone

        //OnlyProposal
        vm.expectRevert(IModule.Module__OnlyCallableByProposal.selector);
        vm.prank(address(0));
        milestoneMod.__Milestone_declineMilestone(id);

        //validId
        vm.expectRevert(MilestoneModule.InvalidMilestoneId.selector);
        milestoneMod.__Milestone_declineMilestone(invalidId);

        //notRemoved
        vm.expectRevert(MilestoneModule.MilestoneRemoved.selector);
        milestoneMod.__Milestone_declineMilestone(removedId);

        //submitted
        vm.expectRevert(MilestoneModule.MilestoneNotSubmitted.selector);
        milestoneMod.__Milestone_declineMilestone(id);

        //notCompleted
        vm.expectRevert(MilestoneModule.MilestoneAlreadyCompleted.selector);
        milestoneMod.__Milestone_declineMilestone(completedId);

        //--------------------------------------------------------------------------------
        //declineMilestone

        //onlyAuthorized
        vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
        vm.prank(address(0));
        milestoneMod.declineMilestone(id);
    }

    //--------------------------------------------------------------------------------
    // TEST REACH-AROUND

    function testReachAround(
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
                (0, title, startDate, details)
            )
        );
        id = milestoneMod.nextNewMilestoneId();
        milestoneMod.addMilestone(id, title, startDate, details);
        assertTrue(id == 0);

        //ChangeDetails
        vm.expectCall(
            address(milestoneMod),
            abi.encodeCall(
                milestoneMod.__Milestone_changeDetails,
                (id, details)
            )
        );
        milestoneMod.changeDetails(id, details);

        //ChangeStartDate
        vm.expectCall(
            address(milestoneMod),
            abi.encodeCall(
                milestoneMod.__Milestone_changeStartDate,
                (id, startDate)
            )
        );
        milestoneMod.changeStartDate(id, startDate);

        //Remove
        id = milestoneMod.nextNewMilestoneId();
        milestoneMod.addMilestone(id, title, startDate, details);
        vm.expectCall(
            address(milestoneMod),
            abi.encodeCall(milestoneMod.__Milestone_removeMilestone, (id))
        );
        milestoneMod.removeMilestone(id);

        //Submit
        id = milestoneMod.nextNewMilestoneId();
        milestoneMod.addMilestone(id, title, startDate, details);

        milestoneMod.grantMilestoneContributorRole(address(this));

        vm.expectCall(
            address(milestoneMod),
            abi.encodeCall(milestoneMod.__Milestone_submitMilestone, (id))
        );
        milestoneMod.submitMilestone(id);

        //Confirm
        id = milestoneMod.nextNewMilestoneId();
        milestoneMod.addMilestone(id, title, startDate, details);
        milestoneMod.submitMilestone(id);

        vm.expectCall(
            address(milestoneMod),
            abi.encodeCall(milestoneMod.__Milestone_confirmMilestone, (id))
        );
        milestoneMod.confirmMilestone(id);

        //Decline
        id = milestoneMod.nextNewMilestoneId();
        milestoneMod.addMilestone(id, title, startDate, details);
        milestoneMod.submitMilestone(id);
        vm.expectCall(
            address(milestoneMod),
            abi.encodeCall(milestoneMod.__Milestone_declineMilestone, (id))
        );
        milestoneMod.declineMilestone(id);
    }

    //--------------------------------------------------------------------------------
    // TEST MAIN

    function testGrantMilestoneContributorRole(address account) public {
        authorizerMock.setAllAuthorized(true);

        milestoneMod.grantMilestoneContributorRole(account);

        assertTrue(
            hasRole(
                address(milestoneMod),
                milestoneMod.MILESTONE_CONTRIBUTOR_ROLE(),
                account
            )
        );
    }

    function testRevokeMilestoneContributorRole(address account) public {
        authorizerMock.setAllAuthorized(true);

        milestoneMod.revokeMilestoneContributorRole(account);

        assertTrue(
            !hasRole(
                address(milestoneMod),
                milestoneMod.MILESTONE_CONTRIBUTOR_ROLE(),
                account
            )
        );

        milestoneMod.grantMilestoneContributorRole(account);
        milestoneMod.revokeMilestoneContributorRole(account);

        assertTrue(
            !hasRole(
                address(milestoneMod),
                milestoneMod.MILESTONE_CONTRIBUTOR_ROLE(),
                account
            )
        );
    }

    //++++++++++++++++++++++++++++++++++++++++++ TEST-MAIN ++++++++++++++++++++++++++++++++++++++++++

    function testAdd(
        string memory title,
        uint256 startDate,
        string memory details
    ) public {
        vm.assume(bytes(title).length != 0);
        vm.assume(bytes(details).length != 0);

        uint256 id = milestoneMod.nextNewMilestoneId();
        milestoneMod.__Milestone_addMilestone(id, title, startDate, details);

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

        //Check for idempotence
        milestoneMod.__Milestone_addMilestone(id, title, startDate, details);
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

        if (
            keccak256(bytes(title)) != keccak256(bytes(" ")) ||
            startDate != 0 ||
            keccak256(bytes(details)) != keccak256(bytes(" "))
        ) {
            vm.expectRevert(
                MilestoneModule.MilestoneWithIdAlreadyCreated.selector
            );
        }
        milestoneMod.__Milestone_addMilestone(id, " ", 0, " ");
    }

    function testAddMultiple() public {
        uint256 realId;
        for (uint256 supposedId = 0; supposedId < 300; supposedId++) {
            realId = milestoneMod.nextNewMilestoneId();
            milestoneMod.__Milestone_addMilestone(realId, " ", 0, " ");
            assertTrue(realId == supposedId);
        }
    }

    function testChangeDetails(string memory newDetails) public {//@note how to test idempotence?
        vm.assume(bytes(newDetails).length != 0);
        uint256 id = milestoneMod.nextNewMilestoneId();
        milestoneMod.__Milestone_addMilestone(id, " ", 0, " ");

        milestoneMod.__Milestone_changeDetails(id, newDetails);

        Milestone memory milestone = getMilestoneFromModule(id);

        assertTrue(keccak256(bytes(milestone.title)) == keccak256(bytes(" ")));
        assertTrue(milestone.startDate == 0);
        assertTrue(
            keccak256(bytes(milestone.details)) == keccak256(bytes(newDetails))
        );
        assertTrue(milestone.submitted == false);
        assertTrue(milestone.completed == false);
        assertTrue(milestone.removed == false);
    }

    function testChangeStartDate(uint256 newStartDate) public {
        uint256 id = milestoneMod.nextNewMilestoneId();
        milestoneMod.__Milestone_addMilestone(id, " ", 0, " ");

        milestoneMod.__Milestone_changeStartDate(id, newStartDate);

        Milestone memory milestone = getMilestoneFromModule(id);

        assertTrue(keccak256(bytes(milestone.title)) == keccak256(bytes(" ")));
        assertTrue(milestone.startDate == newStartDate);
        assertTrue(
            keccak256(bytes(milestone.details)) == keccak256(bytes(" "))
        );
        assertTrue(milestone.submitted == false);
        assertTrue(milestone.completed == false);
        assertTrue(milestone.removed == false);
    }

    function testRemove() public {//@note how to test idempotence?
        uint256 id = milestoneMod.nextNewMilestoneId();
        milestoneMod.__Milestone_addMilestone(id, " ", 0, " ");
        milestoneMod.__Milestone_removeMilestone(id);

        Milestone memory milestone = getMilestoneFromModule(id);
        assertTrue(milestone.removed == true);
    }

    function testSubmit() public {//@note how to test idempotence?
        uint256 id = milestoneMod.nextNewMilestoneId();
        milestoneMod.__Milestone_addMilestone(id, " ", 0, " ");

        milestoneMod.__Milestone_submitMilestone(id);

        Milestone memory milestone = getMilestoneFromModule(id);
        assertTrue(milestone.submitted == true);
        assertTrue(milestone.removed == false);
    }

    function testConfirm() public {//@note how to test idempotence?
        uint256 id = milestoneMod.nextNewMilestoneId();
        milestoneMod.__Milestone_addMilestone(id, " ", 0, " ");

        milestoneMod.__Milestone_submitMilestone(id);
        milestoneMod.__Milestone_confirmMilestone(id);

        Milestone memory milestone = getMilestoneFromModule(id);
        assertTrue(milestone.completed == true);
        assertTrue(milestone.removed == false);
    }

    function testDecline() public {//@note how to test idempotence?
        uint256 id = milestoneMod.nextNewMilestoneId();
        milestoneMod.__Milestone_addMilestone(id, " ", 0, " ");

        milestoneMod.__Milestone_submitMilestone(id);
        milestoneMod.__Milestone_declineMilestone(id);

        Milestone memory milestone = getMilestoneFromModule(id);
        assertTrue(milestone.submitted == false);
        assertTrue(milestone.removed == false);
    }
}
