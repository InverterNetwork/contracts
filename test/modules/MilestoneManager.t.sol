// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {
    ModuleTest,
    IModule,
    IProposal,
    LibString
} from "test/modules/ModuleTest.sol";

// SuT
import {MilestoneManager} from "src/modules/MilestoneManager.sol";
import {IMilestoneManager} from "src/interfaces/modules/IMilestoneManager.sol";

contract MilestoneManagerTest is ModuleTest {
    using LibString for string;

    // SuT
    MilestoneManager milestoneManager;

    // Constants
    string private constant _TITLE = "Title";
    string private constant _DETAILS = "Details";

    function setUp() public {
        milestoneManager = new MilestoneManager();
        milestoneManager.init(_proposal, _METADATA, bytes(""));

        _setUpProposal(milestoneManager);
    }

    //--------------------------------------------------------------------------
    // Test: Access Control Functions

    function testGrantContributorRole(address to) public {
        _authorizer.setIsAuthorized(address(this), true);

        milestoneManager.grantContributorRole(to);
        assertTrue(
            _proposal.hasRole(
                address(milestoneManager),
                milestoneManager.CONTRIBUTOR_ROLE(),
                to
            )
        );
    }

    function testGrantContributorRoleOnlyCallableIfAuthorized(address caller)
        public
    {
        _authorizer.setIsAuthorized(caller, false);

        vm.prank(caller);
        vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
        milestoneManager.grantContributorRole(address(0xBEEF));
    }

    function testRevokeContributorRole(address from) public {
        _authorizer.setIsAuthorized(address(this), true);

        milestoneManager.grantContributorRole(from);

        milestoneManager.revokeContributorRole(from);
        assertTrue(
            !_proposal.hasRole(
                address(milestoneManager),
                milestoneManager.CONTRIBUTOR_ROLE(),
                from
            )
        );
    }

    function testRevokeContributorRoleOnlyCallableIfAuthorized(address caller)
        public
    {
        _authorizer.setIsAuthorized(caller, false);

        vm.prank(caller);
        vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
        milestoneManager.revokeContributorRole(address(0xBEEF));
    }

    //--------------------------------------------------------------------------
    // Test: Milestone API Functions

    // @todo felix, mp: Test API Functions

    function testAddMilestone() public {
        _authorizer.setIsAuthorized(address(this), true);

        uint id =
            milestoneManager.addMilestone(_TITLE, block.timestamp, _DETAILS);
        assertEq(id, 0);
        _assertMilestone(0, _TITLE, block.timestamp, _DETAILS);
    }

    function testAddMilestoneOnlyCallableIfAuthorized(address caller) public {
        _authorizer.setIsAuthorized(caller, false);

        vm.prank(caller);
        vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
        milestoneManager.addMilestone(_TITLE, block.timestamp, _DETAILS);
    }

    function testAddMilestoneCallbackFailed() public {
        _authorizer.setIsAuthorized(address(this), true);

        // Invalid title.
        string memory title = "";

        // @todo mp: Anyone knows how to do this better?
        //           Does not work this way :(
        /*
        vm.expectRevert(
            abi.encodeWithSignature(
                "Module_ProposalCallbackFailed(__Milestone_addMilestone(string,uint256,string))"
            )
        );
        milestoneManager.addMilestone(title, block.timestamp, _DETAILS);
        */
    }

    //--------------------------------------------------------------------------
    // Test: Proposal Callback Functions

    //----------------------------------
    // Test: __Milestone_addMilestone()

    function test__Milestone_addMilestone(
        string memory title,
        uint startDate,
        string memory details
    ) public {
        _assumeNonEmptyString(title);
        _assumeTimestampNotInPast(startDate);
        _assumeNonEmptyString(details);

        vm.startPrank(address(_proposal));

        uint id;

        id =
            milestoneManager.__Milestone_addMilestone(title, startDate, details);

        assertEq(id, 0);
        _assertMilestone(0, title, startDate, details);

        // Add second milestone to verify id increments correctly.
        id =
            milestoneManager.__Milestone_addMilestone(title, startDate, details);

        assertEq(id, 1);
        _assertMilestone(1, title, startDate, details);
    }

    function test__Milestone_addMilestoneOnlyCallableByProposal(address caller)
        public
    {
        vm.assume(caller != address(_proposal));

        vm.prank(caller);
        vm.expectRevert(IModule.Module__OnlyCallableByProposal.selector);
        milestoneManager.__Milestone_addMilestone(
            _TITLE, block.timestamp, _DETAILS
        );
    }

    function test__Milestone_addMilestoneFailsForInvalidTitle(
        uint startDate,
        string memory details
    ) public {
        _assumeTimestampNotInPast(startDate);
        _assumeNonEmptyString(details);

        // Invalid if title is empty.
        string memory title = "";

        vm.startPrank(address(_proposal));

        vm.expectRevert(
            IMilestoneManager.Module__MilestoneManager__InvalidTitle.selector
        );
        milestoneManager.__Milestone_addMilestone(title, startDate, details);
    }

    function test__Milestone_addMilestoneFailsForInvalidStartDate(
        string memory title,
        string memory details
    ) public {
        _assumeNonEmptyString(title);
        _assumeNonEmptyString(details);

        // Invalid if startDate < block.timestamp.
        vm.warp(1);
        uint startDate = 0;

        vm.startPrank(address(_proposal));

        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManager__InvalidStartDate
                .selector
        );
        milestoneManager.__Milestone_addMilestone(title, startDate, details);
    }

    function test__Milestone_addMilestoneFailsForInvalidDetails(
        string memory title,
        uint startDate
    ) public {
        _assumeNonEmptyString(title);
        _assumeTimestampNotInPast(startDate);

        // Invalid if details is empty.
        string memory details = "";

        vm.startPrank(address(_proposal));

        vm.expectRevert(
            IMilestoneManager.Module__MilestoneManager__InvalidDetails.selector
        );
        milestoneManager.__Milestone_addMilestone(title, startDate, details);
    }

    //----------------------------------
    // Test: __Milestone_updateMilestoneDetails()

    //----------------------------------
    // Test: __Milestone_updateMilestoneTitle()

    //----------------------------------
    // Test: __Milestone_removeMilestone()

    //----------------------------------
    // Test: __Milestone_submitMilestone()

    //----------------------------------
    // Test: __Milestone_confirmMilestone()

    //----------------------------------
    // Test: __Milestone_declineMilestone()

    //--------------------------------------------------------------------------
    // Internal Assert Helper Function

    /// @dev Asserts a milestone with given data exists.
    function _assertMilestone(
        uint id,
        string memory title,
        uint startDate,
        string memory details
    ) internal {
        IMilestoneManager.Milestone memory m = milestoneManager.getMilestone(id);

        assertTrue(m.title.equals(title));
        assertEq(m.startDate, startDate);
        assertTrue(m.details.equals(details));
    }
}
