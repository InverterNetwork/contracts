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
        (
            uint currentRoundStart,
            ,
            ,
            ,
            ,
            ,
            ILM_PC_FundingPot_v1.AccumulationMode mode
        ) = fundingPot.getRoundGenericParameters(roundId);

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

        (uint roundStart,,,,,, ILM_PC_FundingPot_v1.AccumulationMode mode) =
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
        (uint roundStart,,,,,, ILM_PC_FundingPot_v1.AccumulationMode mode) =
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

        (uint roundStart,,,,,, ILM_PC_FundingPot_v1.AccumulationMode mode) =
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

        (uint roundStart,,,,,, ILM_PC_FundingPot_v1.AccumulationMode mode) =
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

        (uint roundStart,,,,,, ILM_PC_FundingPot_v1.AccumulationMode mode) =
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

        (uint roundStart,,,,,, ILM_PC_FundingPot_v1.AccumulationMode mode) =
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

        (uint roundStart,,,,,, ILM_PC_FundingPot_v1.AccumulationMode mode) =
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

        (uint roundStart,,,,,, ILM_PC_FundingPot_v1.AccumulationMode mode) =
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

        (uint roundStart,,,,,, ILM_PC_FundingPot_v1.AccumulationMode mode) =
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

        (uint roundStart,,,,,, ILM_PC_FundingPot_v1.AccumulationMode mode) =
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

        (uint roundStart,,,,,, ILM_PC_FundingPot_v1.AccumulationMode mode) =
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
        _defaultRoundParams.accumulationMode =
            ILM_PC_FundingPot_v1.AccumulationMode.All;
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
        (uint roundStart,,,,,, ILM_PC_FundingPot_v1.AccumulationMode mode) =
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
        (
            uint roundStart,
            uint roundEnd,
            uint roundCap,
            address hookContract,
            bytes memory hookFunction,
            bool autoClosure,
            ILM_PC_FundingPot_v1.AccumulationMode mode
        ) = fundingPot.getRoundGenericParameters(roundId);
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

        (uint roundStart,,,,,, ILM_PC_FundingPot_v1.AccumulationMode mode) =
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

        (uint roundStart,,,,,, ILM_PC_FundingPot_v1.AccumulationMode mode) =
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
        (uint roundStart,,,,,, ILM_PC_FundingPot_v1.AccumulationMode mode) =
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

        (uint roundStart,,,,,, ILM_PC_FundingPot_v1.AccumulationMode mode) =
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
            round2Id,
            accessCriteriaId,
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
            fundingPot.exposed_getUserContributionToRound(
                round2Id, contributor2_
            ),
            50
        );
        vm.stopPrank();

        // Verify total contributions to round 2 is exactly the round cap (450 + 50 = 500).
        assertEq(fundingPot.exposed_getTotalRoundContributions(round2Id), 500);

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
        assertEq(fundingPot.exposed_getTotalRoundContributions(round2Id), 500);
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
        ) = _helper_createAccessCriteria(accessCriteriaId);

        fundingPot.setAccessCriteriaForRound(
            round1Id,
            accessCriteriaId,
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
        fundingPot.setAccessCriteriaForRound(
            round2Id,
            accessCriteriaId,
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
            fundingPot.exposed_getUserContributionToRound(
                round1Id, contributor1_
            ),
            600
        );
        assertEq(fundingPot.exposed_getTotalRoundContributions(round1Id), 600);

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
            fundingPot.exposed_getUserContributionToRound(
                round2Id, contributor2_
            ),
            300,
            "C2 contribution should be clamped by personal cap"
        );
        vm.stopPrank();

        // Verify total contributions after C2 is 300
        assertEq(
            fundingPot.exposed_getTotalRoundContributions(round2Id),
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
            fundingPot.exposed_getUserContributionToRound(
                round2Id, contributor1_
            ),
            300,
            "C1 contribution should be clamped by personal cap"
        );
        vm.stopPrank();

        // Verify total round contributions: 300 (C2) + 300 (C1) = 600
        assertEq(
            fundingPot.exposed_getTotalRoundContributions(round2Id),
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
            fundingPot.exposed_getUserContributionToRound(
                round2Id, contributor3_
            ),
            300,
            "C3 contributes remaining 300"
        );
        vm.stopPrank();

        // Total contributions should now be 900 (300 + 300 + 300), matching the effective cap.
        assertEq(
            fundingPot.exposed_getTotalRoundContributions(round2Id),
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
            fundingPot.exposed_getTotalRoundContributions(round2Id),
            900,
            "Final total should be effective cap"
        );
    }

    // -------------------------------------------------------------------------
    // Test: Global Accumulation Start Round Settings
    // -------------------------------------------------------------------------

    function testGetGlobalAccumulationStartRoundId_Default() public {
        // Expecting default value to be 1 as per AC
        assertEq(
            fundingPot.getGlobalAccumulationStartRoundId(),
            1,
            "Default start round ID should be 1"
        );
    }

    function testSetGlobalAccumulationStart_RevertsGivenUnauthorizedUser(
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

    function testSetGlobalAccumulationStart_RevertsGivenStartRoundIsZero()
        public
    {
        // AC: Must revert if startRoundId_ == 0
        // Note: Add specific custom error later if desired
        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__StartRoundCannotBeZero
                    .selector
            )
        );
        fundingPot.setGlobalAccumulationStart(0);
    }

    function testSetGlobalAccumulationStart_RevertsGivenStartRoundGreaterThanCount(
        uint32 startRoundIdOffset
    ) public {
        testCreateRound(); // Ensure roundCount is at least 1
        uint32 currentRoundCount = fundingPot.getRoundCount();

        vm.assume(startRoundIdOffset > 0); // Ensure invalidStartRoundId will be greater
        // Prevent overflow: currentRoundCount + startRoundIdOffset <= type(uint32).max
        // Therefore: startRoundIdOffset <= type(uint32).max - currentRoundCount
        // currentRoundCount is at least 1, so type(uint32).max - currentRoundCount will not underflow.
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

    function testSetGlobalAccumulationStart_Success(uint32 startRoundId)
        public
    {
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
            vm.assume(false);
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

    function testAccumulation_GlobalStartRoundRestricts_PersonalMode() public {
        // SCENARIO: globalAccumulationStartRoundId = 2 restricts accumulation from Round 1 for Personal mode
        // 1. Setup: Round 1, Round 2, Round 3. Partial contributions in R1 & R2.
        // 2. Action: setGlobalAccumulationStart(2)
        // 3. Verification: For contributions to R3 (Personal mode), only unused personal from R2 rolls over.

        uint initialTimestamp = block.timestamp;

        // --- Setup Rounds ---
        uint r1PersonalCap = 500;
        uint r1Contribution = 100;
        uint r1UnusedPersonal = r1PersonalCap - r1Contribution;

        uint r2PersonalCap = 600;
        uint r2Contribution = 200;
        uint r2UnusedPersonal = r2PersonalCap - r2Contribution;

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
        fundingPot.setAccessCriteriaForRound(
            round1Id, 1, address(0), bytes32(0), new address[](0)
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
        fundingPot.setAccessCriteriaForRound(
            round2Id, 1, address(0), bytes32(0), new address[](0)
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
        fundingPot.setAccessCriteriaForRound(
            round3Id, 1, address(0), bytes32(0), new address[](0)
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
        // User claims unspent from R1 (should be ignored)
        unspentCaps[0] = ILM_PC_FundingPot_v1.UnspentPersonalRoundCap(
            round1Id, 1, new bytes32[](0)
        );
        // User claims unspent from R2 (should be counted)
        unspentCaps[1] = ILM_PC_FundingPot_v1.UnspentPersonalRoundCap(
            round2Id, 1, new bytes32[](0)
        );

        uint expectedR3PersonalCap = r3BasePersonalCap + r2UnusedPersonal; // Only R2's unused personal cap

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
            fundingPot.exposed_getUserContributionToRound(
                round3Id, contributor1_
            ),
            expectedR3PersonalCap,
            "R3 personal contribution incorrect"
        );
    }

    function testAccumulation_GlobalStartRoundRestricts_TotalMode() public {
        // SCENARIO: globalAccumulationStartRoundId = 2 restricts accumulation from Round 1 for Total mode
        // 1. Setup: Round 1, Round 2, Round 3. Partial contributions in R1 & R2.
        // 2. Action: setGlobalAccumulationStart(2)
        // 3. Verification: For contributions to R3 (Total mode), only unused total from R2 expands R3 cap.

        uint initialTimestamp = block.timestamp;
        
        // --- Setup Rounds ---
        uint r1BaseCap = 1000;
        uint r1Contribution = 400;
        uint r1UnusedTotal = r1BaseCap - r1Contribution;

        uint r2BaseCap = 1200;
        uint r2Contribution = 500;
        uint r2UnusedTotal = r2BaseCap - r2Contribution;

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
        fundingPot.setAccessCriteriaForRound(
            round1Id, 1, address(0), bytes32(0), new address[](0)
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
        fundingPot.setAccessCriteriaForRound(
            round2Id, 1, address(0), bytes32(0), new address[](0)
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
        fundingPot.setAccessCriteriaForRound(
            round3Id, 1, address(0), bytes32(0), new address[](0)
        );
        fundingPot.setAccessCriteriaPrivileges(
            round3Id, 1, r3BaseCap + r2UnusedTotal, false, 0, 0, 0
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

        uint expectedR3EffectiveCap = r3BaseCap + r2UnusedTotal; // Only R2's unused total cap

        vm.startPrank(contributor1_);
        // Attempt to contribute up to the expected new effective cap
        fundingPot.contributeToRoundFor(
            contributor1_, round3Id, expectedR3EffectiveCap, 1, new bytes32[](0)
        );
        vm.stopPrank();

        // --- Assertion ---
        assertEq(
            fundingPot.exposed_getTotalRoundContributions(round3Id),
            expectedR3EffectiveCap,
            "R3 total contribution incorrect, effective cap not as expected"
        );
        assertEq(
            fundingPot.exposed_getUserContributionToRound(
                round3Id, contributor1_
            ),
            expectedR3EffectiveCap,
            "R3 user contribution incorrect"
        );
    }

    function testAccumulation_DefaultGlobalStartRound_PersonalMode() public {
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
        fundingPot.setAccessCriteriaForRound(
            round1Id, accessId, address(0), bytes32(0), new address[](0)
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
        fundingPot.setAccessCriteriaForRound(
            round2Id, accessId, address(0), bytes32(0), new address[](0)
        );
        fundingPot.setAccessCriteriaPrivileges(
            round2Id, accessId, r2BasePersonalCapC1, false, 0, 0, 0
        );

        // --- Contribution by C1 to Round 1 ---
        vm.startPrank(contributor1_);
        vm.warp(initialTimestamp + 1 days + 1 hours); // Enter Round 1
        fundingPot.contributeToRoundFor(
            contributor1_, round1Id, r1ContributionC1, accessId, new bytes32[](0)
        );
        vm.stopPrank();

        // --- Verify Default Global Start Round ID ---
        assertEq(fundingPot.getGlobalAccumulationStartRoundId(), 1, "Default global start round ID should be 1");

        // --- Attempt Contribution in Round 2 by C1 ---
        vm.warp(initialTimestamp + 3 days + 1 hours); // Enter Round 2

        ILM_PC_FundingPot_v1.UnspentPersonalRoundCap[] memory unspentCapsC1 =
            new ILM_PC_FundingPot_v1.UnspentPersonalRoundCap[](1);
        unspentCapsC1[0] = ILM_PC_FundingPot_v1.UnspentPersonalRoundCap(
            round1Id, accessId, new bytes32[](0) // Should be counted
        );

        uint r1UnusedPersonalC1 = r1PersonalCapC1 - r1ContributionC1; // 400

        // Expected C1 effective personal cap in R2 = R2_Base (300) + R1_Unused (400) = 700
        uint expectedC1EffectivePersonalCapR2 = r2BasePersonalCapC1 + r1UnusedPersonalC1;

        uint c1AttemptR2 = expectedC1EffectivePersonalCapR2 + 50; // Try to contribute slightly more
        uint expectedC1ContributionR2 = expectedC1EffectivePersonalCapR2; // Should be clamped

        // Ensure the attempt is not clamped by the round cap (which is large)
        if (expectedC1ContributionR2 > 10_000) { // 10_000 is round cap for R2
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
            fundingPot.exposed_getUserContributionToRound(round2Id, contributor1_),
            expectedC1ContributionR2,
            "R2 C1 personal contribution incorrect (should use R1 unused)"
        );
    }

    function testAccumulation_DefaultGlobalStartRound_TotalMode() public {
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
        fundingPot.setAccessCriteriaForRound(
            round1Id, accessId, address(0), bytes32(0), new address[](0)
        );
        fundingPot.setAccessCriteriaPrivileges(
            round1Id, accessId, r1PersonalCap, false, 0, 0, 0
        );

        // --- Contribution by C1 to Round 1 ---
        vm.warp(initialTimestamp + 1 days + 1 hours); 
        vm.startPrank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_, round1Id, r1ContributionC1, accessId, new bytes32[](0)
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
        fundingPot.setAccessCriteriaForRound(
            round2Id, accessId, address(0), bytes32(0), new address[](0)
        );
        // Set personal cap for R2 to be at least the expected effective total cap
        uint r2ExpectedEffectiveTotalCap = r2BaseCap + r1UnusedTotal; // 500 + 400 = 900
        fundingPot.setAccessCriteriaPrivileges(
            round2Id, accessId, r2ExpectedEffectiveTotalCap, false, 0, 0, 0 
        );

        // --- Verify Default Global Start Round ID ---
        assertEq(fundingPot.getGlobalAccumulationStartRoundId(), 1, "Default global start round ID should be 1");

        // --- Attempt Contribution in Round 2 by C1 ---
        vm.warp(initialTimestamp + 3 days + 1 hours); 

        uint c1AttemptR2 = r2ExpectedEffectiveTotalCap - 100; // e.g., 900 - 100 = 800. Utilizes expanded cap.
        assertTrue(c1AttemptR2 > r2BaseCap, "C1 R2 attempt should be > R2 base cap");
        assertTrue(c1AttemptR2 <= r2ExpectedEffectiveTotalCap, "C1 R2 attempt should be <= R2 effective cap");

        vm.startPrank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_, round2Id, c1AttemptR2, accessId, new bytes32[](0)
        );
        vm.stopPrank();

        // --- Assertions ---
        assertEq(
            fundingPot.exposed_getUserContributionToRound(round2Id, contributor1_),
            c1AttemptR2,
            "R2 C1 contribution incorrect"
        );
        assertEq(
            fundingPot.exposed_getTotalRoundContributions(round2Id),
            c1AttemptR2,
            "R2 Total contributions after C1 incorrect"
        );
        
        // Verify that the total contributions possible is indeed the effective cap
        // by trying to contribute slightly more by another user (or same user if personal cap allows more)
        // For simplicity, let's check if C1 can contribute the remaining if personal cap on R2 was higher than c1AttemptR2.
        // Here, personal cap for R2 for accessId 1 was set to r2ExpectedEffectiveTotalCap.
        // C1 already contributed c1AttemptR2. Remaining personal = r2ExpectedEffectiveTotalCap - c1AttemptR2.
        // Remaining total = r2ExpectedEffectiveTotalCap - c1AttemptR2.
        uint remainingToFill = r2ExpectedEffectiveTotalCap - c1AttemptR2;
        if (remainingToFill > 0) {
             vm.startPrank(contributor1_); // C1 continues, as personal cap allows
             fundingPot.contributeToRoundFor(
                contributor1_, round2Id, remainingToFill, accessId, new bytes32[](0)
            );
            vm.stopPrank();
        }

        assertEq(
            fundingPot.exposed_getTotalRoundContributions(round2Id),
            r2ExpectedEffectiveTotalCap,
            "R2 final total contributions should match effective total cap"
        );
    }

    function testAccumulation_DisabledMode_IgnoresGlobalStartRound() public {
        // SCENARIO: AccumulationMode.Disabled on a target round (R2) prevents any accumulation 
        // from a previous round (R1), even if globalAccumulationStartRoundId would allow it.

        uint initialTimestamp = block.timestamp;
        uint8 accessId = 1; // Open access

        // --- Round 1 Parameters (set to allow accumulation to make the test meaningful) ---
        uint r1PersonalCapC1 = 500;
        uint r1ContributionC1 = 100; // Leaves 400 unused personal from R1
        uint r1BaseCap = 1000;       // R1 total cap
                                      // R1 unused total = 1000 - 100 = 900 (assuming only C1 contributes to R1)

        // --- Round 2 Parameters (Disabled Mode) ---
        uint r2BasePersonalCapC1 = 50; // Very small base personal cap for C1 in R2
        uint r2BaseCap = 200;          // Small base total cap for R2

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
            ILM_PC_FundingPot_v1.AccumulationMode.Personal // R1 allows personal accumulation
        );
        fundingPot.setAccessCriteriaForRound(
            round1Id, accessId, address(0), bytes32(0), new address[](0)
        );
        fundingPot.setAccessCriteriaPrivileges(
            round1Id, accessId, r1PersonalCapC1, false, 0, 0, 0
        );

        // --- Contribution by C1 to Round 1 ---
        vm.warp(initialTimestamp + 1 days + 1 hours); 
        vm.startPrank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_, round1Id, r1ContributionC1, accessId, new bytes32[](0)
        );
        vm.stopPrank();
        // uint r1UnusedPersonalFromC1 = r1PersonalCapC1 - r1ContributionC1; // 400
        // uint r1UnusedTotalFromR1 = r1BaseCap - r1ContributionC1;       // 900

        // --- Create Round 2 (Disabled Mode) ---
        uint32 round2Id = fundingPot.createRound(
            initialTimestamp + 3 days,
            initialTimestamp + 4 days,
            r2BaseCap, // R2's own base cap
            address(0),
            bytes(""),
            false,
            ILM_PC_FundingPot_v1.AccumulationMode.Disabled // R2 accumulation is DISABLED
        );
        fundingPot.setAccessCriteriaForRound(
            round2Id, accessId, address(0), bytes32(0), new address[](0)
        );
        fundingPot.setAccessCriteriaPrivileges(
            round2Id, accessId, r2BasePersonalCapC1, false, 0, 0, 0 // R2 personal cap for C1
        );

        // --- Set Global Start Round ID to allow R1 (to show it's ignored by R2's Disabled mode) ---
        fundingPot.setGlobalAccumulationStart(1);
        assertEq(fundingPot.getGlobalAccumulationStartRoundId(), 1, "Global start round ID should be 1");

        // --- Attempt Contribution in Round 2 by C1 ---
        vm.warp(initialTimestamp + 3 days + 1 hours); 

        // C1 attempts to contribute more than R2's base personal cap, expecting it to be clamped
        // even though R1 had unused personal capacity and global start allows R1.
        uint c1AttemptR2 = r2BasePersonalCapC1 + 100; // e.g., 50 + 100 = 150
        
        // This unspentCaps array would be used if accumulation was active.
        // We pass it to show that even with it, Disabled mode takes precedence.
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
            unspentCapsC1 // Provide R1 unspent, should be ignored
        );
        vm.stopPrank();

        // --- Assertions ---
        // 1. C1's contribution should be clamped by R2's base personal cap (r2BasePersonalCapC1)
        assertEq(
            fundingPot.exposed_getUserContributionToRound(round2Id, contributor1_),
            r2BasePersonalCapC1,
            "R2 C1 personal contribution should be clamped by R2's base personal cap (Disabled mode)"
        );

        // 2. Total contributions to R2 should reflect this clamped amount.
        //    If C1 was the only contributor and got clamped to r2BasePersonalCapC1, total is r2BasePersonalCapC1.
        //    This also implicitly tests that R2's total cap wasn't expanded by R1's unused total.
        assertEq(
            fundingPot.exposed_getTotalRoundContributions(round2Id),
            r2BasePersonalCapC1, // Assuming C1 is the only one contributing and capped
            "R2 Total contributions should not be expanded by R1 (Disabled mode)"
        );
        
        // 3. Further check: ensure total contributions do not exceed R2's original base cap.
        assertTrue(
            fundingPot.exposed_getTotalRoundContributions(round2Id) <= r2BaseCap,
            "R2 Total contributions exceeded R2's original base cap (Disabled mode)"
        );  
    }

    function testAccumulation_GlobalStartEqualsTargetRound_NoAccumulation()
        public
    {
        // SCENARIO: If globalAccumulationStartRoundId is set to the target round's ID (R2),
        // no accumulation from any previous round (R1) occurs for R2, even if R2's mode would allow it.

        uint initialTimestamp = block.timestamp;
        uint8 accessId = 1; // Open access

        // --- Round 1 Parameters (set to allow accumulation to make the test meaningful) ---
        uint r1PersonalCapC1 = 500;
        uint r1ContributionC1 = 100; // Leaves 400 unused personal from R1
        uint r1BaseCap = 1000;       // R1 total cap
                                      // R1 unused total = 1000 - 100 = 900

        // --- Round 2 Parameters (Mode that would normally allow accumulation, e.g., Personal) ---
        uint r2BasePersonalCapC1 = 50; // Very small base personal cap for C1 in R2
        uint r2BaseCap = 200;          // Small base total cap for R2

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
            ILM_PC_FundingPot_v1.AccumulationMode.Personal // R1 allows personal accumulation
        );
        fundingPot.setAccessCriteriaForRound(
            round1Id, accessId, address(0), bytes32(0), new address[](0)
        );
        fundingPot.setAccessCriteriaPrivileges(
            round1Id, accessId, r1PersonalCapC1, false, 0, 0, 0
        );

        // --- Contribution by C1 to Round 1 ---
        vm.warp(initialTimestamp + 1 days + 1 hours); 
        vm.startPrank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_, round1Id, r1ContributionC1, accessId, new bytes32[](0)
        );
        vm.stopPrank();

        // --- Create Round 2 (Personal Mode - would normally allow accumulation from R1) ---
        uint32 round2Id = fundingPot.createRound(
            initialTimestamp + 3 days,
            initialTimestamp + 4 days,
            r2BaseCap, // R2's own base cap
            address(0),
            bytes(""),
            false,
            ILM_PC_FundingPot_v1.AccumulationMode.Personal 
        );
        fundingPot.setAccessCriteriaForRound(
            round2Id, accessId, address(0), bytes32(0), new address[](0)
        );
        fundingPot.setAccessCriteriaPrivileges(
            round2Id, accessId, r2BasePersonalCapC1, false, 0, 0, 0 // R2 personal cap for C1
        );

        // --- Set Global Start Round ID to be Round 2's ID ---
        fundingPot.setGlobalAccumulationStart(round2Id); // Key part of the test
        assertEq(fundingPot.getGlobalAccumulationStartRoundId(), round2Id, "Global start round ID not set to R2 ID");

        // --- Attempt Contribution in Round 2 by C1 ---
        vm.warp(initialTimestamp + 3 days + 1 hours); 

        // C1 attempts to contribute more than R2's base personal cap.
        // It should be clamped because R1 is not considered for accumulation.
        uint c1AttemptR2 = r2BasePersonalCapC1 + 100; // e.g., 50 + 100 = 150
        
        ILM_PC_FundingPot_v1.UnspentPersonalRoundCap[] memory unspentCapsC1 =
            new ILM_PC_FundingPot_v1.UnspentPersonalRoundCap[](1);
        unspentCapsC1[0] = ILM_PC_FundingPot_v1.UnspentPersonalRoundCap(
            round1Id, accessId, new bytes32[](0) // Provide R1 unspent, should be ignored
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
        // 1. C1's contribution should be clamped by R2's base personal cap (r2BasePersonalCapC1)
        assertEq(
            fundingPot.exposed_getUserContributionToRound(round2Id, contributor1_),
            r2BasePersonalCapC1,
            "R2 C1 personal contribution should be clamped by R2's base personal cap (global start = R2)"
        );

        // 2. Total contributions to R2 should reflect this clamped amount.
        assertEq(
            fundingPot.exposed_getTotalRoundContributions(round2Id),
            r2BasePersonalCapC1, 
            "R2 Total contributions should not be expanded by R1 (global start = R2)"
        );
        
        // 3. Further check: ensure total contributions do not exceed R2's original base cap.
        assertTrue(
            fundingPot.exposed_getTotalRoundContributions(round2Id) <= r2BaseCap,
            "R2 Total contributions exceeded R2's original base cap (global start = R2)"
        );
    }

    // -------------------------------------------------------------------------
    // Test: Global Accumulation Start Round - Logic Integration - Remaining Tests
    // -------------------------------------------------------------------------

    function testAccumulation_GlobalStartRoundAllows_PersonalMode() public {
        // SCENARIO: globalAccumulationStartRoundId = 1 allows personal cap accumulation from R1 AND R2
        // for contributions to R3, when all rounds are in Personal mode.
        // 1. Setup: R1, R2, R3 in Personal mode. C1 makes partial contributions in R1 & R2.
        // 2. Action: Verify globalAccumulationStartRoundId = 1. C1 contributes to R3.
        // 3. Verification: C1's effective personal cap in R3 includes unused from R1 and R2.

        uint initialTimestamp = block.timestamp;
        
        // --- Round Parameters, Personal Caps, and Contributions for contributor1_ ---
        uint r1PersonalCapC1 = 500;
        uint r1ContributionC1 = 200;
        // uint r1UnusedPersonalC1 = r1PersonalCapC1 - r1ContributionC1; // 300

        uint r2PersonalCapC1 = 600;
        uint r2ContributionC1 = 250;
        // uint r2UnusedPersonalC1 = r2PersonalCapC1 - r2ContributionC1; // 350

        uint r3BasePersonalCapC1 = 300;

        // Large round caps to not interfere with personal cap testing
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
        fundingPot.setAccessCriteriaForRound(round1Id, 1, address(0), bytes32(0), new address[](0));
        fundingPot.setAccessCriteriaPrivileges(round1Id, 1, r1PersonalCapC1, false, 0, 0, 0);

        // --- Contribution by C1 to Round 1 ---
        vm.warp(initialTimestamp + 1 days + 1 hours);
        vm.startPrank(contributor1_);
        fundingPot.contributeToRoundFor(contributor1_, round1Id, r1ContributionC1, 1, new bytes32[](0));
        vm.stopPrank();
        assertEq(fundingPot.exposed_getUserContributionToRound(round1Id, contributor1_), r1ContributionC1);

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
        fundingPot.setAccessCriteriaForRound(round2Id, 1, address(0), bytes32(0), new address[](0));
        fundingPot.setAccessCriteriaPrivileges(round2Id, 1, r2PersonalCapC1, false, 0, 0, 0);

        // --- Contribution by C1 to Round 2 ---
        vm.warp(initialTimestamp + 3 days + 1 hours);
        vm.startPrank(contributor1_);
        fundingPot.contributeToRoundFor(contributor1_, round2Id, r2ContributionC1, 1, new bytes32[](0));
        vm.stopPrank();
        assertEq(fundingPot.exposed_getUserContributionToRound(round2Id, contributor1_), r2ContributionC1);

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
        fundingPot.setAccessCriteriaForRound(round3Id, 1, address(0), bytes32(0), new address[](0));
        fundingPot.setAccessCriteriaPrivileges(round3Id, 1, r3BasePersonalCapC1, false, 0, 0, 0);

        // --- Verify Global Start Round ID ---
        assertEq(fundingPot.getGlobalAccumulationStartRoundId(), 1, "Default global start round ID should be 1");

        // --- Attempt Contribution in Round 3 by C1 ---
        vm.warp(initialTimestamp + 5 days + 1 hours);

        ILM_PC_FundingPot_v1.UnspentPersonalRoundCap[] memory unspentCapsC1 =
            new ILM_PC_FundingPot_v1.UnspentPersonalRoundCap[](2);
        unspentCapsC1[0] = ILM_PC_FundingPot_v1.UnspentPersonalRoundCap(round1Id, 1, new bytes32[](0));
        unspentCapsC1[1] = ILM_PC_FundingPot_v1.UnspentPersonalRoundCap(round2Id, 1, new bytes32[](0));

        uint expectedR3PersonalCapC1 = r3BasePersonalCapC1 +
                                      (r1PersonalCapC1 - r1ContributionC1) +
                                      (r2PersonalCapC1 - r2ContributionC1);
        // 300 + (500-200) + (600-250) = 300 + 300 + 350 = 950

        uint c1AttemptR3 = expectedR3PersonalCapC1; // Attempt to contribute the full expected amount

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
            fundingPot.exposed_getUserContributionToRound(round3Id, contributor1_),
            expectedR3PersonalCapC1,
            "R3 C1 personal contribution incorrect (should use R1 & R2 unused)"
        );

        // Verify total round contributions if C1 is the only one
        assertEq(
            fundingPot.exposed_getTotalRoundContributions(round3Id),
            expectedR3PersonalCapC1,
            "R3 total contributions incorrect after C1"
        );

        // Try to contribute 1 more to ensure personal cap is met for C1
        vm.startPrank(contributor1_);
        _token.approve(address(fundingPot), 1); // Approve 1 more
        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1.Module__LM_PC_FundingPot__PersonalCapReached.selector
            )
        );
        fundingPot.contributeToRoundFor(
            contributor1_,
            round3Id,
            1, // Attempt to contribute 1 more
            1,
            new bytes32[](0),
            unspentCapsC1 // Provide same unspent caps, shouldn't change outcome
        );
        vm.stopPrank();
    }

    function testAccumulation_GlobalStartRoundAllows_TotalMode() public {
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
        fundingPot.setAccessCriteriaForRound(round1Id, 1, address(0), bytes32(0), new address[](0));
        fundingPot.setAccessCriteriaPrivileges(round1Id, 1, r1BaseCap, false, 0, 0, 0); // Personal cap = round cap for simplicity

        // --- Contribution by C1 to Round 1 ---
        vm.warp(initialTimestamp + 1 days + 1 hours);
        vm.startPrank(contributor1_);
        fundingPot.contributeToRoundFor(contributor1_, round1Id, r1ContributionC1, 1, new bytes32[](0));
        vm.stopPrank();
        assertEq(fundingPot.exposed_getTotalRoundContributions(round1Id), r1ContributionC1);

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
        fundingPot.setAccessCriteriaForRound(round2Id, 1, address(0), bytes32(0), new address[](0));
        fundingPot.setAccessCriteriaPrivileges(round2Id, 1, r2BaseCap, false, 0, 0, 0); // Personal cap = round cap

        // --- Contribution by C2 to Round 2 ---
        vm.warp(initialTimestamp + 3 days + 1 hours);
        vm.startPrank(contributor2_);
        fundingPot.contributeToRoundFor(contributor2_, round2Id, r2ContributionC2, 1, new bytes32[](0));
        vm.stopPrank();
        assertEq(fundingPot.exposed_getTotalRoundContributions(round2Id), r2ContributionC2);

        // --- Create Round 3 (Total Mode) ---
        uint r3ExpectedEffectiveCap = r3BaseCap + (r1BaseCap - r1ContributionC1) + (r2BaseCap - r2ContributionC2); // 300 + 600 + 500 = 1400
        uint32 round3Id = fundingPot.createRound(
            initialTimestamp + 5 days,
            initialTimestamp + 6 days,
            r3BaseCap, // Base cap, will be expanded by accumulation
            address(0),
            bytes(""),
            false,
            ILM_PC_FundingPot_v1.AccumulationMode.Total
        );
        (address nftR3, bytes32 merkleR3, address[] memory allowedR3) = _helper_createAccessCriteria(1);
        fundingPot.setAccessCriteriaForRound(round3Id, 1, nftR3, merkleR3, allowedR3);
        // Set personal cap for C3 high enough to contribute to the full effective cap
        fundingPot.setAccessCriteriaPrivileges(round3Id, 1, r3ExpectedEffectiveCap, false, 0, 0, 0);

        // --- Set/Verify Global Start Round ID ---
        // Default is 1, but explicitly set for clarity if needed, or rely on default.
        // fundingPot.setGlobalAccumulationStart(1);
        assertEq(fundingPot.getGlobalAccumulationStartRoundId(), 1, "Default global start round ID should be 1");

        // --- Attempt Contribution in Round 3 by C3 ---
        vm.warp(initialTimestamp + 5 days + 1 hours);

        vm.startPrank(contributor3_);
        fundingPot.contributeToRoundFor(contributor3_, round3Id, r3ExpectedEffectiveCap, 1, new bytes32[](0));
        vm.stopPrank();

        // --- Assertions ---
        assertEq(
            fundingPot.exposed_getTotalRoundContributions(round3Id),
            r3ExpectedEffectiveCap,
            "R3 total contributions should match effective cap with rollover from R1 and R2"
        );
        assertEq(
            fundingPot.exposed_getUserContributionToRound(round3Id, contributor3_),
            r3ExpectedEffectiveCap,
            "R3 C3 contribution incorrect"
        );

        // Try to contribute 1 more to ensure cap is met
        vm.startPrank(contributor1_); // Use any contributor
         _token.approve(address(fundingPot), 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1.Module__LM_PC_FundingPot__RoundCapReached.selector
            )
        );
        fundingPot.contributeToRoundFor(contributor1_, round3Id, 1, 1, new bytes32[](0));
        vm.stopPrank();
    }

    function testAccumulation_GlobalStartRoundAllows_AllMode_PersonalCap()
        public
    {
        // SCENARIO: globalAccumulationStartRoundId = 1 allows personal cap 
        // accumulation from R1 to R2, when both are in All mode. (Simplified for stack)

        uint initialTimestamp = block.timestamp;
        uint8 accessId = 1; 

        // --- Round 1: Setup & C1 Contribution ---
        uint r1PersonalCapC1 = 500;
        uint r1ContributionC1 = 100; 
        uint32 round1Id = fundingPot.createRound(
            initialTimestamp + 1 days, initialTimestamp + 2 days, 1000, // R1 total cap large
            address(0), bytes(""), false, ILM_PC_FundingPot_v1.AccumulationMode.All 
        );
        fundingPot.setAccessCriteriaForRound(round1Id, accessId, address(0), bytes32(0), new address[](0));
        fundingPot.setAccessCriteriaPrivileges(round1Id, accessId, r1PersonalCapC1, false, 0, 0, 0);

        vm.warp(initialTimestamp + 1 days + 1 hours); 
        vm.startPrank(contributor1_);
        _token.approve(address(fundingPot), type(uint).max); // Approve inside prank, closer to use
        fundingPot.contributeToRoundFor(contributor1_, round1Id, r1ContributionC1, accessId, new bytes32[](0));
        vm.stopPrank();
        uint r1UnusedPersonalForC1 = r1PersonalCapC1 - r1ContributionC1; // 400

        // --- Round 2: Setup ---
        uint r2BasePersonalCapC1 = 200; 
        uint32 round2Id = fundingPot.createRound(
            initialTimestamp + 3 days, initialTimestamp + 4 days, 2000, // R2 total cap large
            address(0), bytes(""), false, ILM_PC_FundingPot_v1.AccumulationMode.All 
        );
        fundingPot.setAccessCriteriaForRound(round2Id, accessId, address(0), bytes32(0), new address[](0));
        fundingPot.setAccessCriteriaPrivileges(round2Id, accessId, r2BasePersonalCapC1, false, 0, 0, 0);

        // --- Global Start ID Check ---
        assertEq(fundingPot.getGlobalAccumulationStartRoundId(), 1, "Default global start ID is 1");

        // --- C1 Contribution to Round 2 (Testing Personal Cap Rollover) ---
        vm.warp(initialTimestamp + 3 days + 1 hours); 
        uint expectedEffectivePersonalCapC1R2 = r2BasePersonalCapC1 + r1UnusedPersonalForC1; // 200 + 400 = 600
        uint c1AttemptR2 = expectedEffectivePersonalCapC1R2 + 50; // Attempt 650
        
        ILM_PC_FundingPot_v1.UnspentPersonalRoundCap[] memory unspentCapsC1 = new ILM_PC_FundingPot_v1.UnspentPersonalRoundCap[](1);
        unspentCapsC1[0] = ILM_PC_FundingPot_v1.UnspentPersonalRoundCap(round1Id, accessId, new bytes32[](0));

        vm.startPrank(contributor1_); 
        // Note: Approval already done for C1
        fundingPot.contributeToRoundFor(contributor1_, round2Id, c1AttemptR2, accessId, new bytes32[](0), unspentCapsC1);
        vm.stopPrank();

        // --- Assertions ---
        assertEq(
            fundingPot.exposed_getUserContributionToRound(round2Id, contributor1_),
            expectedEffectivePersonalCapC1R2, // Should be clamped to 600
            "R2 C1 personal contribution incorrect"
        );
        assertEq(
            fundingPot.exposed_getTotalRoundContributions(round2Id),
            expectedEffectivePersonalCapC1R2,
            "R2 Total contributions incorrect"
        );
    }

    function testAccumulation_GlobalStartRoundAllows_AllMode_TotalCap() public {
        // SCENARIO: globalAccumulationStartRoundId = 1 (default or set) allows total cap 
        // accumulation from R1 to R2, when both are in All mode.

        uint initialTimestamp = block.timestamp;
        uint8 accessId = 1; // Open access

        // --- Round 1 Parameters (All Mode) ---
        uint r1BaseTotalCap = 1000;
        uint r1C1PersonalCap = 800; // C1 personal cap for R1
        uint r1C1Contribution = 600; // C1 contributes, leaving 400 unused total from R1

        // --- Round 2 Parameters (All Mode) ---
        uint r2BaseTotalCap = 500;
        // Personal cap for C1 in R2 will be set to the expected effective total cap of R2

        // --- Approvals ---
        vm.startPrank(contributor1_);
        _token.approve(address(fundingPot), type(uint).max);
        vm.stopPrank();
        // If using a second contributor for R2, approve for them too.
        // vm.startPrank(contributor2_);
        // _token.approve(address(fundingPot), type(uint).max);
        // vm.stopPrank();

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
        fundingPot.setAccessCriteriaForRound(
            round1Id, accessId, address(0), bytes32(0), new address[](0)
        );
        fundingPot.setAccessCriteriaPrivileges(
            round1Id, accessId, r1C1PersonalCap, false, 0, 0, 0
        );

        // --- Contribution by C1 to Round 1 ---
        vm.warp(initialTimestamp + 1 days + 1 hours); 
        vm.startPrank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_, round1Id, r1C1Contribution, accessId, new bytes32[](0)
        );
        vm.stopPrank();
        uint r1UnusedTotal = r1BaseTotalCap - r1C1Contribution; // Should be 400

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
        fundingPot.setAccessCriteriaForRound(
            round2Id, accessId, address(0), bytes32(0), new address[](0)
        );
        // Set personal cap for C1 in R2 to be the expected effective total cap of R2
        // R2_effective_total_cap = R2_base_total_cap (500) + R1_unused_total (400) = 900
        uint r2ExpectedEffectiveTotalCap = r2BaseTotalCap + r1UnusedTotal;
        fundingPot.setAccessCriteriaPrivileges(
            round2Id, accessId, r2ExpectedEffectiveTotalCap, false, 0, 0, 0 
        );

        // --- Ensure Global Start Round ID is 1 ---
        assertEq(fundingPot.getGlobalAccumulationStartRoundId(), 1, "Global start round ID should be 1 by default");

        // --- Attempt Contribution in Round 2 by C1 to fill effective total cap ---
        vm.warp(initialTimestamp + 3 days + 1 hours); 

        uint c1AttemptR2 = r2ExpectedEffectiveTotalCap; // C1 attempts to contribute the full effective total

        vm.startPrank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_,
            round2Id,
            c1AttemptR2,
            accessId,
            new bytes32[](0) // No personal unspent caps needed from C1 for *this* specific test logic focus
        );
        vm.stopPrank();

        // --- Assertions ---
        // 1. C1's contribution should be the amount they attempted (which is the effective total cap)
        assertEq(
            fundingPot.exposed_getUserContributionToRound(round2Id, contributor1_),
            c1AttemptR2,
            "R2 C1 contribution should match attempt (filling effective total cap)"
        );

        // 2. Total contributions to R2 should match the expected effective total cap.
        assertEq(
            fundingPot.exposed_getTotalRoundContributions(round2Id),
            r2ExpectedEffectiveTotalCap, 
            "R2 Total contributions should match effective total cap (All mode, global_start=1)"
        );
    }

    function testAccumulation_GlobalStartRoundRestricts_AllMode_PersonalCap()
        public
    {
        // SCENARIO: globalAccumulationStartRoundId = 2 restricts personal cap accumulation 
        // from R1 for R2, when both are in All mode.

        uint initialTimestamp = block.timestamp;
        uint8 accessId = 1; // Open access

        // --- Round 1 Parameters (All Mode) ---
        uint r1PersonalCapC1 = 500;
        uint r1ContributionC1 = 100; // Leaves 400 unused personal from R1 for C1
        uint r1BaseTotalCap = 1000;   // R1 total cap (large enough)

        // --- Round 2 Parameters (All Mode) ---
        uint r2BasePersonalCapC1 = 50;  // Small base personal cap for C1 in R2
        uint r2BaseTotalCap = 1000;    // R2 total cap (large enough)

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
        fundingPot.setAccessCriteriaForRound(
            round1Id, accessId, address(0), bytes32(0), new address[](0)
        );
        fundingPot.setAccessCriteriaPrivileges(
            round1Id, accessId, r1PersonalCapC1, false, 0, 0, 0
        );

        // --- Contribution by C1 to Round 1 ---
        vm.warp(initialTimestamp + 1 days + 1 hours); 
        vm.startPrank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_, round1Id, r1ContributionC1, accessId, new bytes32[](0)
        );
        vm.stopPrank();
        // uint r1UnusedPersonalForC1 = r1PersonalCapC1 - r1ContributionC1; // 400

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
        fundingPot.setAccessCriteriaForRound(
            round2Id, accessId, address(0), bytes32(0), new address[](0)
        );
        fundingPot.setAccessCriteriaPrivileges(
            round2Id, accessId, r2BasePersonalCapC1, false, 0, 0, 0 
        );

        // --- Set Global Start Round ID to Round 2's ID ---
        fundingPot.setGlobalAccumulationStart(round2Id); 
        assertEq(fundingPot.getGlobalAccumulationStartRoundId(), round2Id, "Global start ID not set to R2 ID");

        // --- Attempt Contribution in Round 2 by C1 ---
        vm.warp(initialTimestamp + 3 days + 1 hours); 

        // C1 attempts to contribute more than R2's base personal cap.
        // Should be clamped to R2's base personal cap as R1 is ignored.
        uint c1AttemptR2 = r2BasePersonalCapC1 + 100; // e.g., 50 + 100 = 150
        
        ILM_PC_FundingPot_v1.UnspentPersonalRoundCap[] memory unspentCapsC1 =
            new ILM_PC_FundingPot_v1.UnspentPersonalRoundCap[](1);
        unspentCapsC1[0] = ILM_PC_FundingPot_v1.UnspentPersonalRoundCap(
            round1Id, accessId, new bytes32[](0) // Provide R1 unspent, should be ignored
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
        // 1. C1's contribution should be clamped by R2's base personal cap (r2BasePersonalCapC1)
        assertEq(
            fundingPot.exposed_getUserContributionToRound(round2Id, contributor1_),
            r2BasePersonalCapC1,
            "R2 C1 personal contribution should be clamped by R2 base personal cap (All mode, global_start=R2)"
        );

        // 2. Total contributions to R2 should reflect this clamped amount.
        assertEq(
            fundingPot.exposed_getTotalRoundContributions(round2Id),
            r2BasePersonalCapC1, 
            "R2 Total contributions should be C1's clamped amount (All mode, global_start=R2)"
        );
    }

    function testAccumulation_GlobalStartRoundRestricts_AllMode_TotalCap()
        public
    {
        // SCENARIO: globalAccumulationStartRoundId = 2 restricts total cap accumulation 
        // from R1 for R2, when both are in All mode.

        uint initialTimestamp = block.timestamp;
        uint8 accessId = 1; // Open access

        // --- Round 1 Parameters (All Mode) ---
        uint r1BaseTotalCap = 1000;
        uint r1C1PersonalCap = 800; 
        uint r1C1Contribution = 400; // Leaves 600 unused total from R1

        // --- Round 2 Parameters (All Mode) ---
        uint r2BaseTotalCap = 200;  // Small base total cap for R2
        // Personal cap for C1 in R2 will be set to R2's base total cap for this test

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
        fundingPot.setAccessCriteriaForRound(
            round1Id, accessId, address(0), bytes32(0), new address[](0)
        );
        fundingPot.setAccessCriteriaPrivileges(
            round1Id, accessId, r1C1PersonalCap, false, 0, 0, 0
        );

        // --- Contribution by C1 to Round 1 ---
        vm.warp(initialTimestamp + 1 days + 1 hours); 
        vm.startPrank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_, round1Id, r1C1Contribution, accessId, new bytes32[](0)
        );
        vm.stopPrank();
        // uint r1UnusedTotal = r1BaseTotalCap - r1C1Contribution; // 600

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
        fundingPot.setAccessCriteriaForRound(
            round2Id, accessId, address(0), bytes32(0), new address[](0)
        );
        // Set C1's personal cap in R2 to R2's base total cap to isolate total cap behavior
        fundingPot.setAccessCriteriaPrivileges(
            round2Id, accessId, r2BaseTotalCap, false, 0, 0, 0 
        );

        // --- Set Global Start Round ID to Round 2's ID ---
        fundingPot.setGlobalAccumulationStart(round2Id); 
        assertEq(fundingPot.getGlobalAccumulationStartRoundId(), round2Id, "Global start ID not set to R2 ID");

        // --- Attempt Contribution in Round 2 by C1 ---
        vm.warp(initialTimestamp + 3 days + 1 hours); 

        // C1 attempts to contribute more than R2's base total cap.
        // Should be clamped to R2's base total cap as R1's unused total is ignored.
        uint c1AttemptR2 = r2BaseTotalCap + 100; // e.g., 200 + 100 = 300
        
        // No UnspentPersonalRoundCap needed here as we are testing total cap restriction primarily,
        // and C1's personal cap in R2 is already set to r2BaseTotalCap.

        vm.startPrank(contributor1_);
        fundingPot.contributeToRoundFor(
            contributor1_,
            round2Id,
            c1AttemptR2,
            accessId,
            new bytes32[](0) 
        );
        vm.stopPrank();

        // --- Assertions ---
        // 1. C1's contribution should be clamped by R2's base total cap (which also matches C1's personal cap for this test).
        assertEq(
            fundingPot.exposed_getUserContributionToRound(round2Id, contributor1_),
            r2BaseTotalCap,
            "R2 C1 contribution should be clamped by R2 base total cap (All mode, global_start=R2)"
        );

        // 2. Total contributions to R2 should be R2's base total cap.
        assertEq(
            fundingPot.exposed_getTotalRoundContributions(round2Id),
            r2BaseTotalCap, 
            "R2 Total contributions should be R2 base total cap (All mode, global_start=R2)"
        );
    }
}
