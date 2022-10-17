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

    //----------------------------------
    // Test: addMilestone()

    function testAddMilestone() public {
        _authorizer.setIsAuthorized(address(this), true);

        uint id =
            milestoneManager.addMilestone(_TITLE, block.timestamp, _DETAILS);
        assertEq(id, 0);
        _assertMilestone(
            0, _TITLE, block.timestamp, _DETAILS, false, false, false
        );
    }

    function testAddMilestoneOnlyCallableIfAuthorized(address caller) public {
        _authorizer.setIsAuthorized(caller, false);

        vm.prank(caller);
        vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
        milestoneManager.addMilestone(_TITLE, block.timestamp, _DETAILS);
    }

    function testAddMilestoneCallbackFailed() public {
        _authorizer.setIsAuthorized(address(this), true);

        // Empty title is invalid.
        string memory invalidTitle = "";

        _expectProposalCallbackFailure(
            "__Milestone_addMilestone(string,uint256,string)"
        );
        milestoneManager.addMilestone(invalidTitle, block.timestamp, _DETAILS);
    }

    //----------------------------------
    // Test: updateMilestoneDetails()

    function testUpdateMilestoneDetails() public {
        _authorizer.setIsAuthorized(address(this), true);

        uint id =
            milestoneManager.addMilestone(_TITLE, block.timestamp, _DETAILS);

        string memory newDetails = "new Details";
        milestoneManager.updateMilestoneDetails(id, newDetails);

        _assertMilestone(
            id, _TITLE, block.timestamp, newDetails, false, false, false
        );
    }

    function testUpdateMilestoneDetailsOnlyCallableIfAuthorized(address caller)
        public
    {
        _authorizer.setIsAuthorized(caller, false);

        vm.prank(caller);
        vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
        milestoneManager.updateMilestoneDetails(0, _DETAILS);
    }

    function testUpdateMilestoneDetailsCallbackFailed() public {
        _authorizer.setIsAuthorized(address(this), true);

        uint id =
            milestoneManager.addMilestone(_TITLE, block.timestamp, _DETAILS);

        // Invalid id.
        uint invalidId = id + 1;

        _expectProposalCallbackFailure(
            "__Milestone_updateMilestoneDetails(uint256,string)"
        );
        milestoneManager.updateMilestoneDetails(invalidId, _DETAILS);
    }

    //----------------------------------
    // Test: updateMilestoneStartDate()

    function testUpdateMilestoneStartDate() public {
        _authorizer.setIsAuthorized(address(this), true);

        uint id =
            milestoneManager.addMilestone(_TITLE, block.timestamp, _DETAILS);

        uint newStartDate = block.timestamp + 1;
        milestoneManager.updateMilestoneStartDate(id, newStartDate);

        _assertMilestone(
            id, _TITLE, newStartDate, _DETAILS, false, false, false
        );
    }

    function testUpdateMilestoneStartDateOnlyCallableIfAuthorized(
        address caller
    ) public {
        _authorizer.setIsAuthorized(caller, false);

        vm.prank(caller);
        vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
        milestoneManager.updateMilestoneStartDate(0, block.timestamp);
    }

    function testUpdateMilestoneStartDateCallbackFailed() public {
        _authorizer.setIsAuthorized(address(this), true);

        // Invalid id.
        uint invalidId = 1;

        _expectProposalCallbackFailure(
            "__Milestone_updateMilestoneStartDate(uint256,uint256)"
        );
        milestoneManager.updateMilestoneStartDate(invalidId, block.timestamp);
    }

    //----------------------------------
    // Test: removeMilestone()

    function testRemoveMilestone() public {
        _authorizer.setIsAuthorized(address(this), true);

        uint id =
            milestoneManager.addMilestone(_TITLE, block.timestamp, _DETAILS);

        milestoneManager.removeMilestone(id);
        _assertMilestone({
            id: id,
            title: _TITLE,
            startDate: block.timestamp,
            details: _DETAILS,
            submitted: false,
            completed: false,
            removed: true
        });
    }

    function testRemoveMilestoneOnlyCallableIfAuthorized(address caller)
        public
    {
        _authorizer.setIsAuthorized(caller, false);

        vm.prank(caller);
        vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
        milestoneManager.removeMilestone(0);
    }

    function testRemoveMilestoneCallbackFailed() public {
        _authorizer.setIsAuthorized(address(this), true);

        // Invalid id.
        uint invalidId = 1;

        _expectProposalCallbackFailure("__Milestone_removeMilestone(uint256)");
        milestoneManager.removeMilestone(invalidId);
    }

    //----------------------------------
    // Test: submitMilestone()

    function testSubmitMilestone() public {
        _authorizer.setIsAuthorized(address(this), true);

        uint id =
            milestoneManager.addMilestone(_TITLE, block.timestamp, _DETAILS);

        // Grant contributor role to address(this).
        milestoneManager.grantContributorRole(address(this));

        milestoneManager.submitMilestone(id);
        _assertMilestone({
            id: id,
            title: _TITLE,
            startDate: block.timestamp,
            details: _DETAILS,
            submitted: true,
            completed: false,
            removed: false
        });
    }

    function testSubmitMilestoneOnlyCallableIfContributor(address caller)
        public
    {
        _authorizer.setIsAuthorized(address(this), true);

        milestoneManager.revokeContributorRole(caller);

        vm.prank(caller);
        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManager__OnlyCallableByContributor
                .selector
        );
        milestoneManager.submitMilestone(0);
    }

    function testSubmitMilestoneCallbackFailed() public {
        _authorizer.setIsAuthorized(address(this), true);

        milestoneManager.grantContributorRole(address(this));

        // Invalid id.
        uint invalidId = 1;

        _expectProposalCallbackFailure("__Milestone_submitMilestone(uint256)");
        milestoneManager.submitMilestone(invalidId);
    }

    //----------------------------------
    // Test: confirmMilestone()

    function testConfirmMilestone() public {
        _authorizer.setIsAuthorized(address(this), true);

        uint id =
            milestoneManager.addMilestone(_TITLE, block.timestamp, _DETAILS);

        milestoneManager.confirmMilestone(id);
        _assertMilestone({
            id: id,
            title: _TITLE,
            startDate: block.timestamp,
            details: _DETAILS,
            submitted: false,
            completed: true,
            removed: false
        });
    }

    function testConfirmMilestoneOnlyCallableIfAuthorized(address caller)
        public
    {
        _authorizer.setIsAuthorized(caller, false);

        vm.prank(caller);
        vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
        milestoneManager.confirmMilestone(0);
    }

    function testConfirmMilestoneCallbackFailed() public {
        _authorizer.setIsAuthorized(address(this), true);

        // Invalid id.
        uint invalidId = 1;

        _expectProposalCallbackFailure("__Milestone_confirmMilestone(uint256)");
        milestoneManager.confirmMilestone(invalidId);
    }

    //----------------------------------
    // Test: declineMilestone()

    function testDeclineMilestone() public {
        _authorizer.setIsAuthorized(address(this), true);

        uint id =
            milestoneManager.addMilestone(_TITLE, block.timestamp, _DETAILS);

        // Note that a milestone is only declineable if currently submitted.
        milestoneManager.grantContributorRole(address(this));
        milestoneManager.submitMilestone(id);

        milestoneManager.declineMilestone(id);
        _assertMilestone({
            id: id,
            title: _TITLE,
            startDate: block.timestamp,
            details: _DETAILS,
            submitted: false,
            completed: false,
            removed: false
        });
    }

    function testDeclineMilestoneOnlyCallableIfAuthorized(address caller)
        public
    {
        _authorizer.setIsAuthorized(caller, false);

        vm.prank(caller);
        vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
        milestoneManager.declineMilestone(0);
    }

    function testDeclineMilestoneCallbackFailed() public {
        _authorizer.setIsAuthorized(address(this), true);

        // Invalid id.
        uint invalidId = 1;

        _expectProposalCallbackFailure("__Milestone_declineMilestone(uint256)");
        milestoneManager.declineMilestone(invalidId);
    }

    //--------------------------------------------------------------------------
    // Test: Proposal Callback Functions

    //----------------------------------
    // Test: __Milestone_addMilestone()

    function test__Milestone_addMilestone() public {
        vm.startPrank(address(_proposal));

        uint id;

        id = milestoneManager.__Milestone_addMilestone(
            _TITLE, block.timestamp, _DETAILS
        );

        assertEq(id, 0);
        _assertMilestone(
            0, _TITLE, block.timestamp, _DETAILS, false, false, false
        );

        // Add second milestone to verify id increments correctly.
        id = milestoneManager.__Milestone_addMilestone(
            _TITLE, block.timestamp, _DETAILS
        );

        assertEq(id, 1);
        _assertMilestone(
            1, _TITLE, block.timestamp, _DETAILS, false, false, false
        );
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

    function test__Milestone_addMilestoneFailsForInvalidTitle() public {
        // Title invalid if:
        //  - empty
        string memory invalidTitle = "";

        vm.startPrank(address(_proposal));

        vm.expectRevert(
            IMilestoneManager.Module__MilestoneManager__InvalidTitle.selector
        );
        milestoneManager.__Milestone_addMilestone(
            invalidTitle, block.timestamp, _DETAILS
        );
    }

    function test__Milestone_addMilestoneFailsForInvalidStartDate() public {
        // StartDate invalid if:
        //  - less than block.timestamp
        vm.warp(1);
        uint invalidStartDate = 0;

        vm.startPrank(address(_proposal));

        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManager__InvalidStartDate
                .selector
        );
        milestoneManager.__Milestone_addMilestone(
            _TITLE, invalidStartDate, _DETAILS
        );
    }

    function test__Milestone_addMilestoneFailsForInvalidDetails() public {
        // Details invalid if:
        //  - empty
        string memory invalidDetails = "";

        vm.startPrank(address(_proposal));

        vm.expectRevert(
            IMilestoneManager.Module__MilestoneManager__InvalidDetails.selector
        );
        milestoneManager.__Milestone_addMilestone(
            _TITLE, block.timestamp, invalidDetails
        );
    }

    //----------------------------------
    // Test: __Milestone_updateMilestoneDetails()

    function test__Milestone_updateMilestoneDetails() public {
        vm.startPrank(address(_proposal));

        uint id = milestoneManager.__Milestone_addMilestone(
            _TITLE, block.timestamp, _DETAILS
        );

        string memory newDetails = "new Details";
        milestoneManager.__Milestone_updateMilestoneDetails(id, newDetails);

        _assertMilestone(
            id, _TITLE, block.timestamp, newDetails, false, false, false
        );
    }

    function test__Milestone_updateMilestoneDetailsOnlyCallableByProposal(
        address caller
    ) public {
        vm.assume(caller != address(_proposal));

        vm.prank(caller);
        vm.expectRevert(IModule.Module__OnlyCallableByProposal.selector);
        milestoneManager.__Milestone_updateMilestoneDetails(0, _DETAILS);
    }

    function test__Milestone_updateMilestoneDetailsFailsForInvalidDetails()
        public
    {
        // Details invalid if:
        //  - empty
        string memory invalidDetails = "";

        vm.startPrank(address(_proposal));

        // Add milestone to update.
        uint id = milestoneManager.__Milestone_addMilestone(
            _TITLE, block.timestamp, _DETAILS
        );

        vm.expectRevert(
            IMilestoneManager.Module__MilestoneManager__InvalidDetails.selector
        );
        milestoneManager.__Milestone_updateMilestoneDetails(id, invalidDetails);
    }

    function test__Milestone_updateMilestoneDetailsFailsIfNotUpdateable() public {
    }

    //----------------------------------
    // Test: __Milestone_updateMilestoneStartDate()

    function test__Milestone_updateMilestoneStartDate() public {
        vm.startPrank(address(_proposal));

        uint id = milestoneManager.__Milestone_addMilestone(
            _TITLE, block.timestamp, _DETAILS
        );

        uint newStartDate = block.timestamp + 1;
        milestoneManager.__Milestone_updateMilestoneStartDate(id, newStartDate);

        _assertMilestone(
            id, _TITLE, newStartDate, _DETAILS, false, false, false
        );
    }

    function test__Milestone_updateMilestoneStartDateOnlyCallableByProposal(
        address caller
    ) public {
        vm.assume(caller != address(_proposal));

        vm.prank(caller);
        vm.expectRevert(IModule.Module__OnlyCallableByProposal.selector);
        milestoneManager.__Milestone_updateMilestoneStartDate(0, block.timestamp);
    }

    function test__Milestone_updateMilestoneStartDateFailsForInvalidDetails()
        public
    {
        // StartDate invalid if:
        //  - less than block.timestamp
        vm.warp(1);
        uint invalidStartDate = 0;

        vm.startPrank(address(_proposal));

        // Add milestone to update.
        uint id = milestoneManager.__Milestone_addMilestone(
            _TITLE, block.timestamp, _DETAILS
        );

        vm.expectRevert(
            IMilestoneManager.Module__MilestoneManager__InvalidStartDate.selector
        );
        milestoneManager.__Milestone_updateMilestoneStartDate(id, invalidStartDate);
    }

    function test__Milestone_updateMilestoneStartDateFailsIfNotUpdateable() public {

    }

    //----------------------------------
    // Test: __Milestone_removeMilestone()

    function test__Milestone_removeMilestone() public {

    }

    //----------------------------------
    // Test: __Milestone_submitMilestone()

    //----------------------------------
    // Test: __Milestone_confirmMilestone()

    //----------------------------------
    // Test: __Milestone_declineMilestone()

    //--------------------------------------------------------------------------
    // Assert Helper Function

    /// @dev Asserts milestone with given data exists.
    function _assertMilestone(
        uint id,
        string memory title,
        uint startDate,
        string memory details,
        bool submitted,
        bool completed,
        bool removed
    ) internal {
        IMilestoneManager.Milestone memory m = milestoneManager.getMilestone(id);

        assertTrue(m.title.equals(title));
        assertEq(m.startDate, startDate);
        assertTrue(m.details.equals(details));

        assertEq(m.submitted, submitted);
        assertEq(m.completed, completed);
        assertEq(m.removed, removed);
    }
}
