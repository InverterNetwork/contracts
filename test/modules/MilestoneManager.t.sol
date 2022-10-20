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

    // Events copied from SuT
    event MilestoneAdded(
        uint indexed id, string title, uint startDate, string details
    );
    event MilestoneStartDateUpdated(uint indexed id, uint startDate);
    event MilestoneDetailsUpdated(uint indexed id, string details);
    event MilestoneRemoved(uint indexed id);
    event MilestoneSubmitted(uint indexed id);
    event MilestoneConfirmed(uint indexed id);
    event MilestoneDeclined(uint indexed id);

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

        string memory invalidTitle = _createInvalidTitles()[0];

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
            milestoneManager.addMilestone(_TITLE, block.timestamp + 1, _DETAILS);

        string memory newDetails = "new Details";
        milestoneManager.updateMilestoneDetails(id, newDetails);

        _assertMilestone(
            id, _TITLE, block.timestamp + 1, newDetails, false, false, false
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
            milestoneManager.addMilestone(_TITLE, block.timestamp + 1, _DETAILS);

        uint newStartDate = block.timestamp + 2;
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

        uint invalidId = 1;

        _expectProposalCallbackFailure("__Milestone_removeMilestone(uint256)");
        milestoneManager.removeMilestone(invalidId);
    }

    //----------------------------------
    // Test: submitMilestone()

    function testSubmitMilestone() public {
        _authorizer.setIsAuthorized(address(this), true);

        uint id =
            milestoneManager.addMilestone(_TITLE, block.timestamp + 1, _DETAILS);

        // Grant contributor role to address(this).
        milestoneManager.grantContributorRole(address(this));

        milestoneManager.submitMilestone(id);
        _assertMilestone({
            id: id,
            title: _TITLE,
            startDate: block.timestamp + 1,
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

        uint invalidId = 1;

        _expectProposalCallbackFailure("__Milestone_confirmMilestone(uint256)");
        milestoneManager.confirmMilestone(invalidId);
    }

    //----------------------------------
    // Test: declineMilestone()

    function testDeclineMilestone() public {
        _authorizer.setIsAuthorized(address(this), true);

        uint id =
            milestoneManager.addMilestone(_TITLE, block.timestamp + 1, _DETAILS);

        // Note that a milestone is only declineable if currently submitted.
        milestoneManager.grantContributorRole(address(this));
        milestoneManager.submitMilestone(id);

        milestoneManager.declineMilestone(id);
        _assertMilestone({
            id: id,
            title: _TITLE,
            startDate: block.timestamp + 1,
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

        // Add first milestone.
        vm.expectEmit(true, true, true, true);
        emit MilestoneAdded(0, _TITLE, block.timestamp, _DETAILS);

        id = milestoneManager.__Milestone_addMilestone(
            _TITLE, block.timestamp, _DETAILS
        );

        assertEq(id, 0);
        _assertMilestone(
            0, _TITLE, block.timestamp, _DETAILS, false, false, false
        );

        // Add second milestone to verify id increments correctly.
        vm.expectEmit(true, true, true, true);
        emit MilestoneAdded(1, _TITLE, block.timestamp, _DETAILS);

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
        string[] memory invalidTitles = _createInvalidTitles();

        vm.startPrank(address(_proposal));

        for (uint i; i < invalidTitles.length; i++) {
            vm.expectRevert(
                IMilestoneManager
                    .Module__MilestoneManager__InvalidTitle
                    .selector
            );
            milestoneManager.__Milestone_addMilestone(
                invalidTitles[i], block.timestamp, _DETAILS
            );
        }
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
        string[] memory invalidDetails = _createInvalidDetails();

        vm.startPrank(address(_proposal));

        for (uint i; i < invalidDetails.length; i++) {
            vm.expectRevert(
                IMilestoneManager
                    .Module__MilestoneManager__InvalidDetails
                    .selector
            );
            milestoneManager.__Milestone_addMilestone(
                _TITLE, block.timestamp, invalidDetails[i]
            );
        }
    }

    //----------------------------------
    // Test: __Milestone_updateMilestoneDetails()

    function test__Milestone_updateMilestoneDetails() public {
        vm.startPrank(address(_proposal));

        uint id = milestoneManager.__Milestone_addMilestone(
            _TITLE, block.timestamp + 1, _DETAILS
        );

        string memory newDetails = "new Details";

        vm.expectEmit(true, true, true, true);
        emit MilestoneDetailsUpdated(id, newDetails);

        milestoneManager.__Milestone_updateMilestoneDetails(id, newDetails);

        _assertMilestone(
            id, _TITLE, block.timestamp + 1, newDetails, false, false, false
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

    function test__Milestone_updateMilestoneDetailsFailsForInvalidId() public {
        vm.startPrank(address(_proposal));

        uint invalidId = 1;

        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManager__InvalidMilestoneId
                .selector
        );
        milestoneManager.__Milestone_updateMilestoneDetails(invalidId, _DETAILS);
    }

    function test__Milestone_updateMilestoneDetailsFailsForInvalidDetails()
        public
    {
        string[] memory invalidDetails = _createInvalidDetails();

        vm.startPrank(address(_proposal));

        // Add milestone to update.
        uint id = milestoneManager.__Milestone_addMilestone(
            _TITLE, block.timestamp + 1, _DETAILS
        );

        for (uint i; i < invalidDetails.length; i++) {
            vm.expectRevert(
                IMilestoneManager
                    .Module__MilestoneManager__InvalidDetails
                    .selector
            );
            milestoneManager.__Milestone_updateMilestoneDetails(
                id, invalidDetails[i]
            );
        }
    }

    function test__Milestone_updateMilestoneDetailsFailsIfNotUpdateable()
        public
    {
        vm.startPrank(address(_proposal));

        // Note that a milestone is not updateable if it started already, i.e.
        // if `block.timestamp` >= `startDate`.
        uint id = milestoneManager.__Milestone_addMilestone(
            _TITLE, block.timestamp, _DETAILS
        );

        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManager__MilestoneNotUpdateable
                .selector
        );
        milestoneManager.__Milestone_updateMilestoneDetails(id, _DETAILS);
    }

    //----------------------------------
    // Test: __Milestone_updateMilestoneStartDate()

    function test__Milestone_updateMilestoneStartDate() public {
        vm.startPrank(address(_proposal));

        uint id = milestoneManager.__Milestone_addMilestone(
            _TITLE, block.timestamp + 1, _DETAILS
        );

        uint newStartDate = block.timestamp + 2;

        vm.expectEmit(true, true, true, true);
        emit MilestoneStartDateUpdated(id, newStartDate);

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
        milestoneManager.__Milestone_updateMilestoneStartDate(
            0, block.timestamp
        );
    }

    function test__Milestone_updateMilestoneStartDateFailsForInvalidId()
        public
    {
        vm.startPrank(address(_proposal));

        uint invalidId = 1;

        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManager__InvalidMilestoneId
                .selector
        );
        milestoneManager.__Milestone_updateMilestoneStartDate(
            invalidId, block.timestamp
        );
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
            _TITLE, block.timestamp + 1, _DETAILS
        );

        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManager__InvalidStartDate
                .selector
        );
        milestoneManager.__Milestone_updateMilestoneStartDate(
            id, invalidStartDate
        );
    }

    function test__Milestone_updateMilestoneStartDateFailsIfNotUpdateable()
        public
    {
        vm.startPrank(address(_proposal));

        // Note that a milestone is not updateable if it started already, i.e.
        // if `block.timestamp` >= `startDate`.
        uint id = milestoneManager.__Milestone_addMilestone(
            _TITLE, block.timestamp, _DETAILS
        );

        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManager__MilestoneNotUpdateable
                .selector
        );
        milestoneManager.__Milestone_updateMilestoneStartDate(
            id, block.timestamp
        );
    }

    //----------------------------------
    // Test: __Milestone_removeMilestone()

    function test__Milestone_removeMilestone() public {
        vm.startPrank(address(_proposal));

        uint id = milestoneManager.__Milestone_addMilestone(
            _TITLE, block.timestamp + 1, _DETAILS
        );

        vm.expectEmit(true, true, true, true);
        emit MilestoneRemoved(id);

        milestoneManager.__Milestone_removeMilestone(id);

        _assertMilestone({
            id: id,
            title: _TITLE,
            startDate: block.timestamp + 1,
            details: _DETAILS,
            submitted: false,
            completed: false,
            removed: true
        });
    }

    function test__Milestone_removeMilestoneOnlyCallableByProposal(
        address caller
    ) public {
        vm.assume(caller != address(_proposal));

        vm.prank(caller);
        vm.expectRevert(IModule.Module__OnlyCallableByProposal.selector);
        milestoneManager.__Milestone_removeMilestone(0);
    }

    function test__Milestone_removeMilestoneFailsForInvalidId() public {
        vm.startPrank(address(_proposal));

        uint invalidId = 1;

        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManager__InvalidMilestoneId
                .selector
        );
        milestoneManager.__Milestone_removeMilestone(invalidId);
    }

    function test__Milestone_removeMilestoneFailsIfNotRemoveable() public {
        vm.startPrank(address(_proposal));

        uint id = milestoneManager.__Milestone_addMilestone(
            _TITLE, block.timestamp + 1, _DETAILS
        );

        // Note that a milestone is not removeable if it is already completed,
        // i.e. confirmed.
        milestoneManager.__Milestone_confirmMilestone(id);

        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManager__MilestoneNotRemovable
                .selector
        );
        milestoneManager.__Milestone_removeMilestone(id);
    }

    //----------------------------------
    // Test: __Milestone_submitMilestone()

    function test__Milestone_submitMilestone() public {
        vm.startPrank(address(_proposal));

        uint id = milestoneManager.__Milestone_addMilestone(
            _TITLE, block.timestamp + 1, _DETAILS
        );

        vm.expectEmit(true, true, true, true);
        emit MilestoneSubmitted(id);

        milestoneManager.__Milestone_submitMilestone(id);

        _assertMilestone({
            id: id,
            title: _TITLE,
            startDate: block.timestamp + 1,
            details: _DETAILS,
            submitted: true,
            completed: false,
            removed: false
        });
    }

    function test__Milestone_submitMilestoneOnlyCallableByProposal(
        address caller
    ) public {
        vm.assume(caller != address(_proposal));

        vm.prank(caller);
        vm.expectRevert(IModule.Module__OnlyCallableByProposal.selector);
        milestoneManager.__Milestone_submitMilestone(0);
    }

    function test__Milestone_submitMilestoneFailsForInvalidId() public {
        vm.startPrank(address(_proposal));

        uint invalidId = 1;

        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManager__InvalidMilestoneId
                .selector
        );
        milestoneManager.__Milestone_submitMilestone(invalidId);
    }

    function test__Milestone_submitMilestoneFailsIfNotSubmitable() public {
        vm.startPrank(address(_proposal));

        // Note that a milestone is not updateable if it started already, i.e.
        // if `block.timestamp` >= `startDate`.
        uint id = milestoneManager.__Milestone_addMilestone(
            _TITLE, block.timestamp, _DETAILS
        );

        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManager__MilestoneNotSubmitable
                .selector
        );
        milestoneManager.__Milestone_submitMilestone(id);
    }

    //----------------------------------
    // Test: __Milestone_confirmMilestone()

    function test__Milestone_confirmMilestone() public {
        vm.startPrank(address(_proposal));

        uint id = milestoneManager.__Milestone_addMilestone(
            _TITLE, block.timestamp + 1, _DETAILS
        );

        vm.expectEmit(true, true, true, true);
        emit MilestoneConfirmed(id);

        milestoneManager.__Milestone_confirmMilestone(id);

        _assertMilestone({
            id: id,
            title: _TITLE,
            startDate: block.timestamp + 1,
            details: _DETAILS,
            submitted: false,
            completed: true,
            removed: false
        });
    }

    function test__Milestone_confirmMilestoneOnlyCallableByProposal(
        address caller
    ) public {
        vm.assume(caller != address(_proposal));

        vm.prank(caller);
        vm.expectRevert(IModule.Module__OnlyCallableByProposal.selector);
        milestoneManager.__Milestone_confirmMilestone(0);
    }

    function test__Milestone_confirmMilestoneFailsForInvalidId() public {
        vm.startPrank(address(_proposal));

        uint invalidId = 1;

        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManager__InvalidMilestoneId
                .selector
        );
        milestoneManager.__Milestone_confirmMilestone(invalidId);
    }

    function test__Milestone_confirmMilestoneFailsIfNotConfirmable() public {
        vm.startPrank(address(_proposal));

        uint id = milestoneManager.__Milestone_addMilestone(
            _TITLE, block.timestamp, _DETAILS
        );

        // Note that a milestone is not confirmable if it is already removed.
        milestoneManager.__Milestone_removeMilestone(id);

        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManager__MilestoneNotConfirmable
                .selector
        );
        milestoneManager.__Milestone_confirmMilestone(id);
    }

    //----------------------------------
    // Test: __Milestone_declineMilestone()

    function test__Milestone_declineMilestone() public {
        vm.startPrank(address(_proposal));

        uint id = milestoneManager.__Milestone_addMilestone(
            _TITLE, block.timestamp + 1, _DETAILS
        );

        // Note that a milestone is only declineable if it is submitted already.
        milestoneManager.__Milestone_submitMilestone(id);

        vm.expectEmit(true, true, true, true);
        emit MilestoneDeclined(id);

        milestoneManager.__Milestone_declineMilestone(id);

        _assertMilestone({
            id: id,
            title: _TITLE,
            startDate: block.timestamp + 1,
            details: _DETAILS,
            submitted: false,
            completed: false,
            removed: false
        });
    }

    function test__Milestone_declineMilestoneOnlyCallableByProposal(
        address caller
    ) public {
        vm.assume(caller != address(_proposal));

        vm.prank(caller);
        vm.expectRevert(IModule.Module__OnlyCallableByProposal.selector);
        milestoneManager.__Milestone_declineMilestone(0);
    }

    function test__Milestone_declineMilestoneFailsForInvalidId() public {
        vm.startPrank(address(_proposal));

        uint invalidId = 1;

        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManager__InvalidMilestoneId
                .selector
        );
        milestoneManager.__Milestone_declineMilestone(invalidId);
    }

    function test__Milestone_declineMilestoneFailsIfNotConfirmable() public {
        vm.startPrank(address(_proposal));

        uint id = milestoneManager.__Milestone_addMilestone(
            _TITLE, block.timestamp, _DETAILS
        );

        // Note that a milestone is not declineable if it is not yet submitted.

        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManager__MilestoneNotDeclineable
                .selector
        );
        milestoneManager.__Milestone_declineMilestone(id);
    }

    //--------------------------------------------------------------------------
    // Assert Helper Functions

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

    //--------------------------------------------------------------------------
    // Data Creation Helper Functions

    /// @dev Returns an element of each category of invalid titles.
    function _createInvalidTitles() internal pure returns (string[] memory) {
        string[] memory invalidTitles = new string[](1);

        invalidTitles[0] = ""; // Empty string

        return invalidTitles;
    }

    /// @dev Returns an element of each category of invalid details.
    function _createInvalidDetails() internal pure returns (string[] memory) {
        string[] memory invalidDetails = new string[](1);

        invalidDetails[0] = ""; // Empty string

        return invalidDetails;
    }
}
