// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {
    ModuleTest,
    IModule,
    IProposal,
    LibString
} from "test/modules/ModuleTest.sol";

// SuT
import {
    MilestoneManager,
    IMilestoneManager
} from "src/modules/MilestoneManager.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

contract MilestoneManagerTest is ModuleTest {
    using LibString for string;

    // SuT
    MilestoneManager milestoneManager;

    // Constants
    uint constant MAX_MILESTONES = 20;
    uint constant DURATION = 1 weeks;
    uint constant BUDGET = 1000 * 1e18;
    string constant TITLE = "Title";
    string constant DETAILS = "Details";

    // Constant copied from SuT
    uint private constant _SENTINEL = type(uint).max;

    // Events copied from SuT
    event MilestoneAdded(
        uint indexed id,
        uint duration,
        uint budget,
        string title,
        string details
    );
    event MilestoneUpdated(
        uint indexed id, uint duration, uint budget, string details
    );
    event MilestoneRemoved(uint indexed id);
    event MilestoneSubmitted(uint indexed id);
    event MilestoneConfirmed(uint indexed id);
    event MilestoneDeclined(uint indexed id);

    function setUp() public {
        milestoneManager = new MilestoneManager();
        milestoneManager.init(_proposal, _METADATA, bytes(""));

        _setUpProposal(milestoneManager);

        _authorizer.setIsAuthorized(address(this), true);
    }

    //--------------------------------------------------------------------------
    // Test: Initialization

    function testInit() public override (ModuleTest) {
        // SENTINEL milestone does not exist.
        assertTrue(!milestoneManager.isExistingMilestoneId(_SENTINEL));

        // Not current active milestone.
        assertTrue(!milestoneManager.hasActiveMilestone());

        // Next milestone not activateable.
        assertTrue(!milestoneManager.isNextMilestoneActivateable());

        // Current milestone list is empty.
        uint[] memory milestones = milestoneManager.listMilestoneIds();
        assertEq(milestones.length, 0);
    }

    function testReinitFails() public override (ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__AlreadyInitialized);
        milestoneManager.init(_proposal, _METADATA, bytes(""));
    }

    //--------------------------------------------------------------------------
    // Test: Milestone API Functions

    /*

    //----------------------------------
    // Test: addMilestone()

    function testAddMilestone() public {
        _authorizer.setIsAuthorized(address(this), true);

        uint id =
            milestoneManager.addMilestone(TITLE, block.timestamp, DETAILS);
        assertEq(id, 0);
        _assertMilestone(
            0, TITLE, block.timestamp, DETAILS, false, false, false
        );
    }

    function testAddMilestoneOnlyCallableIfAuthorized(address caller) public {
        _authorizer.setIsAuthorized(caller, false);

        vm.prank(caller);
        vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
        milestoneManager.addMilestone(TITLE, block.timestamp, DETAILS);
    }

    function testAddMilestoneCallbackFailed() public {
        _authorizer.setIsAuthorized(address(this), true);

        string memory invalidTitle = _createInvalidTitles()[0];

        _expectProposalCallbackFailure(
            "__Milestone_addMilestone(string,uint256,string)"
        );
        milestoneManager.addMilestone(invalidTitle, block.timestamp, DETAILS);
    }

    //----------------------------------
    // Test: updateMilestoneDetails()

    function testUpdateMilestoneDetails() public {
        _authorizer.setIsAuthorized(address(this), true);

        uint id =
            milestoneManager.addMilestone(TITLE, block.timestamp + 1, DETAILS);

        string memory newDetails = "new Details";
        milestoneManager.updateMilestoneDetails(id, newDetails);

        _assertMilestone(
            id, TITLE, block.timestamp + 1, newDetails, false, false, false
        );
    }

    function testUpdateMilestoneDetailsOnlyCallableIfAuthorized(address caller)
        public
    {
        _authorizer.setIsAuthorized(caller, false);

        vm.prank(caller);
        vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
        milestoneManager.updateMilestoneDetails(0, DETAILS);
    }

    function testUpdateMilestoneDetailsCallbackFailed() public {
        _authorizer.setIsAuthorized(address(this), true);

        uint id =
            milestoneManager.addMilestone(TITLE, block.timestamp, DETAILS);

        uint invalidId = id + 1;

        _expectProposalCallbackFailure(
            "__Milestone_updateMilestoneDetails(uint256,string)"
        );
        milestoneManager.updateMilestoneDetails(invalidId, DETAILS);
    }

    //----------------------------------
    // Test: updateMilestoneStartDate()

    function testUpdateMilestoneStartDate() public {
        _authorizer.setIsAuthorized(address(this), true);

        uint id =
            milestoneManager.addMilestone(TITLE, block.timestamp + 1, DETAILS);

        uint newStartDate = block.timestamp + 2;
        milestoneManager.updateMilestoneStartDate(id, newStartDate);

        _assertMilestone(
            id, TITLE, newStartDate, DETAILS, false, false, false
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
            milestoneManager.addMilestone(TITLE, block.timestamp, DETAILS);

        milestoneManager.removeMilestone(id);
        _assertMilestone({
            id: id,
            title: TITLE,
            startDate: block.timestamp,
            details: DETAILS,
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
            milestoneManager.addMilestone(TITLE, block.timestamp + 1, DETAILS);

        // Grant contributor role to address(this).
        milestoneManager.grantContributorRole(address(this));

        milestoneManager.submitMilestone(id);
        _assertMilestone({
            id: id,
            title: TITLE,
            startDate: block.timestamp + 1,
            details: DETAILS,
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
            milestoneManager.addMilestone(TITLE, block.timestamp, DETAILS);

        milestoneManager.confirmMilestone(id);
        _assertMilestone({
            id: id,
            title: TITLE,
            startDate: block.timestamp,
            details: DETAILS,
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
            milestoneManager.addMilestone(TITLE, block.timestamp + 1, DETAILS);

        // Note that a milestone is only declineable if currently submitted.
        milestoneManager.grantContributorRole(address(this));
        milestoneManager.submitMilestone(id);

        milestoneManager.declineMilestone(id);
        _assertMilestone({
            id: id,
            title: TITLE,
            startDate: block.timestamp + 1,
            details: DETAILS,
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
    */

    //--------------------------------------------------------------------------
    // Test: Proposal Callback Functions

    //----------------------------------
    // Test: addMilestone()

    function testAddMilestone() public {
        uint gotId;
        uint wantId;

        // Add each milestone.
        for (uint i; i < MAX_MILESTONES; i++) {
            wantId = i + 1; // Note that id's start at 1.

            vm.expectEmit(true, true, true, true);
            emit MilestoneAdded(wantId, DURATION, BUDGET, TITLE, DETAILS);

            gotId =
                milestoneManager.addMilestone(DURATION, BUDGET, TITLE, DETAILS);

            assertEq(gotId, wantId);
            _assertMilestone(
                gotId, DURATION, BUDGET, TITLE, DETAILS, false, false
            );
        }

        // Assert that all milestone id's are fetchable.
        // Note that the list is traversed.
        uint[] memory ids = milestoneManager.listMilestoneIds();

        assertEq(ids.length, MAX_MILESTONES);
        for (uint i; i < MAX_MILESTONES; i++) {
            wantId = MAX_MILESTONES - i; // Note that id's start at 1.

            assertEq(ids[i], wantId);
        }
    }

    function testAddMilestoneFailsIfCallerNotAuthorized() public {
        _authorizer.setIsAuthorized(address(this), false);

        vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
        milestoneManager.addMilestone(DURATION, BUDGET, TITLE, DETAILS);
    }

    function testAddMilestoneFailsForInvalidDuration() public {
        uint[] memory invalids = _createInvalidDurations();

        for (uint i; i < invalids.length; i++) {
            vm.expectRevert(
                IMilestoneManager
                    .Module__MilestoneManager__InvalidDuration
                    .selector
            );
            milestoneManager.addMilestone(invalids[i], BUDGET, TITLE, DETAILS);
        }
    }

    /*
    @todo mp, marvin, nuggan: There are currently no invalid budgets.
    function test__Milestone_addMilestoneFailsForInvalidBudget() public {
        uint[] memory invalids = _createInvalidBudgets();

        vm.startPrank(address(_proposal));

        for (uint i; i < invalids.length; i++) {
            vm.expectRevert(
                IMilestoneManager
                    .Module__MilestoneManager__InvalidBudget
                    .selector
            );
            milestoneManager.__Milestone_addMilestone(
                DURATION, invalids[i], TITLE, DETAILS
            );
        }
    }
    */

    function testAddMilestoneFailsForInvalidTitle() public {
        string[] memory invalidTitles = _createInvalidTitles();

        for (uint i; i < invalidTitles.length; i++) {
            vm.expectRevert(
                IMilestoneManager
                    .Module__MilestoneManager__InvalidTitle
                    .selector
            );
            milestoneManager.addMilestone(
                DURATION, BUDGET, invalidTitles[i], DETAILS
            );
        }
    }

    function testAddMilestoneFailsForInvalidDetails() public {
        string[] memory invalidDetails = _createInvalidDetails();

        for (uint i; i < invalidDetails.length; i++) {
            vm.expectRevert(
                IMilestoneManager
                    .Module__MilestoneManager__InvalidDetails
                    .selector
            );
            milestoneManager.addMilestone(
                DURATION, BUDGET, TITLE, invalidDetails[i]
            );
        }
    }

    //----------------------------------
    // Test: removeMilestone()

    function testRemoveMilestone() public {
        uint numberMilestones = 10;

        // Fill list with milestones.
        for (uint i; i < numberMilestones; i++) {
            milestoneManager.addMilestone(DURATION, BUDGET, TITLE, DETAILS);
        }

        // Remove milestones from the front, i.e. highest milestone id, until
        // list is empty.
        for (uint i; i < numberMilestones; i++) {
            uint id = numberMilestones - i; // Note that id's start at 1.

            vm.expectEmit(true, true, true, true);
            emit MilestoneRemoved(id);

            milestoneManager.removeMilestone(_SENTINEL, id);
            assertEq(
                milestoneManager.listMilestoneIds().length,
                numberMilestones - i - 1
            );
        }

        // Fill list again with milestones.
        for (uint i; i < numberMilestones; i++) {
            milestoneManager.addMilestone(DURATION, BUDGET, TITLE, DETAILS);
        }

        // Remove milestones from the back, i.e. lowest milestone id, until
        // list is empty.
        // Note that removing the last milestone requires the sentinel as
        // prevId.
        for (uint i; i < numberMilestones - 1; i++) {
            // Note that id's start at 1.
            uint prevId = i + 2;
            uint id = i + 1;

            vm.expectEmit(true, true, true, true);
            emit MilestoneRemoved(id);

            milestoneManager.removeMilestone(prevId, id);
            assertEq(
                milestoneManager.listMilestoneIds().length,
                numberMilestones - i - 1
            );
        }

        milestoneManager.removeMilestone(_SENTINEL, numberMilestones);
        assertEq(milestoneManager.listMilestoneIds().length, 0);
    }

    function testRemoveMilestoneFailsIfCallerNotAuthorized() public {
        _authorizer.setIsAuthorized(address(this), false);

        vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
        milestoneManager.removeMilestone(0, 1);
    }

    function testRemoveMilestoneFailsForInvalidId() public {
        uint invalidId = 1;

        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManager__InvalidMilestoneId
                .selector
        );
        milestoneManager.removeMilestone(_SENTINEL, invalidId);
    }

    /*
    // @todo mp: Need mock to set completed field per hand.
    function test__Milestone_removeMilestoneFailsIfMilestoneAlreadyStarted() public {
        vm.startPrank(address(_proposal));

        // Add and start a milestone.
        milestoneManager.__Milestone_addMilestone(DURATION, BUDGET, TITLE, DETAILS);
        // @todo mp: Set as completed.

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
    // Test: __Milestone_startNextMilestone()

    //----------------------------------
    // Test: __Milestone_updateMilestoneDetails()

    function test__Milestone_updateMilestoneDetails() public {
        vm.startPrank(address(_proposal));

        uint id = milestoneManager.__Milestone_addMilestone(
            TITLE, block.timestamp + 1, DETAILS
        );

        string memory newDetails = "new Details";

        vm.expectEmit(true, true, true, true);
        emit MilestoneDetailsUpdated(id, newDetails);

        milestoneManager.__Milestone_updateMilestoneDetails(id, newDetails);

        _assertMilestone(
            id, TITLE, block.timestamp + 1, newDetails, false, false, false
        );
    }

    function test__Milestone_updateMilestoneDetailsOnlyCallableByProposal(
        address caller
    ) public {
        vm.assume(caller != address(_proposal));

        vm.prank(caller);
        vm.expectRevert(IModule.Module__OnlyCallableByProposal.selector);
        milestoneManager.__Milestone_updateMilestoneDetails(0, DETAILS);
    }

    function test__Milestone_updateMilestoneDetailsFailsForInvalidId() public {
        vm.startPrank(address(_proposal));

        uint invalidId = 1;

        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManager__InvalidMilestoneId
                .selector
        );
        milestoneManager.__Milestone_updateMilestoneDetails(invalidId, DETAILS);
    }

    function test__Milestone_updateMilestoneDetailsFailsForInvalidDetails()
        public
    {
        string[] memory invalidDetails = _createInvalidDetails();

        vm.startPrank(address(_proposal));

        // Add milestone to update.
        uint id = milestoneManager.__Milestone_addMilestone(
            TITLE, block.timestamp + 1, DETAILS
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
            TITLE, block.timestamp, DETAILS
        );

        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManager__MilestoneNotUpdateable
                .selector
        );
        milestoneManager.__Milestone_updateMilestoneDetails(id, DETAILS);
    }

    //----------------------------------
    // Test: __Milestone_updateMilestoneStartDate()

    function test__Milestone_updateMilestoneStartDate() public {
        vm.startPrank(address(_proposal));

        uint id = milestoneManager.__Milestone_addMilestone(
            TITLE, block.timestamp + 1, DETAILS
        );

        uint newStartDate = block.timestamp + 2;

        vm.expectEmit(true, true, true, true);
        emit MilestoneStartDateUpdated(id, newStartDate);

        milestoneManager.__Milestone_updateMilestoneStartDate(id, newStartDate);

        _assertMilestone(
            id, TITLE, newStartDate, DETAILS, false, false, false
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
            TITLE, block.timestamp + 1, DETAILS
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
            TITLE, block.timestamp, DETAILS
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
    // Test: __Milestone_submitMilestone()

    function test__Milestone_submitMilestone() public {
        vm.startPrank(address(_proposal));

        uint id = milestoneManager.__Milestone_addMilestone(
            TITLE, block.timestamp + 1, DETAILS
        );

        vm.expectEmit(true, true, true, true);
        emit MilestoneSubmitted(id);

        milestoneManager.__Milestone_submitMilestone(id);

        _assertMilestone({
            id: id,
            title: TITLE,
            startDate: block.timestamp + 1,
            details: DETAILS,
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
            TITLE, block.timestamp, DETAILS
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
            TITLE, block.timestamp + 1, DETAILS
        );

        vm.expectEmit(true, true, true, true);
        emit MilestoneConfirmed(id);

        milestoneManager.__Milestone_confirmMilestone(id);

        _assertMilestone({
            id: id,
            title: TITLE,
            startDate: block.timestamp + 1,
            details: DETAILS,
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
            TITLE, block.timestamp, DETAILS
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
            TITLE, block.timestamp + 1, DETAILS
        );

        // Note that a milestone is only declineable if it is submitted already.
        milestoneManager.__Milestone_submitMilestone(id);

        vm.expectEmit(true, true, true, true);
        emit MilestoneDeclined(id);

        milestoneManager.__Milestone_declineMilestone(id);

        _assertMilestone({
            id: id,
            title: TITLE,
            startDate: block.timestamp + 1,
            details: DETAILS,
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
            TITLE, block.timestamp, DETAILS
        );

        // Note that a milestone is not declineable if it is not yet submitted.

        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManager__MilestoneNotDeclineable
                .selector
        );
        milestoneManager.__Milestone_declineMilestone(id);
    }*/

    //--------------------------------------------------------------------------
    // Assert Helper Functions

    /// @dev Asserts milestone with given data exists.
    function _assertMilestone(
        uint id,
        uint duration,
        uint budget,
        string memory title,
        string memory details,
        bool submitted,
        bool completed
    ) internal {
        IMilestoneManager.Milestone memory m =
            milestoneManager.getMilestoneInformation(id);

        assertEq(m.duration, duration);
        assertEq(m.budget, budget);

        assertTrue(m.title.equals(title));
        assertTrue(m.details.equals(details));

        assertEq(m.submitted, submitted);
        assertEq(m.completed, completed);
    }

    //--------------------------------------------------------------------------
    // Data Creation Helper Functions

    /// @dev Returns an element of each category of invalid durations.
    function _createInvalidDurations() internal pure returns (uint[] memory) {
        uint[] memory invalids = new uint[](1);

        invalids[0] = 0;

        return invalids;
    }

    /// @dev Returns an element of each category of invalid budgets.
    function _createInvalidBudgets() internal pure returns (uint[] memory) {
        uint[] memory invalids = new uint[](0);

        return invalids;
    }

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
