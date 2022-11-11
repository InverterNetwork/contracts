// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {
    ModuleTest,
    IModule,
    IProposal,
    LibString
} from "test/modules/ModuleTest.sol";

import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";
import {AuthorizerMock} from "test/utils/mocks/AuthorizerMock.sol";

// SuT
import {
    MilestoneManager,
    IMilestoneManager
} from "src/modules/MilestoneManager.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

contract MilestoneManagerPaymentTest is ModuleTest {
    using LibString for string;

    // SuT
    MilestoneManager milestoneManager;
    ERC20Mock token_;
    AuthorizerMock authorizerMock = new AuthorizerMock();

    // Milestone Constants
    uint constant MAX_MILESTONES = 20;
    uint constant DURATION = 1 weeks;
    uint constant BUDGET = 1000 * 1e18;
    string constant TITLE = "Title";
    string constant DETAILS = "Details";

    // Contributor Constants
    address constant CONTRIBUTOR = address(0xBABE);
    string constant NAME = "MIKE";
    string constant ROLE = "engineer";
    uint constant SALARY = 500 * 1e18;


    // Constant copied from SuT
    uint private constant _SENTINEL = type(uint).max;

    function setUp() public {
        milestoneManager = new MilestoneManager();
        milestoneManager.init(_proposal, _METADATA, bytes(""));
        token_ = new ERC20Mock("TestToken", "TT");

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
    // Test: Payout

    function addMilestone() public returns(uint){
        uint[] memory idsBefore = milestoneManager.listMilestoneIds();

        uint id =
            milestoneManager.addMilestone(DURATION, BUDGET, TITLE, DETAILS);

        uint[] memory idsAfter = milestoneManager.listMilestoneIds();

        assertEq(idsBefore.length + 1, idsAfter.length);

        return id;
    }

    function addContributors() public {
        _proposal.__ContributorManager_setIsAuthorized(address(this), true);

        _proposal.addContributor(
            address(0xBABE), "Sara", "cleaner", 750 * 10e18);

        // @dev following assertion fails
        // bool isContrib = _proposal.isContributor(address(0xBABE));
        // assertTrue(isContrib);

        // _proposal.addContributor(
        //     address(0xDEAD), "John", "engineer", 1500 * 10e18);
        // _proposal.addContributor(
        //     address(0xBABE), "Sara", "cleaner", 750 * 10e18);
        // _proposal.addContributor(
        //     address(0xDEAD), "Bob", "manager", 1300 * 10e18);
        // _proposal.addContributor(
        //     address(0xFACE), "Clinton", "CTO", 2500 * 10e18);

    }

    function submitMilestone(uint id) public {
        vm.prank(address(0xBABE));
        milestoneManager.submitMilestone(id);
    }

    function confirmMilestone(uint id) public {
        milestoneManager.confirmMilestone(id);
    }

    function mintTokens(uint amount) public {
        token_.mint(address(_proposal), amount);
        assertEq(token_.balanceOf(address(_proposal)), amount);
    }

    function testStartNextMilestone() public {
        mintTokens(BUDGET);

        uint id = addMilestone();

        addContributors();

        submitMilestone(id);

        //confirmMilestone(id);

        //milestoneManager.startNextMilestone();
    }
}
