// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

// Internal
import {
    ModuleTest,
    IModule_v1,
    IOrchestrator_v1
} from "test/modules/ModuleTest.sol";
import {OZErrors} from "test/utils/errors/OZErrors.sol";

// External
import {Clones} from "@oz/proxy/Clones.sol";

// Mocks
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

        // Give test contract the FUNDING_POT_ROLE.
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

    /* Test fuzzed createRound()
    ├── Given user does not have FUNDING_POT_ADMIN_ROLE
    │   └── When user attempts to create a round
    │       └── Then it should revert
    └── Given user has FUNDING_POT_ADMIN_ROLE
    ├── And round start < block.timestamp
    │   └── When user attempts to create a round
    │       └── Then it should revert
    ├── And round end time == 0 
    │   ├── And round cap == 0
    │   │   └── When user attempts to create a round
    │   │       └── Then it should revert
    ├── And round end time is set 
    │   ├── And round end != 0
    │   ├── And round end < round start
    │   │   └── When user attempts to create a round
    │   │       └── Then it should revert
    ├── And hook contract is set but hook function is not set
    │   └── When user attempts to create a round
    │       └── Then it should revert
    ├── And hook function is set but hook contract is not set
    │   └── When user attempts to create a round
    │       └── Then it should revert
    └── Given all the valid parameters are provided
        └── When user attempts to create a round
            └── Then it should not be active and should return the round id
    */

    function testCreateRound_revertsGivenUserIsNotFundingPotAdmin(address user_)
        public
    {
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
        ILM_PC_FundingPot_v1.Round memory round =
            _helper_createDefaultFundingRound();

        _helper_callCreateRound(round);
        vm.stopPrank();
    }

    function testCreateRound_revertsGivenRoundStartIsInThePast(uint roundStart_)
        public
    {
        vm.assume(roundStart_ < block.timestamp);
        ILM_PC_FundingPot_v1.Round memory round =
            _helper_createDefaultFundingRound();
        round.roundStart = roundStart_;
        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundStartMustBeInFuture
                    .selector
            )
        );
        _helper_callCreateRound(round);
    }

    function testCreateRound_revertsGivenRoundEndTimeAndCapAreBothZero()
        public
    {
        ILM_PC_FundingPot_v1.Round memory round =
            _helper_createDefaultFundingRound();
        round.roundEnd = 0;
        round.roundCap = 0;
        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundMustHaveEndTimeOrCap
                    .selector
            )
        );
        _helper_callCreateRound(round);
    }

    function testCreateRound_revertsGivenRoundEndTimeIsBeforeRoundStart(
        uint roundEnd_
    ) public {
        ILM_PC_FundingPot_v1.Round memory round =
            _helper_createDefaultFundingRound();
        vm.assume(roundEnd_ != 0 && roundEnd_ < round.roundStart);
        round.roundEnd = roundEnd_;
        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundEndMustBeAfterStart
                    .selector
            )
        );
        _helper_callCreateRound(round);
    }

    function testCreateRound_revertsGivenHookContractIsSetButHookFunctionIsEmpty(
    ) public {
        ILM_PC_FundingPot_v1.Round memory round =
            _helper_createDefaultFundingRound();
        round.hookContract = address(1);
        round.hookFunction = bytes("");
        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__HookFunctionRequiredWithHookContract
                    .selector
            )
        );
        _helper_callCreateRound(round);
    }

    function testCreateRound_revertsGivenHookFunctionIsSetButHookContractIsEmpty(
    ) public {
        ILM_PC_FundingPot_v1.Round memory round =
            _helper_createDefaultFundingRound();
        round.hookContract = address(0);
        round.hookFunction = bytes("test");
        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__HookContractRequiredWithHookFunction
                    .selector
            )
        );
        _helper_callCreateRound(round);
    }

    /* Test createRound()
    ├── Given all the valid parameters are provided
    │   └── When user attempts to create a round
    │       └── Then it should not be active and should return the round id
    */

    function testCreateRound() public {
        ILM_PC_FundingPot_v1.Round memory round =
            _helper_createDefaultFundingRound();
        _helper_callCreateRound(round);

        uint64 lastRoundId = fundingPot.getRoundCount();
        ILM_PC_FundingPot_v1.Round memory lastRound =
            fundingPot.getRoundDetails(lastRoundId);

        assertEq(lastRound.roundStart, round.roundStart);
        assertEq(lastRound.roundEnd, round.roundEnd);
        assertEq(lastRound.roundCap, round.roundCap);
        assertEq(lastRound.hookContract, round.hookContract);
        assertEq(lastRound.hookFunction, round.hookFunction);
        assertEq(lastRound.closureMechanism, round.closureMechanism);
        assertEq(lastRound.globalAccumulativeCaps, round.globalAccumulativeCaps);
    }

    /* Test fuzzed editRound()
    ├── Given user does not have FUNDING_POT_ADMIN_ROLE
    │   └── When user attempts to edit a round
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
    ├── Given round end time == 0
    │   ├── And round cap == 0
    │   └── When user attempts to edit a round with the above parameters
    │       └── Then it should revert
    ├── Given round end time is set
    │   ├── And round end is before round start
    │   └── When user attempts to edit the round
    │       └── Then it should revert
    ├── Given hook contract is set
    │   ├── And hook function is empty
    │   └── When user attempts to edit the round
    │       └── Then it should revert
    └── Given hook function is set
        ├── And hook contract is empty
            └── When user attempts to edit the round
                └── Then it should revert  
    */

    function testFuzzEditRound_revertsGivenUserIsNotFundingPotAdmin(
        address user_
    ) public {
        testCreateRound();

        uint64 roundId = fundingPot.getRoundCount();

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
            _helper_createEditedRoundParams();

        _helper_callEditRound(roundId, editedRound);
        vm.stopPrank();
    }

    function testFuzzEditRound_revertsGivenRoundIsNotCreated() public {
        testCreateRound();

        uint64 roundId = fundingPot.getRoundCount();

        ILM_PC_FundingPot_v1.Round memory editedRound =
            _helper_createEditedRoundParams();

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundNotCreated
                    .selector
            )
        );
        _helper_callEditRound(roundId + 1, editedRound);
    }

    function testFuzzEditRound_revertsGivenRoundIsActive(uint roundStart_)
        public
    {
        testCreateRound();
        uint64 roundId = fundingPot.getRoundCount();

        ILM_PC_FundingPot_v1.Round memory roundDetails =
            fundingPot.getRoundDetails(roundId);

        vm.warp(roundDetails.roundStart + 1);

        ILM_PC_FundingPot_v1.Round memory editedRound =
            _helper_createEditedRoundParams();
        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundAlreadyStarted
                    .selector
            )
        );
        _helper_callEditRound(roundId, editedRound);
    }

    function testFuzzEditRound_revertsGivenRoundStartIsInThePast(
        uint roundStart_
    ) public {
        testCreateRound();
        uint64 roundId = fundingPot.getRoundCount();

        vm.assume(roundStart_ < block.timestamp);
        ILM_PC_FundingPot_v1.Round memory editedRound =
            _helper_createEditedRoundParams();
        editedRound.roundStart = roundStart_;

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundStartMustBeInFuture
                    .selector
            )
        );

        _helper_callEditRound(roundId, editedRound);
    }

    function testFuzzEditRound_revertsGivenRoundEndTimeAndCapAreBothZero()
        public
    {
        testCreateRound();
        uint64 roundId = fundingPot.getRoundCount();

        ILM_PC_FundingPot_v1.Round memory editedRound =
            _helper_createEditedRoundParams();
        editedRound.roundEnd = 0;
        editedRound.roundCap = 0;

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundMustHaveEndTimeOrCap
                    .selector
            )
        );

        _helper_callEditRound(roundId, editedRound);
    }

    function testFuzzEditRound_revertsGivenRoundEndTimeIsBeforeRoundStart(
        uint roundEnd_
    ) public {
        testCreateRound();
        uint64 roundId = fundingPot.getRoundCount();

        ILM_PC_FundingPot_v1.Round memory editedRound =
            _helper_createEditedRoundParams();
        vm.assume(roundEnd_ != 0 && roundEnd_ < editedRound.roundStart);
        editedRound.roundEnd = roundEnd_;

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundEndMustBeAfterStart
                    .selector
            )
        );

        _helper_callEditRound(roundId, editedRound);
    }

    function testFuzzEditRound_revertsGivenHookContractIsSetButHookFunctionIsEmpty(
    ) public {
        testCreateRound();
        uint64 roundId = fundingPot.getRoundCount();

        ILM_PC_FundingPot_v1.Round memory editedRound =
            _helper_createEditedRoundParams();
        editedRound.hookContract = address(1);
        editedRound.hookFunction = bytes("");

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__HookFunctionRequiredWithHookContract
                    .selector
            )
        );

        _helper_callEditRound(roundId, editedRound);
    }

    function testFuzzEditRound_revertsGivenHookFunctionIsSetButHookContractIsEmpty(
    ) public {
        testCreateRound();
        uint64 roundId = fundingPot.getRoundCount();

        ILM_PC_FundingPot_v1.Round memory editedRound =
            _helper_createEditedRoundParams();
        editedRound.hookContract = address(0);
        editedRound.hookFunction = bytes("test");

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__HookContractRequiredWithHookFunction
                    .selector
            )
        );

        _helper_callEditRound(roundId, editedRound);
    }

    /* Test editRound()
    └── Given a round has been created
    ├── And the round is not active
    └── When an admin provides valid parameters to edit the round
        └── Then all the round details should be successfully updated
            ├── roundStart should be updated to the new value
            ├── roundEnd should be updated to the new value
            ├── roundCap should be updated to the new value
            ├── hookContract should be updated to the new value
            ├── hookFunction should be updated to the new value
            ├── closureMechanism should be updated to the new value
            └── globalAccumulativeCaps should be updated to the new value
    */

    function testEditRound() public {
        testCreateRound();
        uint64 lastRoundId = fundingPot.getRoundCount();

        ILM_PC_FundingPot_v1.Round memory editedRound =
            _helper_createEditedRoundParams();

        _helper_callEditRound(lastRoundId, editedRound);

        ILM_PC_FundingPot_v1.Round memory updatedRound =
            fundingPot.getRoundDetails(lastRoundId);

        assertEq(updatedRound.roundStart, editedRound.roundStart);
        assertEq(updatedRound.roundEnd, editedRound.roundEnd);
        assertEq(updatedRound.roundCap, editedRound.roundCap);
        assertEq(updatedRound.hookContract, editedRound.hookContract);
        assertEq(
            keccak256(updatedRound.hookFunction),
            keccak256(editedRound.hookFunction)
        );
        assertEq(updatedRound.closureMechanism, editedRound.closureMechanism);
        assertEq(
            updatedRound.globalAccumulativeCaps,
            editedRound.globalAccumulativeCaps
        );
    }

    // -------------------------------------------------------------------------
    // Test: Internal Functions

    // Helper Functions

    // @notice Creates a default funding round
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
            globalAccumulativeCaps: globalAccumulativeCaps_
        });
        return round;
    }

    // @notice Creates a default funding round
    function _helper_createDefaultFundingRound()
        internal
        returns (ILM_PC_FundingPot_v1.Round memory)
    {
        //@todo need to randomize the input using vm.bound or vm.assume, do the same for the edited round
        //@33 do you have any input here?
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
    function _helper_callCreateRound(ILM_PC_FundingPot_v1.Round memory round)
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
    function _helper_createEditedRoundParams()
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
    function _helper_callEditRound(
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
