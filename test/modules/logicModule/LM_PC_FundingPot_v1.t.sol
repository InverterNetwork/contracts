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

import {
    ERC721Mock,
    MockHookContract,
    MockFailingHookContract
} from "test/utils/mocks/modules/logicModules/LM_PC_FundingPot_v1Mock.sol";

import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";

// System under Test (SuT)
import {LM_PC_FundingPot_v1_Exposed} from
    "test/modules/logicModule/LM_PC_FundingPot_v1_Exposed.sol";
import {ILM_PC_FundingPot_v1} from
    "src/modules/logicModule/interfaces/ILM_PC_FundingPot_v1.sol";

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

    // -------------------------------------------------------------------------
    // State

    // SuT

    LM_PC_FundingPot_v1_Exposed fundingPot;

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
    MockFailingHookContract failingHook = new MockFailingHookContract();

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
            accumulationMode: ILM_PC_FundingPot_v1.AccumulationMode.All
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

        uint32 roundId = fundingPot.getRoundCount();

        // Retrieve the stored parameters
        (
            uint storedRoundStart,
            uint storedRoundEnd,
            uint storedRoundCap,
            address storedHookContract,
            bytes memory storedHookFunction,
            bool storedAutoClosure,
            ILM_PC_FundingPot_v1.AccumulationMode storedAccumulationMode
        ) = fundingPot.getRoundGenericParameters(roundId);

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
        vm.assume(user_ != address(0) && user_ != address(this));
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
        (uint currentRoundStart,,,,,,) =
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
    ├── Given AccessCriteriaId is greater than MAX_ACCESS_CRITERIA_ID
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
    ├── Given all the valid parameters are provided
    │   └── When user attempts to set access criteria
    │        └── Then it should not revert
    └── Given all the valid parameters and access criteria is set
        └── When user attempts to edit access criteria
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
        ) = _helper_createAccessCriteria(accessCriteriaEnum_, roundId);

        vm.startPrank(user_);
        bytes32 roleId = _authorizer.generateRoleId(
            address(fundingPot), fundingPot.FUNDING_POT_ADMIN_ROLE()
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector, roleId, user_
            )
        );
        fundingPot.setAccessCriteria(
            roundId,
            accessCriteriaEnum_,
            0,
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
        ) = _helper_createAccessCriteria(accessCriteriaEnum, roundId);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundNotCreated
                    .selector
            )
        );
        fundingPot.setAccessCriteria(
            roundId,
            accessCriteriaEnum,
            0,
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
        ) = _helper_createAccessCriteria(accessCriteriaEnum, roundId);

        (uint roundStart,,,,,,) = fundingPot.getRoundGenericParameters(roundId);
        vm.warp(roundStart + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundAlreadyStarted
                    .selector
            )
        );
        fundingPot.setAccessCriteria(
            roundId,
            accessCriteriaEnum,
            0,
            nftContract,
            merkleRoot,
            allowedAddresses
        );
    }

    function testFuzzSetAccessCriteria_revertsGivenAccessCriteriaIdIsGreaterThanMaxAccessCriteriaId(
        uint8 accessCriteriaEnum
    ) public {
        vm.assume(accessCriteriaEnum > 4);

        testCreateRound();
        uint32 roundId = fundingPot.getRoundCount();

        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessCriteriaEnum, roundId);

        (uint roundStart,,,,,,) = fundingPot.getRoundGenericParameters(roundId);
        vm.warp(roundStart + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__InvalidAccessCriteriaId
                    .selector
            )
        );
        fundingPot.setAccessCriteria(
            roundId,
            accessCriteriaEnum,
            0,
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
        ) = _helper_createAccessCriteria(accessCriteriaEnum, roundId);
        nftContract = address(0);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__MissingRequiredAccessCriteriaData
                    .selector
            )
        );
        fundingPot.setAccessCriteria(
            roundId,
            accessCriteriaEnum,
            0,
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
        ) = _helper_createAccessCriteria(accessCriteriaEnum, roundId);
        merkleRoot = bytes32(uint(0x0));

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__MissingRequiredAccessCriteriaData
                    .selector
            )
        );
        fundingPot.setAccessCriteria(
            roundId,
            accessCriteriaEnum,
            0,
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
        ) = _helper_createAccessCriteria(accessCriteriaEnum, roundId);
        allowedAddresses = new address[](0);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__MissingRequiredAccessCriteriaData
                    .selector
            )
        );
        fundingPot.setAccessCriteria(
            roundId,
            accessCriteriaEnum,
            0,
            nftContract,
            merkleRoot,
            allowedAddresses
        );
    }

    function testFuzzSetAccessCriteria(uint8 accessCriteriaEnum) public {
        vm.assume(accessCriteriaEnum >= 0 && accessCriteriaEnum <= 4);

        testCreateRound();
        uint32 roundId = fundingPot.getRoundCount();
        uint8 accessCriteriaId = 1;

        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessCriteriaEnum, roundId);

        fundingPot.setAccessCriteria(
            roundId,
            accessCriteriaEnum,
            0,
            nftContract,
            merkleRoot,
            allowedAddresses
        );

        (
            bool isOpen,
            address retrievedNftContract,
            bytes32 retrievedMerkleRoot,
            bool hasAccess
        ) = fundingPot.getRoundAccessCriteria(uint32(roundId), accessCriteriaId);

        assertEq(isOpen, accessCriteriaEnum == 1);
        assertEq(retrievedNftContract, nftContract);
        assertEq(retrievedMerkleRoot, merkleRoot);
        if (accessCriteriaEnum == 1 || accessCriteriaEnum == 4) {
            assertTrue(hasAccess);
        } else {
            assertFalse(hasAccess);
        }
    }

    function testFuzzEditAccessCriteria(
        uint8 oldAccessCriteriaEnum,
        uint8 newAccessCriteriaEnum
    ) public {
        vm.assume(oldAccessCriteriaEnum >= 1 && oldAccessCriteriaEnum <= 4);
        vm.assume(
            newAccessCriteriaEnum != oldAccessCriteriaEnum
                && newAccessCriteriaEnum >= 1 && newAccessCriteriaEnum <= 4
        );

        testFuzzSetAccessCriteria(oldAccessCriteriaEnum);

        uint32 roundId = fundingPot.getRoundCount();
        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(newAccessCriteriaEnum, roundId);

        vm.expectEmit(true, true, true, false);
        emit ILM_PC_FundingPot_v1.AccessCriteriaEdited(
            roundId, uint8(newAccessCriteriaEnum)
        );
        fundingPot.setAccessCriteria(
            roundId,
            newAccessCriteriaEnum,
            1,
            nftContract,
            merkleRoot,
            allowedAddresses
        );
    }

    /* Test removeAllowlistedAddresses
    ├── Given user does not have FUNDING_POT_ADMIN_ROLE
    │   └── When user attempts to remove allowlisted addresses
    │       └── Then it should revert
    │
    ├── Given the round does not exist
    │   └── When user attempts to remove allowlisted addresses
    │       └── Then it should revert
    │
    ├── Given the round has already started
    │   └── When user attempts to remove allowlisted addresses
    │       └── Then it should revert
    │
    └── Given a valid round with LIST access criteria
        └── When admin removes allowlisted addresses
            └── Then the addresses should be removed from the allowlist
    */
    function testRemoveAllowlistedAddresses() public {
        testCreateRound();
        uint32 roundId = fundingPot.getRoundCount();

        uint8 accessCriteriaId = 1;
        uint8 accessType = uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.LIST);
        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessType, roundId);

        fundingPot.setAccessCriteria(
            roundId, accessType, 0, nftContract, merkleRoot, allowedAddresses
        );

        address[] memory addressesToRemove = new address[](2);
        addressesToRemove[0] = address(0x2);
        addressesToRemove[1] = contributor2_;

        fundingPot.removeAllowlistedAddresses(
            roundId, accessCriteriaId, addressesToRemove
        );

        bool hasAccess = fundingPot.exposed_checkAccessCriteriaEligibility(
            roundId, accessCriteriaId, new bytes32[](0), contributor2_
        );

        assertFalse(hasAccess);

        bool otherAddressesHaveAccess = fundingPot
            .exposed_checkAccessCriteriaEligibility(
            roundId, accessCriteriaId, new bytes32[](0), address(0x3)
        );

        assertTrue(otherAddressesHaveAccess);
    }

    /* Test: setAccessCriteriaPrivileges()
    ├── Given user does not have FUNDING_POT_ADMIN_ROLE
    │   └── When user attempts to set access criteria privileges
    │       └── Then it should revert
    │
    └── Given user has FUNDING_POT_ADMIN_ROLE
        └── Given all valid parameters are provided
            └── When user attempts to set access criteria privileges
                ├── Then it should not revert
                └── Then the access criteria privileges should be updated
    */

    function testFuzzSetAccessCriteriaPrivileges_revertsGivenUserDoesNotHaveFundingPotAdminRole(
        uint8 accessCriteriaEnum,
        address user_
    ) public {
        vm.assume(accessCriteriaEnum >= 0 && accessCriteriaEnum <= 4);
        vm.assume(user_ != address(0) && user_ != address(this));

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
        ) = _helper_createAccessCriteria(accessCriteriaEnum, roundId);

        fundingPot.setAccessCriteria(
            roundId,
            accessCriteriaEnum,
            0,
            nftContract,
            merkleRoot,
            allowedAddresses
        );

        vm.startPrank(user_);
        bytes32 roleId = _authorizer.generateRoleId(
            address(fundingPot), fundingPot.FUNDING_POT_ADMIN_ROLE()
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector, roleId, user_
            )
        );

        fundingPot.setAccessCriteriaPrivileges(roundId, 1, 1000, false, 0, 0, 0);
        vm.stopPrank();
    }

    function testFuzzSetAccessCriteriaPrivileges_worksGivenAllConditionsMet(
        uint8 accessCriteriaEnum
    ) public {
        vm.assume(accessCriteriaEnum > 0 && accessCriteriaEnum <= 4);
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
        ) = _helper_createAccessCriteria(accessCriteriaEnum, roundId);

        uint8 accessCriteriaId = 1;

        fundingPot.setAccessCriteria(
            roundId,
            accessCriteriaEnum,
            0,
            nftContract,
            merkleRoot,
            allowedAddresses
        );

        fundingPot.setAccessCriteriaPrivileges(
            roundId, accessCriteriaId, 1000, false, 0, 0, 0
        );

        (
            uint personalCap,
            bool overrideContributionSpan,
            uint start,
            uint cliff,
            uint end
        ) = fundingPot.getRoundAccessCriteriaPrivileges(
            roundId, accessCriteriaId
        );

        assertEq(personalCap, 1000);
        assertEq(overrideContributionSpan, false);
        assertEq(start, 0);
        assertEq(cliff, 0);
        assertEq(end, 0);
    }

    /* Test: getRoundAccessCriteriaPrivileges()
    ├── Given the access criteria does not exist
    │   └── When user attempts to get access criteria privileges
    │       └── Then it should return default values
    
    */
    function testFuzzGetRoundAccessCriteriaPrivileges_returnsDefaultValuesGivenInvalidAccessCriteriaId(
        uint8 accessCriteriaEnum
    ) public {
        vm.assume(accessCriteriaEnum > 4);

        RoundParams memory params = _defaultRoundParams;

        uint32 roundId = fundingPot.createRound(
            params.roundStart,
            params.roundEnd,
            params.roundCap,
            params.hookContract,
            params.hookFunction,
            params.autoClosure,
            params.accumulationMode
        );

        (
            uint personalCap,
            bool overrideContributionSpan,
            uint start,
            uint cliff,
            uint end
        ) = fundingPot.getRoundAccessCriteriaPrivileges(
            roundId, accessCriteriaEnum
        );

        assertEq(personalCap, 0);
        assertFalse(overrideContributionSpan);
        assertEq(start, 0);
        assertEq(cliff, 0);
        assertEq(end, 0);
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
    │   ├── Given the user tries to contribute with a zero amount
    │   │   └── When the user contributes to the round
    │   │       └── Then the transaction should revert
    │   │
    │   └── Given a user has already contributed up to their personal cap
    │       └── When the user attempts to contribute again
    │           └── Then the transaction should revert
    │
    └── Given the round contribution cap is reached
        └── When the user attempts to contribute
            └── Then the transaction should revert
    */

    function testContributeToRoundFor_revertsGivenContributionIsBeforeRoundStart(
    ) public {
        testCreateRound();

        uint32 roundId = fundingPot.getRoundCount();
        uint8 accessCriteriaId = 1;
        uint8 accessType = uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.OPEN);
        uint amount = 250;

        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessType, roundId);

        fundingPot.setAccessCriteria(
            roundId, accessType, 0, nftContract, merkleRoot, allowedAddresses
        );
        fundingPot.setAccessCriteriaPrivileges(
            roundId, accessCriteriaId, 500, false, 0, 0, 0
        );

        // Approve
        vm.prank(contributor1_);
        _token.approve(address(fundingPot), amount);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundHasNotStarted
                    .selector
            )
        );

        vm.prank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_, roundId, amount, accessCriteriaId, new bytes32[](0)
        );
    }

    function testContributeToRoundFor_revertsGivenContributionIsAfterRoundEnd()
        public
    {
        testCreateRound();

        uint32 roundId = fundingPot.getRoundCount();
        uint8 accessCriteriaId = 1;
        uint8 accessType = uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.OPEN);

        uint amount = 250;

        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessType, roundId);

        fundingPot.setAccessCriteria(
            roundId, accessType, 0, nftContract, merkleRoot, allowedAddresses
        );
        fundingPot.setAccessCriteriaPrivileges(
            roundId, accessCriteriaId, 500, false, 0, 0, 0
        );

        (uint roundStart,,,,,,) = fundingPot.getRoundGenericParameters(roundId);
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
            contributor1_, roundId, amount, accessCriteriaId, new bytes32[](0)
        );
    }

    function testContributeToRoundFor_revertsGivenNFTAccessCriteriaIsNotMet()
        public
    {
        uint8 accessCriteriaId = 1;
        uint8 accessType = uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.NFT);
        _helper_setupRoundWithAccessCriteria(accessType);

        uint32 roundId = fundingPot.getRoundCount();

        uint amount = 250;

        (uint roundStart,,,,,,) = fundingPot.getRoundGenericParameters(roundId);
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
            contributor1_, roundId, amount, accessCriteriaId, new bytes32[](0)
        );
    }

    function testContributeToRoundFor_revertsGivenMerkleRootAccessCriteriaIsNotMet(
    ) public {
        testCreateRound();

        uint32 roundId = fundingPot.getRoundCount();
        uint8 accessCriteriaId = 1;
        uint8 accessType = uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.MERKLE);
        uint amount = 250;

        (,,,, bytes32[] memory proofB) = _helper_generateMerkleTreeForTwoLeaves(
            contributor1_, contributor2_, roundId
        );

        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessType, roundId);

        fundingPot.setAccessCriteria(
            roundId, accessType, 0, nftContract, merkleRoot, allowedAddresses
        );
        fundingPot.setAccessCriteriaPrivileges(
            roundId, accessCriteriaId, 500, false, 0, 0, 0
        );

        (uint roundStart,,,,,,) = fundingPot.getRoundGenericParameters(roundId);
        vm.warp(roundStart + 1);

        // Approve
        vm.prank(contributor3_);
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
            contributor1_, roundId, amount, accessCriteriaId, proofB
        );
    }

    function testContributeToRoundFor_revertsGivenAllowedListAccessCriteriaIsNotMet(
    ) public {
        testCreateRound();

        uint32 roundId = fundingPot.getRoundCount();
        uint8 accessCriteriaId = 1;
        uint8 accessType = uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.LIST);
        uint amount = 250;

        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessType, roundId);

        fundingPot.setAccessCriteria(
            roundId, accessType, 0, nftContract, merkleRoot, allowedAddresses
        );
        fundingPot.setAccessCriteriaPrivileges(
            roundId, accessCriteriaId, 500, false, 0, 0, 0
        );

        (uint roundStart,,,,,,) = fundingPot.getRoundGenericParameters(roundId);
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
            contributor1_, roundId, amount, accessCriteriaId, new bytes32[](0)
        );
    }

    function testContributeToRoundFor_revertsGivenPreviousContributionExceedsPersonalCap(
    ) public {
        testCreateRound();

        uint32 roundId = fundingPot.getRoundCount();
        uint8 accessCriteriaId = 1;
        uint8 accessType = uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.NFT);
        uint amount = 500;

        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessType, roundId);

        fundingPot.setAccessCriteria(
            roundId, accessType, 0, nftContract, merkleRoot, allowedAddresses
        );
        fundingPot.setAccessCriteriaPrivileges(
            roundId, accessCriteriaId, 500, false, 0, 0, 0
        );

        mockNFTContract.mint(contributor1_);

        (uint roundStart,,,,,,) = fundingPot.getRoundGenericParameters(roundId);
        vm.warp(roundStart + 1);

        // Approve
        vm.prank(contributor1_);
        _token.approve(address(fundingPot), 1000);

        vm.prank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_, roundId, amount, accessCriteriaId, new bytes32[](0)
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
            contributor1_, roundId, 251, accessCriteriaId, new bytes32[](0)
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
    │
    ├──  Given the access criteria is NFT
    │    And the user fulfills the access criteria
    │       └── When the user contributes to the round
    │           └── Then the funds are transferred to the funding pot
    │               And the contribution is recorded
    │
    ├──  Given the access criteria is MERKLE 
    │   And the user fulfills the access criteria
    │   └── When the user contributes to the round
    │       └── Then the funds are transferred to the funding pot
    │           And the contribution is recorded
    │
    ├──  Given the access criteria is LIST
    │   And the user fulfills the access criteria
    │   └── When the user contributes to the round
    │       └── Then the funds are transferred to the funding pot
    │           And the contribution is recorded
    │
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

        uint8 accessCriteriaId = 1;
        uint8 accessType = uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.NFT);

        uint32 roundId = fundingPot.getRoundCount();
        uint amount = 250;

        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessType, roundId);

        fundingPot.setAccessCriteria(
            roundId, accessType, 0, nftContract, merkleRoot, allowedAddresses
        );
        fundingPot.setAccessCriteriaPrivileges(
            roundId, accessCriteriaId, 1000, false, 0, 0, 0
        );
        mockNFTContract.mint(contributor1_);

        (bool isEligible, uint remainingAmountAllowedToContribute) = fundingPot
            .getUserEligibility(
            roundId, accessCriteriaId, new bytes32[](0), contributor1_
        );

        assertTrue(isEligible);
        assertEq(remainingAmountAllowedToContribute, 1000);

        vm.warp(_defaultRoundParams.roundStart + 1);

        // Approve
        vm.prank(contributor1_);
        _token.approve(address(fundingPot), amount);

        vm.expectEmit(true, false, false, true);
        emit ILM_PC_FundingPot_v1.ContributionMade(
            roundId, contributor1_, amount
        );

        vm.prank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_, roundId, amount, accessCriteriaId, new bytes32[](0)
        );

        uint totalContributions = fundingPot.getTotalRoundContribution(roundId);

        assertEq(totalContributions, amount);

        uint personalContributions =
            fundingPot.getUserContributionToRound(roundId, contributor1_);
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
        uint8 accessCriteriaId = 1;
        uint8 accessType = uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.NFT);
        _helper_setupRoundWithAccessCriteria(accessCriteriaId);
        uint32 roundId = fundingPot.getRoundCount();

        mockNFTContract.mint(contributor1_);

        fundingPot.setAccessCriteriaPrivileges(
            roundId, accessCriteriaId, 500, false, 0, 0, 0
        );

        vm.warp(_defaultRoundParams.roundStart + 1);

        vm.startPrank(contributor1_);
        _token.approve(address(fundingPot), 250);

        vm.expectEmit(true, false, false, true);
        emit ILM_PC_FundingPot_v1.ContributionMade(roundId, contributor1_, 250);

        fundingPot.contributeToRoundFor(
            contributor1_, roundId, 250, accessCriteriaId, new bytes32[](0)
        );
        vm.stopPrank();

        uint userContribution =
            fundingPot.getUserContributionToRound(roundId, contributor1_);
        assertEq(userContribution, 250);

        uint totalContributions = fundingPot.getTotalRoundContribution(roundId);
        assertEq(totalContributions, 250);
    }

    function testContributeToRoundFor_worksGivenMerkleAccessCriteriaMet()
        public
    {
        uint8 accessCriteriaId = 1;
        uint8 accessType = uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.MERKLE);

        _helper_setupRoundWithAccessCriteria(accessType);

        uint32 roundId = fundingPot.getRoundCount();

        (,,,, bytes32[] memory proofB) = _helper_generateMerkleTreeForTwoLeaves(
            contributor1_, contributor2_, roundId
        );

        fundingPot.setAccessCriteriaPrivileges(
            roundId, accessCriteriaId, 500, false, 0, 0, 0
        );

        vm.warp(_defaultRoundParams.roundStart + 1);

        uint contributionAmount = 250;
        vm.startPrank(contributor2_);
        _token.approve(address(fundingPot), contributionAmount);

        vm.expectEmit(true, false, false, true);
        emit ILM_PC_FundingPot_v1.ContributionMade(
            roundId, contributor2_, contributionAmount
        );
        fundingPot.contributeToRoundFor(
            contributor2_, roundId, contributionAmount, accessCriteriaId, proofB
        );

        vm.stopPrank();

        uint userContribution =
            fundingPot.getUserContributionToRound(roundId, contributor2_);
        assertEq(userContribution, contributionAmount);

        uint totalContributions = fundingPot.getTotalRoundContribution(roundId);
        assertEq(totalContributions, contributionAmount);
    }

    function testContributeToRoundFor_worksGivenUserCurrentContributionExceedsTheRoundCap(
    ) public {
        _defaultRoundParams.roundCap = 150;
        _defaultRoundParams.autoClosure = true;

        uint8 accessCriteriaId = 1;
        uint8 accessType = uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.NFT);

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
        ) = _helper_createAccessCriteria(accessType, roundId);

        fundingPot.setAccessCriteria(
            roundId, accessType, 0, nftContract, merkleRoot, allowedAddresses
        );

        uint personalCap = 200;
        fundingPot.setAccessCriteriaPrivileges(
            roundId, accessCriteriaId, personalCap, false, 0, 0, 0
        );

        mockNFTContract.mint(contributor1_);
        mockNFTContract.mint(contributor2_);

        vm.warp(_defaultRoundParams.roundStart);

        vm.startPrank(contributor1_);
        _token.approve(address(fundingPot), 100);
        fundingPot.contributeToRoundFor(
            contributor1_, roundId, 100, accessCriteriaId, new bytes32[](0)
        );
        vm.stopPrank();

        vm.startPrank(contributor2_);
        _token.approve(address(fundingPot), 100);
        fundingPot.contributeToRoundFor(
            contributor2_, roundId, 100, accessCriteriaId, new bytes32[](0)
        );
        vm.stopPrank();

        uint contribution =
            fundingPot.getUserContributionToRound(roundId, contributor2_);
        assertEq(contribution, 50);

        uint totalContribution = fundingPot.getTotalRoundContribution(roundId);
        assertEq(totalContribution, _defaultRoundParams.roundCap);
        assertTrue(fundingPot.isRoundClosed(roundId));
    }

    function testContributeToRoundFor_worksGivenContributionPartiallyExceedingPersonalCap(
    ) public {
        testCreateRound();

        uint32 roundId = fundingPot.getRoundCount();
        uint8 accessCriteriaId = 1;
        uint8 accessType = uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.NFT);

        uint firstAmount = 400;
        uint personalCap = 500;

        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessType, roundId);

        fundingPot.setAccessCriteria(
            roundId, accessType, 0, nftContract, merkleRoot, allowedAddresses
        );
        fundingPot.setAccessCriteriaPrivileges(
            roundId, accessCriteriaId, personalCap, false, 0, 0, 0
        );

        mockNFTContract.mint(contributor1_);

        (uint roundStart,,,,,,) = fundingPot.getRoundGenericParameters(roundId);
        vm.warp(roundStart + 1);

        // Approve
        vm.prank(contributor1_);
        _token.approve(address(fundingPot), 1000 ether);

        vm.expectEmit(true, false, false, true);
        emit ILM_PC_FundingPot_v1.ContributionMade(
            roundId, contributor1_, firstAmount
        );

        // First contribution
        vm.prank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_,
            roundId,
            firstAmount,
            accessCriteriaId,
            new bytes32[](0)
        );

        uint secondAmount = 200;
        uint expectedSecondAmount = personalCap - firstAmount;

        vm.expectEmit(true, false, false, true);
        emit ILM_PC_FundingPot_v1.ContributionMade(
            roundId, contributor1_, expectedSecondAmount
        );

        vm.prank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_,
            roundId,
            secondAmount,
            accessCriteriaId,
            new bytes32[](0)
        );

        uint totalContribution =
            fundingPot.getUserContributionToRound(roundId, contributor1_);

        assertEq(totalContribution, personalCap);
    }

    function testContributeToRoundFor_worksGivenUserCanOverrideTimeConstraints()
        public
    {
        testCreateRound();

        uint32 roundId = fundingPot.getRoundCount();
        uint8 accessCriteriaId = 1;
        uint8 accessType = uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.NFT);
        uint amount = 250;

        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessType, roundId);

        fundingPot.setAccessCriteria(
            roundId, accessType, 0, nftContract, merkleRoot, allowedAddresses
        );

        // Set privileges with override capability
        fundingPot.setAccessCriteriaPrivileges(
            roundId, accessCriteriaId, 500, true, 0, 0, 0
        );

        mockNFTContract.mint(contributor1_);

        (uint roundStart,,,,,,) = fundingPot.getRoundGenericParameters(roundId);

        vm.warp(roundStart + 10 days);

        // Approve
        vm.prank(contributor1_);
        _token.approve(address(fundingPot), amount);

        // Expect the ContributionMade event to be emitted
        vm.expectEmit(true, true, false, true);
        emit ILM_PC_FundingPot_v1.ContributionMade(
            roundId, contributor1_, amount
        );

        // This should succeed despite being after round end, due to override privilege
        vm.prank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_, roundId, amount, accessCriteriaId, new bytes32[](0)
        );

        // Verify the contribution was recorded
        uint totalContribution = fundingPot.getTotalRoundContribution(roundId);
        assertEq(totalContribution, amount);
    }

    function testContributeToRoundFor_worksGivenPersonalCapAccumulation()
        public
    {
        _defaultRoundParams.accumulationMode =
            ILM_PC_FundingPot_v1.AccumulationMode.Personal;
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
        uint8 accessCriteriaType =
            uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.NFT);
        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessCriteriaType, round1Id);
        fundingPot.setAccessCriteria(
            round1Id,
            accessCriteriaType,
            0,
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

        fundingPot.setAccessCriteria(
            round2Id,
            accessCriteriaType,
            0,
            nftContract,
            merkleRoot,
            allowedAddresses
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

        vm.expectEmit(true, false, false, true);
        emit ILM_PC_FundingPot_v1.ContributionMade(round2Id, contributor1_, 700);

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

        assertEq(
            fundingPot.getUserContributionToRound(round1Id, contributor1_), 200
        );

        assertEq(
            fundingPot.getUserContributionToRound(round2Id, contributor1_), 700
        );
    }

    function testContributeToRoundFor_worksGivenTotalRoundCapAccumulation()
        public
    {
        _defaultRoundParams.accumulationMode =
            ILM_PC_FundingPot_v1.AccumulationMode.All;

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

        uint8 accessCriteriaId = 1;
        uint8 accessType = uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.OPEN);

        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessType, round1Id);
        fundingPot.setAccessCriteria(
            round1Id, accessType, 0, nftContract, merkleRoot, allowedAddresses
        );
        fundingPot.setAccessCriteriaPrivileges(
            round1Id, accessCriteriaId, 500, false, 0, 0, 0
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
        fundingPot.setAccessCriteria(
            round2Id, accessType, 0, nftContract, merkleRoot, allowedAddresses
        );
        fundingPot.setAccessCriteriaPrivileges(
            round2Id, accessCriteriaId, 500, false, 0, 0, 0
        );

        // Round 1: Multiple users contribute, but don't reach the cap
        vm.warp(_defaultRoundParams.roundStart + 1);

        vm.startPrank(contributor1_);
        _token.approve(address(fundingPot), 300);
        fundingPot.contributeToRoundFor(
            contributor1_, round1Id, 300, accessCriteriaId, new bytes32[](0)
        );
        vm.stopPrank();

        vm.startPrank(contributor2_);
        _token.approve(address(fundingPot), 200);
        fundingPot.contributeToRoundFor(
            contributor2_, round1Id, 200, accessCriteriaId, new bytes32[](0)
        );
        vm.stopPrank();

        // Move to Round 2
        vm.warp(_defaultRoundParams.roundStart + 3 days + 1);

        vm.startPrank(contributor2_);
        _token.approve(address(fundingPot), 400);
        fundingPot.contributeToRoundFor(
            contributor2_, round2Id, 400, accessCriteriaId, new bytes32[](0)
        );
        vm.stopPrank();

        vm.startPrank(contributor3_);
        _token.approve(address(fundingPot), 300);
        fundingPot.contributeToRoundFor(
            contributor3_, round2Id, 300, accessCriteriaId, new bytes32[](0)
        );
        vm.stopPrank();

        assertEq(fundingPot.getTotalRoundContribution(round1Id), 500);
        assertEq(
            fundingPot.getUserContributionToRound(round1Id, contributor1_), 300
        );
        assertEq(
            fundingPot.getUserContributionToRound(round1Id, contributor2_), 200
        );

        assertEq(fundingPot.getTotalRoundContribution(round2Id), 700);
        assertEq(
            fundingPot.getUserContributionToRound(round2Id, contributor2_), 400
        );
        assertEq(
            fundingPot.getUserContributionToRound(round2Id, contributor3_), 300
        );

        assertEq(fundingPot.getTotalRoundContribution(round2Id), 700);
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
    ├── Given hook execution fails
    │   └── When user attempts to close the round
    │       └── Then it should revert with Module__LM_PC_FundingPot__HookExecutionFailed
    │
    ├── Given closure conditions are not met
    │   └── When user attempts to close the round
    │       └── Then it should revert with Module__LM_PC_FundingPot__ClosureConditionsNotMet
    │
    ├── Given round has started but not ended
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

    function testFuzzCloseRound_revertsGivenRoundDoesNotExist(
        uint8 accessCriteriaEnum
    ) public {
        vm.assume(accessCriteriaEnum >= 0 && accessCriteriaEnum <= 4);

        uint32 roundId = fundingPot.getRoundCount();

        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessCriteriaEnum, roundId);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundNotCreated
                    .selector
            )
        );
        fundingPot.closeRound(roundId);
    }

    function testCloseRound_revertsGivenHookExecutionFails() public {
        uint8 accessCriteriaId =
            uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.OPEN);

        uint32 roundId = fundingPot.createRound(
            _defaultRoundParams.roundStart,
            _defaultRoundParams.roundEnd,
            _defaultRoundParams.roundCap,
            address(failingHook),
            abi.encodeWithSignature("executeHook()"),
            _defaultRoundParams.autoClosure,
            _defaultRoundParams.accumulationMode
        );

        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessCriteriaId, roundId);

        fundingPot.setAccessCriteria(
            roundId,
            accessCriteriaId,
            0,
            nftContract,
            merkleRoot,
            allowedAddresses
        );

        fundingPot.setAccessCriteriaPrivileges(roundId, 0, 1000, false, 0, 0, 0);

        vm.warp(_defaultRoundParams.roundEnd + 1);

        vm.expectRevert(
            ILM_PC_FundingPot_v1
                .Module__LM_PC_FundingPot__HookExecutionFailed
                .selector
        );
        fundingPot.closeRound(roundId);
    }

    function testCloseRound_revertsGivenClosureConditionsNotMet() public {
        uint8 accessCriteriaId =
            uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.OPEN);

        _helper_setupRoundWithAccessCriteria(accessCriteriaId);
        uint32 roundId = fundingPot.getRoundCount();

        fundingPot.setAccessCriteriaPrivileges(roundId, 0, 1000, false, 0, 0, 0);

        vm.expectRevert(
            ILM_PC_FundingPot_v1
                .Module__LM_PC_FundingPot__ClosureConditionsNotMet
                .selector
        );
        fundingPot.closeRound(roundId);
    }

    function testCloseRound_revertsGivenRoundHasAlreadyBeenClosed() public {
        uint8 accessCriteriaId =
            uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.OPEN);

        _helper_setupRoundWithAccessCriteria(accessCriteriaId);
        uint32 roundId = fundingPot.getRoundCount();
        fundingPot.setAccessCriteriaPrivileges(
            roundId, accessCriteriaId, 1000, false, 0, 0, 0
        );

        (uint roundStart,,,,,,) = fundingPot.getRoundGenericParameters(roundId);

        vm.warp(roundStart + 1);

        vm.startPrank(contributor1_);
        _token.approve(address(fundingPot), 1000);
        fundingPot.contributeToRoundFor(
            contributor1_, roundId, 1000, accessCriteriaId, new bytes32[](0)
        );
        vm.stopPrank();

        fundingPot.closeRound(roundId);
        vm.expectRevert(
            ILM_PC_FundingPot_v1
                .Module__LM_PC_FundingPot__RoundHasEnded
                .selector
        );
        fundingPot.closeRound(roundId);
    }

    function testCloseRound_worksGivenRoundHasStartedButNotEnded() public {
        testCreateRound();
        uint32 roundId = fundingPot.getRoundCount();

        uint8 accessCriteriaId = 1;
        uint8 accessType = uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.OPEN);
        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessType, roundId);

        fundingPot.setAccessCriteria(
            roundId, accessType, 0, nftContract, merkleRoot, allowedAddresses
        );
        fundingPot.setAccessCriteriaPrivileges(
            roundId, accessCriteriaId, 1000, false, 0, 0, 0
        );

        // Warp to round start
        (uint roundStart,,,,,,) = fundingPot.getRoundGenericParameters(roundId);
        vm.warp(roundStart + 1);

        // Make a contribution
        vm.startPrank(contributor1_);
        _token.approve(address(fundingPot), 1000);
        fundingPot.contributeToRoundFor(
            contributor1_, roundId, 1000, accessCriteriaId, new bytes32[](0)
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

        uint8 accessCriteriaId = 1;
        uint8 accessType = uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.OPEN);

        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessType, roundId);

        fundingPot.setAccessCriteria(
            roundId, accessType, 0, nftContract, merkleRoot, allowedAddresses
        );
        fundingPot.setAccessCriteriaPrivileges(
            roundId, accessCriteriaId, 1000, false, 0, 0, 0
        );

        // Make a contribution
        (uint roundStart, uint roundEnd,,,,,) =
            fundingPot.getRoundGenericParameters(roundId);
        vm.warp(roundStart + 1);

        vm.startPrank(contributor1_);
        _token.approve(address(fundingPot), 500);
        fundingPot.contributeToRoundFor(
            contributor1_, roundId, 500, accessCriteriaId, new bytes32[](0)
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
        uint8 accessCriteriaId = 1;
        uint8 accessType = uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.NFT);

        uint amount = 1000;

        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessType, roundId);

        fundingPot.setAccessCriteria(
            roundId, accessType, 0, nftContract, merkleRoot, allowedAddresses
        );
        fundingPot.setAccessCriteriaPrivileges(
            roundId, accessCriteriaId, 1000, false, 0, 0, 0
        );

        mockNFTContract.mint(contributor1_);

        (uint roundStart,,,,,,) = fundingPot.getRoundGenericParameters(roundId);
        vm.warp(roundStart + 1);

        // Approve
        vm.prank(contributor1_);
        _token.approve(address(fundingPot), 1000);

        vm.prank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_, roundId, amount, accessCriteriaId, new bytes32[](0)
        );

        assertEq(fundingPot.isRoundClosed(roundId), false);
        fundingPot.closeRound(roundId);
        assertEq(fundingPot.isRoundClosed(roundId), true);
    }

    function testCloseRound_worksGivenRoundisAutoClosure() public {
        testEditRound();

        uint32 roundId = fundingPot.getRoundCount();
        uint8 accessCriteriaId = 1;
        uint8 accessType = uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.OPEN);

        uint amount = 2000;

        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessType, roundId);

        fundingPot.setAccessCriteria(
            roundId, accessType, 0, nftContract, merkleRoot, allowedAddresses
        );

        fundingPot.setAccessCriteriaPrivileges(
            roundId, accessCriteriaId, 2000, false, 0, 0, 0
        );
        mockNFTContract.mint(contributor1_);

        (uint roundStart,,,,,,) = fundingPot.getRoundGenericParameters(roundId);
        vm.warp(roundStart + 1);

        // Approve
        vm.prank(contributor1_);
        _token.approve(address(fundingPot), 2000);

        vm.prank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_, roundId, amount, accessCriteriaId, new bytes32[](0)
        );

        assertEq(fundingPot.isRoundClosed(roundId), true);
    }

    function testCloseRound_worksWithMultipleContributors() public {
        testCreateRound();
        uint32 roundId = fundingPot.getRoundCount();

        // Set up access criteria
        uint8 accessCriteriaId = 1;
        uint8 accessType = uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.OPEN);

        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessType, roundId);

        fundingPot.setAccessCriteria(
            roundId, accessType, 0, nftContract, merkleRoot, allowedAddresses
        );
        fundingPot.setAccessCriteriaPrivileges(
            roundId, accessCriteriaId, 1000, false, 0, 0, 0
        );

        // Warp to round start
        (uint roundStart,,,,,,) = fundingPot.getRoundGenericParameters(roundId);
        vm.warp(roundStart + 1);

        // Multiple contributors
        vm.startPrank(contributor1_);
        _token.approve(address(fundingPot), 500);
        fundingPot.contributeToRoundFor(
            contributor1_, roundId, 500, accessCriteriaId, new bytes32[](0)
        );
        vm.stopPrank();

        vm.startPrank(contributor2_);
        _token.approve(address(fundingPot), 200);
        fundingPot.contributeToRoundFor(
            contributor2_, roundId, 200, accessCriteriaId, new bytes32[](0)
        );
        vm.stopPrank();

        vm.startPrank(contributor3_);
        _token.approve(address(fundingPot), 300);
        fundingPot.contributeToRoundFor(
            contributor3_, roundId, 300, accessCriteriaId, new bytes32[](0)
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
        bytes32 roleId = _authorizer.generateRoleId(
            address(fundingPot), fundingPot.FUNDING_POT_ADMIN_ROLE()
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector,
                roleId,
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
    function testFuzz_validateAndAdjustCapsWithUnspentCap(
        uint32 roundId_,
        uint amount_,
        uint8 accessCriteriaId_,
        bool canOverrideContributionSpan_,
        uint unspentPersonalCap_
    ) external {
        vm.assume(roundId_ > 0 && roundId_ >= fundingPot.getRoundCount());
        vm.assume(amount_ <= 1000);
        vm.assume(accessCriteriaId_ <= 4);
        vm.assume(unspentPersonalCap_ >= 0);

        try fundingPot.exposed_validateAndAdjustCapsWithUnspentCap(
            contributor1_,
            roundId_,
            amount_,
            accessCriteriaId_,
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

    function testFuzz_ValidTimes(uint start, uint cliff, uint end) public {
        vm.assume(cliff <= type(uint).max - start);

        bool isValid = fundingPot.exposed_validTimes(start, cliff, end);

        assertEq(isValid, start + cliff <= end);

        if (start > end) {
            assertFalse(isValid);
        }

        if (start == end) {
            assertEq(isValid, cliff == 0);
        }
    }

    // -------------------------------------------------------------------------
    // Test: _calculateUnusedCapacityFromPreviousRounds

    function test_calculateUnusedCapacityFromPreviousRounds() public {
        // round 1 (no accumulation)
        fundingPot.createRound(
            _defaultRoundParams.roundStart,
            _defaultRoundParams.roundEnd,
            _defaultRoundParams.roundCap,
            _defaultRoundParams.hookContract,
            _defaultRoundParams.hookFunction,
            _defaultRoundParams.autoClosure,
            ILM_PC_FundingPot_v1.AccumulationMode.Disabled
        );

        // round 2 (with accumulation)
        fundingPot.createRound(
            _defaultRoundParams.roundStart + 300,
            _defaultRoundParams.roundEnd + 400,
            _defaultRoundParams.roundCap,
            _defaultRoundParams.hookContract,
            _defaultRoundParams.hookFunction,
            _defaultRoundParams.autoClosure,
            ILM_PC_FundingPot_v1.AccumulationMode.All // globalAccumulativeCaps on
        );

        // round 3
        fundingPot.createRound(
            _defaultRoundParams.roundStart + 500,
            _defaultRoundParams.roundEnd + 600,
            _defaultRoundParams.roundCap,
            _defaultRoundParams.hookContract,
            _defaultRoundParams.hookFunction,
            _defaultRoundParams.autoClosure,
            ILM_PC_FundingPot_v1.AccumulationMode.All
        );

        // Calculate unused capacity
        uint actualUnusedCapacity =
            fundingPot.exposed_calculateUnusedCapacityFromPreviousRounds(3);
        assertEq(actualUnusedCapacity, 1000);
    }

    // -------------------------------------------------------------------------
    // Test: _contributeToRoundFor()

    function testFuzz_contributeToRoundFor_revertsGivenInvalidAccessCriteria(
        uint8 accessCriteriaEnum
    ) public {
        vm.assume(accessCriteriaEnum > 4);

        testCreateRound();
        uint32 roundId = fundingPot.getRoundCount();
        (uint roundStart,,,,,,) = fundingPot.getRoundGenericParameters(roundId);
        vm.warp(roundStart + 1);

        vm.prank(contributor1_);
        _token.approve(address(fundingPot), 1000);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__InvalidAccessCriteriaId
                    .selector
            )
        );

        fundingPot.exposed_contributeToRoundFor(
            contributor1_,
            roundId,
            1000,
            accessCriteriaEnum,
            new bytes32[](0),
            0
        );
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
        uint8 accessCriteriaId = 1;
        uint8 accessType = uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.OPEN);

        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessType, roundId);
        fundingPot.setAccessCriteria(
            roundId, accessType, 0, nftContract, merkleRoot, allowedAddresses
        );
        fundingPot.setAccessCriteriaPrivileges(
            roundId, accessCriteriaId, 1000, false, 0, 0, 0
        );

        vm.warp(params.roundStart + 1);
        vm.startPrank(contributor1_);
        _token.approve(address(fundingPot), params.roundCap);
        fundingPot.contributeToRoundFor(
            contributor1_,
            roundId,
            params.roundCap,
            accessCriteriaId,
            new bytes32[](0)
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
        uint8 accessCriteriaId = 1;
        uint8 accessType = uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.OPEN);

        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessType, roundId);
        fundingPot.setAccessCriteria(
            roundId, accessType, 0, nftContract, merkleRoot, allowedAddresses
        );
        fundingPot.setAccessCriteriaPrivileges(
            roundId,
            accessCriteriaId,
            1000,
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
            contributor1_,
            roundId,
            params.roundCap,
            accessCriteriaId,
            new bytes32[](0)
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

    function test_closeRound_worksGivenCapReached() public {
        testCreateRound();

        uint32 roundId = fundingPot.getRoundCount();
        uint8 accessCriteriaId = 1;
        uint8 accessType = uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.OPEN);

        uint amount = 1000;

        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(accessType, roundId);

        fundingPot.setAccessCriteria(
            roundId, accessType, 0, nftContract, merkleRoot, allowedAddresses
        );
        fundingPot.setAccessCriteriaPrivileges(
            roundId, accessCriteriaId, 1000, false, 0, 0, 0
        );

        mockNFTContract.mint(contributor1_);

        (uint roundStart,,,,,,) = fundingPot.getRoundGenericParameters(roundId);
        vm.warp(roundStart + 1);

        // Approve
        vm.prank(contributor1_);
        _token.approve(address(fundingPot), 1000);

        vm.prank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_, roundId, amount, accessCriteriaId, new bytes32[](0)
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
    // Test: _buyBondingCurveToken
    function test_buyBondingCurveToken_revertsGivenNoContributions() public {
        testCreateRound();
        uint32 roundId = fundingPot.getRoundCount();
        (uint roundStart,,,,,,) = fundingPot.getRoundGenericParameters(roundId);
        vm.warp(roundStart + 1);

        vm.expectRevert(
            ILM_PC_FundingPot_v1
                .Module__LM_PC_FundingPot__NoContributions
                .selector
        );
        fundingPot.exposed_buyBondingCurveToken(roundId);
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

    function _helper_generateMerkleTreeForTwoLeaves(
        address contributorA,
        address contributorB,
        uint32 roundId
    )
        internal
        pure
        returns (
            bytes32 root,
            bytes32 leafA,
            bytes32 leafB,
            bytes32[] memory proofA,
            bytes32[] memory proofB
        )
    {
        leafA = keccak256(abi.encodePacked(contributorA, roundId));
        leafB = keccak256(abi.encodePacked(contributorB, roundId));

        proofA = new bytes32[](1);
        proofB = new bytes32[](1);

        // Ensure consistent ordering for root calculation
        if (leafA < leafB) {
            root = keccak256(abi.encodePacked(leafA, leafB));
            proofA[0] = leafB; // Proof for A is B
            proofB[0] = leafA; // Proof for B is A
        } else {
            root = keccak256(abi.encodePacked(leafB, leafA));
            proofA[0] = leafB; // Proof for A is still B
            proofB[0] = leafA; // Proof for B is still A
        }
    }

    function _helper_createAccessCriteria(
        uint8 accessCriteriaEnum,
        uint32 roundId
    )
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
                (bytes32 merkleRoot,,,,) =
                _helper_generateMerkleTreeForTwoLeaves(
                    contributor1_, contributor2_, roundId
                );

                nftContract_ = address(0x0);
                merkleRoot_ = merkleRoot;
                allowedAddresses_ = new address[](0);
            } else if (
                accessCriteriaEnum
                    == uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.LIST)
            ) {
                address[] memory allowedAddresses = new address[](4);
                allowedAddresses[0] = address(this);
                allowedAddresses[1] = address(0x2);
                allowedAddresses[2] = address(0x3);
                allowedAddresses[3] = contributor2_;
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
        ) = _helper_createAccessCriteria(accessCriteriaEnum, roundId);

        fundingPot.setAccessCriteria(
            roundId,
            accessCriteriaEnum,
            0,
            nftContract,
            merkleRoot,
            allowedAddresses
        );
    }

    function testContribute_PersonalMode_AccumulatesPersonalOnly() public {
        // 1. Create the first round with AccumulationMode.Personal
        _defaultRoundParams.accumulationMode =
            ILM_PC_FundingPot_v1.AccumulationMode.Personal;

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
        ) = _helper_createAccessCriteria(
            uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.OPEN), round1Id
        );

        fundingPot.setAccessCriteria(
            round1Id,
            uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.OPEN), // accessCriteriaType
            0, // accessCriteriaId (0 for new)
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
        fundingPot.setAccessCriteria(
            round2Id,
            uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.OPEN), // accessCriteriaType
            0, // accessCriteriaId (0 for new)
            nftContract,
            merkleRoot,
            allowedAddresses
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
            fundingPot.getUserContributionToRound(round1Id, contributor1_), 200
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
        uint contributionAmount =
            fundingPot.getUserContributionToRound(round2Id, contributor1_);
        assertEq(contributionAmount, 450);
        assertTrue(contributionAmount > 400, "Personal cap should accumulate");

        // ------------ PART 2: VERIFY TOTAL CAP NON-ACCUMULATION ------------
        // Attempt to contribute more than the remaining round cap
        vm.startPrank(contributor2_);
        _token.approve(address(fundingPot), 200);

        // Contributor 2 attempts to contribute 100.
        // Since contributor1 contributed 450 and round cap is 500, only 50 is remaining.
        // The contribution should be clamped to 50.
        fundingPot.contributeToRoundFor(
            contributor2_, round2Id, 100, accessCriteriaId, new bytes32[](0)
        );
        // Verify contributor 2's contribution was clamped to the remaining 50.
        assertEq(
            fundingPot.getUserContributionToRound(round2Id, contributor2_), 50
        );
        vm.stopPrank();

        // Verify total contributions to round 2 is exactly the round cap (450 + 50 = 500).
        assertEq(fundingPot.getTotalRoundContribution(round2Id), 500);

        // Additional contributor3 should not be able to contribute anything as the cap is full.
        // Attempting to contribute when the cap is already full should revert.
        vm.startPrank(contributor3_);
        _token.approve(address(fundingPot), 100);

        // Expect revert because the round cap (500) is already met.
        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundCapReached
                    .selector
            )
        );
        fundingPot.contributeToRoundFor(
            contributor3_, round2Id, 1, accessCriteriaId, new bytes32[](0)
        );
        vm.stopPrank();

        // Final check that total contributions remain at the round cap.
        assertEq(fundingPot.getTotalRoundContribution(round2Id), 500);
    }

    function testContribute_TotalMode_AccumulatesTotalOnly() public {
        // 1. Create the first round with AccumulationMode.Total
        _defaultRoundParams.accumulationMode =
            ILM_PC_FundingPot_v1.AccumulationMode.Total;

        fundingPot.createRound(
            _defaultRoundParams.roundStart,
            _defaultRoundParams.roundEnd,
            1000, // Round 1 cap of 1000
            _defaultRoundParams.hookContract,
            _defaultRoundParams.hookFunction,
            _defaultRoundParams.autoClosure,
            _defaultRoundParams.accumulationMode
        );
        uint32 round1Id = fundingPot.getRoundCount();

        // Set up access criteria for round 1 (Open)
        uint8 accessCriteriaId = 1;
        (
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = _helper_createAccessCriteria(
            uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.OPEN), round1Id
        );

        fundingPot.setAccessCriteria(
            round1Id,
            uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.OPEN), // accessCriteriaType
            0, // accessCriteriaId (0 for new)
            nftContract,
            merkleRoot,
            allowedAddresses
        );

        // Set a personal cap of 800 for round 1
        fundingPot.setAccessCriteriaPrivileges(
            round1Id, accessCriteriaId, 800, false, 0, 0, 0
        );

        // 2. Create the second round, also with AccumulationMode.Total
        RoundParams memory params = _helper_createEditRoundParams(
            _defaultRoundParams.roundStart + 3 days,
            _defaultRoundParams.roundEnd + 3 days,
            500, // Round 2 base cap of 500
            _defaultRoundParams.hookContract,
            _defaultRoundParams.hookFunction,
            _defaultRoundParams.autoClosure,
            ILM_PC_FundingPot_v1.AccumulationMode.Total
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

        // Set up access criteria for round 2 (Open)
        fundingPot.setAccessCriteria(
            round2Id,
            uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.OPEN), // accessCriteriaType
            0, // accessCriteriaId (0 for new)
            nftContract,
            merkleRoot,
            allowedAddresses
        );

        // Set a personal cap of 300 for round 2
        fundingPot.setAccessCriteriaPrivileges(
            round2Id, accessCriteriaId, 300, false, 0, 0, 0
        );

        // Round 1 contribution: contributor1 contributes 600 (less than round cap 1000, less than personal 800)
        // Undersubscription: 1000 - 600 = 400
        vm.warp(_defaultRoundParams.roundStart + 1);
        vm.startPrank(contributor1_);
        _token.approve(address(fundingPot), 1000);
        fundingPot.contributeToRoundFor(
            contributor1_, round1Id, 600, accessCriteriaId, new bytes32[](0)
        );
        vm.stopPrank();

        // Verify contribution to round 1
        assertEq(
            fundingPot.getUserContributionToRound(round1Id, contributor1_), 600
        );
        assertEq(fundingPot.getTotalRoundContribution(round1Id), 600);

        // Move to round 2
        vm.warp(_defaultRoundParams.roundStart + 3 days + 1);

        // ------------ PART 1: VERIFY TOTAL CAP ACCUMULATION ------------
        // Effective Round 2 Cap = Base Cap (500) + Unused from Round 1 (400) = 900
        vm.startPrank(contributor2_);
        _token.approve(address(fundingPot), 1000); // Approve enough

        // Contributor 2 attempts to contribute 700.
        // Personal Cap (R2) is 300. Gets clamped to 300.
        fundingPot.contributeToRoundFor(
            contributor2_, round2Id, 700, accessCriteriaId, new bytes32[](0)
        );
        // Verify contributor 2's contribution was clamped by personal cap.
        assertEq(
            fundingPot.getUserContributionToRound(round2Id, contributor2_),
            300,
            "C2 contribution should be clamped by personal cap"
        );
        vm.stopPrank();

        // Verify total contributions after C2 is 300
        assertEq(
            fundingPot.getTotalRoundContribution(round2Id),
            300,
            "Total after C2 should be 300"
        );

        // ------------ PART 2: VERIFY PERSONAL CAP NON-ACCUMULATION ------------
        // Contributor 1 had 800 personal cap in R1, contributed 600, unused = 200.
        // Contributor 1 has 300 personal cap in R2.
        // In Total mode, personal cap does NOT roll over. Max contribution is 300.

        // Prepare unspent caps struct (even though it shouldn't work for personal in Total mode)
        ILM_PC_FundingPot_v1.UnspentPersonalRoundCap[] memory unspentCaps =
            new ILM_PC_FundingPot_v1.UnspentPersonalRoundCap[](1);
        unspentCaps[0] = ILM_PC_FundingPot_v1.UnspentPersonalRoundCap({
            roundId: round1Id,
            accessCriteriaId: accessCriteriaId,
            merkleProof: new bytes32[](0)
        });

        vm.startPrank(contributor1_);
        _token.approve(address(fundingPot), 500);

        // Attempt to contribute 400 ( > R2 personal cap 300)
        // Total contributions = 300. Effective Round Cap = 900. Remaining Round Cap = 600.
        // Personal Cap (R2) = 300. Unspent (R1) = 200, ignored in Total mode.
        // Min(Remaining Round Cap, Remaining Personal Cap) = Min(600, 300) = 300.
        // Should be clamped to 300.
        fundingPot.contributeToRoundFor(
            contributor1_,
            round2Id,
            400,
            accessCriteriaId,
            new bytes32[](0),
            unspentCaps // Provide unspent caps, although they should be ignored for personal limit
        );
        // Verify contributor 1's contribution was clamped to their R2 personal cap.
        assertEq(
            fundingPot.getUserContributionToRound(round2Id, contributor1_),
            300,
            "C1 contribution should be clamped by personal cap"
        );
        vm.stopPrank();

        // Verify total round contributions: 300 (C2) + 300 (C1) = 600
        assertEq(
            fundingPot.getTotalRoundContribution(round2Id),
            600,
            "Total after C1 and C2 should be 600"
        );
        // Effective cap 900, current total 600. Remaining = 300.

        // Contributor 3 contributes 300. Personal Cap = 300. Remaining Round Cap = 300. Should succeed.
        vm.startPrank(contributor3_);
        _token.approve(address(fundingPot), 300);
        fundingPot.contributeToRoundFor(
            contributor3_, round2Id, 300, accessCriteriaId, new bytes32[](0)
        );
        // Verify C3 contributed 300
        assertEq(
            fundingPot.getUserContributionToRound(round2Id, contributor3_),
            300,
            "C3 contributes remaining 300"
        );
        vm.stopPrank();

        // Total contributions should now be 900 (300 + 300 + 300), matching the effective cap.
        assertEq(
            fundingPot.getTotalRoundContribution(round2Id),
            900,
            "Total should match effective cap after C3"
        );

        // Now the effective cap is full. Try contributing 1 again.
        vm.startPrank(contributor3_); // Can use C3 or another contributor
        _token.approve(address(fundingPot), 1);

        // Try contributing 1, expect revert as cap is full
        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundCapReached
                    .selector
            )
        );
        fundingPot.contributeToRoundFor(
            contributor3_, round2Id, 1, accessCriteriaId, new bytes32[](0)
        );
        vm.stopPrank();

        // Final total check should remain 900
        assertEq(
            fundingPot.getTotalRoundContribution(round2Id),
            900,
            "Final total should be effective cap"
        );
    }

    // -------------------------------------------------------------------------
    // Test: Global Accumulation Start Round Settings
    // -------------------------------------------------------------------------

    /* Test getGlobalAccumulationStartRoundId() and setGlobalAccumulationStart()
    ├── For getGlobalAccumulationStartRoundId()
    │   └── When no explicit value has been set
    │       └── Then it should return the default value of 1
    │
    └── For setGlobalAccumulationStart()
        ├── Given user does not have FUNDING_POT_ADMIN_ROLE
        │   └── When user attempts to set the global accumulation start round
        │       └── Then it should revert
        │
        ├── Given user has FUNDING_POT_ADMIN_ROLE
        │   ├── And the provided start round ID is 0
        │   │   └── When user attempts to set the global accumulation start round
        │   │       └── Then it should revert
        │   │
        │   ├── And the provided start round ID is greater than the current round count
        │   │   └── When user attempts to set the global accumulation start round
        │   │       └── Then it should revert
        │   │
        │   └── And a valid start round ID is provided
        │       └── When user attempts to set the global accumulation start round
        │           ├── Then it should update the globalAccumulationStartRoundId state variable
        │           ├── Then it should emit a GlobalAccumulationStartSet event
        │           └── Then getGlobalAccumulationStartRoundId() should return the new value
    */

    function testGetGlobalAccumulationStartRoundId_returnsDefaultWhenNotSet()
        public
    {
        // Expecting default value to be 1 as per AC
        assertEq(
            fundingPot.getGlobalAccumulationStartRoundId(),
            1,
            "Default start round ID should be 1"
        );
    }

    function testSetGlobalAccumulationStart_revertsGivenUserIsNotFundingPotAdmin(
        address unauthorizedUser,
        uint32 startRoundId
    ) public {
        vm.assume(unauthorizedUser != address(this));
        vm.assume(startRoundId >= 1);

        bytes32 roleId = _authorizer.generateRoleId(
            address(fundingPot), fundingPot.FUNDING_POT_ADMIN_ROLE()
        );

        vm.startPrank(unauthorizedUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector,
                roleId,
                unauthorizedUser
            )
        );
        fundingPot.setGlobalAccumulationStart(startRoundId);
        vm.stopPrank();
    }

    function testSetGlobalAccumulationStart_revertsGivenStartRoundIsZero()
        public
    {
        // AC: Must revert if startRoundId_ == 0
        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__StartRoundCannotBeZero
                    .selector
            )
        );
        fundingPot.setGlobalAccumulationStart(0);
    }

    function testSetGlobalAccumulationStart_revertsGivenStartRoundGreaterThanCurrentRoundCount(
        uint32 startRoundIdOffset
    ) public {
        testCreateRound(); // Ensure roundCount is at least 1
        uint32 currentRoundCount = fundingPot.getRoundCount();

        vm.assume(startRoundIdOffset > 0); // Ensure invalidStartRoundId will be greater
        vm.assume(startRoundIdOffset <= type(uint32).max - currentRoundCount);

        uint32 invalidStartRoundId = currentRoundCount + startRoundIdOffset;

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__StartRoundGreaterThanRoundCount
                    .selector,
                invalidStartRoundId,
                currentRoundCount
            )
        );
        fundingPot.setGlobalAccumulationStart(invalidStartRoundId);
    }

    function testSetGlobalAccumulationStart_worksGivenValidParameters(
        uint32 startRoundId
    ) public {
        // Ensure we have at least startRoundId rounds created if startRoundId > 0
        if (startRoundId > 0) {
            vm.assume(startRoundId <= 10); // Bound the fuzzing
            for (
                uint32 i = fundingPot.getRoundCount() + 1;
                i <= startRoundId;
                i++
            ) {
                fundingPot.createRound(
                    _defaultRoundParams.roundStart + (i * 3 days),
                    _defaultRoundParams.roundEnd + (i * 3 days),
                    _defaultRoundParams.roundCap,
                    _defaultRoundParams.hookContract,
                    _defaultRoundParams.hookFunction,
                    _defaultRoundParams.autoClosure,
                    _defaultRoundParams.accumulationMode
                );
            }
            vm.assume(startRoundId <= fundingPot.getRoundCount()); // Final check
        } else {
            vm.assume(startRoundId == 0);
            // For startRoundId = 0, test should actually fail based on the revert check above
            // However, fuzzing might pass 0. Let's test non-zero valid cases.
            vm.assume(false); // This will cause fuzz to skip startRoundId = 0 here
        }

        // Expect event emission
        vm.expectEmit(true, true, true, true);
        emit ILM_PC_FundingPot_v1.GlobalAccumulationStartSet(startRoundId);

        // Set the value
        fundingPot.setGlobalAccumulationStart(startRoundId);

        // Verify the value using the getter
        assertEq(
            fundingPot.getGlobalAccumulationStartRoundId(),
            startRoundId,
            "Getter should return the set value"
        );
    }

    // -------------------------------------------------------------------------
    // Test: Global Accumulation Start Round - Logic Integration
    // -------------------------------------------------------------------------

    /* Test Accumulation Logic with Global Start Round
    │
    ├── Scenario: Global start round restricts accumulation
    │   ├── Given globalAccumulationStartRoundId is set to 2 (e.g., R2)
    │   │   ├── And target round (e.g., R3) uses AccumulationMode.Personal
    │   │   │   └── When contributing to R3 with unspent capacity from R1 and R2
    │   │   │       └── Then only unspent personal capacity from R2 should be considered
    │   │   ├── And target round (e.g., R3) uses AccumulationMode.Total
    │   │   │   └── When contributing to R3
    │   │   │       └── Then only unspent total capacity from R2 should expand R3's effective cap
    │   │   └── And target round (e.g., R3) uses AccumulationMode.All
    │   │       ├── When contributing to R3 with unspent personal capacity from R1 and R2
    │   │       │   └── Then only unspent personal capacity from R2 should be considered
    │   │       └── When calculating R3's effective total cap
    │   │           └── Then only unspent total capacity from R2 should expand R3's effective cap
    │
    ├── Scenario: Default global start round (1) allows accumulation from all previous applicable rounds
    │   ├── Given globalAccumulationStartRoundId is 1 (default)
    │   │   ├── And target round (e.g., R2 or R3) uses AccumulationMode.Personal
    │   │   │   └── When contributing with unspent capacity from all previous valid rounds (e.g., R1 for R2; R1 & R2 for R3)
    │   │   │       └── Then unspent personal capacity from all applicable previous rounds should be considered
    │   │   ├── And target round (e.g., R2 or R3) uses AccumulationMode.Total
    │   │   │   └── When calculating effective total cap
    │   │   │       └── Then unspent total capacity from all applicable previous rounds should expand the effective cap
    │   │   └── And target round (e.g., R2 or R3) uses AccumulationMode.All
    │   │       ├── When contributing with unspent personal capacity from all previous valid rounds
    │   │       │   └── Then unspent personal capacity from all applicable previous rounds should be considered
    │   │       └── When calculating effective total cap
    │   │           └── Then unspent total capacity from all applicable previous rounds should expand the effective cap
    │
    ├── Scenario: Interaction with AccumulationMode.Disabled
    │   └── Given target round's AccumulationMode is Disabled
    │       └── When globalAccumulationStartRoundId is set to allow previous rounds
    │           └── Then no accumulation (personal or total) should occur for the target round
    │
    └── Scenario: Global start round equals target round
        └── Given globalAccumulationStartRoundId is set to the target round's ID
            └── When target round's AccumulationMode would normally allow accumulation
                └── Then no accumulation (personal or total) from any *previous* round should occur
    */

    function testContribute_personalMode_globalStartRestrictsAccumulationFromEarlierRounds(
    ) public {
        // SCENARIO: globalAccumulationStartRoundId = 2 restricts accumulation from Round 1 for Personal mode
        // 1. Setup: Round 1, Round 2, Round 3. Partial contributions in R1 & R2.
        // 2. Action: setGlobalAccumulationStart(2)
        // 3. Verification: For contributions to R3 (Personal mode), only unused personal from R2 rolls over.

        uint initialTimestamp = block.timestamp;

        // --- Setup Rounds ---
        uint r1PersonalCap = 500;
        uint r1Contribution = 100;
        // uint r1UnusedPersonal = r1PersonalCap - r1Contribution; // Not used in this restricted scenario directly for R3 calc

        uint r2PersonalCap = 600;
        uint r2Contribution = 200;
        uint r2UnusedPersonal = r2PersonalCap - r2Contribution; // This IS used for R3 calculation

        uint r3BasePersonalCap = 300;

        // Round 1
        uint32 round1Id = fundingPot.createRound(
            initialTimestamp + 1 days,
            initialTimestamp + 2 days,
            10_000, // large round cap
            address(0),
            bytes(""),
            false,
            ILM_PC_FundingPot_v1.AccumulationMode.Personal
        );
        fundingPot.setAccessCriteria(
            round1Id, 1, 0, address(0), bytes32(0), new address[](0)
        ); // Open access
        fundingPot.setAccessCriteriaPrivileges(
            round1Id, 1, r1PersonalCap, false, 0, 0, 0
        );

        // Round 2
        uint32 round2Id = fundingPot.createRound(
            initialTimestamp + 3 days,
            initialTimestamp + 4 days,
            10_000, // large round cap
            address(0),
            bytes(""),
            false,
            ILM_PC_FundingPot_v1.AccumulationMode.Personal
        );
        fundingPot.setAccessCriteria(
            round2Id, 1, 0, address(0), bytes32(0), new address[](0)
        );
        fundingPot.setAccessCriteriaPrivileges(
            round2Id, 1, r2PersonalCap, false, 0, 0, 0
        );

        // Round 3
        uint32 round3Id = fundingPot.createRound(
            initialTimestamp + 5 days,
            initialTimestamp + 6 days,
            10_000, // large round cap
            address(0),
            bytes(""),
            false,
            ILM_PC_FundingPot_v1.AccumulationMode.Personal
        );
        fundingPot.setAccessCriteria(
            round3Id, 1, 0, address(0), bytes32(0), new address[](0)
        );
        fundingPot.setAccessCriteriaPrivileges(
            round3Id, 1, r3BasePersonalCap, false, 0, 0, 0
        );

        // --- Contributions ---
        vm.startPrank(contributor1_);
        _token.approve(address(fundingPot), type(uint).max);

        vm.warp(initialTimestamp + 1 days + 1 hours); // Enter Round 1
        fundingPot.contributeToRoundFor(
            contributor1_, round1Id, r1Contribution, 1, new bytes32[](0)
        );

        vm.warp(initialTimestamp + 3 days + 1 hours); // Enter Round 2
        fundingPot.contributeToRoundFor(
            contributor1_, round2Id, r2Contribution, 1, new bytes32[](0)
        );
        vm.stopPrank();

        // --- Set Global Start ---
        fundingPot.setGlobalAccumulationStart(2);
        assertEq(fundingPot.getGlobalAccumulationStartRoundId(), 2);

        // --- Attempt Contribution in Round 3 ---
        vm.warp(initialTimestamp + 5 days + 1 hours); // Enter Round 3

        ILM_PC_FundingPot_v1.UnspentPersonalRoundCap[] memory unspentCaps =
            new ILM_PC_FundingPot_v1.UnspentPersonalRoundCap[](2);
        // User claims unspent from R1 (should be ignored due to global start)
        unspentCaps[0] = ILM_PC_FundingPot_v1.UnspentPersonalRoundCap(
            round1Id, 1, new bytes32[](0)
        );
        // User claims unspent from R2 (should be counted)
        unspentCaps[1] = ILM_PC_FundingPot_v1.UnspentPersonalRoundCap(
            round2Id, 1, new bytes32[](0)
        );

        uint expectedR3PersonalCap = r3BasePersonalCap + r2Contribution; // Only R2's unused personal cap

        vm.startPrank(contributor1_);
        // Attempt to contribute up to the expected new personal cap
        fundingPot.contributeToRoundFor(
            contributor1_,
            round3Id,
            expectedR3PersonalCap,
            1,
            new bytes32[](0),
            unspentCaps
        );
        vm.stopPrank();

        // --- Assertion ---
        assertEq(
            fundingPot.getUserContributionToRound(round3Id, contributor1_),
            expectedR3PersonalCap,
            "R3 personal contribution incorrect"
        );
    }

    function testContribute_totalMode_globalStartRestrictsAccumulationFromEarlierRounds(
    ) public {
        // SCENARIO: globalAccumulationStartRoundId = 2 restricts accumulation from Round 1 for Total mode
        // 1. Setup: Round 1, Round 2, Round 3. Partial contributions in R1 & R2.
        // 2. Action: setGlobalAccumulationStart(2)
        // 3. Verification: For contributions to R3 (Total mode), only unused total from R2 expands R3 cap.

        uint initialTimestamp = block.timestamp;

        // --- Setup Rounds ---
        uint r1BaseCap = 1000;
        uint r1Contribution = 400;
        // uint r1UnusedTotal = r1BaseCap - r1Contribution;

        uint r2BaseCap = 1200;
        uint r2Contribution = 500;
        // uint r2UnusedTotal = r2BaseCap - r2Contribution;

        uint r3BaseCap = 300;

        // Round 1
        uint32 round1Id = fundingPot.createRound(
            initialTimestamp + 1 days,
            initialTimestamp + 2 days,
            r1BaseCap,
            address(0),
            bytes(""),
            false,
            ILM_PC_FundingPot_v1.AccumulationMode.Total
        );
        fundingPot.setAccessCriteria(
            round1Id, 1, 0, address(0), bytes32(0), new address[](0)
        ); // Open access
        fundingPot.setAccessCriteriaPrivileges(
            round1Id, 1, r1BaseCap, false, 0, 0, 0
        ); // Personal cap equals round cap

        // Round 2
        uint32 round2Id = fundingPot.createRound(
            initialTimestamp + 3 days,
            initialTimestamp + 4 days,
            r2BaseCap,
            address(0),
            bytes(""),
            false,
            ILM_PC_FundingPot_v1.AccumulationMode.Total
        );
        fundingPot.setAccessCriteria(
            round2Id, 1, 0, address(0), bytes32(0), new address[](0)
        );
        fundingPot.setAccessCriteriaPrivileges(
            round2Id, 1, r2BaseCap, false, 0, 0, 0
        );

        // Round 3
        uint32 round3Id = fundingPot.createRound(
            initialTimestamp + 5 days,
            initialTimestamp + 6 days,
            r3BaseCap,
            address(0),
            bytes(""),
            false,
            ILM_PC_FundingPot_v1.AccumulationMode.Total
        );
        fundingPot.setAccessCriteria(
            round3Id, 1, 0, address(0), bytes32(0), new address[](0)
        );
        fundingPot.setAccessCriteriaPrivileges(
            round3Id, 1, r3BaseCap + r2Contribution, false, 0, 0, 0
        ); // Allow full contribution for testing effective cap

        // --- Contributions ---
        vm.startPrank(contributor1_);
        _token.approve(address(fundingPot), type(uint).max);

        vm.warp(initialTimestamp + 1 days + 1 hours); // Enter Round 1
        fundingPot.contributeToRoundFor(
            contributor1_, round1Id, r1Contribution, 1, new bytes32[](0)
        );

        vm.warp(initialTimestamp + 3 days + 1 hours); // Enter Round 2
        fundingPot.contributeToRoundFor(
            contributor1_, round2Id, r2Contribution, 1, new bytes32[](0)
        );
        vm.stopPrank();

        // --- Set Global Start ---
        fundingPot.setGlobalAccumulationStart(2);
        assertEq(fundingPot.getGlobalAccumulationStartRoundId(), 2);

        // --- Attempt Contribution in Round 3 ---
        vm.warp(initialTimestamp + 5 days + 1 hours); // Enter Round 3

        uint expectedR3EffectiveCap = r3BaseCap + r2Contribution; // Only R2's unused total cap

        vm.startPrank(contributor1_);
        // Attempt to contribute up to the expected new effective cap
        fundingPot.contributeToRoundFor(
            contributor1_, round3Id, expectedR3EffectiveCap, 1, new bytes32[](0)
        );
        vm.stopPrank();

        // --- Assertion ---
        assertEq(
            fundingPot.getTotalRoundContribution(round3Id),
            expectedR3EffectiveCap,
            "R3 total contribution incorrect, effective cap not as expected"
        );
        assertEq(
            fundingPot.getUserContributionToRound(round3Id, contributor1_),
            expectedR3EffectiveCap,
            "R3 user contribution incorrect"
        );
    }

    function testContribute_personalMode_defaultGlobalStartAllowsAccumulationFromAllPrevious(
    ) public {
        // SCENARIO: Default globalAccumulationStartRoundId = 1 allows accumulation from R1 for R2 (Personal mode)
        // 1. Setup: Round 1 (Personal), Round 2 (Personal).
        //    Partial contribution by C1 in R1.
        // 2. Action: Verify getGlobalAccumulationStartRoundId() == 1 (default).
        // 3. Verification: For C1's contribution to R2, unused personal capacity from R1 rolls over.

        uint initialTimestamp = block.timestamp;
        uint8 accessId = 1; // Open access

        // --- Round Parameters & Contributions for C1 ---
        uint r1PersonalCapC1 = 500;
        uint r1ContributionC1 = 100; // C1 leaves 400 personal unused from R1

        uint r2BasePersonalCapC1 = 300; // C1's base personal cap in R2

        // --- Approvals ---
        vm.startPrank(contributor1_);
        _token.approve(address(fundingPot), type(uint).max);
        vm.stopPrank();

        // --- Create Round 1 (Personal Mode) ---
        uint32 round1Id = fundingPot.createRound(
            initialTimestamp + 1 days,
            initialTimestamp + 2 days,
            10_000, // Large round cap, not relevant for personal accumulation focus
            address(0),
            bytes(""),
            false,
            ILM_PC_FundingPot_v1.AccumulationMode.Personal
        );
        fundingPot.setAccessCriteria(
            round1Id, accessId, 0, address(0), bytes32(0), new address[](0)
        );
        fundingPot.setAccessCriteriaPrivileges(
            round1Id, accessId, r1PersonalCapC1, false, 0, 0, 0
        );

        // --- Create Round 2 (Personal Mode) ---
        uint32 round2Id = fundingPot.createRound(
            initialTimestamp + 3 days,
            initialTimestamp + 4 days,
            10_000, // Large round cap
            address(0),
            bytes(""),
            false,
            ILM_PC_FundingPot_v1.AccumulationMode.Personal
        );
        fundingPot.setAccessCriteria(
            round2Id, accessId, 0, address(0), bytes32(0), new address[](0)
        );
        fundingPot.setAccessCriteriaPrivileges(
            round2Id, accessId, r2BasePersonalCapC1, false, 0, 0, 0
        );

        // --- Contribution by C1 to Round 1 ---
        vm.startPrank(contributor1_);
        vm.warp(initialTimestamp + 1 days + 1 hours); // Enter Round 1
        fundingPot.contributeToRoundFor(
            contributor1_,
            round1Id,
            r1ContributionC1,
            accessId,
            new bytes32[](0)
        );
        vm.stopPrank();

        // --- Verify Default Global Start Round ID ---
        assertEq(
            fundingPot.getGlobalAccumulationStartRoundId(),
            1,
            "Default global start round ID should be 1"
        );

        // --- Attempt Contribution in Round 2 by C1 ---
        vm.warp(initialTimestamp + 3 days + 1 hours); // Enter Round 2

        ILM_PC_FundingPot_v1.UnspentPersonalRoundCap[] memory unspentCapsC1 =
            new ILM_PC_FundingPot_v1.UnspentPersonalRoundCap[](1);
        unspentCapsC1[0] = ILM_PC_FundingPot_v1.UnspentPersonalRoundCap(
            round1Id,
            accessId,
            new bytes32[](0) // Should be counted
        );

        uint r1UnusedPersonalC1 = r1PersonalCapC1 - r1ContributionC1; // 400

        // Expected C1 effective personal cap in R2 = R2_Base (300) + R1_Unused (400) = 700
        uint expectedC1EffectivePersonalCapR2 =
            r2BasePersonalCapC1 + r1UnusedPersonalC1;

        uint c1AttemptR2 = expectedC1EffectivePersonalCapR2 + 50; // Try to contribute slightly more
        uint expectedC1ContributionR2 = expectedC1EffectivePersonalCapR2; // Should be clamped

        // Ensure the attempt is not clamped by the round cap (which is large)
        if (expectedC1ContributionR2 > 10_000) {
            // 10_000 is round cap for R2
            expectedC1ContributionR2 = 10_000;
        }

        vm.startPrank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_,
            round2Id,
            c1AttemptR2,
            accessId,
            new bytes32[](0),
            unspentCapsC1
        );
        vm.stopPrank();

        // --- Assertion ---
        assertEq(
            fundingPot.getUserContributionToRound(round2Id, contributor1_),
            expectedC1ContributionR2,
            "R2 C1 personal contribution incorrect (should use R1 unused)"
        );
    }

    function testContribute_totalMode_defaultGlobalStartAllowsAccumulationFromAllPrevious(
    ) public {
        // SCENARIO: Default globalAccumulationStartRoundId = 1 allows total cap accumulation from R1 to R2 (Total mode)
        // Simplified to reduce stack depth.

        uint initialTimestamp = block.timestamp;
        uint8 accessId = 1; // Open access

        // --- Round 1 Parameters & Contribution ---
        uint r1BaseCap = 1000;
        uint r1ContributionC1 = 600; // Leaves 400 unused total from R1
        uint r1PersonalCap = 1000;

        // --- Round 2 Parameters ---
        uint r2BaseCap = 500;

        // --- Approvals ---
        vm.startPrank(contributor1_);
        _token.approve(address(fundingPot), type(uint).max);
        vm.stopPrank();

        // --- Create Round 1 (Total Mode) ---
        uint32 round1Id = fundingPot.createRound(
            initialTimestamp + 1 days,
            initialTimestamp + 2 days,
            r1BaseCap,
            address(0),
            bytes(""),
            false,
            ILM_PC_FundingPot_v1.AccumulationMode.Total
        );
        fundingPot.setAccessCriteria(
            round1Id, accessId, 0, address(0), bytes32(0), new address[](0)
        );
        fundingPot.setAccessCriteriaPrivileges(
            round1Id, accessId, r1PersonalCap, false, 0, 0, 0
        );

        // --- Contribution by C1 to Round 1 ---
        vm.warp(initialTimestamp + 1 days + 1 hours);
        vm.startPrank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_,
            round1Id,
            r1ContributionC1,
            accessId,
            new bytes32[](0)
        );
        vm.stopPrank();
        uint r1UnusedTotal = r1BaseCap - r1ContributionC1; // Should be 400

        // --- Create Round 2 (Total Mode) ---
        uint32 round2Id = fundingPot.createRound(
            initialTimestamp + 3 days,
            initialTimestamp + 4 days,
            r2BaseCap,
            address(0),
            bytes(""),
            false,
            ILM_PC_FundingPot_v1.AccumulationMode.Total
        );
        fundingPot.setAccessCriteria(
            round2Id, accessId, 0, address(0), bytes32(0), new address[](0)
        );
        // Set personal cap for R2 to be at least the expected effective total cap
        uint r2ExpectedEffectiveTotalCap = r2BaseCap + r1UnusedTotal; // 500 + 400 = 900
        fundingPot.setAccessCriteriaPrivileges(
            round2Id, accessId, r2ExpectedEffectiveTotalCap, false, 0, 0, 0
        );

        // --- Verify Default Global Start Round ID ---
        assertEq(
            fundingPot.getGlobalAccumulationStartRoundId(),
            1,
            "Default global start round ID should be 1"
        );

        // --- Attempt Contribution in Round 2 by C1 ---
        vm.warp(initialTimestamp + 3 days + 1 hours);

        uint c1AttemptR2 = r2ExpectedEffectiveTotalCap - 100; // e.g., 900 - 100 = 800. Utilizes expanded cap.
        assertTrue(
            c1AttemptR2 > r2BaseCap, "C1 R2 attempt should be > R2 base cap"
        );
        assertTrue(
            c1AttemptR2 <= r2ExpectedEffectiveTotalCap,
            "C1 R2 attempt should be <= R2 effective cap"
        );

        vm.startPrank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_, round2Id, c1AttemptR2, accessId, new bytes32[](0)
        );
        vm.stopPrank();

        // --- Assertions ---
        assertEq(
            fundingPot.getUserContributionToRound(round2Id, contributor1_),
            c1AttemptR2,
            "R2 C1 contribution incorrect"
        );
        assertEq(
            fundingPot.getTotalRoundContribution(round2Id),
            c1AttemptR2,
            "R2 Total contributions after C1 incorrect"
        );

        // Verify that the total contributions possible is indeed the effective cap
        uint remainingToFill = r2ExpectedEffectiveTotalCap - c1AttemptR2;
        if (remainingToFill > 0) {
            vm.startPrank(contributor1_);
            fundingPot.contributeToRoundFor(
                contributor1_,
                round2Id,
                remainingToFill,
                accessId,
                new bytes32[](0)
            );
            vm.stopPrank();
        }

        assertEq(
            fundingPot.getTotalRoundContribution(round2Id),
            r2ExpectedEffectiveTotalCap,
            "R2 final total contributions should match effective total cap"
        );
    }

    function testContribute_disabledMode_ignoresGlobalStartAndPreventsAccumulation(
    ) public {
        // SCENARIO: AccumulationMode.Disabled on a target round (R2) prevents any accumulation
        // from a previous round (R1), even if globalAccumulationStartRoundId would allow it.

        uint initialTimestamp = block.timestamp;
        uint8 accessId = 1; // Open access

        // --- Round 1 Parameters ---
        uint r1PersonalCapC1 = 500;
        uint r1ContributionC1 = 100;
        uint r1BaseCap = 1000;

        // --- Round 2 Parameters (Disabled Mode) ---
        uint r2BasePersonalCapC1 = 50;
        uint r2BaseCap = 200;

        // --- Approvals ---
        vm.startPrank(contributor1_);
        _token.approve(address(fundingPot), type(uint).max);
        vm.stopPrank();

        // --- Create Round 1 (Personal Mode to generate unused personal capacity) ---
        uint32 round1Id = fundingPot.createRound(
            initialTimestamp + 1 days,
            initialTimestamp + 2 days,
            r1BaseCap,
            address(0),
            bytes(""),
            false,
            ILM_PC_FundingPot_v1.AccumulationMode.Personal
        );
        fundingPot.setAccessCriteria(
            round1Id, accessId, 0, address(0), bytes32(0), new address[](0)
        );
        fundingPot.setAccessCriteriaPrivileges(
            round1Id, accessId, r1PersonalCapC1, false, 0, 0, 0
        );

        // --- Contribution by C1 to Round 1 ---
        vm.warp(initialTimestamp + 1 days + 1 hours);
        vm.startPrank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_,
            round1Id,
            r1ContributionC1,
            accessId,
            new bytes32[](0)
        );
        vm.stopPrank();

        // --- Create Round 2 (Disabled Mode) ---
        uint32 round2Id = fundingPot.createRound(
            initialTimestamp + 3 days,
            initialTimestamp + 4 days,
            r2BaseCap,
            address(0),
            bytes(""),
            false,
            ILM_PC_FundingPot_v1.AccumulationMode.Disabled
        );
        fundingPot.setAccessCriteria(
            round2Id, accessId, 0, address(0), bytes32(0), new address[](0)
        );
        fundingPot.setAccessCriteriaPrivileges(
            round2Id, accessId, r2BasePersonalCapC1, false, 0, 0, 0
        );

        // --- Set Global Start Round ID to allow R1 (to show it's ignored by R2's Disabled mode) ---
        fundingPot.setGlobalAccumulationStart(1);
        assertEq(
            fundingPot.getGlobalAccumulationStartRoundId(),
            1,
            "Global start round ID should be 1"
        );

        // --- Attempt Contribution in Round 2 by C1 ---
        vm.warp(initialTimestamp + 3 days + 1 hours);

        uint c1AttemptR2 = r2BasePersonalCapC1 + 100;

        ILM_PC_FundingPot_v1.UnspentPersonalRoundCap[] memory unspentCapsC1 =
            new ILM_PC_FundingPot_v1.UnspentPersonalRoundCap[](1);
        unspentCapsC1[0] = ILM_PC_FundingPot_v1.UnspentPersonalRoundCap(
            round1Id, accessId, new bytes32[](0)
        );

        vm.startPrank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_,
            round2Id,
            c1AttemptR2,
            accessId,
            new bytes32[](0),
            unspentCapsC1
        );
        vm.stopPrank();

        // --- Assertions ---
        assertEq(
            fundingPot.getUserContributionToRound(round2Id, contributor1_),
            r2BasePersonalCapC1,
            "R2 C1 personal contribution should be clamped by R2's base personal cap (Disabled mode)"
        );
        assertEq(
            fundingPot.getTotalRoundContribution(round2Id),
            r2BasePersonalCapC1,
            "R2 Total contributions should not be expanded by R1 (Disabled mode)"
        );
        assertTrue(
            fundingPot.getTotalRoundContribution(round2Id) <= r2BaseCap,
            "R2 Total contributions exceeded R2's original base cap (Disabled mode)"
        );
    }

    function testContribute_anyAccumulativeMode_noAccumulationWhenGlobalStartEqualsTargetRound(
    ) public {
        // SCENARIO: If globalAccumulationStartRoundId is set to the target round's ID (R2),
        // no accumulation from any previous round (R1) occurs for R2, even if R2's mode would allow it.

        uint initialTimestamp = block.timestamp;
        uint8 accessId = 1; // Open access

        // --- Round 1 Parameters ---
        uint r1PersonalCapC1 = 500;
        uint r1ContributionC1 = 100;
        uint r1BaseCap = 1000;

        // --- Round 2 Parameters (Mode that would normally allow accumulation, e.g., Personal) ---
        uint r2BasePersonalCapC1 = 50;
        uint r2BaseCap = 200;

        // --- Approvals ---
        vm.startPrank(contributor1_);
        _token.approve(address(fundingPot), type(uint).max);
        vm.stopPrank();

        // --- Create Round 1 (Personal Mode to generate unused personal capacity) ---
        uint32 round1Id = fundingPot.createRound(
            initialTimestamp + 1 days,
            initialTimestamp + 2 days,
            r1BaseCap,
            address(0),
            bytes(""),
            false,
            ILM_PC_FundingPot_v1.AccumulationMode.Personal
        );
        fundingPot.setAccessCriteria(
            round1Id, accessId, 0, address(0), bytes32(0), new address[](0)
        );
        fundingPot.setAccessCriteriaPrivileges(
            round1Id, accessId, r1PersonalCapC1, false, 0, 0, 0
        );

        // --- Contribution by C1 to Round 1 ---
        vm.warp(initialTimestamp + 1 days + 1 hours);
        vm.startPrank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_,
            round1Id,
            r1ContributionC1,
            accessId,
            new bytes32[](0)
        );
        vm.stopPrank();

        // --- Create Round 2 (Personal Mode - would normally allow accumulation from R1) ---
        uint32 round2Id = fundingPot.createRound(
            initialTimestamp + 3 days,
            initialTimestamp + 4 days,
            r2BaseCap,
            address(0),
            bytes(""),
            false,
            ILM_PC_FundingPot_v1.AccumulationMode.Personal
        );
        fundingPot.setAccessCriteria(
            round2Id, accessId, 0, address(0), bytes32(0), new address[](0)
        );
        fundingPot.setAccessCriteriaPrivileges(
            round2Id, accessId, r2BasePersonalCapC1, false, 0, 0, 0
        );

        // --- Set Global Start Round ID to be Round 2's ID ---
        fundingPot.setGlobalAccumulationStart(round2Id);
        assertEq(
            fundingPot.getGlobalAccumulationStartRoundId(),
            round2Id,
            "Global start round ID not set to R2 ID"
        );

        // --- Attempt Contribution in Round 2 by C1 ---
        vm.warp(initialTimestamp + 3 days + 1 hours);

        uint c1AttemptR2 = r2BasePersonalCapC1 + 100;

        ILM_PC_FundingPot_v1.UnspentPersonalRoundCap[] memory unspentCapsC1 =
            new ILM_PC_FundingPot_v1.UnspentPersonalRoundCap[](1);
        unspentCapsC1[0] = ILM_PC_FundingPot_v1.UnspentPersonalRoundCap(
            round1Id, accessId, new bytes32[](0)
        );

        vm.startPrank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_,
            round2Id,
            c1AttemptR2,
            accessId,
            new bytes32[](0),
            unspentCapsC1
        );
        vm.stopPrank();

        // --- Assertions ---
        assertEq(
            fundingPot.getUserContributionToRound(round2Id, contributor1_),
            r2BasePersonalCapC1,
            "R2 C1 personal contribution should be clamped by R2's base personal cap (global start = R2)"
        );
        assertEq(
            fundingPot.getTotalRoundContribution(round2Id),
            r2BasePersonalCapC1,
            "R2 Total contributions should not be expanded by R1 (global start = R2)"
        );
        assertTrue(
            fundingPot.getTotalRoundContribution(round2Id) <= r2BaseCap,
            "R2 Total contributions exceeded R2's original base cap (global start = R2)"
        );
    }

    // -------------------------------------------------------------------------
    // Test: Global Accumulation Start Round - Logic Integration - Remaining Tests
    // (Covers multi-round accumulation where global start allows all previous)
    // -------------------------------------------------------------------------

    function testContribute_personalMode_defaultGlobalStartAllowsAccumulationFromMultiplePreviousRounds(
    ) public {
        // SCENARIO: globalAccumulationStartRoundId = 1 allows personal cap accumulation from R1 AND R2
        // for contributions to R3, when all rounds are in Personal mode.
        // 1. Setup: R1, R2, R3 in Personal mode. C1 makes partial contributions in R1 & R2.
        // 2. Action: Verify globalAccumulationStartRoundId = 1. C1 contributes to R3.
        // 3. Verification: C1's effective personal cap in R3 includes unused from R1 and R2.

        uint initialTimestamp = block.timestamp;

        // --- Round Parameters, Personal Caps, and Contributions for contributor1_ ---
        uint r1PersonalCapC1 = 500;
        uint r1ContributionC1 = 200;

        uint r2PersonalCapC1 = 600;
        uint r2ContributionC1 = 250;

        uint r3BasePersonalCapC1 = 300;

        uint largeRoundCap = 1_000_000;

        // --- Approvals ---
        vm.startPrank(contributor1_);
        _token.approve(address(fundingPot), type(uint).max);
        vm.stopPrank();

        // --- Create Round 1 (Personal Mode) ---
        uint32 round1Id = fundingPot.createRound(
            initialTimestamp + 1 days,
            initialTimestamp + 2 days,
            largeRoundCap,
            address(0),
            bytes(""),
            false,
            ILM_PC_FundingPot_v1.AccumulationMode.Personal
        );
        fundingPot.setAccessCriteria(
            round1Id, 1, 0, address(0), bytes32(0), new address[](0)
        );
        fundingPot.setAccessCriteriaPrivileges(
            round1Id, 1, r1PersonalCapC1, false, 0, 0, 0
        );

        // --- Contribution by C1 to Round 1 ---
        vm.warp(initialTimestamp + 1 days + 1 hours);
        vm.startPrank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_, round1Id, r1ContributionC1, 1, new bytes32[](0)
        );
        vm.stopPrank();
        assertEq(
            fundingPot.getUserContributionToRound(round1Id, contributor1_),
            r1ContributionC1
        );

        // --- Create Round 2 (Personal Mode) ---
        uint32 round2Id = fundingPot.createRound(
            initialTimestamp + 3 days,
            initialTimestamp + 4 days,
            largeRoundCap,
            address(0),
            bytes(""),
            false,
            ILM_PC_FundingPot_v1.AccumulationMode.Personal
        );
        fundingPot.setAccessCriteria(
            round2Id, 1, 0, address(0), bytes32(0), new address[](0)
        );
        fundingPot.setAccessCriteriaPrivileges(
            round2Id, 1, r2PersonalCapC1, false, 0, 0, 0
        );

        // --- Contribution by C1 to Round 2 ---
        vm.warp(initialTimestamp + 3 days + 1 hours);
        vm.startPrank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_, round2Id, r2ContributionC1, 1, new bytes32[](0)
        );
        vm.stopPrank();
        assertEq(
            fundingPot.getUserContributionToRound(round2Id, contributor1_),
            r2ContributionC1
        );

        // --- Create Round 3 (Personal Mode) ---
        uint32 round3Id = fundingPot.createRound(
            initialTimestamp + 5 days,
            initialTimestamp + 6 days,
            largeRoundCap,
            address(0),
            bytes(""),
            false,
            ILM_PC_FundingPot_v1.AccumulationMode.Personal
        );
        fundingPot.setAccessCriteria(
            round3Id, 1, 0, address(0), bytes32(0), new address[](0)
        );
        fundingPot.setAccessCriteriaPrivileges(
            round3Id, 1, r3BasePersonalCapC1, false, 0, 0, 0
        );

        // --- Verify Global Start Round ID ---
        assertEq(
            fundingPot.getGlobalAccumulationStartRoundId(),
            1,
            "Default global start round ID should be 1"
        );

        // --- Attempt Contribution in Round 3 by C1 ---
        vm.warp(initialTimestamp + 5 days + 1 hours);

        ILM_PC_FundingPot_v1.UnspentPersonalRoundCap[] memory unspentCapsC1 =
            new ILM_PC_FundingPot_v1.UnspentPersonalRoundCap[](2);
        unspentCapsC1[0] = ILM_PC_FundingPot_v1.UnspentPersonalRoundCap(
            round1Id, 1, new bytes32[](0)
        );
        unspentCapsC1[1] = ILM_PC_FundingPot_v1.UnspentPersonalRoundCap(
            round2Id, 1, new bytes32[](0)
        );

        uint expectedR3PersonalCapC1 = r3BasePersonalCapC1
            + (r1PersonalCapC1 - r1ContributionC1)
            + (r2PersonalCapC1 - r2ContributionC1);

        uint c1AttemptR3 = expectedR3PersonalCapC1;

        vm.startPrank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_,
            round3Id,
            c1AttemptR3,
            1,
            new bytes32[](0),
            unspentCapsC1
        );
        vm.stopPrank();

        // --- Assertions ---
        assertEq(
            fundingPot.getUserContributionToRound(round3Id, contributor1_),
            expectedR3PersonalCapC1,
            "R3 C1 personal contribution incorrect (should use R1 & R2 unused)"
        );
        assertEq(
            fundingPot.getTotalRoundContribution(round3Id),
            expectedR3PersonalCapC1,
            "R3 total contributions incorrect after C1"
        );

        vm.startPrank(contributor1_);
        _token.approve(address(fundingPot), 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__PersonalCapReached
                    .selector
            )
        );
        fundingPot.contributeToRoundFor(
            contributor1_, round3Id, 1, 1, new bytes32[](0), unspentCapsC1
        );
        vm.stopPrank();
    }

    function testContribute_totalMode_defaultGlobalStartAllowsAccumulationFromMultiplePreviousRounds(
    ) public {
        // SCENARIO: globalAccumulationStartRoundId = 1 allows accumulation from Round 1 AND Round 2 for Total mode
        // 1. Setup: Round 1, Round 2, Round 3. Partial total contributions in R1 & R2. All in Total mode.
        // 2. Action: setGlobalAccumulationStart(1) (or verify default).
        // 3. Verification: For contributions to R3 (Total mode), unused total from R1 AND R2 rolls over, expanding R3's effective cap.

        uint initialTimestamp = block.timestamp;

        // --- Round Parameters & Contributions ---
        uint r1BaseCap = 1000;
        uint r1ContributionC1 = 400;

        uint r2BaseCap = 1200;
        uint r2ContributionC2 = 700;

        uint r3BaseCap = 300;

        // --- Approvals ---
        vm.startPrank(contributor1_);
        _token.approve(address(fundingPot), type(uint).max);
        vm.stopPrank();

        vm.startPrank(contributor2_);
        _token.approve(address(fundingPot), type(uint).max);
        vm.stopPrank();

        vm.startPrank(contributor3_);
        _token.approve(address(fundingPot), type(uint).max);
        vm.stopPrank();

        // --- Create Round 1 (Total Mode) ---
        uint32 round1Id = fundingPot.createRound(
            initialTimestamp + 1 days,
            initialTimestamp + 2 days,
            r1BaseCap,
            address(0),
            bytes(""),
            false,
            ILM_PC_FundingPot_v1.AccumulationMode.Total
        );
        fundingPot.setAccessCriteria(
            round1Id, 1, 0, address(0), bytes32(0), new address[](0)
        );
        fundingPot.setAccessCriteriaPrivileges(
            round1Id, 1, r1BaseCap, false, 0, 0, 0
        );

        // --- Contribution by C1 to Round 1 ---
        vm.warp(initialTimestamp + 1 days + 1 hours);
        vm.startPrank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_, round1Id, r1ContributionC1, 1, new bytes32[](0)
        );
        vm.stopPrank();
        assertEq(
            fundingPot.getTotalRoundContribution(round1Id), r1ContributionC1
        );

        // --- Create Round 2 (Total Mode) ---
        uint32 round2Id = fundingPot.createRound(
            initialTimestamp + 3 days,
            initialTimestamp + 4 days,
            r2BaseCap,
            address(0),
            bytes(""),
            false,
            ILM_PC_FundingPot_v1.AccumulationMode.Total
        );
        fundingPot.setAccessCriteria(
            round2Id, 1, 0, address(0), bytes32(0), new address[](0)
        );
        fundingPot.setAccessCriteriaPrivileges(
            round2Id, 1, r2BaseCap, false, 0, 0, 0
        );

        // --- Contribution by C2 to Round 2 ---
        vm.warp(initialTimestamp + 3 days + 1 hours);
        vm.startPrank(contributor2_);
        fundingPot.contributeToRoundFor(
            contributor2_, round2Id, r2ContributionC2, 1, new bytes32[](0)
        );
        vm.stopPrank();
        assertEq(
            fundingPot.getTotalRoundContribution(round2Id), r2ContributionC2
        );

        // --- Create Round 3 (Total Mode) ---
        uint r3ExpectedEffectiveCap = r3BaseCap + (r1BaseCap - r1ContributionC1)
            + (r2BaseCap - r2ContributionC2);
        uint32 round3Id = fundingPot.createRound(
            initialTimestamp + 5 days,
            initialTimestamp + 6 days,
            r3BaseCap,
            address(0),
            bytes(""),
            false,
            ILM_PC_FundingPot_v1.AccumulationMode.Total
        );
        (address nftR3, bytes32 merkleR3, address[] memory allowedR3) =
            _helper_createAccessCriteria(1, round3Id);

        // TODO
        fundingPot.setAccessCriteria(round3Id, 1, 0, nftR3, merkleR3, allowedR3);
        fundingPot.setAccessCriteriaPrivileges(
            round3Id, 1, r3ExpectedEffectiveCap, false, 0, 0, 0
        );

        assertEq(
            fundingPot.getGlobalAccumulationStartRoundId(),
            1,
            "Default global start round ID should be 1"
        );

        // --- Attempt Contribution in Round 3 by C3 ---
        vm.warp(initialTimestamp + 5 days + 1 hours);

        vm.startPrank(contributor3_);
        fundingPot.contributeToRoundFor(
            contributor3_, round3Id, r3ExpectedEffectiveCap, 1, new bytes32[](0)
        );
        vm.stopPrank();

        // --- Assertions ---
        assertEq(
            fundingPot.getTotalRoundContribution(round3Id),
            r3ExpectedEffectiveCap,
            "R3 total contributions should match effective cap with rollover from R1 and R2"
        );
        assertEq(
            fundingPot.getUserContributionToRound(round3Id, contributor3_),
            r3ExpectedEffectiveCap,
            "R3 C3 contribution incorrect"
        );

        vm.startPrank(contributor1_);
        _token.approve(address(fundingPot), 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundCapReached
                    .selector
            )
        );
        fundingPot.contributeToRoundFor(
            contributor1_, round3Id, 1, 1, new bytes32[](0)
        );
        vm.stopPrank();
    }

    function testContribute_allMode_defaultGlobalStartAllowsPersonalCapAccumulationFromAllPrevious(
    ) public {
        // SCENARIO: globalAccumulationStartRoundId = 1 allows personal cap
        // accumulation from R1 to R2, when both are in All mode. (Simplified for stack)

        uint initialTimestamp = block.timestamp;
        uint8 accessId = 1;

        // --- Round 1: Setup & C1 Contribution ---
        uint r1PersonalCapC1 = 500;
        uint r1ContributionC1 = 100;
        uint32 round1Id = fundingPot.createRound(
            initialTimestamp + 1 days,
            initialTimestamp + 2 days,
            1000,
            address(0),
            bytes(""),
            false,
            ILM_PC_FundingPot_v1.AccumulationMode.All
        );
        fundingPot.setAccessCriteria(
            round1Id, accessId, 0, address(0), bytes32(0), new address[](0)
        );
        fundingPot.setAccessCriteriaPrivileges(
            round1Id, accessId, r1PersonalCapC1, false, 0, 0, 0
        );

        vm.warp(initialTimestamp + 1 days + 1 hours);
        vm.startPrank(contributor1_);
        _token.approve(address(fundingPot), type(uint).max);
        fundingPot.contributeToRoundFor(
            contributor1_,
            round1Id,
            r1ContributionC1,
            accessId,
            new bytes32[](0)
        );
        vm.stopPrank();
        uint r1UnusedPersonalForC1 = r1PersonalCapC1 - r1ContributionC1;

        // --- Round 2: Setup ---
        uint r2BasePersonalCapC1 = 200;
        uint32 round2Id = fundingPot.createRound(
            initialTimestamp + 3 days,
            initialTimestamp + 4 days,
            2000,
            address(0),
            bytes(""),
            false,
            ILM_PC_FundingPot_v1.AccumulationMode.All
        );
        fundingPot.setAccessCriteria(
            round2Id, accessId, 0, address(0), bytes32(0), new address[](0)
        );
        fundingPot.setAccessCriteriaPrivileges(
            round2Id, accessId, r2BasePersonalCapC1, false, 0, 0, 0
        );

        // --- Global Start ID Check ---
        assertEq(
            fundingPot.getGlobalAccumulationStartRoundId(),
            1,
            "Default global start ID is 1"
        );

        // --- C1 Contribution to Round 2 (Testing Personal Cap Rollover) ---
        vm.warp(initialTimestamp + 3 days + 1 hours);
        uint expectedEffectivePersonalCapC1R2 =
            r2BasePersonalCapC1 + r1UnusedPersonalForC1;
        uint c1AttemptR2 = expectedEffectivePersonalCapC1R2 + 50;

        ILM_PC_FundingPot_v1.UnspentPersonalRoundCap[] memory unspentCapsC1 =
            new ILM_PC_FundingPot_v1.UnspentPersonalRoundCap[](1);
        unspentCapsC1[0] = ILM_PC_FundingPot_v1.UnspentPersonalRoundCap(
            round1Id, accessId, new bytes32[](0)
        );

        vm.startPrank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_,
            round2Id,
            c1AttemptR2,
            accessId,
            new bytes32[](0),
            unspentCapsC1
        );
        vm.stopPrank();

        // --- Assertions ---
        assertEq(
            fundingPot.getUserContributionToRound(round2Id, contributor1_),
            expectedEffectivePersonalCapC1R2,
            "R2 C1 personal contribution incorrect"
        );
        assertEq(
            fundingPot.getTotalRoundContribution(round2Id),
            expectedEffectivePersonalCapC1R2,
            "R2 Total contributions incorrect"
        );
    }

    function testContribute_allMode_defaultGlobalStartAllowsTotalCapAccumulationFromAllPrevious(
    ) public {
        // SCENARIO: globalAccumulationStartRoundId = 1 (default or set) allows total cap
        // accumulation from R1 to R2, when both are in All mode.

        uint initialTimestamp = block.timestamp;
        uint8 accessId = 1; // Open access

        // --- Round 1 Parameters (All Mode) ---
        uint r1BaseTotalCap = 1000;
        uint r1C1PersonalCap = 800;
        uint r1C1Contribution = 600;

        // --- Round 2 Parameters (All Mode) ---
        uint r2BaseTotalCap = 500;

        // --- Approvals ---
        vm.startPrank(contributor1_);
        _token.approve(address(fundingPot), type(uint).max);
        vm.stopPrank();

        // --- Create Round 1 (All Mode) ---
        uint32 round1Id = fundingPot.createRound(
            initialTimestamp + 1 days,
            initialTimestamp + 2 days,
            r1BaseTotalCap,
            address(0),
            bytes(""),
            false,
            ILM_PC_FundingPot_v1.AccumulationMode.All
        );
        fundingPot.setAccessCriteria(
            round1Id, accessId, 0, address(0), bytes32(0), new address[](0)
        );
        fundingPot.setAccessCriteriaPrivileges(
            round1Id, accessId, r1C1PersonalCap, false, 0, 0, 0
        );

        // --- Contribution by C1 to Round 1 ---
        vm.warp(initialTimestamp + 1 days + 1 hours);
        vm.startPrank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_,
            round1Id,
            r1C1Contribution,
            accessId,
            new bytes32[](0)
        );
        vm.stopPrank();
        uint r1UnusedTotal = r1BaseTotalCap - r1C1Contribution;

        // --- Create Round 2 (All Mode) ---
        uint32 round2Id = fundingPot.createRound(
            initialTimestamp + 3 days,
            initialTimestamp + 4 days,
            r2BaseTotalCap,
            address(0),
            bytes(""),
            false,
            ILM_PC_FundingPot_v1.AccumulationMode.All
        );
        fundingPot.setAccessCriteria(
            round2Id, accessId, 0, address(0), bytes32(0), new address[](0)
        );
        uint r2ExpectedEffectiveTotalCap = r2BaseTotalCap + r1UnusedTotal;
        fundingPot.setAccessCriteriaPrivileges(
            round2Id, accessId, r2ExpectedEffectiveTotalCap, false, 0, 0, 0
        );

        // --- Ensure Global Start Round ID is 1 ---
        assertEq(
            fundingPot.getGlobalAccumulationStartRoundId(),
            1,
            "Global start round ID should be 1 by default"
        );

        // --- Attempt Contribution in Round 2 by C1 to fill effective total cap ---
        vm.warp(initialTimestamp + 3 days + 1 hours);

        uint c1AttemptR2 = r2ExpectedEffectiveTotalCap;

        vm.startPrank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_, round2Id, c1AttemptR2, accessId, new bytes32[](0)
        );
        vm.stopPrank();

        // --- Assertions ---
        assertEq(
            fundingPot.getUserContributionToRound(round2Id, contributor1_),
            c1AttemptR2,
            "R2 C1 contribution should match attempt (filling effective total cap)"
        );
        assertEq(
            fundingPot.getTotalRoundContribution(round2Id),
            r2ExpectedEffectiveTotalCap,
            "R2 Total contributions should match effective total cap (All mode, global_start=1)"
        );
    }

    function testContribute_allMode_globalStartRestrictsPersonalCapAccumulationFromEarlierRounds(
    ) public {
        // SCENARIO: globalAccumulationStartRoundId = 2 restricts personal cap accumulation
        // from R1 for R2, when both are in All mode.

        uint initialTimestamp = block.timestamp;
        uint8 accessId = 1; // Open access

        // --- Round 1 Parameters (All Mode) ---
        uint r1PersonalCapC1 = 500;
        uint r1ContributionC1 = 100;
        uint r1BaseTotalCap = 1000;

        // --- Round 2 Parameters (All Mode) ---
        uint r2BasePersonalCapC1 = 50;
        uint r2BaseTotalCap = 1000;

        // --- Approvals ---
        vm.startPrank(contributor1_);
        _token.approve(address(fundingPot), type(uint).max);
        vm.stopPrank();

        // --- Create Round 1 (All Mode) ---
        uint32 round1Id = fundingPot.createRound(
            initialTimestamp + 1 days,
            initialTimestamp + 2 days,
            r1BaseTotalCap,
            address(0),
            bytes(""),
            false,
            ILM_PC_FundingPot_v1.AccumulationMode.All
        );
        fundingPot.setAccessCriteria(
            round1Id, accessId, 0, address(0), bytes32(0), new address[](0)
        );
        fundingPot.setAccessCriteriaPrivileges(
            round1Id, accessId, r1PersonalCapC1, false, 0, 0, 0
        );

        // --- Contribution by C1 to Round 1 ---
        vm.warp(initialTimestamp + 1 days + 1 hours);
        vm.startPrank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_,
            round1Id,
            r1ContributionC1,
            accessId,
            new bytes32[](0)
        );
        vm.stopPrank();

        // --- Create Round 2 (All Mode) ---
        uint32 round2Id = fundingPot.createRound(
            initialTimestamp + 3 days,
            initialTimestamp + 4 days,
            r2BaseTotalCap,
            address(0),
            bytes(""),
            false,
            ILM_PC_FundingPot_v1.AccumulationMode.All
        );
        fundingPot.setAccessCriteria(
            round2Id, accessId, 0, address(0), bytes32(0), new address[](0)
        );
        fundingPot.setAccessCriteriaPrivileges(
            round2Id, accessId, r2BasePersonalCapC1, false, 0, 0, 0
        );

        // --- Set Global Start Round ID to Round 2's ID ---
        fundingPot.setGlobalAccumulationStart(round2Id);
        assertEq(
            fundingPot.getGlobalAccumulationStartRoundId(),
            round2Id,
            "Global start ID not set to R2 ID"
        );

        // --- Attempt Contribution in Round 2 by C1 ---
        vm.warp(initialTimestamp + 3 days + 1 hours);

        uint c1AttemptR2 = r2BasePersonalCapC1 + 100;

        ILM_PC_FundingPot_v1.UnspentPersonalRoundCap[] memory unspentCapsC1 =
            new ILM_PC_FundingPot_v1.UnspentPersonalRoundCap[](1);
        unspentCapsC1[0] = ILM_PC_FundingPot_v1.UnspentPersonalRoundCap(
            round1Id, accessId, new bytes32[](0)
        );

        vm.startPrank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_,
            round2Id,
            c1AttemptR2,
            accessId,
            new bytes32[](0),
            unspentCapsC1
        );
        vm.stopPrank();

        // --- Assertions ---
        assertEq(
            fundingPot.getUserContributionToRound(round2Id, contributor1_),
            r2BasePersonalCapC1,
            "R2 C1 personal contribution should be clamped by R2 base personal cap (All mode, global_start=R2)"
        );
        assertEq(
            fundingPot.getTotalRoundContribution(round2Id),
            r2BasePersonalCapC1,
            "R2 Total contributions should be C1's clamped amount (All mode, global_start=R2)"
        );
    }

    function testContribute_allMode_globalStartRestrictsTotalCapAccumulationFromEarlierRounds(
    ) public {
        // SCENARIO: globalAccumulationStartRoundId = 2 restricts total cap accumulation
        // from R1 for R2, when both are in All mode.

        uint initialTimestamp = block.timestamp;
        uint8 accessId = 1; // Open access

        // --- Round 1 Parameters (All Mode) ---
        uint r1BaseTotalCap = 1000;
        uint r1C1PersonalCap = 800;
        uint r1C1Contribution = 400;

        // --- Round 2 Parameters (All Mode) ---
        uint r2BaseTotalCap = 200;

        // --- Approvals ---
        vm.startPrank(contributor1_);
        _token.approve(address(fundingPot), type(uint).max);
        vm.stopPrank();

        // --- Create Round 1 (All Mode) ---
        uint32 round1Id = fundingPot.createRound(
            initialTimestamp + 1 days,
            initialTimestamp + 2 days,
            r1BaseTotalCap,
            address(0),
            bytes(""),
            false,
            ILM_PC_FundingPot_v1.AccumulationMode.All
        );
        fundingPot.setAccessCriteria(
            round1Id, accessId, 0, address(0), bytes32(0), new address[](0)
        );
        fundingPot.setAccessCriteriaPrivileges(
            round1Id, accessId, r1C1PersonalCap, false, 0, 0, 0
        );

        // --- Contribution by C1 to Round 1 ---
        vm.warp(initialTimestamp + 1 days + 1 hours);
        vm.startPrank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_,
            round1Id,
            r1C1Contribution,
            accessId,
            new bytes32[](0)
        );
        vm.stopPrank();

        // --- Create Round 2 (All Mode) ---
        uint32 round2Id = fundingPot.createRound(
            initialTimestamp + 3 days,
            initialTimestamp + 4 days,
            r2BaseTotalCap,
            address(0),
            bytes(""),
            false,
            ILM_PC_FundingPot_v1.AccumulationMode.All
        );
        fundingPot.setAccessCriteria(
            round2Id, accessId, 0, address(0), bytes32(0), new address[](0)
        );
        fundingPot.setAccessCriteriaPrivileges(
            round2Id, accessId, r2BaseTotalCap, false, 0, 0, 0
        );

        // --- Set Global Start Round ID to Round 2's ID ---
        fundingPot.setGlobalAccumulationStart(round2Id);
        assertEq(
            fundingPot.getGlobalAccumulationStartRoundId(),
            round2Id,
            "Global start ID not set to R2 ID"
        );

        // --- Attempt Contribution in Round 2 by C1 ---
        vm.warp(initialTimestamp + 3 days + 1 hours);

        uint c1AttemptR2 = r2BaseTotalCap + 100;

        vm.startPrank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_, round2Id, c1AttemptR2, accessId, new bytes32[](0)
        );
        vm.stopPrank();

        // --- Assertions ---
        assertEq(
            fundingPot.getUserContributionToRound(round2Id, contributor1_),
            r2BaseTotalCap,
            "R2 C1 contribution should be clamped by R2 base total cap (All mode, global_start=R2)"
        );
        assertEq(
            fundingPot.getTotalRoundContribution(round2Id),
            r2BaseTotalCap,
            "R2 Total contributions should be R2 base total cap (All mode, global_start=R2)"
        );
    }
}
