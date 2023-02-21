// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

import "forge-std/console.sol";

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

import {IPaymentClient} from "src/modules/mixins/IPaymentClient.sol";

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
    uint constant SALARY_PRECISION = 100_000_000;
    uint constant MAX_CONTRIBUTORS = 50;
    bytes constant DETAILS = "Details";
    bytes constant SUBMISSION_DATA = "SubmissionData";
    uint constant TIMELOCK = 3 days;

    IMilestoneManager.Contributor ALICE = IMilestoneManager.Contributor(
        address(0xA11CE), 50_000_000, "AliceIdHash"
    );
    IMilestoneManager.Contributor BOB =
        IMilestoneManager.Contributor(address(0x606), 50_000_000, "BobIdHash");
    IMilestoneManager.Contributor[] DEFAULT_CONTRIBUTORS;

    // Constant copied from SuT
    uint private constant _SENTINEL = type(uint).max;

    // Events copied from SuT
    event MilestoneAdded(
        uint indexed id,
        uint duration,
        uint budget,
        IMilestoneManager.Contributor[] contributors,
        bytes details
    );
    event MilestoneUpdated(
        uint indexed id,
        uint duration,
        uint budget,
        IMilestoneManager.Contributor[] contributors,
        bytes details
    );
    event MilestoneRemoved(uint indexed id);
    event MilestoneSubmitted(uint indexed id, bytes indexed submissionData);
    event MilestoneConfirmed(uint indexed id);
    event MilestoneDeclined(uint indexed id);

    function setUp() public {
        address impl = address(new MilestoneManager());
        milestoneManager = MilestoneManager(Clones.clone(impl));

        _setUpProposal(milestoneManager);

        milestoneManager.init(_proposal, _METADATA, bytes(""));

        _authorizer.setIsAuthorized(address(this), true);

        DEFAULT_CONTRIBUTORS.push(ALICE);
        DEFAULT_CONTRIBUTORS.push(BOB);
    }

    //--------------------------------------------------------------------------
    // Test: Initialization

    function testInit() public override(ModuleTest) {
        // SENTINEL milestone does not exist.
        assertTrue(!milestoneManager.isExistingMilestoneId(_SENTINEL));

        // No current active milestone.
        assertTrue(!milestoneManager.hasActiveMilestone());

        // Next milestone not activateable.
        assertTrue(!milestoneManager.isNextMilestoneActivatable());

        // Current milestone list is empty.
        uint[] memory milestones = milestoneManager.listMilestoneIds();
        assertEq(milestones.length, 0);
    }

    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__AlreadyInitialized);
        milestoneManager.init(_proposal, _METADATA, bytes(""));
    }

    //--------------------------------------------------------------------------
    // Tests: Milestone View Functions

    //----------------------------------
    // Test: getMilestoneInformation()

    function testGetMilesoneInformation() public {
        uint id = milestoneManager.addMilestone(
            DURATION, BUDGET, DEFAULT_CONTRIBUTORS, DETAILS
        );

        _assertMilestone(
            id, DURATION, BUDGET, DEFAULT_CONTRIBUTORS, DETAILS, "", false
        );
    }

    function testGetMilesoneInformationFailsIfNoMilestoneExists() public {
        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManager__InvalidMilestoneId
                .selector
        );
        milestoneManager.getMilestoneInformation(1);
    }

    //----------------------------------
    // Test: listMilestoneIds()

    function testListMilestoneIds(uint amount) public {
        amount = bound(amount, 0, MAX_MILESTONES);

        for (uint i; i < amount; ++i) {
            milestoneManager.addMilestone(
                DURATION, BUDGET, DEFAULT_CONTRIBUTORS, DETAILS
            );
        }

        uint[] memory ids = milestoneManager.listMilestoneIds();

        for (uint i; i < amount; ++i) {
            assertEq(ids[i], i + 1); // Note that id's start at one.
        }
    }

    //----------------------------------
    // Tests: getPreviousMilestone()

    function testGetPreviousMilestone(uint whos, uint randomWho) public {
        whos = bound(whos, 1, MAX_MILESTONES);
        randomWho = bound(randomWho, 1, whos);

        for (uint i; i < whos; ++i) {
            milestoneManager.addMilestone(
                DURATION, BUDGET, DEFAULT_CONTRIBUTORS, DETAILS
            );
        }

        uint prevMilestoneId;

        if (randomWho == 1) {
            prevMilestoneId = _SENTINEL;
        } else {
            prevMilestoneId = randomWho - 1;
        }

        assertEq(
            milestoneManager.getPreviousMilestoneId(randomWho), prevMilestoneId
        );
    }

    //----------------------------------
    // Test: getActiveMilestoneId()

    function testGetActiveMilestoneId() public {
        // Mint tokens to proposal.
        // Note that these tokens are transfered to the milestone module
        // when the payment orders are created.
        _token.mint(address(_proposal), BUDGET);

        uint id = milestoneManager.addMilestone(
            DURATION, BUDGET, DEFAULT_CONTRIBUTORS, DETAILS
        );

        // We wait for the timelock to pass
        vm.warp(block.timestamp + TIMELOCK + 1);

        milestoneManager.startNextMilestone();

        assertEq(milestoneManager.getActiveMilestoneId(), id);
    }

    function testGetActiveMilestoneIdFailsIfNoActiveMilestone() public {
        // Note to add a milestone to not receive an `InvalidMilestoneId` error.
        milestoneManager.addMilestone(
            DURATION, BUDGET, DEFAULT_CONTRIBUTORS, DETAILS
        );

        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManager__NoActiveMilestone
                .selector
        );
        milestoneManager.getActiveMilestoneId();
    }

    //----------------------------------
    // Test: hasActiveMilestone()

    function testHasActiveMilestone() public {
        // Mint tokens to proposal.
        // Note that these tokens are transfered to the milestone module
        // when the payment orders are created.
        _token.mint(address(_proposal), BUDGET);

        milestoneManager.addMilestone(
            DURATION, BUDGET, DEFAULT_CONTRIBUTORS, DETAILS
        );

        // We wait for the timelock to pass
        vm.warp(block.timestamp + TIMELOCK + 1);

        milestoneManager.startNextMilestone();

        assertTrue(milestoneManager.hasActiveMilestone());
    }

    function testHasActiveMilestoneFalseIfNoActiveMilestoneYet() public {
        milestoneManager.addMilestone(
            DURATION, BUDGET, DEFAULT_CONTRIBUTORS, DETAILS
        );

        assertTrue(!milestoneManager.hasActiveMilestone());
    }

    function testHasActiveMilestoneFalseIfMilestoneAlreadyCompleted(
        address[] memory contributors
    ) public {
        IMilestoneManager.Contributor[] memory contribs =
            _generateEqualContributors(contributors);

        // Mint tokens to proposal.
        // Note that these tokens are transfered to the milestone module
        // when the payment orders are created.
        _token.mint(address(_proposal), BUDGET);

        uint id =
            milestoneManager.addMilestone(DURATION, BUDGET, contribs, DETAILS);

        // We wait for the timelock to pass
        vm.warp(block.timestamp + TIMELOCK + 1);

        milestoneManager.startNextMilestone();

        // Milestone must be submitted by a contributor.
        vm.prank(contributors[0]);
        milestoneManager.submitMilestone(id, SUBMISSION_DATA);

        milestoneManager.completeMilestone(id);

        assertTrue(!milestoneManager.hasActiveMilestone());
    }

    function testHasActiveMilestoneFalseIfMilestonesDurationOver(
        address[] memory contributors
    ) public {
        IMilestoneManager.Contributor[] memory contribs =
            _generateEqualContributors(contributors);

        // Mint tokens to proposal.
        // Note that these tokens are transfered to the milestone module
        // when the payment orders are created.
        _token.mint(address(_proposal), BUDGET);

        milestoneManager.addMilestone(DURATION, BUDGET, contribs, DETAILS);

        // We wait for the timelock to pass
        vm.warp(block.timestamp + TIMELOCK + 1);

        milestoneManager.startNextMilestone();

        vm.warp(block.timestamp + DURATION + 1);
        assertTrue(!milestoneManager.hasActiveMilestone());
    }

    //----------------------------------
    // Test: isNextMilestoneActivatable()

    function testNextMilestoneNotActivatableIfNoNextMilestone() public {
        assertTrue(!milestoneManager.isNextMilestoneActivatable());
    }

    function testNextMilestoneNotActivatableIfCurrentMilestoneStartedAndDurationNotExceeded(
        address[] memory contributors
    ) public {
        IMilestoneManager.Contributor[] memory contribs =
            _generateEqualContributors(contributors);

        // Mint tokens to proposal.
        // Note that these tokens are transfered to the milestone module
        // when the payment orders are created.
        _token.mint(address(_proposal), BUDGET);

        milestoneManager.addMilestone(DURATION, BUDGET, contribs, DETAILS);

        // We wait for the timelock to pass
        vm.warp(block.timestamp + TIMELOCK + 1);

        milestoneManager.startNextMilestone();

        milestoneManager.addMilestone(DURATION, BUDGET, contribs, DETAILS);
        assertTrue(!milestoneManager.isNextMilestoneActivatable());
    }

    function testNextMilestoneNotActivatableIfUnderTimelock(
        address[] memory contributors
    ) public {
        IMilestoneManager.Contributor[] memory contribs =
            _generateEqualContributors(contributors);

        // Mint tokens to proposal.
        // Note that these tokens are transfered to the milestone module
        // when the payment orders are created.
        _token.mint(address(_proposal), BUDGET);

        milestoneManager.addMilestone(DURATION, BUDGET, contribs, DETAILS);

        // We wait for the timelock to pass
        vm.warp(block.timestamp + TIMELOCK + 1);

        milestoneManager.startNextMilestone();

        uint secondID =
            milestoneManager.addMilestone(DURATION, BUDGET, contribs, DETAILS);

        vm.warp(block.timestamp + DURATION - 1 days);

        //update milestone
        milestoneManager.updateMilestone(
            secondID, DURATION + 1, BUDGET + 1, contribs, DETAILS
        );

        // Current milestone is over, but next still under timelock
        vm.warp(block.timestamp + 2 days);

        assertTrue(!milestoneManager.isNextMilestoneActivatable());
    }

    function testNextMilestoneActivatableIfFirstMilestone() public {
        milestoneManager.addMilestone(
            DURATION, BUDGET, DEFAULT_CONTRIBUTORS, DETAILS
        );

        // We wait for the timelock to pass
        vm.warp(block.timestamp + TIMELOCK + 1);

        assertTrue(milestoneManager.isNextMilestoneActivatable());
    }

    function testNextMilestoneActivatableIfCurrentMilestoneStartedAndDurationExceeded(
        address[] memory contributors
    ) public {
        IMilestoneManager.Contributor[] memory contribs =
            _generateEqualContributors(contributors);

        // Mint tokens to proposal.
        // Note that these tokens are transfered to the milestone module
        // when the payment orders are created.
        _token.mint(address(_proposal), BUDGET);

        milestoneManager.addMilestone(DURATION, BUDGET, contribs, DETAILS);
        milestoneManager.addMilestone(DURATION, BUDGET, contribs, DETAILS);

        // We wait for the timelock to pass
        vm.warp(block.timestamp + TIMELOCK + 1);

        milestoneManager.startNextMilestone();

        // Wait until milestones duration is over.
        vm.warp(block.timestamp + DURATION + 1);

        assertTrue(milestoneManager.isNextMilestoneActivatable());
    }

    //----------------------------------
    // Test: getSalaryPrecision()

    function testGetSalaryPrecision() public {
        assertEq(milestoneManager.getSalaryPrecision(), SALARY_PRECISION);
    }

    //----------------------------------
    // Test: getSalaryPrecision()

    function testGetMaximumContributors() public {
        assertEq(milestoneManager.getMaximumContributors(), MAX_CONTRIBUTORS);
    }

    //--------------------------------------------------------------------------
    // Tests: Milestone Management

    //----------------------------------
    // Test: addMilestone()

    function testAddMilestone(uint amount) public {
        // Note to stay reasonable.
        vm.assume(amount < MAX_MILESTONES);

        uint id;

        // Add each milestone.
        for (uint i; i < amount; ++i) {
            vm.expectEmit(true, true, true, true);
            emit MilestoneAdded(
                i + 1, DURATION, BUDGET, DEFAULT_CONTRIBUTORS, DETAILS
                );

            id = milestoneManager.addMilestone(
                DURATION, BUDGET, DEFAULT_CONTRIBUTORS, DETAILS
            );

            assertEq(id, i + 1); // Note that id's start at 1.
            _assertMilestone(
                id, DURATION, BUDGET, DEFAULT_CONTRIBUTORS, DETAILS, "", false
            );
        }

        // Assert that all milestone id's are fetchable.
        uint[] memory ids = milestoneManager.listMilestoneIds();

        assertEq(ids.length, amount);
        for (uint i; i < amount; ++i) {
            assertEq(ids[i], i + 1); // Note that id's start at 1.
        }
    }

    function testAddMilestoneFailsIfCallerNotAuthorizedOrOwner(address caller)
        public
    {
        _authorizer.setIsAuthorized(caller, false);
        vm.assume(caller != _proposal.owner());

        vm.prank(caller);
        vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
        milestoneManager.addMilestone(
            DURATION, BUDGET, DEFAULT_CONTRIBUTORS, DETAILS
        );
    }

    function testAddMilestoneFailsForInvalidDuration() public {
        uint[] memory invalids = _createInvalidDurations();

        for (uint i; i < invalids.length; ++i) {
            vm.expectRevert(
                IMilestoneManager
                    .Module__MilestoneManager__InvalidDuration
                    .selector
            );
            milestoneManager.addMilestone(
                invalids[i], BUDGET, DEFAULT_CONTRIBUTORS, DETAILS
            );
        }
    }

    // Note that there are currently no invalid budgets defined (Issue #97).
    // If this changes:
    // 1. Adjust `createInvalidBudget()` function
    // 2. Add error type to IMilestoneManager
    // 3. Uncomment this test
    //function testAddMilesteonFailsForInvalidBudget() public {
    //    uint[] memory invalids = _createInvalidBudgets();
    //
    //    vm.startPrank(address(_proposal));
    //
    //    for (uint i; i < invalids.length; ++i) {
    //        vm.expectRevert(
    //            IMilestoneManager
    //                .Module__MilestoneManager__InvalidBudget
    //                .selector
    //        );
    //        milestoneManager.__Milestone_addMilestone(
    //            DURATION, invalids[i], DETAILS
    //        );
    //    }
    //}

    // Note that there are currently no invalid details defined.
    // If this changes:
    // 1. Adjust `createInvalidDetails()` function
    // 2. Add error type to IMilestoneManager
    // 3. Uncomment this test
    // function testAddMilestoneFailsForInvalidDetails() public {
    //     string[] memory invalidDetails = _createInvalidDetails();
    //     for (uint i; i < invalidDetails.length; ++i) {
    //         vm.expectRevert(
    //             IMilestoneManager
    //                 .Module__MilestoneManager__InvalidDetails
    //                 .selector
    //         );
    //         milestoneManager.addMilestone(
    //          DURATION, BUDGET, DEFAULT_CONTRIBUTORS, TITLE, invalidDetails[i]
    //         );
    //     }
    // }

    function testAddMilestoneFailsIfContributorsListEmpty() public {
        IMilestoneManager.Contributor[] memory emptyContribs;

        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManager__InvalidContributorAmount
                .selector
        );
        milestoneManager.addMilestone(DURATION, BUDGET, emptyContribs, DETAILS);
    }

    function testAddMilestoneFailsIfContributorsListTooBig() public {
        IMilestoneManager.Contributor[] memory contribs =
            new IMilestoneManager.Contributor[](MAX_CONTRIBUTORS + 1);

        for (uint i; i < contribs.length; ++i) {
            //It should revert even before we notice the contributor list is invalid
            contribs[i] = ALICE;
        }

        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManager__InvalidContributorAmount
                .selector
        );
        milestoneManager.addMilestone(DURATION, BUDGET, contribs, DETAILS);
    }

    function testAddMilestoneFailsForDuplicateContributors() public {
        IMilestoneManager.Contributor[] memory contribs =
            new IMilestoneManager.Contributor[](3);

        contribs[0] = ALICE;
        contribs[1] = BOB;
        contribs[2] = ALICE;

        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManager__DuplicateContributorAddress
                .selector
        );
        milestoneManager.addMilestone(DURATION, BUDGET, contribs, DETAILS);
    }

    function testAddMilestoneFailsForInvalidContributorAddresses() public {
        IMilestoneManager.Contributor[] memory contribs =
            new IMilestoneManager.Contributor[](3);

        contribs[0] = ALICE;
        contribs[1] = BOB;
        contribs[2] = ALICE;
        contribs[2].addr = address(_proposal);

        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManager__InvalidContributorAddress
                .selector
        );
        milestoneManager.addMilestone(DURATION, BUDGET, contribs, DETAILS);

        contribs[2].addr = address(0);

        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManager__InvalidContributorAddress
                .selector
        );
        milestoneManager.addMilestone(DURATION, BUDGET, contribs, DETAILS);

        contribs[2].addr = address(milestoneManager);

        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManager__InvalidContributorAddress
                .selector
        );
        milestoneManager.addMilestone(DURATION, BUDGET, contribs, DETAILS);
    }

    function testAddMilestoneFailsForInvalidSalarySum() public {
        IMilestoneManager.Contributor[] memory contribs =
            new IMilestoneManager.Contributor[](2);

        contribs[0] = ALICE;
        contribs[1] = BOB;
        contribs[1].salary = 51_000_000;

        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManager__InvalidSalarySum
                .selector
        );
        milestoneManager.addMilestone(DURATION, BUDGET, contribs, DETAILS);
    }

    //----------------------------------
    // Test: removeMilestone()

    function testRemoveMilestone(uint amount) public {
        amount = bound(amount, 1, MAX_MILESTONES);

        // Fill list with milestones.
        for (uint i; i < amount; ++i) {
            milestoneManager.addMilestone(
                DURATION, BUDGET, DEFAULT_CONTRIBUTORS, DETAILS
            );
        }

        // Remove milestones from the front, i.e. lowest milestone id, until
        // list is empty.
        for (uint i; i < amount; ++i) {
            uint id = i + 1; // Note that id's start at 1.

            vm.expectEmit(true, true, true, true);
            emit MilestoneRemoved(id);

            milestoneManager.removeMilestone(_SENTINEL, id);
            assertEq(milestoneManager.listMilestoneIds().length, amount - i - 1);
        }

        // Fill list again with milestones.
        for (uint i; i < amount; ++i) {
            milestoneManager.addMilestone(
                DURATION, BUDGET, DEFAULT_CONTRIBUTORS, DETAILS
            );
        }

        // Remove milestones from the back, i.e. highest milestone id, until
        // list is empty.
        for (uint i; i < amount; ++i) {
            // Note that id's start at 1.
            uint prevId = amount - i - 1;
            uint id = amount - i;

            // Note that removing the last milestone requires the sentinel as
            // prevId.
            if (prevId == 0) {
                prevId = _SENTINEL;
            }

            vm.expectEmit(true, true, true, true);
            emit MilestoneRemoved(id);

            milestoneManager.removeMilestone(prevId, id);
            assertEq(milestoneManager.listMilestoneIds().length, amount - i - 1);
        }
    }

    function testRemoveMilestoneFailsIfCallerNotAuthorizedOrOwner(
        address caller
    ) public {
        _authorizer.setIsAuthorized(caller, false);
        vm.assume(caller != _proposal.owner());

        vm.prank(caller);
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

    function testRemoveMilestoneFailsIfNotConsecutiveMilestonesGiven(
        uint notPrevId
    ) public {
        vm.assume(notPrevId != _SENTINEL);

        uint id = milestoneManager.addMilestone(
            DURATION, BUDGET, DEFAULT_CONTRIBUTORS, DETAILS
        );

        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManager__MilestonesNotConsecutive
                .selector
        );
        milestoneManager.removeMilestone(notPrevId, id);
    }

    function testRemoveMilestoneFailsIfMilestoneActive(
        address[] memory contributors
    ) public {
        IMilestoneManager.Contributor[] memory contribs =
            _generateEqualContributors(contributors);

        // Mint tokens to proposal.
        // Note that these tokens are transfered to the milestone module
        // when the payment orders are created.
        _token.mint(address(_proposal), BUDGET);

        uint id =
            milestoneManager.addMilestone(DURATION, BUDGET, contribs, DETAILS);

        // We wait for the timelock to pass
        vm.warp(block.timestamp + TIMELOCK + 1);

        milestoneManager.startNextMilestone();

        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManager__MilestoneNotRemovable
                .selector
        );
        milestoneManager.removeMilestone(_SENTINEL, id);
    }

    //----------------------------------
    // Test: startNextMilestone()

    function testStartNextMilestone(address[] memory contributors) public {
        IMilestoneManager.Contributor[] memory contribs =
            _generateEqualContributors(contributors);

        // Mint tokens to proposal.
        // Note that these tokens are transfered to the milestone module
        // when the payment orders are created.
        _token.mint(address(_proposal), BUDGET);

        uint id =
            milestoneManager.addMilestone(DURATION, BUDGET, contribs, DETAILS);

        // Add a second milestone to make sure the correct one, i.e. first
        // added, is started.
        milestoneManager.addMilestone(
            DURATION + 1, BUDGET + 1, contribs, "Details2"
        );

        // We wait for the timelock to pass
        vm.warp(block.timestamp + TIMELOCK + 1);

        milestoneManager.startNextMilestone();

        // Check that milestone started.
        assertEq(
            milestoneManager.getMilestoneInformation(id).startTimestamp,
            block.timestamp
        );

        // Check that payment orders were added correctly.
        IPaymentClient.PaymentOrder[] memory orders =
            milestoneManager.paymentOrders();

        assertEq(orders.length, contributors.length);

        //control how much we expect the payouts to be
        uint[] memory payouts = new uint[](contribs.length);
        for (uint i; i < contribs.length; ++i) {
            uint bufPayout;
            bufPayout = (BUDGET / SALARY_PRECISION) * contribs[i].salary;
            payouts[i] = bufPayout;
        }

        // control the total amount being paid out.
        uint totalCount;

        for (uint i; i < orders.length; ++i) {
            totalCount += orders[i].amount;
            assertEq(orders[i].recipient, contribs[i].addr);
            assertEq(orders[i].amount, payouts[i]);
            assertEq(orders[i].createdAt, block.timestamp);
            assertEq(orders[i].dueTo, DURATION);
        }

        // Check that we are indeed paying out the full budget
        assertTrue(totalCount == BUDGET);

        // Check that milestoneManager's token balance is sufficient for the
        // payment orders.
        assertTrue(_token.balanceOf(address(milestoneManager)) == totalCount);
    }

    function testStartNextMilestoneFailsIfCallerNotAuthorizedOrOwner(
        address caller
    ) public {
        _authorizer.setIsAuthorized(caller, false);
        vm.assume(caller != _proposal.owner());

        milestoneManager.addMilestone(
            DURATION, BUDGET, DEFAULT_CONTRIBUTORS, DETAILS
        );

        // We wait for the timelock to pass
        vm.warp(block.timestamp + TIMELOCK + 1);

        vm.prank(caller);
        vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
        milestoneManager.startNextMilestone();
    }

    function testStartNextMilestoneFailsIfNextMilestoneNotActivatable()
        public
    {
        // Fails due to no current active milestone.
        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManager__MilestoneNotActivateable
                .selector
        );
        milestoneManager.startNextMilestone();
    }

    function testStartNextMilestoneFailsIfTransferOfTokensFromProposalFailed(
        address[] memory contributors
    ) public {
        IMilestoneManager.Contributor[] memory contribs =
            _generateEqualContributors(contributors);

        milestoneManager.addMilestone(DURATION, BUDGET, contribs, DETAILS);

        // We wait for the timelock to pass
        vm.warp(block.timestamp + TIMELOCK + 1);

        vm.expectRevert(
            IPaymentClient.Module__PaymentClient__TokenTransferFailed.selector
        );
        milestoneManager.startNextMilestone();
    }

    //----------------------------------
    // Test: updateMilestone()

    function testUpdateMilestone(
        uint duration,
        uint budget,
        bytes memory details,
        address[] memory contributors
    ) public {
        _assumeValidDuration(duration);
        _assumeValidBudgets(budget);
        _assumeValidDetails(details);

        IMilestoneManager.Contributor[] memory contribs =
            _generateEqualContributors(contributors);

        uint id = milestoneManager.addMilestone(
            DURATION, BUDGET, DEFAULT_CONTRIBUTORS, DETAILS
        );

        vm.expectEmit(true, true, true, true);
        emit MilestoneUpdated(id, DURATION, BUDGET, contribs, DETAILS);

        milestoneManager.updateMilestone(
            id, DURATION, BUDGET, contribs, DETAILS
        );

        _assertMilestone(id, DURATION, BUDGET, contribs, DETAILS, "", false);
    }

    function testUpdateMilestoneOneByOne(
        uint duration,
        uint budget,
        bytes memory details,
        address[] memory contributors
    ) public {
        _assumeValidDuration(duration);
        _assumeValidBudgets(budget);
        _assumeValidDetails(details);

        IMilestoneManager.Contributor[] memory contribs =
            _generateEqualContributors(contributors);

        uint id = milestoneManager.addMilestone(
            DURATION, BUDGET, DEFAULT_CONTRIBUTORS, DETAILS
        );

        // update duration

        vm.expectEmit(true, true, true, true);
        emit MilestoneUpdated(
            id, duration, BUDGET, DEFAULT_CONTRIBUTORS, DETAILS
            );

        milestoneManager.updateMilestone(
            id, duration, BUDGET, DEFAULT_CONTRIBUTORS, DETAILS
        );

        // update budget

        vm.expectEmit(true, true, true, true);
        emit MilestoneUpdated(
            id, duration, budget, DEFAULT_CONTRIBUTORS, DETAILS
            );

        milestoneManager.updateMilestone(
            id, duration, budget, DEFAULT_CONTRIBUTORS, DETAILS
        );

        // update contributors

        vm.expectEmit(true, true, true, true);
        emit MilestoneUpdated(id, duration, budget, contribs, DETAILS);

        milestoneManager.updateMilestone(
            id, duration, budget, contribs, DETAILS
        );

        // update details

        vm.expectEmit(true, true, true, true);
        emit MilestoneUpdated(id, duration, budget, contribs, details);

        milestoneManager.updateMilestone(
            id, duration, budget, contribs, details
        );

        // check everything ended up ok

        _assertMilestone(id, duration, budget, contribs, details, "", false);
    }

    function testUpdateMilestoneFailsIfCallerNotAuthorizedOrOwner(
        address caller
    ) public {
        _authorizer.setIsAuthorized(caller, false);
        vm.assume(caller != _proposal.owner());

        uint id = milestoneManager.addMilestone(
            DURATION, BUDGET, DEFAULT_CONTRIBUTORS, DETAILS
        );

        vm.prank(caller);
        vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
        milestoneManager.updateMilestone(
            id, DURATION, BUDGET, DEFAULT_CONTRIBUTORS, DETAILS
        );
    }

    function testUpdateMilestoneFailsForInvalidId() public {
        uint id = milestoneManager.addMilestone(
            DURATION, BUDGET, DEFAULT_CONTRIBUTORS, DETAILS
        );

        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManager__InvalidMilestoneId
                .selector
        );
        milestoneManager.updateMilestone(
            id + 1, DURATION, BUDGET, DEFAULT_CONTRIBUTORS, DETAILS
        );
    }

    function testUpdateMilestoneFailsForInvalidDuration() public {
        uint id = milestoneManager.addMilestone(
            DURATION, BUDGET, DEFAULT_CONTRIBUTORS, DETAILS
        );

        uint[] memory invalids = _createInvalidDurations();

        for (uint i; i < invalids.length; ++i) {
            vm.expectRevert(
                IMilestoneManager
                    .Module__MilestoneManager__InvalidDuration
                    .selector
            );
            milestoneManager.updateMilestone(
                id, invalids[i], BUDGET, DEFAULT_CONTRIBUTORS, DETAILS
            );
        }
    }

    // Note that there are currently no invalid budgets defined (Issue #97).
    // If this changes:
    // 1. Adjust `createInvalidBudget()` function
    // 2. Add error type to IMilestoneManager
    // 3. Uncomment this test
    //function testUpdateMilestoneFailsForInvalidBudget() public {
    //    uint id =
    //        milestoneManager.addMilestone(DURATION, BUDGET, DEFAULT_CONTRIBUTORS, DETAILS);
    //
    //    uint[] memory invalids = _createInvalidBudgets();
    //
    //    for (uint i; i < invalids.length; ++i) {
    //        vm.expectRevert(IMilestoneManager.Module__MilestoneManager__InvalidBudgets.selector);
    //        milestoneManager.updateMilestone(id, DURATION, invalids[i], DEFAULT_CONTRIBUTORS, DETAILS);
    //    }
    //}

    // Note that there are currently no invalid details defined.
    // If this changes:
    // 1. Adjust `createInvalidDetails()` function
    // 2. Add error type to IMilestoneManager
    // 3. Uncomment this test
    // function testUpdateMilestoneFailsForInvalidDetails() public {
    //     uint id = milestoneManager.addMilestone(
    //         DURATION, BUDGET, DEFAULT_CONTRIBUTORS, DETAILS
    //     );

    //     bytes32[] memory invalids = _createInvalidDetails();

    //     for (uint i; i < invalids.length; ++i) {
    //         vm.expectRevert(
    //             IMilestoneManager
    //                 .Module__MilestoneManager__InvalidDetails
    //                 .selector
    //         );
    //         milestoneManager.updateMilestone(
    //             id, DURATION, BUDGET, DEFAULT_CONTRIBUTORS, invalids[i]
    //         );
    //     }
    // }

    function testUpdateMilestoneFailsIfMilestoneAlreadyStarted(
        address[] memory contributors
    ) public {
        IMilestoneManager.Contributor[] memory contribs =
            _generateEqualContributors(contributors);

        // Mint tokens to proposal.
        // Note that these tokens are transfered to the milestone module
        // when the payment orders are created.
        _token.mint(address(_proposal), BUDGET);

        uint id =
            milestoneManager.addMilestone(DURATION, BUDGET, contribs, DETAILS);

        // We wait for the timelock to pass
        vm.warp(block.timestamp + TIMELOCK + 1);

        milestoneManager.startNextMilestone();

        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManager__MilestoneNotUpdateable
                .selector
        );
        milestoneManager.updateMilestone(
            id, DURATION, BUDGET, contribs, DETAILS
        );
    }

    //----------------------------------
    // Test: moveMilestoneInList()

    function testMoveMilestoneInList(
        uint amountOfMilestones,
        uint moveId,
        uint moveToId
    ) public {
        amountOfMilestones = bound(amountOfMilestones, 2, 30);
        vm.assume(moveId != moveToId);

        vm.assume(moveId != 0 && moveId < amountOfMilestones + 1);

        //MoveToId can be SENTINEL
        if (moveToId != type(uint).max) {
            vm.assume(moveToId != 0 && moveToId < amountOfMilestones + 1);
        }

        for (uint i = 0; i < amountOfMilestones; ++i) {
            milestoneManager.addMilestone(
                DURATION, BUDGET, DEFAULT_CONTRIBUTORS, DETAILS
            );
        }

        uint prevId = milestoneManager.getPreviousMilestoneId(moveId);
        vm.assume(moveToId != prevId);

        milestoneManager.moveMilestoneInList(moveId, prevId, moveToId);

        assertTrue(_getPositionAfter(moveToId) == moveId);
        assertTrue(_getPositionAfter(prevId) != moveId);

        //Check if _last is set correctly

        //New Milestone should have last position and therefor link to SENTINEL
        assertTrue(
            _getPositionAfter(
                milestoneManager.addMilestone(
                    DURATION, BUDGET, DEFAULT_CONTRIBUTORS, DETAILS
                )
            ) == type(uint).max
        );
    }

    function testMoveMilestoneForInvalidId() public {
        milestoneManager.addMilestone(
            DURATION, BUDGET, DEFAULT_CONTRIBUTORS, DETAILS
        );

        uint id = milestoneManager.addMilestone(
            DURATION, BUDGET, DEFAULT_CONTRIBUTORS, DETAILS
        );

        uint prevId = milestoneManager.getPreviousMilestoneId(id);

        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManager__InvalidMilestoneId
                .selector
        ); //Move after Sentinel
        milestoneManager.moveMilestoneInList(id + 1, prevId, type(uint).max);
    }

    function testMoveMilestoneForInvalidPosition() public {
        milestoneManager.addMilestone(
            DURATION, BUDGET, DEFAULT_CONTRIBUTORS, DETAILS
        );

        uint id = milestoneManager.addMilestone(
            DURATION, BUDGET, DEFAULT_CONTRIBUTORS, DETAILS
        );

        uint prevId = milestoneManager.getPreviousMilestoneId(id);

        vm.expectRevert(
            IMilestoneManager.Module__MilestoneManager__InvalidPosition.selector
        );
        milestoneManager.moveMilestoneInList(id, prevId, 0);

        vm.expectRevert(
            IMilestoneManager.Module__MilestoneManager__InvalidPosition.selector
        );
        milestoneManager.moveMilestoneInList(id, 0, type(uint).max);
    }

    function testMoveMilestoneForInvalidIntermediatePosition(
        address[] memory contributors
    ) public {
        IMilestoneManager.Contributor[] memory contribs =
            _generateEqualContributors(contributors);

        _token.mint(address(_proposal), BUDGET);

        milestoneManager.addMilestone(DURATION, BUDGET, contribs, DETAILS);

        uint id =
            milestoneManager.addMilestone(DURATION, BUDGET, contribs, DETAILS);

        uint prevId = milestoneManager.getPreviousMilestoneId(id);

        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManager__InvalidIntermediatePosition
                .selector
        );
        milestoneManager.moveMilestoneInList(id, prevId, id);

        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManager__InvalidIntermediatePosition
                .selector
        );
        milestoneManager.moveMilestoneInList(id, prevId, prevId);

        // We wait for the timelock to pass
        vm.warp(block.timestamp + TIMELOCK + 1);

        milestoneManager.startNextMilestone();

        //Cant move a milestone that already started
        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManager__InvalidIntermediatePosition
                .selector
        );
        milestoneManager.moveMilestoneInList(1, prevId, 2);

        //Check Cant move before a milestone that has started at some point
        //In this case id 1
        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManager__InvalidIntermediatePosition
                .selector
        );
        milestoneManager.moveMilestoneInList(id, prevId, type(uint).max);
    }

    //----------------------------------
    // Test: submitMilestone()

    function testSubmitMilestone(
        address[] memory contributors,
        bytes calldata submissionData
    ) public {
        IMilestoneManager.Contributor[] memory contribs =
            _generateEqualContributors(contributors);

        vm.assume(submissionData.length != 0);

        // Mint tokens to proposal.
        // Note that these tokens are transfered to the milestone module
        // when the payment orders are created.
        _token.mint(address(_proposal), BUDGET);

        uint id =
            milestoneManager.addMilestone(DURATION, BUDGET, contribs, DETAILS);

        // We wait for the timelock to pass
        vm.warp(block.timestamp + TIMELOCK + 1);

        milestoneManager.startNextMilestone();

        // Milestone must be submitted by a contributor.
        vm.prank(contributors[0]);
        milestoneManager.submitMilestone(id, submissionData);

        assertTrue(
            milestoneManager.getMilestoneInformation(id).submissionData.length
                != 0
        );
        assertTrue(
            keccak256(
                milestoneManager.getMilestoneInformation(id).submissionData
            ) == keccak256(submissionData)
        );
    }

    function testSubmitMilestoneSubmissionDataNotChangeable(
        address[] memory contributors,
        bytes calldata submissionData1,
        bytes calldata submissionData2
    ) public {
        IMilestoneManager.Contributor[] memory contribs =
            _generateEqualContributors(contributors);

        vm.assume(submissionData1.length != 0);
        vm.assume(submissionData2.length != 0);
        //Assume submissionData 1 and 2 is different
        vm.assume(keccak256(submissionData1) != keccak256(submissionData2));

        // Mint tokens to proposal.
        // Note that these tokens are transfered to the milestone module
        // when the payment orders are created.
        _token.mint(address(_proposal), BUDGET);

        uint id =
            milestoneManager.addMilestone(DURATION, BUDGET, contribs, DETAILS);

        // We wait for the timelock to pass
        vm.warp(block.timestamp + TIMELOCK + 1);

        milestoneManager.startNextMilestone();

        // Milestone must be submitted by a contributor.
        vm.prank(contributors[0]);
        //submit submissionData1
        milestoneManager.submitMilestone(id, submissionData1);

        //assert that submissionData is submissionData1
        assertTrue(
            keccak256(
                milestoneManager.getMilestoneInformation(id).submissionData
            ) == keccak256(submissionData1)
        );

        // Milestone must be submitted by a contributor.
        vm.prank(contributors[0]);
        //submit submissionData2
        milestoneManager.submitMilestone(id, submissionData1);

        //assert that submissionData did not change
        assertEq(
            keccak256(
                milestoneManager.getMilestoneInformation(id).submissionData
            ),
            keccak256(submissionData1)
        );
    }

    function testSubmitMilestoneFailsIfCallerNotContributor(
        address[] memory contributors
    ) public {
        IMilestoneManager.Contributor[] memory contribs =
            _generateEqualContributors(contributors);
        _assumeElemNotInSet(contributors, address(this));

        // Mint tokens to proposal.
        // Note that these tokens are transfered to the milestone module
        // when the payment orders are created.
        _token.mint(address(_proposal), BUDGET);

        uint id =
            milestoneManager.addMilestone(DURATION, BUDGET, contribs, DETAILS);

        // We wait for the timelock to pass
        vm.warp(block.timestamp + TIMELOCK + 1);

        milestoneManager.startNextMilestone();

        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManager__OnlyCallableByContributor
                .selector
        );
        milestoneManager.submitMilestone(id, "");
    }

    function testSubmitMilestoneFailsForInvalidId(address[] memory contributors)
        public
    {
        IMilestoneManager.Contributor[] memory contribs =
            _generateEqualContributors(contributors);

        // Mint tokens to proposal.
        // Note that these tokens are transfered to the milestone module
        // when the payment orders are created.
        _token.mint(address(_proposal), BUDGET);

        uint id =
            milestoneManager.addMilestone(DURATION, BUDGET, contribs, DETAILS);

        // We wait for the timelock to pass
        vm.warp(block.timestamp + TIMELOCK + 1);

        milestoneManager.startNextMilestone();

        // Milestone must be submitted by a contributor.
        vm.prank(contributors[0]);
        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManager__InvalidMilestoneId
                .selector
        );
        milestoneManager.submitMilestone(id + 1, "");
    }

    function testSubmitMilestoneFailsForInvalidSubmissionData(
        address[] memory contributors
    ) public {
        IMilestoneManager.Contributor[] memory contribs =
            _generateEqualContributors(contributors);

        // Mint tokens to proposal.
        // Note that these tokens are transfered to the milestone module
        // when the payment orders are created.
        _token.mint(address(_proposal), BUDGET);

        uint id =
            milestoneManager.addMilestone(DURATION, BUDGET, contribs, DETAILS);

        // We wait for the timelock to pass
        vm.warp(block.timestamp + TIMELOCK + 1);

        milestoneManager.startNextMilestone();

        // Milestone must be submitted by a contributor.
        vm.prank(contributors[0]);
        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManage__InvalidSubmissionData
                .selector
        );
        milestoneManager.submitMilestone(id, "");
    }

    function testSubmitMilestoneFailsIfMilestoneNotYetStarted(
        address[] memory contributors
    ) public {
        IMilestoneManager.Contributor[] memory contribs =
            _generateEqualContributors(contributors);

        // Mint tokens to proposal.
        // Note that these tokens are transfered to the milestone module
        // when the payment orders are created.
        _token.mint(address(_proposal), BUDGET);

        uint id =
            milestoneManager.addMilestone(DURATION, BUDGET, contribs, DETAILS);

        // Note that the milestone was not started.

        // Milestone must be submitted by a contributor.
        vm.prank(contributors[0]);
        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManager__MilestoneNotSubmitable
                .selector
        );
        milestoneManager.submitMilestone(id, SUBMISSION_DATA);
    }

    function testSubmitMilestoneFailsIfMilestoneAlreadyCompleted(
        address[] memory contributors
    ) public {
        IMilestoneManager.Contributor[] memory contribs =
            _generateEqualContributors(contributors);

        // Mint tokens to proposal.
        // Note that these tokens are transfered to the milestone module
        // when the payment orders are created.
        _token.mint(address(_proposal), BUDGET);

        uint id =
            milestoneManager.addMilestone(DURATION, BUDGET, contribs, DETAILS);

        // We wait for the timelock to pass
        vm.warp(block.timestamp + TIMELOCK + 1);

        milestoneManager.startNextMilestone();

        // Milestone must be submitted by a contributor.
        vm.prank(contributors[0]);
        milestoneManager.submitMilestone(id, SUBMISSION_DATA);

        // Note that milestone gets completed.
        milestoneManager.completeMilestone(id);

        // Milestone must be submitted by a contributor.
        vm.prank(contributors[0]);
        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManager__MilestoneNotSubmitable
                .selector
        );
        milestoneManager.submitMilestone(id, SUBMISSION_DATA);
    }

    //----------------------------------
    // Test: completeMilestone()

    function testCompleteMilestone(address[] memory contributors) public {
        IMilestoneManager.Contributor[] memory contribs =
            _generateEqualContributors(contributors);

        // Mint tokens to proposal.
        // Note that these tokens are transfered to the milestone module
        // when the payment orders are created.
        _token.mint(address(_proposal), BUDGET);

        uint id =
            milestoneManager.addMilestone(DURATION, BUDGET, contribs, DETAILS);

        // We wait for the timelock to pass
        vm.warp(block.timestamp + TIMELOCK + 1);

        milestoneManager.startNextMilestone();

        // Milestone must be submitted by a contributor.
        vm.prank(contributors[0]);
        milestoneManager.submitMilestone(id, SUBMISSION_DATA);

        milestoneManager.completeMilestone(id);
        assertTrue(milestoneManager.getMilestoneInformation(id).completed);
    }

    function testCompleteMilestoneFailsIfCallerNotAuthorizedOrOwner(
        address caller,
        address[] memory contributors
    ) public {
        _authorizer.setIsAuthorized(caller, false);
        vm.assume(caller != _proposal.owner());

        IMilestoneManager.Contributor[] memory contribs =
            _generateEqualContributors(contributors);

        // Mint tokens to proposal.
        // Note that these tokens are transfered to the milestone module
        // when the payment orders are created.
        _token.mint(address(_proposal), BUDGET);

        uint id =
            milestoneManager.addMilestone(DURATION, BUDGET, contribs, DETAILS);

        // We wait for the timelock to pass
        vm.warp(block.timestamp + TIMELOCK + 1);

        milestoneManager.startNextMilestone();

        // Milestone must be submitted by a contributor.
        vm.prank(contributors[0]);
        milestoneManager.submitMilestone(id, SUBMISSION_DATA);

        vm.prank(caller);
        vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
        milestoneManager.completeMilestone(id);
    }

    function testCompleteMilestoneFailsForInvalidId(
        address[] memory contributors
    ) public {
        IMilestoneManager.Contributor[] memory contribs =
            _generateEqualContributors(contributors);

        // Mint tokens to proposal.
        // Note that these tokens are transfered to the milestone module
        // when the payment orders are created.
        _token.mint(address(_proposal), BUDGET);

        uint id =
            milestoneManager.addMilestone(DURATION, BUDGET, contribs, DETAILS);

        // We wait for the timelock to pass
        vm.warp(block.timestamp + TIMELOCK + 1);

        milestoneManager.startNextMilestone();

        // Milestone must be submitted by a contributor.
        vm.prank(contributors[0]);
        milestoneManager.submitMilestone(id, SUBMISSION_DATA);

        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManager__InvalidMilestoneId
                .selector
        );
        milestoneManager.completeMilestone(id + 1);
    }

    function testCompleteMilestoneFailsIfMilestoneNotYetSubmitted(
        address[] memory contributors
    ) public {
        IMilestoneManager.Contributor[] memory contribs =
            _generateEqualContributors(contributors);

        // Mint tokens to proposal.
        // Note that these tokens are transfered to the milestone module
        // when the payment orders are created.
        _token.mint(address(_proposal), BUDGET);

        uint id =
            milestoneManager.addMilestone(DURATION, BUDGET, contribs, DETAILS);

        // We wait for the timelock to pass
        vm.warp(block.timestamp + TIMELOCK + 1);

        milestoneManager.startNextMilestone();

        // Note that the milestone does not get submitted.

        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManager__MilestoneNotCompleteable
                .selector
        );
        milestoneManager.completeMilestone(id);
    }

    //----------------------------------
    // Test: declineMilestone()

    function testDeclineMilestone(address[] memory contributors) public {
        IMilestoneManager.Contributor[] memory contribs =
            _generateEqualContributors(contributors);

        // Mint tokens to proposal.
        // Note that these tokens are transfered to the milestone module
        // when the payment orders are created.
        _token.mint(address(_proposal), BUDGET);

        uint id =
            milestoneManager.addMilestone(DURATION, BUDGET, contribs, DETAILS);

        // We wait for the timelock to pass
        vm.warp(block.timestamp + TIMELOCK + 1);

        milestoneManager.startNextMilestone();

        // Milestone must be submitted by a contributor.
        vm.prank(contributors[0]);
        milestoneManager.submitMilestone(id, SUBMISSION_DATA);

        milestoneManager.declineMilestone(id);
        assertEq(
            milestoneManager.getMilestoneInformation(id).submissionData.length,
            0
        );
    }

    function testDeclineMilestoneFailsIfCallerNotAuthorized(
        address caller,
        address[] memory contributors
    ) public {
        _authorizer.setIsAuthorized(caller, false);
        vm.assume(caller != _proposal.owner());

        IMilestoneManager.Contributor[] memory contribs =
            _generateEqualContributors(contributors);

        // Mint tokens to proposal.
        // Note that these tokens are transfered to the milestone module
        // when the payment orders are created.
        _token.mint(address(_proposal), BUDGET);

        uint id =
            milestoneManager.addMilestone(DURATION, BUDGET, contribs, DETAILS);

        // We wait for the timelock to pass
        vm.warp(block.timestamp + TIMELOCK + 1);

        milestoneManager.startNextMilestone();

        // Milestone must be submitted by a contributor.
        vm.prank(contributors[0]);
        milestoneManager.submitMilestone(id, SUBMISSION_DATA);

        vm.prank(caller);
        vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
        milestoneManager.declineMilestone(id);
    }

    function testDeclineMilestoneFailsForInvalidId(
        address[] memory contributors
    ) public {
        IMilestoneManager.Contributor[] memory contribs =
            _generateEqualContributors(contributors);

        // Mint tokens to proposal.
        // Note that these tokens are transfered to the milestone module
        // when the payment orders are created.
        _token.mint(address(_proposal), BUDGET);

        uint id =
            milestoneManager.addMilestone(DURATION, BUDGET, contribs, DETAILS);

        // We wait for the timelock to pass
        vm.warp(block.timestamp + TIMELOCK + 1);

        milestoneManager.startNextMilestone();

        // Milestone must be submitted by a contributor.
        vm.prank(contributors[0]);
        milestoneManager.submitMilestone(id, SUBMISSION_DATA);

        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManager__InvalidMilestoneId
                .selector
        );
        milestoneManager.declineMilestone(id + 1);
    }

    function testDeclineMilestoneFailsIfMilestoneNotYetSubmitted(
        address[] memory contributors
    ) public {
        IMilestoneManager.Contributor[] memory contribs =
            _generateEqualContributors(contributors);

        // Mint tokens to proposal.
        // Note that these tokens are transfered to the milestone module
        // when the payment orders are created.
        _token.mint(address(_proposal), BUDGET);

        uint id =
            milestoneManager.addMilestone(DURATION, BUDGET, contribs, DETAILS);

        // We wait for the timelock to pass
        vm.warp(block.timestamp + TIMELOCK + 1);

        milestoneManager.startNextMilestone();

        // Note that the milestone does not get submitted.

        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManager__MilestoneNotDeclineable
                .selector
        );
        milestoneManager.declineMilestone(id);
    }

    function testDeclineMilestoneFailsIfMilestoneAlreadyCompleted(
        address[] memory contributors
    ) public {
        IMilestoneManager.Contributor[] memory contribs =
            _generateEqualContributors(contributors);

        // Mint tokens to proposal.
        // Note that these tokens are transfered to the milestone module
        // when the payment orders are created.
        _token.mint(address(_proposal), BUDGET);

        uint id =
            milestoneManager.addMilestone(DURATION, BUDGET, contribs, DETAILS);

        // We wait for the timelock to pass
        vm.warp(block.timestamp + TIMELOCK + 1);

        milestoneManager.startNextMilestone();

        // Milestone must be submitted by a contributor.
        vm.prank(contributors[0]);
        milestoneManager.submitMilestone(id, SUBMISSION_DATA);

        milestoneManager.completeMilestone(id);

        vm.expectRevert(
            IMilestoneManager
                .Module__MilestoneManager__MilestoneNotDeclineable
                .selector
        );
        milestoneManager.declineMilestone(id);
    }

    //----------------------------------
    // Test Milestone Contributor math

    function testPctMathWithEqualSalary(address[] memory contributors) public {
        IMilestoneManager.Contributor[] memory contribs =
            _generateEqualContributors(contributors);

        uint[] memory payouts = new uint[](contributors.length);

        //we are not using them, but startNextMilestone pulls the tokens
        _token.mint(address(_proposal), BUDGET);

        // Make sure that we generated a valid set of contributor salaries and calculate payouts
        uint precCount;
        uint payoutCount;
        for (uint i; i < contribs.length; ++i) {
            precCount += contribs[i].salary;
            uint bufPayout;
            bufPayout = (
                ((BUDGET * 1e18) / SALARY_PRECISION) * contribs[i].salary
            ) / 1e18;
            payouts[i] = bufPayout;
            payoutCount += bufPayout;
        }
        assertEq(precCount, SALARY_PRECISION);

        milestoneManager.addMilestone(DURATION, BUDGET, contribs, DETAILS);

        // We wait for the timelock to pass
        vm.warp(block.timestamp + TIMELOCK + 1);

        milestoneManager.startNextMilestone();

        //Make sure the values in the payment orders are the same
        // Check that payment orders were added correctly.
        IPaymentClient.PaymentOrder[] memory orders =
            milestoneManager.paymentOrders();

        for (uint i = 1; i < orders.length; ++i) {
            assertEq(orders[i].amount, payouts[i]);
        }

        // Check that we are indeed paying out the full budget
        assertTrue(payoutCount == BUDGET);
    }

    function testPctMathWithDissimilarSalaries(address[] memory contributors)
        public
    {
        IMilestoneManager.Contributor[] memory contribs =
            _generateDissimilarContributors(contributors);

        uint[] memory payouts = new uint[](contributors.length);

        //we are not using them, but startNextMilestone pulls the tokens
        _token.mint(address(_proposal), BUDGET);

        // Make sure that we generated a valid set of contributor salaries and calculate payouts
        uint precCount;
        uint payoutCount;
        for (uint i; i < contribs.length; ++i) {
            precCount += contribs[i].salary;
            uint bufPayout;
            bufPayout = (
                ((BUDGET * 1e18) / SALARY_PRECISION) * contribs[i].salary
            ) / 1e18;
            payouts[i] = bufPayout;
            payoutCount += bufPayout;
        }
        assertEq(precCount, SALARY_PRECISION);

        milestoneManager.addMilestone(DURATION, BUDGET, contribs, DETAILS);

        // We wait for the timelock to pass
        vm.warp(block.timestamp + TIMELOCK + 1);

        milestoneManager.startNextMilestone();

        //Make sure the values in the payment orders are the same
        // Check that payment orders were added correctly.
        IPaymentClient.PaymentOrder[] memory orders =
            milestoneManager.paymentOrders();

        for (uint i = 1; i < orders.length; ++i) {
            assertEq(orders[i].amount, payouts[i]);
        }

        // Check that we are indeed paying out the full budget
        assertTrue(payoutCount == BUDGET);
    }

    //--------------------------------------------------------------------------
    // Assert Helper Functions

    /// @dev Asserts milestone with given data exists.
    function _assertMilestone(
        uint id,
        uint duration,
        uint budget,
        IMilestoneManager.Contributor[] memory contributors,
        bytes memory details,
        bytes memory submissionData,
        bool completed
    ) internal {
        IMilestoneManager.Milestone memory m =
            milestoneManager.getMilestoneInformation(id);

        assertEq(m.duration, duration);
        assertEq(m.budget, budget);

        assertEq(m.contributors.length, contributors.length);
        for (uint i; i < m.contributors.length; ++i) {
            assertEq(m.contributors[i].addr, contributors[i].addr);
            assertEq(m.contributors[i].salary, contributors[i].salary);
        }

        assertTrue(
            keccak256(abi.encodePacked(m.details))
                == keccak256(abi.encodePacked(details))
        );

        assertEq(keccak256(m.submissionData), keccak256(submissionData));
        assertEq(m.completed, completed);
    }

    //--------------------------------------------------------------------------
    // Assume Helper Functions

    function _assumeValidDuration(uint duration) internal {
        _assumeElemNotInSet(_createInvalidDurations(), duration);
    }

    function _assumeValidBudgets(uint budget) internal {
        _assumeElemNotInSet(_createInvalidBudgets(), budget);
    }

    function _assumeValidDetails(bytes memory details) internal {
        _assumeElemNotInSet(_createInvalidDetails(), details);
    }

    //--------------------------------------------------------------------------
    // Data Creation Helper Functions

    /// @dev Returns an element of each category of invalid durations.
    function _createInvalidDurations() internal pure returns (uint[] memory) {
        uint[] memory invalids = new uint256[](1);

        invalids[0] = 0;

        return invalids;
    }

    /// @dev Returns an element of each category of invalid budgets.
    function _createInvalidBudgets() internal pure returns (uint[] memory) {
        uint[] memory invalids = new uint256[](0);

        // Note that there are currently no invalid budgets defined (Issue #97).

        return invalids;
    }

    /// Note that there are currently no invalid details.
    /// @dev Returns an element of each category of invalid details.
    function _createInvalidDetails() internal pure returns (bytes[] memory) {
        bytes[] memory invalidDetails = new bytes[](0);

        // Note that there are currently no invalid details defined.

        return invalidDetails;
    }

    //--------------------------------------------------------------------------
    // Contributor Generation Helper Functions

    function _generateEqualContributors(address[] memory contribs)
        internal
        returns (IMilestoneManager.Contributor[] memory)
    {
        vm.assume(contribs.length != 0);
        vm.assume(contribs.length <= MAX_CONTRIBUTORS);
        assumeValidContributors(contribs);

        IMilestoneManager.Contributor[] memory contributors =
            new IMilestoneManager.Contributor[](contribs.length);

        for (uint i; i < contribs.length; ++i) {
            uint _salary = SALARY_PRECISION / contribs.length;
            IMilestoneManager.Contributor memory _buf =
                IMilestoneManager.Contributor(contribs[i], _salary, "testData");
            contributors[i] = _buf;
        }

        //get rid of rounding errors
        contributors[0].salary += SALARY_PRECISION % contribs.length;

        return contributors;
    }

    IMilestoneManager.Contributor[] diffContributors;

    function _generateDissimilarContributors(address[] memory contribs)
        internal
        returns (IMilestoneManager.Contributor[] memory)
    {
        vm.assume(contribs.length != 0);
        vm.assume(contribs.length <= MAX_CONTRIBUTORS);
        assumeValidContributors(contribs);

        //IMilestoneManager.Contributor[] memory contributors =
        new IMilestoneManager.Contributor[](contribs.length);

        //assign pseudoRandom with until limit
        uint accumSalary;

        for (uint i; i < contribs.length; ++i) {
            uint _salary = pseudoRandomSalary(contribs[i], SALARY_PRECISION);
            if ((accumSalary + _salary) <= SALARY_PRECISION) {
                accumSalary += _salary;
            } else {
                _salary = SALARY_PRECISION - accumSalary;
                accumSalary += _salary;
            }

            IMilestoneManager.Contributor memory _buf =
                IMilestoneManager.Contributor(contribs[i], _salary, "testData");
            diffContributors.push(_buf);

            if (accumSalary == SALARY_PRECISION) {
                return diffContributors;
            }
        }

        //if we arrived here, we didn't "fill out" the budget
        diffContributors[0].salary += (SALARY_PRECISION - accumSalary);

        return diffContributors;
    }

    function pseudoRandomSalary(address addr, uint maxValue)
        public
        pure
        returns (uint)
    {
        bytes memory abiEncodeOutput = abi.encode(addr);
        uint kHashOutput = uint(keccak256(abiEncodeOutput));
        return kHashOutput % maxValue;
    }

    function _getPositionAfter(uint id) private view returns (uint) {
        uint[] memory milestoneList = milestoneManager.listMilestoneIds();

        //If SENTINEL return first position in list
        if (id == type(uint).max) {
            return milestoneList[0];
        }

        uint length = milestoneList.length;
        for (uint i = 0; i < length; ++i) {
            if (id == milestoneList[i]) {
                if (i == (length - 1)) {
                    return type(uint).max;
                } else {
                    return milestoneList[i + 1];
                }
            }
        }

        //This means id was not found in line which should not happen
        assert(false);
    }

    // =========================================================================
    // Copied from proposal/helper/TypeSanityHelper.sol
    // @todo Make TypeSanityHelper globally for test available.

    address private constant _SENTINEL_CONTRIBUTOR = address(0x1);

    mapping(address => bool) contributorCache;

    function assumeValidContributors(address[] memory addrs) public {
        for (uint i; i < addrs.length; ++i) {
            assumeValidContributor(addrs[i]);

            // Assume contributor address unique.
            vm.assume(!contributorCache[addrs[i]]);

            // Add contributor address to cache.
            contributorCache[addrs[i]] = true;
        }
    }

    function assumeValidContributor(address a) public view {
        address[] memory invalids = createInvalidContributors();

        for (uint i; i < invalids.length; ++i) {
            vm.assume(a != invalids[i]);
        }
    }

    function createInvalidContributors()
        public
        view
        returns (address[] memory)
    {
        address[] memory invalids = new address[](4);

        invalids[0] = address(0);
        invalids[1] = _SENTINEL_CONTRIBUTOR;
        invalids[2] = address(_proposal);
        invalids[3] = address(milestoneManager);

        return invalids;
    }
    // =========================================================================
}
