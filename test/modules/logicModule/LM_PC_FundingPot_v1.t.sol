// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Internal
import {
    ModuleTest,
    IModule_v1,
    IOrchestrator_v1
} from "test/modules/ModuleTest.sol";
import {OZErrors} from "test/utils/errors/OZErrors.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

// External
import {Clones} from "@oz/proxy/Clones.sol";

// Tests and Mocks
import {
    IERC20PaymentClientBase_v2,
    ERC20PaymentClientBaseV2Mock,
    ERC20Mock
} from "test/utils/mocks/modules/paymentClient/ERC20PaymentClientBaseV2Mock.sol";

// System under Test (SuT)
import {LM_PC_FundingPot_v1_Exposed} from
    "test/modules/logicModule/LM_PC_FundingPot_v1_Exposed.sol";
import {ILM_PC_FundingPot_v1} from
    "src/modules/logicModule/interfaces/ILM_PC_FundingPot_v1.sol";

import {console2} from "forge-std/console2.sol";
/**
 * @title   Inverter Funding Pot Logic Module Tests
 *
 * @notice  Tests for the funding pot logic module
 *
 * @dev     This test contract follows the standard testing pattern showing:
 *          - Initialization tests
 *          - External function tests
 *          - Internal function tests through exposed functions
 *          - Use of Gherkin for test documentation
 *
 * @author  Inverter Network
 */

contract LM_PC_FundingPot_v1_Test is ModuleTest {
    // -------------------------------------------------------------------------
    // Constants

    bytes32 internal constant FUNDING_POT_ADMIN_ROLE = "FUNDING_POT_ADMIN";

    // -------------------------------------------------------------------------
    // State

    // SuT
    LM_PC_FundingPot_v1_Exposed fundingPot;
    address public fundingPotAdmin = makeAddr("FundingPotAdmin");

    // -------------------------------------------------------------------------
    // Setup

    function setUp() public {
        // Deploy the SuT
        address impl = address(new LM_PC_FundingPot_v1_Exposed());
        fundingPot = LM_PC_FundingPot_v1_Exposed(Clones.clone(impl));

        // Setup the module to test
        _setUpOrchestrator(fundingPot);

        // Initiate the Logic Module with the metadata and config data
        fundingPot.init(_orchestrator, _METADATA, abi.encode(""));

        // Give test contract the DEPOSIT_ADMIN_ROLE.
        fundingPot.grantModuleRole(
            fundingPot.FUNDING_POT_ADMIN_ROLE(), fundingPotAdmin
        );
    }

    // -------------------------------------------------------------------------
    // Test: Initialization

    function testInit() public override(ModuleTest) {
        assertEq(address(fundingPot.orchestrator()), address(_orchestrator));
    }

    function testSupportsInterface() public {
        assertTrue(
            fundingPot.supportsInterface(type(ILM_PC_FundingPot_v1).interfaceId)
        );
        assertTrue(
            fundingPot.supportsInterface(type(ILM_PC_FundingPot_v1).interfaceId)
        );
    }

    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        fundingPot.init(_orchestrator, _METADATA, abi.encode(""));
    }

    function test_fundingPotAdminRoleGranted() public {
        bytes32 roleId = _orchestrator.authorizer().generateRoleId(
            address(fundingPot), fundingPot.FUNDING_POT_ADMIN_ROLE()
        );
        assertTrue(_orchestrator.authorizer().hasRole(roleId, fundingPotAdmin));
    }

    // -------------------------------------------------------------------------
    // Test External (public + external)

    /* Test fuzzed createRound()
        ├── Given a round start time is in the future
        │   ├── And the round end time is either after the start or the round has a cap
        │   │   └── When a new round is created with the given parameters
        │   │       └── Then the stored round details should match the provided values
    */
    function testFuzz_createRound(
        uint roundStart,
        uint roundEnd,
        uint roundCap,
        address hookContract,
        bytes memory hookFunction,
        bool closureMechanism,
        bool globalAccumulativeCaps
    ) public {
        vm.assume(roundStart > block.timestamp);
        vm.assume(roundEnd > roundStart || roundCap > 0);
        if (roundEnd > 0) {
            vm.assume(roundEnd > roundStart);
        }

        uint64 roundId = fundingPot.createRound(
            roundStart,
            roundEnd,
            roundCap,
            hookContract,
            hookFunction,
            closureMechanism,
            globalAccumulativeCaps
        );

        (uint storedStart, uint storedEnd, uint storedCap,,,,, bool isActive) =
            fundingPot.rounds(roundId);

        assertEq(storedStart, roundStart, "Round start mismatch");
        assertEq(storedEnd, roundEnd, "Round end mismatch");
        assertEq(storedCap, roundCap, "Round cap mismatch");
        assertTrue(isActive, "Round should be active");
    }

    /* Test createRound() with invalid start time
        ├── Given a start time that is in the past
        │   └── When attempting to create a round with this past start time
        │       └── Then it should revert with "Round start must be in the future"
    */
    function test_createRound_invalidStart() public {
        uint pastTime = block.timestamp - 1;
        vm.expectRevert(
            ILM_PC_FundingPot_v1
                .Module__LM_PC_FundingPot__RoundStartMustBeInFuture
                .selector
        );
        fundingPot.createRound(
            pastTime, block.timestamp + 10, 1000, address(0), "", false, false
        );
    }

    /* Test createRound() with invalid end time
        ├── Given a future start time
        │   └── When attempting to create a round where end time is before start time and cap is zero
        │       └── Then it should revert with "Round must have either end time or cap"
    */
    function test_createRound_invalidEnd() public {
        uint futureTime = block.timestamp + 100;
        vm.expectRevert(
            ILM_PC_FundingPot_v1
                .Module__LM_PC_FundingPot__RoundMustHaveEndTimeOrCap
                .selector
        );
        fundingPot.createRound(
            futureTime, futureTime - 1, 0, address(0), "", false, false
        );
    }

    /* Test fuzzed editRound()
        ├── Given a round start time is in the future
        │   ├── And the round end time is greater than zero and after the start time
        │   │   └── When editing the round with new parameters
        │   │       ├── Then the update should be successful
        │   │       └── And the stored values should match the new parameters
    */
    function testFuzz_editRound(
        uint roundStart,
        uint roundEnd,
        uint roundCap,
        address hookContract,
        bytes memory hookFunction,
        bool closureMechanism,
        bool globalAccumulativeCaps
    ) public {
        vm.assume(roundStart > block.timestamp);
        vm.assume(roundStart < type(uint).max - 100);
        vm.assume(roundEnd > 0);
        vm.assume(roundEnd > roundStart);
        vm.assume(roundEnd <= type(uint).max - 100);
        vm.assume(roundCap <= type(uint).max - 100);

        uint64 roundId = fundingPot.createRound(
            roundStart,
            roundEnd,
            roundCap,
            hookContract,
            hookFunction,
            closureMechanism,
            globalAccumulativeCaps
        );

        uint newStart = roundStart + 100;
        uint newEnd = roundEnd + 100;
        uint newCap = roundCap + 100;

        bool success = fundingPot.editRound(
            roundId,
            newStart,
            newEnd,
            newCap,
            hookContract,
            hookFunction,
            closureMechanism,
            globalAccumulativeCaps
        );

        assertTrue(success, "Round edit failed");

        (uint storedStart, uint storedEnd, uint storedCap,,,,,) =
            fundingPot.rounds(roundId);
        assertEq(storedStart, newStart, "Updated round start mismatch");
        assertEq(storedEnd, newEnd, "Updated round end mismatch");
        assertEq(storedCap, newCap, "Updated round cap mismatch");
    }

    /* Test editRound() on nonexistent round
        ├── Given a round does not exist
        │   └── When attempting to edit the round
        │       └── Then it should revert with "Round does not exist"
    */
    function test_editRound_nonexistent() public {
        vm.expectRevert(
            ILM_PC_FundingPot_v1
                .Module__LM_PC_FundingPot__RoundDoesNotExist
                .selector
        );
        fundingPot.editRound(
            9999,
            block.timestamp + 100,
            block.timestamp + 200,
            1000,
            address(0),
            "",
            false,
            false
        );
    }

    /* Test editRound() after round has started
        ├── Given a round has been created with a future start time
        │   ├── And time has advanced beyond the start time
        │   │   └── When attempting to edit the round
        │   │       └── Then it should revert with "Round has already started"
    */
    function test_editRound_afterStart() public {
        uint64 roundId = fundingPot.createRound(
            block.timestamp + 10,
            block.timestamp + 100,
            1000,
            address(0),
            "",
            false,
            false
        );

        vm.warp(block.timestamp + 11);

        vm.expectRevert(
            ILM_PC_FundingPot_v1
                .Module__LM_PC_FundingPot__RoundAlreadyStarted
                .selector
        );
        fundingPot.editRound(
            roundId,
            block.timestamp + 20,
            block.timestamp + 200,
            2000,
            address(0),
            "",
            false,
            false
        );
    }

    // -------------------------------------------------------------------------
    // Test: Internal Functions
}
