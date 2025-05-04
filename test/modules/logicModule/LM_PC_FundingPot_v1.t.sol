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
import {ERC721Mock} from
    "test/utils/mocks/modules/logicModules/LM_PC_FundingPot_v2NFTMock.sol";
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";

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
    address contributor1_;
    address contributor2_;
    address contributor3_;

    bytes32 PROOF_ONE =
        0x0fd7c981d39bece61f7499702bf59b3114a90e66b51ba2c53abdf7b62986c00a;
    bytes32 PROOF_TWO =
        0xe5ebd1e1b5a5478a944ecab36a9a954ac3b6b8216875f6524caa7a1d87096576;
    bytes32[] PROOF = [PROOF_ONE, PROOF_TWO];
    bytes32 ROOT =
        0xaa5d581231e596618465a56aa0f5870ba6e20785fe436d5bfb82b08662ccc7c4;

    // -------------------------------------------------------------------------
    // State

    // SuT

    LM_PC_FundingPot_v1_Exposed fundingPot;

    // Storage variables to avoid stack too deep
    uint32 private _testRoundId;

    // Default round parameters for testing
    RoundParams private _defaultRoundParams;
    RoundParams private _editedRoundParams;

    // Struct to hold round parameters
    struct RoundParams {
        uint roundStart;
        uint roundEnd;
        uint roundCap;
        address hookContract;
        bytes hookFunction;
        bool autoClosure;
        ILM_PC_FundingPot_v1.AccumulationMode accumulationMode;
    }

    ERC721Mock mockNFTContract = new ERC721Mock("NFT Mock", "NFT");

    // -------------------------------------------------------------------------
    // Setup

    function setUp() public {
        // Deploy the SuT
        address impl = address(new LM_PC_FundingPot_v1_Exposed());
        fundingPot = LM_PC_FundingPot_v1_Exposed(Clones.clone(impl));

        // Mint tokens to the contributors
        contributor1_ = address(0xBeef);
        contributor2_ = address(0xDEAD);
        contributor3_ = address(0xCAFE);

        _token.mint(contributor1_, 10_000);
        _token.mint(contributor2_, 10_000);
        _token.mint(contributor3_, 10_000);

        // Setup the module to test
        _setUpOrchestrator(fundingPot);

        // Initiate the Logic Module with the metadata and config data
        fundingPot.init(_orchestrator, _METADATA, abi.encode(""));

        _authorizer.setIsAuthorized(address(this), true);

        // Set the block timestamp
        vm.warp(block.timestamp + _orchestrator.MODULE_UPDATE_TIMELOCK());

        // Initialize default round parameters
        _defaultRoundParams = RoundParams({
            roundStart: block.timestamp + 1 days,
            roundEnd: block.timestamp + 2 days,
            roundCap: 1000,
            hookContract: address(0),
            hookFunction: bytes(""),
            autoClosure: false,
            accumulationMode: ILM_PC_FundingPot_v1.AccumulationMode.Disabled
        });

        // Initialize edited round parameters
        _editedRoundParams = _helper_createEditRoundParams(
            block.timestamp + 3 days,
            block.timestamp + 4 days,
            2000,
            address(0x1),
            bytes("test"),
            true,
            ILM_PC_FundingPot_v1.AccumulationMode.All
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
    │
    └── Given user has FUNDING_POT_ADMIN_ROLE
    ├── And round start < block.timestamp
    │   └── When user attempts to create a round
    │       └── Then it should revert
    │
    ├── And round end time == 0
    ├── And round cap == 0
    │   └── When user attempts to create a round
    │       └── Then it should revert
    │
    ├── And round end time is set
    ├── And round end != 0
    ├── And round end < round start
    │   └── When user attempts to create a round
    │       └── Then it should revert
    │
    ├── And hook contract is set but hook function is not set
    │   └── When user attempts to create a round
    │       └── Then it should revert
    │
    ├── And hook function is set but hook contract is not set
    │   └── When user attempts to create a round
    │       └── Then it should revert
    │
    └── And all the valid parameters are provided
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
        RoundParams memory params = _defaultRoundParams;

        fundingPot.createRound(
            params.roundStart,
            params.roundEnd,
            params.roundCap,
            params.hookContract,
            params.hookFunction,
            params.autoClosure,
            params.accumulationMode
        );
        vm.stopPrank();
    }

    function testCreateRound_revertsGivenRoundStartIsInThePast(uint roundStart_)
        public
    {
        vm.assume(roundStart_ < block.timestamp);
        RoundParams memory params = _defaultRoundParams;

        params.roundStart = roundStart_;
        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundStartMustBeInFuture
                    .selector
            )
        );
        fundingPot.createRound(
            params.roundStart,
            params.roundEnd,
            params.roundCap,
            params.hookContract,
            params.hookFunction,
            params.autoClosure,
            params.accumulationMode
        );
    }

    function testCreateRound_revertsGivenRoundEndTimeAndCapAreBothZero()
        public
    {
        RoundParams memory params = _defaultRoundParams;

        params.roundEnd = 0;
        params.roundCap = 0;
        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundMustHaveEndTimeOrCap
                    .selector
            )
        );
        fundingPot.createRound(
            params.roundStart,
            params.roundEnd,
            params.roundCap,
            params.hookContract,
            params.hookFunction,
            params.autoClosure,
            params.accumulationMode
        );
    }

    function testCreateRound_revertsGivenRoundEndTimeIsBeforeRoundStart(
        uint roundEnd_
    ) public {
        RoundParams memory params = _defaultRoundParams;

        vm.assume(roundEnd_ != 0 && roundEnd_ < params.roundStart);
        params.roundEnd = roundEnd_;
        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundEndMustBeAfterStart
                    .selector
            )
        );
        fundingPot.createRound(
            params.roundStart,
            params.roundEnd,
            params.roundCap,
            params.hookContract,
            params.hookFunction,
            params.autoClosure,
            params.accumulationMode
        );
    }

    function testCreateRound_revertsGivenHookContractIsSetButHookFunctionIsEmpty(
    ) public {
        RoundParams memory params = _defaultRoundParams;
        params.hookContract = address(1);
        params.hookFunction = bytes("");
        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__HookFunctionRequiredWithHookContract
                    .selector
            )
        );
        fundingPot.createRound(
            params.roundStart,
            params.roundEnd,
            params.roundCap,
            params.hookContract,
            params.hookFunction,
            params.autoClosure,
            params.accumulationMode
        );
    }

    function testCreateRound_revertsGivenHookFunctionIsSetButHookContractIsEmpty(
    ) public {
        RoundParams memory params = _defaultRoundParams;

        params.hookContract = address(0);
        params.hookFunction = bytes("test");
        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__HookContractRequiredWithHookFunction
                    .selector
            )
        );
        fundingPot.createRound(
            params.roundStart,
            params.roundEnd,
            params.roundCap,
            params.hookContract,
            params.hookFunction,
            params.autoClosure,
            params.accumulationMode
        );
    }

    /* Test Fuzz createRound()
        ├── Given all the valid parameters are provided
        │   └── When user attempts to create a round
        │       └── Then it should not be active and should return the round id
        */

    function testCreateRound() public {
        RoundParams memory params = _defaultRoundParams;

        fundingPot.createRound(
            params.roundStart,
            params.roundEnd,
            params.roundCap,
            params.hookContract,
            params.hookFunction,
            params.autoClosure,
            params.accumulationMode
        );

        _testRoundId = fundingPot.getRoundCount();

        // Retrieve the stored parameters
        (
            uint storedRoundStart,
            uint storedRoundEnd,
            uint storedRoundCap,
            address storedHookContract,
            bytes memory storedHookFunction,
            bool storedAutoClosure,
            ILM_PC_FundingPot_v1.AccumulationMode storedAccumulationMode
        ) = fundingPot.getRoundGenericParameters(_testRoundId);

        // Compare with expected values
        assertEq(storedRoundStart, params.roundStart);
        assertEq(storedRoundEnd, params.roundEnd);
        assertEq(storedRoundCap, params.roundCap);
        assertEq(storedHookContract, params.hookContract);
        assertEq(storedHookFunction, params.hookFunction);
        assertEq(storedAutoClosure, params.autoClosure);
        assertEq(uint(storedAccumulationMode), uint(params.accumulationMode));
    }

    /* Test editRound()
    ├── Given user does not have FUNDING_POT_ADMIN_ROLE
    │   └── When user attempts to edit a round
    │       └── Then it should revert
    │
    └── Given user has FUNDING_POT_ADMIN_ROLE
    ├── Given round does not exist
    │   └── When user attempts to edit the round
    │       └── Then it should revert
        │
    ├── Given round is active
    │   └── When user attempts to edit the round
    │       └── Then it should revert
        │
    ├── Given round start time is in the past
        │   └── When user attempts to edit a round with this parameter
    │       └── Then it should revert
        │
        ├── Given round end time == 0 and round cap == 0
        │   └── When user attempts to edit a round with these parameters
    │       └── Then it should revert
        │
        ├── Given round end time is set and round end < round start
    │   └── When user attempts to edit the round
    │       └── Then it should revert
        │
        ├── Given hook contract is set but hook function is empty
    │   └── When user attempts to edit the round
    │       └── Then it should revert
        │
        ├── Given hook function is set but hook contract is empty
        │   └── When user attempts to edit the round
        │       └── Then it should revert
        │
        └── Given all valid parameters are provided
            └── When user attempts to edit the round
                └── Then all round details should be successfully updated
                    ├── roundStart should be updated to the new value
                    ├── roundEnd should be updated to the new value
                    ├── roundCap should be updated to the new value
                    ├── hookContract should be updated to the new value
                    ├── hookFunction should be updated to the new value
                    ├── autoClosure should be updated to the new value
                    └── accumulationMode should be updated to the new value
    */

    function testEditRound_revertsGivenUserIsNotFundingPotAdmin(address user_)
        public
    {
        testCreateRound();
        uint32 roundId = fundingPot.getRoundCount();

        RoundParams memory params = RoundParams({
            roundStart: block.timestamp + 3 days,
            roundEnd: block.timestamp + 4 days,
            roundCap: 2000,
            hookContract: address(0x1),
            hookFunction: bytes("test"),
            autoClosure: true,
            accumulationMode: ILM_PC_FundingPot_v1.AccumulationMode.All
        });

        vm.startPrank(user_);
        bytes32 roleId = _authorizer.generateRoleId(
            address(fundingPot), fundingPot.FUNDING_POT_ADMIN_ROLE()
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector, roleId, user_
            )
        );
        fundingPot.editRound(
            roundId,
            params.roundStart,
            params.roundEnd,
            params.roundCap,
            params.hookContract,
            params.hookFunction,
            params.autoClosure,
            params.accumulationMode
        );
        vm.stopPrank();
    }

    function testEditRound_revertsGivenRoundIsNotCreated() public {
        testCreateRound();
        uint32 roundId = fundingPot.getRoundCount();

        RoundParams memory params = RoundParams({
            roundStart: block.timestamp + 3 days,
            roundEnd: block.timestamp + 4 days,
            roundCap: 2000,
            hookContract: address(0x1),
            hookFunction: bytes("test"),
            autoClosure: true,
            accumulationMode: ILM_PC_FundingPot_v1.AccumulationMode.All
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundNotCreated
                    .selector
            )
        );
        fundingPot.editRound(
            uint32(roundId + 1),
            params.roundStart,
            params.roundEnd,
            params.roundCap,
            params.hookContract,
            params.hookFunction,
            params.autoClosure,
            params.accumulationMode
        );
    }

    function testEditRound_revertsGivenRoundIsActive() public {
        testCreateRound();
        uint32 roundId = fundingPot.getRoundCount();

        RoundParams memory params;
        (
            params.roundStart,
            params.roundEnd,
            params.roundCap,
            params.hookContract,
            params.hookFunction,
            params.autoClosure,
            params.accumulationMode
        ) = fundingPot.getRoundGenericParameters(roundId);
        vm.warp(params.roundStart + 1);

        RoundParams memory params_ = RoundParams({
            roundStart: block.timestamp + 3 days,
            roundEnd: block.timestamp + 4 days,
            roundCap: 2000,
            hookContract: address(0x1),
            hookFunction: bytes("test"),
            autoClosure: true,
            accumulationMode: ILM_PC_FundingPot_v1.AccumulationMode.All
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundAlreadyStarted
                    .selector
            )
        );
        fundingPot.editRound(
            roundId,
            params_.roundStart,
            params_.roundEnd,
            params_.roundCap,
            params_.hookContract,
            params_.hookFunction,
            params_.autoClosure,
            params_.accumulationMode
        );
    }

    function testEditRound_revertsGivenRoundStartIsInThePast(uint roundStart_)
        public
    {
        testCreateRound();
        uint32 roundId = fundingPot.getRoundCount();
        _editedRoundParams;
        vm.assume(roundStart_ < block.timestamp);
        _editedRoundParams.roundStart = roundStart_;

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundStartMustBeInFuture
                    .selector
            )
        );

        fundingPot.editRound(
            roundId,
            _editedRoundParams.roundStart,
            _editedRoundParams.roundEnd,
            _editedRoundParams.roundCap,
            _editedRoundParams.hookContract,
            _editedRoundParams.hookFunction,
            _editedRoundParams.autoClosure,
            _editedRoundParams.accumulationMode
        );
    }

    function testEditRound_revertsGivenRoundEndTimeAndCapAreBothZero() public {
        testCreateRound();
        uint32 roundId = fundingPot.getRoundCount();

        RoundParams memory params = RoundParams({
            roundStart: block.timestamp + 3 days,
            roundEnd: 0,
            roundCap: 0,
            hookContract: address(0x1),
            hookFunction: bytes("test"),
            autoClosure: true,
            accumulationMode: ILM_PC_FundingPot_v1.AccumulationMode.All
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundMustHaveEndTimeOrCap
                    .selector
            )
        );

        fundingPot.editRound(
            roundId,
            params.roundStart,
            params.roundEnd,
            params.roundCap,
            params.hookContract,
            params.hookFunction,
            params.autoClosure,
            params.accumulationMode
        );
    }

    function testEditRound_revertsGivenRoundEndTimeIsBeforeRoundStart(
        uint roundEnd_,
        uint roundStart_
    ) public {
        vm.assume(
            roundEnd_ != 0 && roundStart_ > block.timestamp
                && roundEnd_ < roundStart_
        );
        testCreateRound();
        uint32 roundId = fundingPot.getRoundCount();

        // Get the current round start time
        (uint currentRoundStart,,,,,,ILM_PC_FundingPot_v1.AccumulationMode mode) =
            fundingPot.getRoundGenericParameters(roundId);

        // Ensure roundEnd_ is less than current round start
        vm.assume(roundEnd_ < currentRoundStart);
        vm.assume(roundEnd_ != 0);

        RoundParams memory params = _helper_createEditRoundParams(
            currentRoundStart,
            roundEnd_,
            2000,
            address(0x1),
            bytes("test"),
            true,
            ILM_PC_FundingPot_v1.AccumulationMode.All
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundEndMustBeAfterStart
                    .selector
            )
        );

        fundingPot.editRound(
            roundId,
            params.roundStart,
            params.roundEnd,
            params.roundCap,
            params.hookContract,
            params.hookFunction,
            params.autoClosure,
            params.accumulationMode
        );
    }

    function testEditRound_revertsGivenHookContractIsSetButHookFunctionIsEmpty()
        public
    {
        testCreateRound();
        uint32 roundId = fundingPot.getRoundCount();

        RoundParams memory params = _helper_createEditRoundParams(
            block.timestamp + 3 days,
            block.timestamp + 4 days,
            2000,
            address(1),
            bytes(""),
            true,
            ILM_PC_FundingPot_v1.AccumulationMode.All
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__HookFunctionRequiredWithHookContract
                    .selector
            )
        );

        fundingPot.editRound(
            roundId,
            params.roundStart,
            params.roundEnd,
            params.roundCap,
            params.hookContract,
            params.hookFunction,
            params.autoClosure,
            params.accumulationMode
        );
    }

    function testEditRound_revertsGivenHookFunctionIsSetButHookContractIsEmpty()
        public
    {
        testCreateRound();
        uint32 roundId = fundingPot.getRoundCount();

        RoundParams memory params = _helper_createEditRoundParams(
            block.timestamp + 3 days,
            block.timestamp + 4 days,
            2000,
            address(0),
            bytes("test"),
            true,
            ILM_PC_FundingPot_v1.AccumulationMode.All
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__HookContractRequiredWithHookFunction
                    .selector
            )
        );

        fundingPot.editRound(
            roundId,
            params.roundStart,
            params.roundEnd,
            params.roundCap,
            params.hookContract,
            params.hookFunction,
            params.autoClosure,
            params.accumulationMode
        );
    }

    /* Test editRound()
    └── Given a round has been created
    ├── And the round is not active
    └── When an admin provides valid parameters to edit the round
        └── Then all round details should be successfully updated
            ├── roundStart should be updated to the new value
            ├── roundEnd should be updated to the new value
            ├── roundCap should be updated to the new value
            ├── hookContract should be updated to the new value
            ├── hookFunction should be updated to the new value
            ├── autoClosure should be updated to the new value
            └── accumulationMode should be updated to the new value
    */

    function testEditRound() public {
        testCreateRound();
        uint32 lastRoundId = fundingPot.getRoundCount();

        RoundParams memory params = _editedRoundParams;

        fundingPot.editRound(
            lastRoundId,
            params.roundStart,
            params.roundEnd,
            params.roundCap,
            params.hookContract,
            params.hookFunction,
            params.autoClosure,
            params.accumulationMode
        );

        // Retrieve the stored parameters
        (
            uint storedRoundStart,
            uint storedRoundEnd,
            uint storedRoundCap,
            address storedHookContract,
            bytes memory storedHookFunction,
            bool storedAutoClosure,
            ILM_PC_FundingPot_v1.AccumulationMode storedAccumulationMode
        ) = fundingPot.getRoundGenericParameters(uint32(lastRoundId));

        // Compare with expected values
        assertEq(storedRoundStart, params.roundStart);
        assertEq(storedRoundEnd, params.roundEnd);
        assertEq(storedRoundCap, params.roundCap);
        assertEq(storedHookContract, params.hookContract);
        assertEq(storedHookFunction, params.hookFunction);
        assertEq(storedAutoClosure, params.autoClosure);
        assertEq(uint(storedAccumulationMode), uint(params.accumulationMode));
    }

    /* Test setAccessCriteria()
    ├── Given user does not have FUNDING_POT_ADMIN_ROLE
    │   └── When user attempts to set access criteria
    │       └── Then it should revert
    │
    └── Given user has FUNDING_POT_ADMIN_ROLE
    ├── Given round does not exist
    │   └── When user attempts to set access criteria
    │       └── Then it should revert
        │
    ├── Given round is active
    │   └── When user attempts to set access criteria
    │       └── Then it should revert
        │
    ├── Given AccessCriteriaId is NFT and nftContract is 0x0
    │   └── When user attempts to set access criteria
    │       └── Then it should revert
        │
    ├── Given AccessCriteriaId is MERKLE and merkleRoot is 0x0
    │   └── When user attempts to set access criteria
    │       └── Then it should revert
        │
    ├── Given AccessCriteriaId is LIST and allowedAddresses is empty
    │   └── When user attempts to set access criteria
    │       └── Then it should revert
        │
    └── Given all the valid parameters are provided
        └── When user attempts to set access criteria
            └── Then it should not revert
    */

    function testFuzzSetAccessCriteria_revertsGivenUserDoesNotHaveFundingPotAdminRole(
        uint8 accessCriteriaEnum_,
        address user_
    ) public {
        vm.assume(accessCriteriaEnum_ >= 0 && accessCriteriaEnum_ <= 4);
        vm.assume(user_ != address(0) && user_ != address(this));

        testCreateRound();
        uint32 roundId = fundingPot.getRoundCount();

        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessCriteriaEnum_);

        vm.startPrank(user_);
        bytes32 roleId = _authorizer.generateRoleId(
            address(fundingPot), fundingPot.FUNDING_POT_ADMIN_ROLE()
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector, roleId, user_
            )
        );
        fundingPot.setAccessCriteriaForRound(
            roundId,
            accessCriteriaEnum_,
            nftContract,
            merkleRoot,
            allowedAddresses
        );
        vm.stopPrank();
    }

    function testFuzzSetAccessCriteria_revertsGivenRoundDoesNotExist(
        uint8 accessCriteriaEnum
    ) public {
        vm.assume(accessCriteriaEnum >= 0 && accessCriteriaEnum <= 4);

        uint32 roundId = fundingPot.getRoundCount();

        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessCriteriaEnum);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundNotCreated
                    .selector
            )
        );
        fundingPot.setAccessCriteriaForRound(
            roundId,
            accessCriteriaEnum,
            nftContract,
            merkleRoot,
            allowedAddresses
        );
    }

    function testFuzzSetAccessCriteria_revertsGivenRoundIsActive(
        uint8 accessCriteriaEnum
    ) public {
        vm.assume(accessCriteriaEnum >= 0 && accessCriteriaEnum <= 4);

        testCreateRound();
        uint32 roundId = fundingPot.getRoundCount();

        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessCriteriaEnum);

        (uint roundStart,,,,,,ILM_PC_FundingPot_v1.AccumulationMode mode) =
            fundingPot.getRoundGenericParameters(roundId);
        vm.warp(roundStart + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundAlreadyStarted
                    .selector
            )
        );
        fundingPot.setAccessCriteriaForRound(
            roundId,
            accessCriteriaEnum,
            nftContract,
            merkleRoot,
            allowedAddresses
        );
    }

    function testSetAccessCriteria_revertsGivenAccessCriteriaIdIsNFTAndNftContractIsZero(
    ) public {
        uint8 accessCriteriaEnum =
            uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.NFT);

        testCreateRound();
        uint32 roundId = fundingPot.getRoundCount();

        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessCriteriaEnum);
        nftContract = address(0);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__MissingRequiredAccessCriteriaData
                    .selector
            )
        );
        fundingPot.setAccessCriteriaForRound(
            roundId,
            accessCriteriaEnum,
            nftContract,
            merkleRoot,
            allowedAddresses
        );
    }

    function testSetAccessCriteria_revertsGivenAccessCriteriaIdIsMerkleAndMerkleRootIsZero(
    ) public {
        uint8 accessCriteriaEnum =
            uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.MERKLE);

        testCreateRound();
        uint32 roundId = fundingPot.getRoundCount();

        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessCriteriaEnum);
        merkleRoot = bytes32(uint(0x0));

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__MissingRequiredAccessCriteriaData
                    .selector
            )
        );
        fundingPot.setAccessCriteriaForRound(
            roundId,
            accessCriteriaEnum,
            nftContract,
            merkleRoot,
            allowedAddresses
        );
    }

    function testSetAccessCriteria_revertsGivenAccessCriteriaIdIsListAndAllowedAddressesIsEmpty(
    ) public {
        uint8 accessCriteriaEnum =
            uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.LIST);

        testCreateRound();
        uint32 roundId = fundingPot.getRoundCount();

        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessCriteriaEnum);
        allowedAddresses = new address[](0);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__MissingRequiredAccessCriteriaData
                    .selector
            )
        );
        fundingPot.setAccessCriteriaForRound(
            roundId,
            accessCriteriaEnum,
            nftContract,
            merkleRoot,
            allowedAddresses
        );
    }

    function testFuzzSetAccessCriteria(uint8 accessCriteriaEnum) public {
        vm.assume(accessCriteriaEnum >= 0 && accessCriteriaEnum <= 4);

        testCreateRound();
        uint32 roundId = fundingPot.getRoundCount();

        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessCriteriaEnum);

        fundingPot.setAccessCriteriaForRound(
            roundId,
            accessCriteriaEnum,
            nftContract,
            merkleRoot,
            allowedAddresses
        );

        (
            bool isOpen,
            address retrievedNftContract,
            bytes32 retrievedMerkleRoot,
            bool hasAccess
        ) = fundingPot.getRoundAccessCriteria(
            uint32(roundId), accessCriteriaEnum
        );

        assertEq(isOpen, accessCriteriaEnum == 1);
        assertEq(retrievedNftContract, nftContract);
        assertEq(retrievedMerkleRoot, merkleRoot);
        if (accessCriteriaEnum == 1 || accessCriteriaEnum == 4) {
            assertTrue(hasAccess);
        } else {
            assertFalse(hasAccess);
        }
    }

    /* Test editAccessCriteriaForRound()
    ├── Given user does not have FUNDING_POT_ADMIN_ROLE
    │   └── When user attempts to edit access criteria
    │       └── Then it should revert
    │
    └── Given user has FUNDING_POT_ADMIN_ROLE
        ├── Given access criteria id is greater than the number of access criteria for the round
        │   └── When user attempts to edit access criteria
        │       └── Then it should revert
        │
        ├── Given round does not exist
        │   └── When user attempts to edit access criteria
        │       └── Then it should revert
        │
        ├── Given round is active
        │   └── When user attempts to edit access criteria
        │       └── Then it should revert
        │
        └── Given all valid parameters are provided
            └── When user attempts to edit access criteria
                ├── Then it should not revert
                └── Then the access criteria should be updated
    */

    function testFuzzEditAccessCriteriaForRound_revertsGivenUserDoesNotHaveFundingPotAdminRole(
        uint8 accessCriteriaEnum,
        address user_
    ) public {
        vm.assume(accessCriteriaEnum >= 0 && accessCriteriaEnum <= 4);
        vm.assume(user_ != address(0) && user_ != address(this));

        _helper_setupRoundWithAccessCriteria(accessCriteriaEnum);
        uint32 roundId = fundingPot.getRoundCount();

        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessCriteriaEnum);

        vm.startPrank(user_);
        bytes32 roleId = _authorizer.generateRoleId(
            address(fundingPot), fundingPot.FUNDING_POT_ADMIN_ROLE()
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector, roleId, user_
            )
        );
        fundingPot.editAccessCriteriaForRound(
            roundId,
            accessCriteriaEnum,
            nftContract,
            merkleRoot,
            allowedAddresses
        );
        vm.stopPrank();
    }

    function testFuzzEditAccessCriteriaForRound_revertsGivenAccessCriteriaIdIsGreaterThanAccessCriteriaForTheRound(
        uint8 accessCriteriaEnum
    ) public {
        vm.assume(accessCriteriaEnum >= 0 && accessCriteriaEnum <= 4);

        _helper_setupRoundWithAccessCriteria(accessCriteriaEnum);
        uint32 roundId = fundingPot.getRoundCount();
        uint8 accessCriteriaId = 10; // Invalid ID

        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessCriteriaEnum);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__InvalidAccessCriteriaId
                    .selector
            )
        );
        fundingPot.editAccessCriteriaForRound(
            roundId, accessCriteriaId, nftContract, merkleRoot, allowedAddresses
        );
    }

    function testFuzzEditAccessCriteriaForRound_revertsGivenRoundDoesNotExist(
        uint8 accessCriteriaEnum
    ) public {
        vm.assume(accessCriteriaEnum >= 0 && accessCriteriaEnum <= 4);
        uint32 roundId = fundingPot.getRoundCount();
        uint8 accessCriteriaId = 0;

        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessCriteriaEnum);

        vm.expectRevert();
        fundingPot.editAccessCriteriaForRound(
            roundId, accessCriteriaId, nftContract, merkleRoot, allowedAddresses
        );
    }

    function testFuzzEditAccessCriteriaForRound_revertsGivenRoundIsActive(
        uint8 accessCriteriaEnum
    ) public {
        vm.assume(accessCriteriaEnum >= 0 && accessCriteriaEnum <= 4);

        // Set up a round with access criteria
        _helper_setupRoundWithAccessCriteria(accessCriteriaEnum);
        uint32 roundId = fundingPot.getRoundCount();

        // Warp to make the round active
        (uint roundStart,,,,,,ILM_PC_FundingPot_v1.AccumulationMode mode) =
            fundingPot.getRoundGenericParameters(roundId);
        vm.warp(roundStart + 1);

        // Create a new access criteria to try to edit with
        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria((accessCriteriaEnum + 1) % 5); // Use a different access criteria type

        // Expect revert when trying to edit access criteria for an active round
        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundAlreadyStarted
                    .selector
            )
        );

        // Attempt to edit the access criteria for the active round
        fundingPot.editAccessCriteriaForRound(
            roundId, 0, nftContract, merkleRoot, allowedAddresses
        );
    }

    /* Test: contributeToRoundFor() unhappy paths
    ├── Given the round has not started yet
    │   └── When the user contributes to the round
    │       └── Then the transaction should revert
    │
    ├── Given the round has ended
    │   └── When the user contributes to the round
    │       └── Then the transaction should revert
    │
    ├── Given a round has been configured with generic round configuration and access criteria
    │   And the round has started
    │   And the round has not ended
    │   And the user has approved their contribution
    │   And the total contribution cap is not yet reached
    │   ├── Given the access criteria is an NFT
    │   │   └── And the user does not fulfill the access criteria
    │   │       └── When the user contributes to the round
    │   │           └── Then the transaction should revert
    │   │
    │   ├── Given the access criteria is a Merkle Root
    │   │   └── And the user does not fulfill the access criteria
    │   │       └── When the user contributes to the round
    │   │           └── Then the transaction should revert
    │   │
    │   ├── Given the access criteria is a List
    │   │   └── And the user does not fulfill the access criteria
    │   │       └── When the user contributes to the round
    │   │           └── Then the transaction should revert
    │   │
    │   └── Given a user has already contributed up to their personal cap
    │       └── When the user attempts to contribute again
    │           └── Then the transaction should revert
    */

    function testcontributeToRoundFor_revertsGivenContributionIsBeforeRoundStart(
    ) public {
        testCreateRound();

        uint32 roundId = fundingPot.getRoundCount();
        uint8 accessId = 1;
        uint amount = 250;

        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessId);

        fundingPot.setAccessCriteriaForRound(
            roundId, accessId, nftContract, merkleRoot, allowedAddresses
        );
        fundingPot.setAccessCriteriaPrivileges(
            roundId, accessId, 500, false, 0, 0, 0
        );

        // Approve
        vm.prank(contributor1_);
        _token.approve(address(fundingPot), 500);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundHasNotStarted
                    .selector
            )
        );

        vm.prank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_, roundId, amount, accessId, new bytes32[](0)
        );
    }

    function testcontributeToRoundFor_revertsGivenContributionIsAfterRoundEnd()
        public
    {
        testCreateRound();

        uint32 roundId = fundingPot.getRoundCount();
        uint8 accessId = 0;
        uint amount = 250;

        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessId);

        fundingPot.setAccessCriteriaForRound(
            roundId, accessId, nftContract, merkleRoot, allowedAddresses
        );
        fundingPot.setAccessCriteriaPrivileges(
            roundId, accessId, 500, false, 0, 0, 0
        );

        (uint roundStart,,,,,,ILM_PC_FundingPot_v1.AccumulationMode mode) =
            fundingPot.getRoundGenericParameters(roundId);
        vm.warp(roundStart + 10 days);

        // Approve
        vm.prank(contributor1_);
        _token.approve(address(fundingPot), 500);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundHasEnded
                    .selector
            )
        );

        vm.prank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_, roundId, amount, accessId, new bytes32[](0)
        );
    }

    function testcontributeToRoundFor_revertsGivenNFTAccessCriteriaIsNotMet()
        public
    {
        uint8 accessId = 2;
        _helper_setupRoundWithAccessCriteria(accessId);

        uint32 roundId = fundingPot.getRoundCount();

        uint amount = 250;

        (uint roundStart,,,,,,ILM_PC_FundingPot_v1.AccumulationMode mode) =
            fundingPot.getRoundGenericParameters(roundId);
        vm.warp(roundStart + 1);

        // Approve
        vm.prank(contributor1_);
        _token.approve(address(fundingPot), amount);

        mockNFTContract.balanceOf(contributor1_);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__AccessCriteriaNftFailed
                    .selector
            )
        );

        vm.prank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_, roundId, amount, accessId, new bytes32[](0)
        );
    }

    function testcontributeToRoundFor_revertsGivenMerkleRootAccessCriteriaIsNotMet(
    ) public {
        testCreateRound();

        uint32 roundId = fundingPot.getRoundCount();
        uint8 accessId = 3;
        uint amount = 250;

        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessId);

        fundingPot.setAccessCriteriaForRound(
            roundId, accessId, nftContract, merkleRoot, allowedAddresses
        );
        fundingPot.setAccessCriteriaPrivileges(
            roundId, accessId, 500, false, 0, 0, 0
        );

        (uint roundStart,,,,,,ILM_PC_FundingPot_v1.AccumulationMode mode) =
            fundingPot.getRoundGenericParameters(roundId);
        vm.warp(roundStart + 1);

        // Approve
        vm.prank(contributor1_);
        _token.approve(address(fundingPot), amount);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__AccessCriteriaMerkleFailed
                    .selector
            )
        );

        vm.prank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_, roundId, amount, accessId, PROOF
        );
    }

    function testcontributeToRoundFor_revertsGivenAllowedListAccessCriteriaIsNotMet(
    ) public {
        testCreateRound();

        uint32 roundId = fundingPot.getRoundCount();
        uint8 accessId = 4;
        uint amount = 250;

        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessId);

        fundingPot.setAccessCriteriaForRound(
            roundId, accessId, nftContract, merkleRoot, allowedAddresses
        );
        fundingPot.setAccessCriteriaPrivileges(
            roundId, accessId, 500, false, 0, 0, 0
        );

        (uint roundStart,,,,,,ILM_PC_FundingPot_v1.AccumulationMode mode) =
            fundingPot.getRoundGenericParameters(roundId);
        vm.warp(roundStart + 1);

        // Approve
        vm.prank(contributor1_);
        _token.approve(address(fundingPot), amount);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__AccessCriteriaListFailed
                    .selector
            )
        );

        vm.prank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_, roundId, amount, accessId, new bytes32[](0)
        );
    }

    function testcontributeToRoundFor_revertsGivenPreviousContributionExceedsPersonalCap(
    ) public {
        testCreateRound();

        uint32 roundId = fundingPot.getRoundCount();
        uint8 accessId = 1;
        uint amount = 500;

        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessId);

        fundingPot.setAccessCriteriaForRound(
            roundId, accessId, nftContract, merkleRoot, allowedAddresses
        );
        fundingPot.setAccessCriteriaPrivileges(
            roundId, accessId, 500, false, 0, 0, 0
        );

        mockNFTContract.mint(contributor1_);

        (uint roundStart,,,,,,ILM_PC_FundingPot_v1.AccumulationMode mode) =
            fundingPot.getRoundGenericParameters(roundId);
        vm.warp(roundStart + 1);

        // Approve
        vm.prank(contributor1_);
        _token.approve(address(fundingPot), 1000);

        vm.prank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_, roundId, amount, accessId, new bytes32[](0)
        );

        // Attempt to contribute beyond personal cap
        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__PersonalCapReached
                    .selector
            )
        );
        vm.prank(contributor1_);

        fundingPot.contributeToRoundFor(
            contributor1_, roundId, 251, accessId, new bytes32[](0)
        );
    }

    /* Test: contributeToRoundFor() happy paths
    ├── Given a round has been configured with generic round configuration and access criteria
    │   And the round has started
    │   And the user fulfills the access criteria
    │   And the user doesn't violate any privileges
    │   And the user doesn't violate generic round parameters
    │   And the user has approved the collateral token
    │   └── When the user contributes to the round
    │       └── Then the funds are transferred to the funding pot
    │           And the contribution is recorded
    ├── Given the round contribution cap is not reached
    │   └── When the user contributes to the round so that it exceeds the round contribution cap
    │       └── Then only the valid contribution amount is transferred to the funding pot
    │           And the contribution is recorded
    │           And round closure is initiated
    │
    ├── Given the user fulfills the access criteria
    │   └── And the user has already contributed their personal cap partially
    │       └── When the user attempts to contribute more than their personal cap
    │           └── Then only the amount up to the cap is accepted as contribution
    │               And the contribution is recorded
    │
    ├── Given the user fulfills the access criteria
    │   └── And their access criteria has the privilege to override the contribution span
    │       └── When <reason for end of contribution span>
    │           └── And the user attempts to contribute
    │               └── Then the contribution is still recorded
    │
    ├── Given the user fulfills the access criteria
    │   And the round is set to have global accumulative caps
    │   And the user has not fully utilized their personal contribution potential in previous rounds
    │   └── When the user wants to contribute to the current round
    │       └── Then they can contribute up to their personal limit of the current round plus unfilled potential from previous rounds
    │
    ├── Given the round has been configured with global accumulative caps
    │   And in the previous round the round contribution cap was X
    │   And in total Y had been contributed in the previous round
    │   And the round contribution cap for the current round is Z
    │   └── When users attempt to contribute
    │       └── Then they can in total contribute Z + X - Y
    │           And the funds are transferred into the funding pot
    │
    */
    function testcontributeToRoundFor_worksGivenAllConditionsMet() public {
        testCreateRound();

        uint32 roundId = fundingPot.getRoundCount();
        uint8 accessId = 1;
        uint amount = 250;

        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessId);

        fundingPot.setAccessCriteriaForRound(
            roundId, accessId, nftContract, merkleRoot, allowedAddresses
        );
        fundingPot.setAccessCriteriaPrivileges(
            roundId, accessId, 500, false, 0, 0, 0
        );
        mockNFTContract.mint(contributor1_);

        (uint roundStart,,,,,,ILM_PC_FundingPot_v1.AccumulationMode mode) =
            fundingPot.getRoundGenericParameters(roundId);
        vm.warp(roundStart + 1);

        // Approve
        vm.prank(contributor1_);
        _token.approve(address(fundingPot), 500);

        vm.prank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_, roundId, amount, accessId, new bytes32[](0)
        );

        uint totalContributions =
            fundingPot.exposed_getTotalRoundContributions(roundId);

        assertEq(totalContributions, amount);

        uint personalContributions = fundingPot
            .exposed_getUserContributionToRound(roundId, contributor1_);
        assertEq(personalContributions, amount);
    }

    function testcontributeToRoundFor_worksGivenUserCurrentContributionExceedsTheRoundCap(
        uint8 accessCriteriaEnumOld,
        uint8 accessCriteriaEnumNew
    ) public {
        vm.assume(accessCriteriaEnumOld >= 0 && accessCriteriaEnumOld <= 4);
        vm.assume(
            accessCriteriaEnumNew != accessCriteriaEnumOld
                && accessCriteriaEnumNew >= 0 && accessCriteriaEnumNew <= 4
        );

        _helper_setupRoundWithAccessCriteria(accessCriteriaEnumOld);
        uint32 roundId = fundingPot.getRoundCount();
        uint8 accessId = 0;
        uint amount = 201;

        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessId);

        fundingPot.setAccessCriteriaForRound(
            roundId, accessId, nftContract, merkleRoot, allowedAddresses
        );
        fundingPot.setAccessCriteriaPrivileges(
            roundId, accessId, 200, false, 0, 0, 0
        );

        (uint roundStart,,,,,,ILM_PC_FundingPot_v1.AccumulationMode mode) =
            fundingPot.getRoundGenericParameters(roundId);
        vm.warp(roundStart + 1);

        // Approve
        vm.prank(contributor1_);
        _token.approve(address(fundingPot), amount);

        vm.prank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_, roundId, amount, accessId, new bytes32[](0)
        );

        // only the amount that does not exceed the roundcap is contributed
        assertEq(
            fundingPot.exposed_getUserContributionToRound(
                roundId, contributor1_
            ),
            200
        );
    }

    function testcontributeToRoundFor_worksGivenContributionPartiallyExceedingPersonalCap(
    ) public {
        testCreateRound();

        uint32 roundId = fundingPot.getRoundCount();
        uint8 accessId = 1;

        uint firstAmount = 400;
        uint personalCap = 500;

        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessId);

        fundingPot.setAccessCriteriaForRound(
            roundId, accessId, nftContract, merkleRoot, allowedAddresses
        );
        fundingPot.setAccessCriteriaPrivileges(
            roundId, accessId, personalCap, false, 0, 0, 0
        );

        mockNFTContract.mint(contributor1_);

        (uint roundStart,,,,,,ILM_PC_FundingPot_v1.AccumulationMode mode) =
            fundingPot.getRoundGenericParameters(roundId);
        vm.warp(roundStart + 1);

        // Approve
        vm.prank(contributor1_);
        _token.approve(address(fundingPot), 1000 ether);

        // First contribution
        vm.prank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_, roundId, firstAmount, accessId, new bytes32[](0)
        );

        uint secondAmount = 200;

        vm.prank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_, roundId, secondAmount, accessId, new bytes32[](0)
        );

        uint totalContribution = fundingPot.exposed_getUserContributionToRound(
            roundId, contributor1_
        );

        assertEq(totalContribution, personalCap);
    }

    function testcontributeToRoundFor_worksGivenUserCanOverrideTimeConstraints()
        public
    {
        testCreateRound();

        uint32 roundId = fundingPot.getRoundCount();
        uint8 accessId = 1;
        uint amount = 250;

        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessId);

        fundingPot.setAccessCriteriaForRound(
            roundId, accessId, nftContract, merkleRoot, allowedAddresses
        );

        // Set privileges with override capability
        fundingPot.setAccessCriteriaPrivileges(
            roundId, accessId, 500, true, 0, 0, 0
        );

        mockNFTContract.mint(contributor1_);

        (uint roundStart,,,,,,ILM_PC_FundingPot_v1.AccumulationMode mode) =
            fundingPot.getRoundGenericParameters(roundId);

        vm.warp(roundStart + 10 days);

        // Approve
        vm.prank(contributor1_);
        _token.approve(address(fundingPot), amount);

        // This should succeed despite being after round end, due to override privilege
        vm.prank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_, roundId, amount, accessId, new bytes32[](0)
        );

        // Verify the contribution was recorded
        uint totalContribution =
            fundingPot.exposed_getTotalRoundContributions(roundId);
        assertEq(totalContribution, amount);
    }

    function testcontributeToRoundFor_worksGivenPersonalCapAccumulation()
        public
    {
        _defaultRoundParams.accumulationMode = ILM_PC_FundingPot_v1.AccumulationMode.All;
        fundingPot.createRound(
            _defaultRoundParams.roundStart,
            _defaultRoundParams.roundEnd,
            _defaultRoundParams.roundCap,
            _defaultRoundParams.hookContract,
            _defaultRoundParams.hookFunction,
            _defaultRoundParams.autoClosure,
            _defaultRoundParams.accumulationMode
        );

        uint32 round1Id = fundingPot.getRoundCount();

        uint8 accessCriteriaId = 1;
        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessCriteriaId);
        fundingPot.setAccessCriteriaForRound(
            round1Id,
            accessCriteriaId,
            nftContract,
            merkleRoot,
            allowedAddresses
        );

        fundingPot.setAccessCriteriaPrivileges(
            round1Id, accessCriteriaId, 500, false, 0, 0, 0
        );

        mockNFTContract.mint(contributor1_);

        fundingPot.createRound(
            _defaultRoundParams.roundStart + 3 days,
            _defaultRoundParams.roundEnd + 3 days,
            _defaultRoundParams.roundCap,
            _defaultRoundParams.hookContract,
            _defaultRoundParams.hookFunction,
            _defaultRoundParams.autoClosure,
            _defaultRoundParams.accumulationMode
        );
        uint32 round2Id = fundingPot.getRoundCount();

        fundingPot.setAccessCriteriaForRound(
            round2Id, accessCriteriaId, address(0), bytes32(0), allowedAddresses
        );

        // Set personal cap of 400 for round 2
        fundingPot.setAccessCriteriaPrivileges(
            round2Id, accessCriteriaId, 400, false, 0, 0, 0
        );

        vm.warp(_defaultRoundParams.roundStart + 1);
        vm.startPrank(contributor1_);
        _token.approve(address(fundingPot), 1000);
        fundingPot.contributeToRoundFor(
            contributor1_, round1Id, 200, accessCriteriaId, new bytes32[](0)
        );

        // Warp to round 2
        vm.warp(_defaultRoundParams.roundStart + 3 days + 1);

        // Create unspent capacity structure
        ILM_PC_FundingPot_v1.UnspentPersonalRoundCap[] memory unspentCaps =
            new ILM_PC_FundingPot_v1.UnspentPersonalRoundCap[](1);
        unspentCaps[0] = ILM_PC_FundingPot_v1.UnspentPersonalRoundCap({
            roundId: round1Id,
            accessCriteriaId: accessCriteriaId,
            merkleProof: new bytes32[](0)
        });

        // Contribute to round 2 with unspent capacity from round 1
        fundingPot.contributeToRoundFor(
            contributor1_,
            round2Id,
            700,
            accessCriteriaId,
            new bytes32[](0),
            unspentCaps
        );
        vm.stopPrank();

        // Verify contributions are recorded correctly
        assertEq(
            fundingPot.exposed_getUserContributionToRound(
                round1Id, contributor1_
            ),
            200
        );

        assertEq(
            fundingPot.exposed_getUserContributionToRound(
                round2Id, contributor1_
            ),
            700
        );
    }

    function testcontributeToRoundFor_worksGivenTotalRoundCapAccumulation()
        public
    {
        _defaultRoundParams.accumulationMode = ILM_PC_FundingPot_v1.AccumulationMode.All;

        // Create Round 1
        fundingPot.createRound(
            _defaultRoundParams.roundStart,
            _defaultRoundParams.roundEnd,
            _defaultRoundParams.roundCap,
            _defaultRoundParams.hookContract,
            _defaultRoundParams.hookFunction,
            _defaultRoundParams.autoClosure,
            _defaultRoundParams.accumulationMode
        );
        uint32 round1Id = fundingPot.getRoundCount();

        uint8 accessId = 0;
        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessId);
        fundingPot.setAccessCriteriaForRound(
            round1Id, accessId, nftContract, merkleRoot, allowedAddresses
        );
        fundingPot.setAccessCriteriaPrivileges(
            round1Id, accessId, 500, false, 0, 0, 0
        );

        // Round 2 with a different cap
        uint round2Cap = 500;
        fundingPot.createRound(
            _defaultRoundParams.roundStart + 3 days,
            _defaultRoundParams.roundEnd + 3 days,
            round2Cap,
            _defaultRoundParams.hookContract,
            _defaultRoundParams.hookFunction,
            _defaultRoundParams.autoClosure,
            _defaultRoundParams.accumulationMode
        );
        uint32 round2Id = fundingPot.getRoundCount();
        fundingPot.setAccessCriteriaForRound(
            round2Id, accessId, nftContract, merkleRoot, allowedAddresses
        );
        fundingPot.setAccessCriteriaPrivileges(
            round2Id, accessId, 500, false, 0, 0, 0
        );

        // Round 1: Multiple users contribute, but don't reach the cap
        vm.warp(_defaultRoundParams.roundStart + 1);

        vm.startPrank(contributor1_);
        _token.approve(address(fundingPot), 300);
        fundingPot.contributeToRoundFor(
            contributor1_, round1Id, 300, accessId, new bytes32[](0)
        );
        vm.stopPrank();

        vm.startPrank(contributor2_);
        _token.approve(address(fundingPot), 200);
        fundingPot.contributeToRoundFor(
            contributor2_, round1Id, 200, accessId, new bytes32[](0)
        );
        vm.stopPrank();

        // Move to Round 2
        vm.warp(_defaultRoundParams.roundStart + 3 days + 1);

        // Round 2: Contributors try to use the accumulated capacity

        vm.startPrank(contributor2_);
        _token.approve(address(fundingPot), 400);
        fundingPot.contributeToRoundFor(
            contributor2_, round2Id, 400, accessId, new bytes32[](0)
        );
        vm.stopPrank();

        vm.startPrank(contributor3_);
        _token.approve(address(fundingPot), 300);
        fundingPot.contributeToRoundFor(
            contributor3_, round2Id, 300, accessId, new bytes32[](0)
        );
        vm.stopPrank();

        // Verify Round 1 contributions
        assertEq(fundingPot.exposed_getTotalRoundContributions(round1Id), 500);
        assertEq(
            fundingPot.exposed_getUserContributionToRound(
                round1Id, contributor1_
            ),
            300
        );
        assertEq(
            fundingPot.exposed_getUserContributionToRound(
                round1Id, contributor2_
            ),
            200
        );

        // Verify Round 2 contributions
        assertEq(fundingPot.exposed_getTotalRoundContributions(round2Id), 700);
        assertEq(
            fundingPot.exposed_getUserContributionToRound(
                round2Id, contributor2_
            ),
            400
        );
        assertEq(
            fundingPot.exposed_getUserContributionToRound(
                round2Id, contributor3_
            ),
            300
        );

        assertEq(fundingPot.exposed_getTotalRoundContributions(round2Id), 700);
    }

    // -------------------------------------------------------------------------
    // Test: closeRound()

    /*
    ├── Given user does not have FUNDING_POT_ADMIN_ROLE
    │   └── When user attempts to close a round
    │       └── Then it should revert with Module__CallerNotAuthorized
    │
    ├── Given round does not exist
    │   └── When user attempts to close the round
    │       └── Then it should revert with Module__LM_PC_FundingPot__RoundNotCreated
    │
    ├── Given round is already closed
    │   └── When user attempts to close the round again
    │       └── Then it should revert with Module__LM_PC_FundingPot__RoundHasEnded
    │
    ├── Given round has started but not ended
    │   └── And round cap has not been reached
    │   └── And user has contributed successfully
    │   └── When user attempts to close the round
    │       └── Then it should not revert and round should be closed
    │       └── And payment orders should be created correctly
    │
    ├── Given round has ended (by time)
    │   └── And user has contributed during active round
    │   └── When user attempts to close the round
    │       └── Then it should not revert and round should be closed
    │       └── And payment orders should be created correctly
    │
    ├── Given round cap has been reached
    │   └── And user has contributed up to the cap
    │   └── When user attempts to close the round
    │       └── Then it should not revert and round should be closed
    │       └── And payment orders should be created correctly
    -── Given round cap has been reached
    │   └── And the round is set up for autoclosure
    │   └── And user has contributed up to the cap
    │       └── Then it should not revert and round should be closed
    │       └── And payment orders should be created correctly
    └── Given multiple users contributed before round ended or cap reached
        └── When round is closed
            └── Then it should not revert and round should be closed
            └── And payment orders should be created for all contributors
    */
    function testCloseRound_revertsGivenUserIsNotFundingPotAdmin(address user_)
        public
    {
        vm.assume(user_ != address(0) && user_ != address(this));

        testCreateRound();
        uint32 roundId = fundingPot.getRoundCount();

        vm.startPrank(user_);
        bytes32 roleId = _authorizer.generateRoleId(
            address(fundingPot), fundingPot.FUNDING_POT_ADMIN_ROLE()
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector, roleId, user_
            )
        );
        fundingPot.closeRound(roundId);
        vm.stopPrank();
    }

    function testCloseRound_revertsGivenRoundDoesNotExist() public {
        uint32 nonExistentRoundId = 999;

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundNotCreated
                    .selector
            )
        );
        fundingPot.closeRound(nonExistentRoundId);
    }

    function testCloseRound_revertsGivenRoundIsAlreadyClosed() public {
        testCloseRound_worksGivenRoundCapHasBeenReached();
        // Try to close it again
        uint32 roundId = fundingPot.getRoundCount();

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundHasEnded
                    .selector
            )
        );
        fundingPot.closeRound(roundId);
    }

    function testCloseRound_worksGivenRoundHasStartedButNotEnded() public {
        testCreateRound();
        uint32 roundId = fundingPot.getRoundCount();

        uint8 accessId = 1;
        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessId);

        fundingPot.setAccessCriteriaForRound(
            roundId, accessId, nftContract, merkleRoot, allowedAddresses
        );
        fundingPot.setAccessCriteriaPrivileges(
            roundId, accessId, 1000, false, 0, 0, 0
        );

        // Warp to round start
        (uint roundStart,,,,,,ILM_PC_FundingPot_v1.AccumulationMode mode) =
            fundingPot.getRoundGenericParameters(roundId);
        vm.warp(roundStart + 1);

        // Make a contribution
        vm.startPrank(contributor1_);
        _token.approve(address(fundingPot), 1000);
        fundingPot.contributeToRoundFor(
            contributor1_, roundId, 1000, accessId, new bytes32[](0)
        );
        vm.stopPrank();

        // Close the round
        fundingPot.closeRound(roundId);

        // Verify round is closed
        assertEq(fundingPot.isRoundClosed(roundId), true);
    }

    function testCloseRound_worksGivenRoundHasEnded() public {
        testCreateRound();
        uint32 roundId = fundingPot.getRoundCount();

        uint8 accessId = 1;
        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessId);

        fundingPot.setAccessCriteriaForRound(
            roundId, accessId, nftContract, merkleRoot, allowedAddresses
        );
        fundingPot.setAccessCriteriaPrivileges(
            roundId, accessId, 1000, false, 0, 0, 0
        );

        // Make a contribution
        (uint roundStart, uint roundEnd, uint roundCap, address hookContract, bytes memory hookFunction, bool autoClosure, ILM_PC_FundingPot_v1.AccumulationMode mode) = 
            fundingPot.getRoundGenericParameters(roundId);
        vm.warp(roundStart + 1);

        vm.startPrank(contributor1_);
        _token.approve(address(fundingPot), 500);
        fundingPot.contributeToRoundFor(
            contributor1_, roundId, 500, accessId, new bytes32[](0)
        );
        vm.stopPrank();

        // Warp to after round end
        vm.warp(roundEnd + 1);

        // Close the round
        fundingPot.closeRound(roundId);

        // Verify round is closed
        assertEq(fundingPot.isRoundClosed(roundId), true);
    }

    function testCloseRound_worksGivenRoundCapHasBeenReached() public {
        testCreateRound();

        uint32 roundId = fundingPot.getRoundCount();
        uint8 accessId = 2;
        uint amount = 1000;

        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessId);

        fundingPot.setAccessCriteriaForRound(
            roundId, accessId, nftContract, merkleRoot, allowedAddresses
        );
        fundingPot.setAccessCriteriaPrivileges(
            roundId, accessId, 1000, false, 0, 0, 0
        );

        mockNFTContract.mint(contributor1_);

        (uint roundStart,,,,,,ILM_PC_FundingPot_v1.AccumulationMode mode) =
            fundingPot.getRoundGenericParameters(roundId);
        vm.warp(roundStart + 1);

        // Approve
        vm.prank(contributor1_);
        _token.approve(address(fundingPot), 1000);

        vm.prank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_, roundId, amount, accessId, new bytes32[](0)
        );

        assertEq(fundingPot.isRoundClosed(roundId), false);
        fundingPot.closeRound(roundId);
        assertEq(fundingPot.isRoundClosed(roundId), true);
    }

    function testCloseRound_worksGivenRoundisAutoClosure() public {
        testEditRound();

        uint32 roundId = fundingPot.getRoundCount();
        uint8 accessId = 2;
        uint amount = 2000;

        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessId);

        fundingPot.setAccessCriteriaForRound(
            roundId, accessId, nftContract, merkleRoot, allowedAddresses
        );

        fundingPot.setAccessCriteriaPrivileges(
            roundId, accessId, 2000, false, 0, 0, 0
        );
        mockNFTContract.mint(contributor1_);

        (uint roundStart,,,,,,ILM_PC_FundingPot_v1.AccumulationMode mode) =
            fundingPot.getRoundGenericParameters(roundId);
        vm.warp(roundStart + 1);

        // Approve
        vm.prank(contributor1_);
        _token.approve(address(fundingPot), 2000);

        vm.prank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_, roundId, amount, accessId, new bytes32[](0)
        );

        assertEq(fundingPot.isRoundClosed(roundId), true);
    }

    function testCloseRound_worksWithMultipleContributors() public {
        testCreateRound();
        uint32 roundId = fundingPot.getRoundCount();

        // Set up access criteria
        uint8 accessId = 1;
        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessId);

        fundingPot.setAccessCriteriaForRound(
            roundId, accessId, nftContract, merkleRoot, allowedAddresses
        );
        fundingPot.setAccessCriteriaPrivileges(
            roundId, accessId, 1000, false, 0, 0, 0
        );

        // Warp to round start
        (uint roundStart,,,,,,ILM_PC_FundingPot_v1.AccumulationMode mode) =
            fundingPot.getRoundGenericParameters(roundId);
        vm.warp(roundStart + 1);

        // Multiple contributors
        vm.startPrank(contributor1_);
        _token.approve(address(fundingPot), 500);
        fundingPot.contributeToRoundFor(
            contributor1_, roundId, 500, accessId, new bytes32[](0)
        );
        vm.stopPrank();

        vm.startPrank(contributor2_);
        _token.approve(address(fundingPot), 200);
        fundingPot.contributeToRoundFor(
            contributor2_, roundId, 200, accessId, new bytes32[](0)
        );
        vm.stopPrank();

        vm.startPrank(contributor3_);
        _token.approve(address(fundingPot), 300);
        fundingPot.contributeToRoundFor(
            contributor3_, roundId, 300, accessId, new bytes32[](0)
        );
        vm.stopPrank();

        // Close the round
        fundingPot.closeRound(roundId);

        // Verify round is closed
        assertEq(fundingPot.isRoundClosed(roundId), true);
    }

    //-------------------------------------------------------------------------

    /* Test createPaymentOrdersForContributorsBatch()
    ├── Given round does not exist
    │   └── When user attempts to create payment orders in batch
    │       └── Then it should revert with Module__LM_PC_FundingPot__RoundNotCreated
    │
    ├── Given round is not closed
    │   └── When user attempts to create payment orders in batch
    │       └── Then it should revert with Module__LM_PC_FundingPot__RoundNotClosed
    │
    ├── Given start index is greater than the number of contributors
    │   └── When user attempts to create payment orders in batch
    │       └── Then it should revert with Module__LM_PC_FundingPot__InvalidBatchParameters
    │
    ├── Given batch size is zero
    │   └── When user attempts to create payment orders in batch
    │       └── Then it should revert with Module__LM_PC_FundingPot__InvalidBatchParameters
    │
    ├── Given user does not have FUNDING_POT_ADMIN_ROLE
    │   └── Given the round is configured with autoClosure
    │   └── When user attempts to create payment orders in batch
    │       └── Then it should revert with Module__CallerNotAuthorized
    │
    ├── Given a closed round with autoClosure
    │   └── When user attempts to create payment orders in batch
    │       └── Then it should not revert and payment orders should be created
    │           └── And the payment orders should have correct token amounts
    │
    ├── Given a closed round with manualClosure
    │   └── When funding pot admin attempts to create payment orders in batch
    │       └── Then it should not revert and payment orders should be created
    │           └── And the payment orders should have correct token amounts
    */

    function testCreatePaymentOrdersForContributorsBatch_revertsGivenRoundDoesNotExist(
    ) public {
        uint32 nonExistentRoundId = 999;

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundNotCreated
                    .selector
            )
        );
        fundingPot.createPaymentOrdersForContributorsBatch(
            nonExistentRoundId, 1
        );
    }

    function testCreatePaymentOrdersForContributorsBatch_revertsGivenRoundIsNotClosed(
    ) public {
        testcontributeToRoundFor_worksGivenAllConditionsMet();
        uint32 roundId = fundingPot.getRoundCount();

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundNotClosed
                    .selector
            )
        );
        fundingPot.createPaymentOrdersForContributorsBatch(roundId, 1);
    }

    function testCreatePaymentOrdersForContributorsBatch_revertsGivenBatchSizeIsGreaterThanContributorCount(
    ) public {
        testCloseRound_worksWithMultipleContributors();
        uint32 roundId = fundingPot.getRoundCount();

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__InvalidBatchParameters
                    .selector
            )
        );
        fundingPot.createPaymentOrdersForContributorsBatch(roundId, 999);
    }

    function testCreatePaymentOrdersForContributorsBatch_revertsGivenBatchSizeIsZero(
    ) public {
        testCloseRound_worksWithMultipleContributors();
        uint32 roundId = fundingPot.getRoundCount();

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__InvalidBatchParameters
                    .selector
            )
        );
        fundingPot.createPaymentOrdersForContributorsBatch(roundId, 0);
    }

    function testCreatePaymentOrdersForContributorsBatch_revertsGivenUserDoesNotHaveFundingPotAdminRole(
    ) public {
        testCloseRound_worksWithMultipleContributors();
        uint32 roundId = fundingPot.getRoundCount();

        vm.startPrank(contributor1_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector,
                fundingPot.FUNDING_POT_ADMIN_ROLE(),
                contributor1_
            )
        );
        fundingPot.createPaymentOrdersForContributorsBatch(roundId, 1);
        vm.stopPrank();
    }

    function testCreatePaymentOrdersForContributorsBatch_worksGivenRoundIsAutoClosure(
    ) public {
        testCloseRound_worksGivenRoundisAutoClosure();
        uint32 roundId = fundingPot.getRoundCount();

        fundingPot.createPaymentOrdersForContributorsBatch(roundId, 1);
        assertEq(fundingPot.paymentOrders().length, 1);
    }

    function testCreatePaymentOrdersForContributorsBatch_worksGivenRoundIsManualClosure(
    ) public {
        testCloseRound_worksWithMultipleContributors();
        uint32 roundId = fundingPot.getRoundCount();

        fundingPot.createPaymentOrdersForContributorsBatch(roundId, 3);
        assertEq(fundingPot.paymentOrders().length, 3);
    }
    // -------------------------------------------------------------------------

    // Internal Functions
    function testFuzz_validateAccessCriteria(
        uint32 roundId_,
        uint8 accessId_,
        bytes32[] calldata merkleProof_
    ) external view {
        vm.assume(roundId_ <= fundingPot.getRoundCount() + 1);
        vm.assume(accessId_ <= 4);

        try fundingPot.exposed_validateAccessCriteria(
            roundId_, accessId_, merkleProof_, msg.sender
        ) {
            assert(true);
        } catch (bytes memory) {
            assert(false);
        }
    }

    function testFuzz_validateAndAdjustCapsWithUnspentCap(
        uint32 roundId_,
        uint amount_,
        uint8 accessId_,
        bool canOverrideContributionSpan_,
        uint unspentPersonalCap_
    ) external {
        vm.assume(roundId_ > 0 && roundId_ >= fundingPot.getRoundCount());
        vm.assume(amount_ <= 1000);
        vm.assume(accessId_ <= 4);
        vm.assume(unspentPersonalCap_ >= 0);

        try fundingPot.exposed_validateAndAdjustCapsWithUnspentCap(
            contributor1_,
            roundId_,
            amount_,
            accessId_,
            canOverrideContributionSpan_,
            unspentPersonalCap_
        ) returns (uint adjustedAmount) {
            assertLe(
                adjustedAmount, amount_, "Adjusted amount should be <= amount_"
            );
            assertGe(adjustedAmount, 0, "Adjusted amount should be >= 0");
        } catch (bytes memory reason) {
            bytes32 roundCapReachedSelector = keccak256(
                abi.encodeWithSignature(
                    "Module__LM_PC_FundingPot__RoundCapReached()"
                )
            );
            bytes32 personalCapReachedSelector = keccak256(
                abi.encodeWithSignature(
                    "Module__LM_PC_FundingPot__PersonalCapReached()"
                )
            );

            if (keccak256(reason) == roundCapReachedSelector) {
                assertTrue(
                    !canOverrideContributionSpan_,
                    "Should not revert RoundCapReached when canOverrideContributionSpan is true"
                );
            } else if (keccak256(reason) == personalCapReachedSelector) {
                assertTrue(true, "Personal cap reached as expected");
            } else {
                assertTrue(false, "Unexpected revert reason");
            }
        }
    }

    // -------------------------------------------------------------------------
    // Test: _checkRoundClosureConditions

    function test_checkRoundClosureConditions_whenCapReached() public {
        RoundParams memory params = _defaultRoundParams;
        params.roundStart = block.timestamp + 1 days;
        params.roundEnd = block.timestamp + 2 days;
        params.roundCap = 1000;

        uint32 roundId = fundingPot.createRound(
            params.roundStart,
            params.roundEnd,
            params.roundCap,
            params.hookContract,
            params.hookFunction,
            params.autoClosure,
            params.accumulationMode
        );

        // Set access criteria and privileges
        uint8 accessId = 1;
        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessId);
        fundingPot.setAccessCriteriaForRound(
            roundId, accessId, nftContract, merkleRoot, allowedAddresses
        );
        fundingPot.setAccessCriteriaPrivileges(
            roundId,
            accessId,
            1000, // personal cap equal to round cap
            false,
            0, // no start
            0, // no cliff
            0 // no end
        );

        // Contribute up to the cap
        vm.warp(params.roundStart + 1);
        vm.startPrank(contributor1_);
        _token.approve(address(fundingPot), params.roundCap);
        fundingPot.contributeToRoundFor(
            contributor1_, roundId, params.roundCap, accessId, new bytes32[](0)
        );
        vm.stopPrank();

        assertTrue(fundingPot.exposed_checkRoundClosureConditions(roundId));
    }

    function test_checkRoundClosureConditions_whenEndTimeReached() public {
        RoundParams memory params = _defaultRoundParams;
        params.roundStart = block.timestamp + 1 days;
        params.roundEnd = block.timestamp + 2 days;
        params.roundCap = 1000;

        uint32 roundId = fundingPot.createRound(
            params.roundStart,
            params.roundEnd,
            params.roundCap,
            params.hookContract,
            params.hookFunction,
            params.autoClosure,
            params.accumulationMode
        );

        // Move time past end time
        vm.warp(params.roundEnd + 1);
        assertTrue(fundingPot.exposed_checkRoundClosureConditions(roundId));
    }

    function test_checkRoundClosureConditions_whenNeitherConditionMet()
        public
    {
        RoundParams memory params = _defaultRoundParams;
        params.roundStart = block.timestamp + 1 days;
        params.roundEnd = block.timestamp + 2 days;
        params.roundCap = 1000;

        uint32 roundId = fundingPot.createRound(
            params.roundStart,
            params.roundEnd,
            params.roundCap,
            params.hookContract,
            params.hookFunction,
            params.autoClosure,
            params.accumulationMode
        );

        // Time is before end and no contributions
        assertFalse(fundingPot.exposed_checkRoundClosureConditions(roundId));
    }

    function test_checkRoundClosureConditions_withNoEndTime() public {
        RoundParams memory params = _defaultRoundParams;
        params.roundStart = block.timestamp + 1 days;
        params.roundEnd = 0; // No end time
        params.roundCap = 1000;

        uint32 roundId = fundingPot.createRound(
            params.roundStart,
            params.roundEnd,
            params.roundCap,
            params.hookContract,
            params.hookFunction,
            params.autoClosure,
            params.accumulationMode
        );

        // Set access criteria and privileges
        uint8 accessId = 1;
        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessId);
        fundingPot.setAccessCriteriaForRound(
            roundId, accessId, nftContract, merkleRoot, allowedAddresses
        );
        fundingPot.setAccessCriteriaPrivileges(
            roundId,
            accessId,
            1000, // personal cap equal to round cap
            false,
            0, // no start
            0, // no cliff
            0 // no end
        );

        // Should be false initially
        assertFalse(fundingPot.exposed_checkRoundClosureConditions(roundId));

        // Should be true when cap is reached
        vm.warp(params.roundStart + 1);
        vm.startPrank(contributor1_);
        _token.approve(address(fundingPot), params.roundCap);
        fundingPot.contributeToRoundFor(
            contributor1_, roundId, params.roundCap, accessId, new bytes32[](0)
        );
        vm.stopPrank();

        assertTrue(fundingPot.exposed_checkRoundClosureConditions(roundId));
    }

    function test_checkRoundClosureConditions_withNoCap() public {
        RoundParams memory params = _defaultRoundParams;
        params.roundStart = block.timestamp + 1 days;
        params.roundEnd = block.timestamp + 2 days;
        params.roundCap = 0; // No cap

        uint32 roundId = fundingPot.createRound(
            params.roundStart,
            params.roundEnd,
            params.roundCap,
            params.hookContract,
            params.hookFunction,
            params.autoClosure,
            params.accumulationMode
        );

        // Should be false before end time
        assertFalse(
            fundingPot.exposed_checkRoundClosureConditions(uint32(roundId))
        );

        // Should be true after end time
        vm.warp(params.roundEnd + 1);
        assertTrue(
            fundingPot.exposed_checkRoundClosureConditions(uint32(roundId))
        );
    }

    // Test exposed internal function closeRound
    function test_closeRound_worksGivenCapReached() public {
        testCreateRound();

        uint32 roundId = fundingPot.getRoundCount();
        uint8 accessId = 2;
        uint amount = 1000;

        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessId);

        fundingPot.setAccessCriteriaForRound(
            roundId, accessId, nftContract, merkleRoot, allowedAddresses
        );
        fundingPot.setAccessCriteriaPrivileges(
            roundId, accessId, 1000, false, 0, 0, 0
        );

        mockNFTContract.mint(contributor1_);

        (uint roundStart,,,,,,ILM_PC_FundingPot_v1.AccumulationMode mode) =
            fundingPot.getRoundGenericParameters(roundId);
        vm.warp(roundStart + 1);

        // Approve
        vm.prank(contributor1_);
        _token.approve(address(fundingPot), 1000);

        vm.prank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_, roundId, amount, accessId, new bytes32[](0)
        );

        assertTrue(
            fundingPot.exposed_checkRoundClosureConditions(uint32(roundId))
        );

        uint startIndex = 0;
        uint batchSize = 1;
        fundingPot.exposed_closeRound(uint32(roundId));
        fundingPot.exposed_buyBondingCurveToken(uint32(roundId));
        fundingPot.exposed_createPaymentOrdersForContributors(
            uint32(roundId), startIndex, batchSize
        );

        assertTrue(fundingPot.isRoundClosed(roundId));
    }

    // -------------------------------------------------------------------------
    // Helper Functions

    // @notice Creates edit round parameters with customizable values
    function _helper_createEditRoundParams(
        uint roundStart_,
        uint roundEnd_,
        uint roundCap_,
        address hookContract_,
        bytes memory hookFunction_,
        bool autoClosure_,
        ILM_PC_FundingPot_v1.AccumulationMode accumulationMode_
    ) internal pure returns (RoundParams memory) {
        return RoundParams({
            roundStart: roundStart_,
            roundEnd: roundEnd_,
            roundCap: roundCap_,
            hookContract: hookContract_,
            hookFunction: hookFunction_,
            autoClosure: autoClosure_,
            accumulationMode: accumulationMode_
        });
    }

    function _helper_createAccessCriteria(uint8 accessCriteriaEnum)
        internal
        view
        returns (
            address nftContract_,
            bytes32 merkleRoot_,
            address[] memory allowedAddresses_
        )
    {
        {
            if (
                accessCriteriaEnum
                    == uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.OPEN)
            ) {
                nftContract_ = address(0x0);
                merkleRoot_ = bytes32(uint(0x0));
                allowedAddresses_ = new address[](0);
            } else if (
                accessCriteriaEnum
                    == uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.NFT)
            ) {
                address nftContract = address(mockNFTContract);

                nftContract_ = nftContract;
                merkleRoot_ = bytes32(uint(0x0));
                allowedAddresses_ = new address[](0);
            } else if (
                accessCriteriaEnum
                    == uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.MERKLE)
            ) {
                bytes32 merkleRoot = ROOT;

                nftContract_ = address(0x0);
                merkleRoot_ = merkleRoot;
                allowedAddresses_ = new address[](0);
            } else if (
                accessCriteriaEnum
                    == uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.LIST)
            ) {
                address[] memory allowedAddresses = new address[](3);
                allowedAddresses[0] = address(this);
                allowedAddresses[1] = address(0x2);
                allowedAddresses[2] = address(0x3);

                nftContract_ = address(0x0);
                merkleRoot_ = bytes32(uint(0x0));
                allowedAddresses_ = allowedAddresses;
            }
        }
    }

    // Helper function to set up a round with access criteria
    function _helper_setupRoundWithAccessCriteria(uint8 accessCriteriaEnum)
        internal
    {
        uint32 roundId = fundingPot.createRound(
            _defaultRoundParams.roundStart,
            _defaultRoundParams.roundEnd,
            _defaultRoundParams.roundCap,
            _defaultRoundParams.hookContract,
            _defaultRoundParams.hookFunction,
            _defaultRoundParams.autoClosure,
            _defaultRoundParams.accumulationMode
        );

        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessCriteriaEnum);

        fundingPot.setAccessCriteriaForRound(
            roundId,
            accessCriteriaEnum,
            nftContract,
            merkleRoot,
            allowedAddresses
        );
    }

    function testContribute_PersonalMode_AccumulatesPersonalOnly() public {
        // 1. Create the first round with AccumulationMode.Personal
        _defaultRoundParams.accumulationMode = ILM_PC_FundingPot_v1.AccumulationMode.Personal;
        
        fundingPot.createRound(
            _defaultRoundParams.roundStart,
            _defaultRoundParams.roundEnd,
            1000, // Round cap of 1000
            _defaultRoundParams.hookContract,
            _defaultRoundParams.hookFunction,
            _defaultRoundParams.autoClosure,
            _defaultRoundParams.accumulationMode
        );
        uint32 round1Id = fundingPot.getRoundCount();
        
        // Set up access criteria for round 1
        uint8 accessCriteriaId = 1; // Open access
        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessCriteriaId);
        
        fundingPot.setAccessCriteriaForRound(
            round1Id,
            accessCriteriaId,
            nftContract,
            merkleRoot,
            allowedAddresses
        );
        
        // Set a personal cap of 500 for round 1
        fundingPot.setAccessCriteriaPrivileges(
            round1Id, accessCriteriaId, 500, false, 0, 0, 0
        );
        
        // 2. Create the second round, also with AccumulationMode.Personal
        // Use different start and end times to avoid overlap
        RoundParams memory params = _helper_createEditRoundParams(
            _defaultRoundParams.roundStart + 3 days,
            _defaultRoundParams.roundEnd + 3 days,
            500, // Round cap of 500
            _defaultRoundParams.hookContract,
            _defaultRoundParams.hookFunction,
            _defaultRoundParams.autoClosure,
            ILM_PC_FundingPot_v1.AccumulationMode.Personal
        );
        
        fundingPot.createRound(
            params.roundStart,
            params.roundEnd,
            params.roundCap,
            params.hookContract,
            params.hookFunction,
            params.autoClosure,
            params.accumulationMode
        );
        uint32 round2Id = fundingPot.getRoundCount();
        
        // Set up access criteria for round 2
        fundingPot.setAccessCriteriaForRound(
            round2Id, accessCriteriaId, nftContract, merkleRoot, allowedAddresses
        );
        
        // Set a personal cap of 400 for round 2
        fundingPot.setAccessCriteriaPrivileges(
            round2Id, accessCriteriaId, 400, false, 0, 0, 0
        );
        
        // First round contribution: user contributes 200 out of their 500 personal cap
        vm.warp(_defaultRoundParams.roundStart + 1);
        
        vm.startPrank(contributor1_);
        _token.approve(address(fundingPot), 1000);
        fundingPot.contributeToRoundFor(
            contributor1_, round1Id, 200, accessCriteriaId, new bytes32[](0)
        );
        vm.stopPrank();
        
        // Verify contribution to round 1
        assertEq(
            fundingPot.exposed_getUserContributionToRound(
                round1Id, contributor1_
            ),
            200
        );
        
        // Move to round 2
        vm.warp(_defaultRoundParams.roundStart + 3 days + 1);
        
        // ------------ PART 1: VERIFY PERSONAL CAP ACCUMULATION ------------
        // Create unspent capacity structure
        ILM_PC_FundingPot_v1.UnspentPersonalRoundCap[] memory unspentCaps =
            new ILM_PC_FundingPot_v1.UnspentPersonalRoundCap[](1);
        unspentCaps[0] = ILM_PC_FundingPot_v1.UnspentPersonalRoundCap({
            roundId: round1Id,
            accessCriteriaId: accessCriteriaId,
            merkleProof: new bytes32[](0)
        });
        
        // Try to contribute more than the round 2 personal cap (400)
        // In Personal mode, this should succeed up to the personal cap (400) + unspent from round 1 (300) = 700
        // But capped by round cap of 500
        vm.startPrank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_,
            round2Id,
            450, // More than the personal cap of round 2
            accessCriteriaId,
            new bytes32[](0),
            unspentCaps
        );
        vm.stopPrank();
        
        // Verify contributions to round 2 - should be more than the personal cap of round 2 (400)
        // This verifies personal caps DO accumulate
        uint contributionAmount = fundingPot.exposed_getUserContributionToRound(
            round2Id, contributor1_
        );
        assertEq(contributionAmount, 450);
        assertTrue(contributionAmount > 400, "Personal cap should accumulate"); 
        
        // ------------ PART 2: VERIFY TOTAL CAP NON-ACCUMULATION ------------
        // Clear contribution for round 2 and try again with a higher amount
        // This time we'll try to add up to the round cap of 500
        vm.startPrank(contributor2_);
        _token.approve(address(fundingPot), 200);
        
        // This should revert with RoundCapReached because the first contributor already contributed 450
        // and the round cap is 500, so only 50 more is allowed
        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1.Module__LM_PC_FundingPot__RoundCapReached.selector
            )
        );
        fundingPot.contributeToRoundFor(
            contributor2_, round2Id, 100, accessCriteriaId, new bytes32[](0)
        );
        vm.stopPrank();
        
        // But contributor2 should be able to contribute exactly the remaining amount (50)
        vm.startPrank(contributor2_);
        fundingPot.contributeToRoundFor(
            contributor2_, round2Id, 50, accessCriteriaId, new bytes32[](0)
        );
        vm.stopPrank();
        
        // Verify total contributions to round 2 is exactly the round cap
        assertEq(fundingPot.exposed_getTotalRoundContributions(round2Id), 500);
        
        // Additional contributor3 should not be able to contribute anything
        vm.startPrank(contributor3_);
        _token.approve(address(fundingPot), 100);
        
        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1.Module__LM_PC_FundingPot__RoundCapReached.selector
            )
        );
        fundingPot.contributeToRoundFor(
            contributor3_, round2Id, 1, accessCriteriaId, new bytes32[](0)
        );
        vm.stopPrank();
    }
}
