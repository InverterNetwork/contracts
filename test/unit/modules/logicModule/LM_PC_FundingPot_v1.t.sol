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
        bool globalAccumulativeCaps;
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
            globalAccumulativeCaps: false
        });

        // Initialize edited round parameters
        _editedRoundParams = _helper_createEditRoundParams(
            block.timestamp + 3 days,
            block.timestamp + 4 days,
            2000,
            address(0x1),
            bytes("test"),
            true,
            true
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
            params.globalAccumulativeCaps
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
            params.globalAccumulativeCaps
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
            params.globalAccumulativeCaps
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
            params.globalAccumulativeCaps
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
            params.globalAccumulativeCaps
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
            params.globalAccumulativeCaps
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
            params.globalAccumulativeCaps
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
            bool storedGlobalAccumulativeCaps
        ) = fundingPot.getRoundGenericParameters(roundId);

        // Compare with expected values
        assertEq(storedRoundStart, params.roundStart);
        assertEq(storedRoundEnd, params.roundEnd);
        assertEq(storedRoundCap, params.roundCap);
        assertEq(storedHookContract, params.hookContract);
        assertEq(storedHookFunction, params.hookFunction);
        assertEq(storedAutoClosure, params.autoClosure);
        assertEq(storedGlobalAccumulativeCaps, params.globalAccumulativeCaps);
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
                    └── globalAccumulativeCaps should be updated to the new value
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
            globalAccumulativeCaps: true
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
            params.globalAccumulativeCaps
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
            globalAccumulativeCaps: true
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
            params.globalAccumulativeCaps
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
            params.globalAccumulativeCaps
        ) = fundingPot.getRoundGenericParameters(roundId);
        vm.warp(params.roundStart + 1);

        RoundParams memory params_ = RoundParams({
            roundStart: block.timestamp + 3 days,
            roundEnd: block.timestamp + 4 days,
            roundCap: 2000,
            hookContract: address(0x1),
            hookFunction: bytes("test"),
            autoClosure: true,
            globalAccumulativeCaps: true
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
            params_.globalAccumulativeCaps
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
            _editedRoundParams.globalAccumulativeCaps
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
            globalAccumulativeCaps: true
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
            params.globalAccumulativeCaps
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
            true
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
            params.globalAccumulativeCaps
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
            true
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
            params.globalAccumulativeCaps
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
            true
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
            params.globalAccumulativeCaps
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
            └── globalAccumulativeCaps should be updated to the new value
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
            params.globalAccumulativeCaps
        );

        // Retrieve the stored parameters
        (
            uint storedRoundStart,
            uint storedRoundEnd,
            uint storedRoundCap,
            address storedHookContract,
            bytes memory storedHookFunction,
            bool storedAutoClosure,
            bool storedGlobalAccumulativeCaps
        ) = fundingPot.getRoundGenericParameters(uint32(lastRoundId));

        // Compare with expected values
        assertEq(storedRoundStart, params.roundStart);
        assertEq(storedRoundEnd, params.roundEnd);
        assertEq(storedRoundCap, params.roundCap);
        assertEq(storedHookContract, params.hookContract);
        assertEq(storedHookFunction, params.hookFunction);
        assertEq(storedAutoClosure, params.autoClosure);
        assertEq(storedGlobalAccumulativeCaps, params.globalAccumulativeCaps);
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
            _defaultRoundParams.globalAccumulativeCaps
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
            _defaultRoundParams.globalAccumulativeCaps
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
            params.globalAccumulativeCaps
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

        uint userContribution = fundingPot.exposed_getUserContributionToRound(
            roundId, contributor1_
        );
        assertEq(userContribution, 250);

        uint totalContributions =
            fundingPot.exposed_getTotalRoundContributions(roundId);
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

        uint userContribution = fundingPot.exposed_getUserContributionToRound(
            roundId, contributor2_
        );
        assertEq(userContribution, contributionAmount);

        uint totalContributions =
            fundingPot.exposed_getTotalRoundContributions(roundId);
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
            _defaultRoundParams.globalAccumulativeCaps
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

        uint contribution = fundingPot.exposed_getUserContributionToRound(
            roundId, contributor2_
        );
        assertEq(contribution, 50);

        uint totalContribution =
            fundingPot.exposed_getTotalRoundContributions(roundId);
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

        uint totalContribution = fundingPot.exposed_getUserContributionToRound(
            roundId, contributor1_
        );

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
        uint totalContribution =
            fundingPot.exposed_getTotalRoundContributions(roundId);
        assertEq(totalContribution, amount);
    }

    function testContributeToRoundFor_worksGivenPersonalCapAccumulation()
        public
    {
        _defaultRoundParams.globalAccumulativeCaps = true;
        fundingPot.createRound(
            _defaultRoundParams.roundStart,
            _defaultRoundParams.roundEnd,
            _defaultRoundParams.roundCap,
            _defaultRoundParams.hookContract,
            _defaultRoundParams.hookFunction,
            _defaultRoundParams.autoClosure,
            _defaultRoundParams.globalAccumulativeCaps
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
            _defaultRoundParams.globalAccumulativeCaps
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

    function testContributeToRoundFor_worksGivenTotalRoundCapAccumulation()
        public
    {
        _defaultRoundParams.globalAccumulativeCaps = true;

        // Create Round 1
        fundingPot.createRound(
            _defaultRoundParams.roundStart,
            _defaultRoundParams.roundEnd,
            _defaultRoundParams.roundCap,
            _defaultRoundParams.hookContract,
            _defaultRoundParams.hookFunction,
            _defaultRoundParams.autoClosure,
            _defaultRoundParams.globalAccumulativeCaps
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
            _defaultRoundParams.globalAccumulativeCaps
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
            _defaultRoundParams.globalAccumulativeCaps
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
            _defaultRoundParams.globalAccumulativeCaps
        );

        // round 2 (with accumulation)
        fundingPot.createRound(
            _defaultRoundParams.roundStart + 300,
            _defaultRoundParams.roundEnd + 400,
            _defaultRoundParams.roundCap,
            _defaultRoundParams.hookContract,
            _defaultRoundParams.hookFunction,
            _defaultRoundParams.autoClosure,
            true // globalAccumulativeCaps on
        );

        // round 3
        fundingPot.createRound(
            _defaultRoundParams.roundStart + 500,
            _defaultRoundParams.roundEnd + 600,
            _defaultRoundParams.roundCap,
            _defaultRoundParams.hookContract,
            _defaultRoundParams.hookFunction,
            _defaultRoundParams.autoClosure,
            true
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
            params.globalAccumulativeCaps
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
            params.globalAccumulativeCaps
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
            params.globalAccumulativeCaps
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
            params.globalAccumulativeCaps
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
            params.globalAccumulativeCaps
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
        bool globalAccumulativeCaps_
    ) internal pure returns (RoundParams memory) {
        return RoundParams({
            roundStart: roundStart_,
            roundEnd: roundEnd_,
            roundCap: roundCap_,
            hookContract: hookContract_,
            hookFunction: hookFunction_,
            autoClosure: autoClosure_,
            globalAccumulativeCaps: globalAccumulativeCaps_
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
            _defaultRoundParams.globalAccumulativeCaps
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
}
