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
            fundingPot.FUNDING_POT_ADMIN_ROLE(), address(this)
        );
        _authorizer.setIsAuthorized(address(this), true);

        // Set the block timestamp
        vm.warp(block.timestamp + _orchestrator.MODULE_UPDATE_TIMELOCK());
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

    // -------------------------------------------------------------------------
    // Test External (public + external)

    /* Test createRound()
    ├── Given user does not have FUNDING_POT_ADMIN_ROLE
    │   └── When user attempts to create a round
    │       └── Then it should revert
    ├── Given round start time is in the past
    │   └── When user attempts to create a round
    │       └── Then it should revert
    ├── Given round end time is 0 and round cap is 0
    │   └── When user attempts to create a round
    │       └── Then it should revert
    ├── Given round end time is set and round end time is in the past
    │   └── When user attempts to create a round
    │       └── Then it should revert
    ├── Given hook contract is set but hook function is not set
    │   └── When user attempts to create a round
    │       └── Then it should revert
    ├── Given hook function is set but hook contract is not set
    │   └── When user attempts to create a round
    │       └── Then it should revert
    */

    function testFuzzCreateRound_revertsGivenUserIsNotFundingPotAdmin(
        address user_
    ) public {
        vm.assume(user_ != address(0) && user_ != address(this));
        vm.startPrank(user_);
        bytes32 roleId = _authorizer.generateRoleId(
            address(fundingPot), fundingPot.FUNDING_POT_ADMIN_ROLE()
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector, roleId, user_
            )
        );
        ILM_PC_FundingPot_v1.Round memory round = _createDefaultFundingRound();
        _callCreateRound(round);
        vm.stopPrank();
    }

    function testFuzzCreateRound_revertsGivenRoundStartIsInThePast(
        uint roundStart_
    ) public {
        vm.assume(roundStart_ < block.timestamp);
        ILM_PC_FundingPot_v1.Round memory round = _createDefaultFundingRound();
        round.roundStart = roundStart_;
        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundStartMustBeInFuture
                    .selector
            )
        );
        _callCreateRound(round);
    }

    function testFuzzCreateRound_revertsGivenRoundEndTimeAndCapAreBothZero()
        public
    {
        ILM_PC_FundingPot_v1.Round memory round = _createDefaultFundingRound();
        round.roundEnd = 0;
        round.roundCap = 0;
        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundMustHaveEndTimeOrCap
                    .selector
            )
        );
        _callCreateRound(round);
    }

    function testFuzzCreateRound_revertsGivenRoundEndTimeIsBeforeRoundStart(
        uint roundEnd_
    ) public {
        ILM_PC_FundingPot_v1.Round memory round = _createDefaultFundingRound();
        vm.assume(roundEnd_ != 0 && roundEnd_ < round.roundStart);
        round.roundEnd = roundEnd_;
        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundEndMustBeAfterStart
                    .selector
            )
        );
        _callCreateRound(round);
    }

    function testFuzzCreateRound_revertsGivenHookContractIsSetButHookFunctionIsEmpty(
    ) public {
        ILM_PC_FundingPot_v1.Round memory round = _createDefaultFundingRound();
        round.hookContract = address(1);
        round.hookFunction = bytes("");
        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__HookFunctionRequiredWithHookContract
                    .selector
            )
        );
        _callCreateRound(round);
    }

    function testFuzzCreateRound_revertsGivenHookFunctionIsSetButHookContractIsEmpty(
    ) public {
        ILM_PC_FundingPot_v1.Round memory round = _createDefaultFundingRound();
        round.hookContract = address(0);
        round.hookFunction = bytes("test");
        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__HookContractRequiredWithHookFunction
                    .selector
            )
        );
        _callCreateRound(round);
    }

    /* Test createRound()
    ├── Given all the valid parameters are provided
    │   └── When user attempts to create a round
    │       └── Then it should not be active and should return the round id
    */

    function testFuzzCreateRound() public {
        ILM_PC_FundingPot_v1.Round memory round = _createDefaultFundingRound();
        _callCreateRound(round);

        uint64 lastRoundId = fundingPot.getRoundCount();
        ILM_PC_FundingPot_v1.Round memory lastRound =
            fundingPot.getRoundDetails(lastRoundId);

        assertEq(lastRound.isActive, false);
        assertEq(lastRound.roundStart, round.roundStart);
        assertEq(lastRound.roundEnd, round.roundEnd);
        assertEq(lastRound.roundCap, round.roundCap);
        assertEq(lastRound.hookContract, round.hookContract);
        assertEq(lastRound.hookFunction, round.hookFunction);
        assertEq(lastRound.closureMechanism, round.closureMechanism);
        assertEq(lastRound.globalAccumulativeCaps, round.globalAccumulativeCaps);
    }

    /* Test editRound()
    ├── Given user does not have FUNDING_POT_ADMIN_ROLE
    │   └── When user attempts to create a round
    │       └── Then it should revert
    ├── Given round does not exist
    │   └── When user attempts to edit the round
    │       └── Then it should revert
    ├── Given round is active
    │   └── When user attempts to edit the round
    │       └── Then it should revert
    ├── Given round start time is in the past
    │   └── When user attempts to edit a round with the above parameter
    │       └── Then it should revert
    ├── Given round end time is 0 and round cap is 0
    │   └── When user attempts edit a round with the above parameters
    │       └── Then it should revert
    ├── Given round end time is set and round end time is in the past
    │   └── When user attempts to edit a round with the above parameters
    │       └── Then it should revert
    ├── Given hook contract is set but hook function is not set
    │   └── When user attempts to edit a round with the above parameters
    │       └── Then it should revert
    ├── Given hook function is set but hook contract is not set
    │   └── When user attempts to edit a round with the above parameters
    │       └── Then it should revert
    */

    function testFuzzEditRound_revertsGivenUserIsNotFundingPotAdmin(
        address user_
    ) public {
        testFuzzCreateRound();
        vm.startPrank(user_);
        bytes32 roleId = _authorizer.generateRoleId(
            address(fundingPot), fundingPot.FUNDING_POT_ADMIN_ROLE()
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector, roleId, user_
            )
        );
        ILM_PC_FundingPot_v1.Round memory editedRound =
            _createEditedRoundParams();

        _callEditRound(0, editedRound);
        vm.stopPrank();
    }

    function testFuzzEditRound_revertsGivenRoundIsNotCreated() public {
        testFuzzCreateRound();
        ILM_PC_FundingPot_v1.Round memory editedRound =
            _createEditedRoundParams();

        uint64 roundId = fundingPot.getRoundCount();
        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundNotCreated
                    .selector
            )
        );
        _callEditRound(roundId + 1, editedRound);
    }

    function testFuzzEditRound_revertsGivenRoundIsActive(uint roundStart_)
        public
    {
        testFuzzCreateRound();
        uint64 roundId = fundingPot.getRoundCount();

        ILM_PC_FundingPot_v1.Round memory roundDetails =
            fundingPot.getRoundDetails(roundId);

        vm.warp(roundDetails.roundStart + 1);

        ILM_PC_FundingPot_v1.Round memory editedRound =
            _createEditedRoundParams();
        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundAlreadyStarted
                    .selector
            )
        );
        _callEditRound(roundId, editedRound);
    }

    function testFuzzEditRound_revertsGivenRoundStartIsInThePast(
        uint roundStart_
    ) public {
        testFuzzCreateRound();
        uint64 roundId = fundingPot.getRoundCount();

        vm.assume(roundStart_ < block.timestamp);
        ILM_PC_FundingPot_v1.Round memory editedRound =
            _createEditedRoundParams();
        editedRound.roundStart = roundStart_;

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundStartMustBeInFuture
                    .selector
            )
        );

        _callEditRound(roundId, editedRound);
    }

    function testFuzzEditRound_revertsGivenRoundEndTimeAndCapAreBothZero()
        public
    {
        testFuzzCreateRound();
        uint64 roundId = fundingPot.getRoundCount();

        ILM_PC_FundingPot_v1.Round memory editedRound =
            _createEditedRoundParams();
        editedRound.roundEnd = 0;
        editedRound.roundCap = 0;

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundMustHaveEndTimeOrCap
                    .selector
            )
        );

        _callEditRound(roundId, editedRound);
    }

    function testFuzzEditRound_revertsGivenRoundEndTimeIsBeforeRoundStart(
        uint roundEnd_
    ) public {
        testFuzzCreateRound();
        uint64 roundId = fundingPot.getRoundCount();

        ILM_PC_FundingPot_v1.Round memory editedRound =
            _createEditedRoundParams();
        vm.assume(roundEnd_ != 0 && roundEnd_ < editedRound.roundStart);
        editedRound.roundEnd = roundEnd_;

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundEndMustBeAfterStart
                    .selector
            )
        );

        _callEditRound(roundId, editedRound);
    }

    function testFuzzEditRound_revertsGivenHookContractIsSetButHookFunctionIsEmpty(
    ) public {
        testFuzzCreateRound();
        uint64 roundId = fundingPot.getRoundCount();

        ILM_PC_FundingPot_v1.Round memory editedRound =
            _createEditedRoundParams();
        editedRound.hookContract = address(1);
        editedRound.hookFunction = bytes("");

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__HookFunctionRequiredWithHookContract
                    .selector
            )
        );

        _callEditRound(roundId, editedRound);
    }

    function testFuzzEditRound_revertsGivenHookFunctionIsSetButHookContractIsEmpty(
    ) public {
        testFuzzCreateRound();
        uint64 roundId = fundingPot.getRoundCount();

        ILM_PC_FundingPot_v1.Round memory editedRound =
            _createEditedRoundParams();
        editedRound.hookContract = address(0);
        editedRound.hookFunction = bytes("test");

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__HookContractRequiredWithHookFunction
                    .selector
            )
        );

        _callEditRound(roundId, editedRound);
    }

    /* Test editRound()
    ├── Given a round has been created and is not active
    │   └── When an admin provides valid parameters to edit the round
    │       └── Then all the round details should be successfully updated
    │           ├── roundStart should be updated to the new value
    │           ├── roundEnd should be updated to the new value
    │           ├── roundCap should be updated to the new value
    │           ├── hookContract should be updated to the new value
    │           ├── hookFunction should be updated to the new value
    │           ├── closureMechanism should be updated to the new value
    │           └── globalAccumulativeCaps should be updated to the new value
    */

    function testFuzzEditRound() public {
        testFuzzCreateRound();
        uint64 lastRoundId = fundingPot.getRoundCount();

        ILM_PC_FundingPot_v1.Round memory editedRound =
            _createEditedRoundParams();

        _callEditRound(lastRoundId, editedRound);

        ILM_PC_FundingPot_v1.Round memory updatedRound =
            fundingPot.getRoundDetails(lastRoundId);

        assertEq(
            updatedRound.roundStart,
            editedRound.roundStart,
            "roundStart not updated"
        );
        assertEq(
            updatedRound.roundEnd, editedRound.roundEnd, "roundEnd not updated"
        );
        assertEq(
            updatedRound.roundCap, editedRound.roundCap, "roundCap not updated"
        );
        assertEq(
            updatedRound.hookContract,
            editedRound.hookContract,
            "hookContract not updated"
        );
        assertEq(
            keccak256(updatedRound.hookFunction),
            keccak256(editedRound.hookFunction),
            "hookFunction not updated"
        );
        assertEq(
            updatedRound.closureMechanism,
            editedRound.closureMechanism,
            "closureMechanism not updated"
        );
        assertEq(
            updatedRound.globalAccumulativeCaps,
            editedRound.globalAccumulativeCaps,
            "globalAccumulativeCaps not updated"
        );
    }

    // -------------------------------------------------------------------------
    // Test: Internal Functions

    // Helper Functions

    // @notice Creates a default funding round
    // @dev make the parameters fuzzable @TODO Jeffrey
    function _generateFundingRoundParams(
        uint roundStart_,
        uint roundEnd_,
        uint roundCap_,
        address hookContract_,
        bytes memory hookFunction_,
        bool closureMechanism_,
        bool globalAccumulativeCaps_
    ) internal returns (ILM_PC_FundingPot_v1.Round memory) {
        ILM_PC_FundingPot_v1.Round memory round = ILM_PC_FundingPot_v1.Round({
            roundStart: roundStart_,
            roundEnd: roundEnd_,
            roundCap: roundCap_,
            hookContract: hookContract_,
            hookFunction: hookFunction_,
            closureMechanism: closureMechanism_,
            globalAccumulativeCaps: globalAccumulativeCaps_,
            isActive: false
        });
        return round;
    }

    // @notice Creates a default funding round
    function _createDefaultFundingRound()
        internal
        returns (ILM_PC_FundingPot_v1.Round memory)
    {
        return _generateFundingRoundParams(
            block.timestamp + 1 days,
            block.timestamp + 2 days,
            1000,
            address(0),
            bytes(""),
            false,
            false
        );
    }

    // @notice calls the create round function
    function _callCreateRound(ILM_PC_FundingPot_v1.Round memory round)
        internal
    {
        fundingPot.createRound(
            round.roundStart,
            round.roundEnd,
            round.roundCap,
            round.hookContract,
            round.hookFunction,
            round.closureMechanism,
            round.globalAccumulativeCaps
        );
    }

    // @notice Creates a predefined funding round with edited parameters for testing
    function _createEditedRoundParams()
        internal
        returns (ILM_PC_FundingPot_v1.Round memory)
    {
        return _generateFundingRoundParams(
            block.timestamp + 150,
            block.timestamp + 250,
            20,
            address(0x1),
            hex"abcd",
            true,
            true
        );
    }

    // @notice calls the create round function
    function _callEditRound(
        uint64 roundId,
        ILM_PC_FundingPot_v1.Round memory round
    ) internal {
        fundingPot.editRound(
            roundId,
            round.roundStart,
            round.roundEnd,
            round.roundCap,
            round.hookContract,
            round.hookFunction,
            round.closureMechanism,
            round.globalAccumulativeCaps
        );
    }
}
