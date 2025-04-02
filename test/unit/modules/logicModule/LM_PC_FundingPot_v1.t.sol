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
    struct RoundParameters {
        uint roundStart;
        uint roundEnd;
        uint roundCap;
        address hookContract;
        bytes hookFunction;
        bool closureMechanism;
        bool globalAccumulativeCaps;
    }
    // SuT

    LM_PC_FundingPot_v1_Exposed fundingPot;

    // Storage variables to avoid stack too deep
    uint64 private _testRoundId;

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

        fundingPotToken.mint(contributor1_, 10_000);
        fundingPotToken.mint(contributor2_, 10_000);
        fundingPotToken.mint(contributor3_, 10_000);

        // Setup the module to test
        _setUpOrchestrator(fundingPot);

        // Initiate the Logic Module with the metadata and config data
        fundingPot.init(
            _orchestrator, _METADATA, abi.encode(address(fundingPotToken))
        );

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
        RoundParams memory params = _helper_createDefaultFundingRound();
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
        RoundParams memory params = _helper_createDefaultFundingRound();
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
        RoundParams memory params = _helper_createDefaultFundingRound();
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
        RoundParams memory params = _helper_createDefaultFundingRound();
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
        RoundParams memory params = _helper_createDefaultFundingRound();
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
        RoundParams memory params = _helper_createDefaultFundingRound();
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

        _testRoundId = fundingPot.getRoundCount();

        // Retrieve the stored parameters
        (
            uint storedRoundStart,
            uint storedRoundEnd,
            uint storedRoundCap,
            address storedHookContract,
            bytes memory storedHookFunction,
            bool storedAutoClosure,
            bool storedGlobalAccumulativeCaps
        ) = fundingPot.getRoundGenericParameters(_testRoundId);

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
    */

    function testEditRound_revertsGivenUserIsNotFundingPotAdmin(address user_)
        public
    {
        testCreateRound(1000);
        uint64 roundId = fundingPot.getRoundCount();

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
        testCreateRound(1000);
        uint64 roundId = fundingPot.getRoundCount() + 1;

        uint64 roundId = fundingPot.getRoundCount();

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
            roundId + 1,
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
        testCreateRound(1000);
        uint64 roundId = fundingPot.getRoundCount();

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

    function testEditRound_revertsGivenRoundStartIsInThePast(uint roundStartP_)
        public
    {
        testCreateRound(1000);
        uint64 roundId = fundingPot.getRoundCount();

        RoundParameters memory editedParams = _helper_createEditedRoundParams();
        vm.assume(roundStartP_ < block.timestamp);
        RoundParams memory params = RoundParams({
            roundStart: roundStartP_,
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
                    .Module__LM_PC_FundingPot__RoundStartMustBeInFuture
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

    function testEditRound_revertsGivenRoundEndTimeAndCapAreBothZero() public {
        testCreateRound(1000);
        uint64 roundId = fundingPot.getRoundCount();

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
        testCreateRound(1000);
        uint64 roundId = fundingPot.getRoundCount();

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
        testCreateRound(1000);
        uint64 roundId = fundingPot.getRoundCount();

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
        testCreateRound(1000);
        uint64 roundId = fundingPot.getRoundCount();

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
        testCreateRound(1000);
        uint64 lastRoundId = fundingPot.getRoundCount();

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
        ) = fundingPot.getRoundGenericParameters(lastRoundId);

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

        testCreateRound(1000);
        uint64 roundId = fundingPot.getRoundCount();

        ILM_PC_FundingPot_v1.AccessCriteria memory accessCriteria =
            _helper_createAccessCriteria(accessCriteriaEnum_);

        vm.startPrank(user_);
        bytes32 roleId = _authorizer.generateRoleId(
            address(fundingPot), fundingPot.FUNDING_POT_ADMIN_ROLE()
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector, roleId, user_
            )
        );
        fundingPot.setAccessCriteriaForRound(roundId, accessCriteria);
        vm.stopPrank();
    }

    function testFuzzSetAccessCriteria_revertsGivenRoundDoesNotExist(
        uint8 accessCriteriaEnum
    ) public {
        vm.assume(accessCriteriaEnum >= 0 && accessCriteriaEnum <= 4);

        uint64 roundId = fundingPot.getRoundCount();

        ILM_PC_FundingPot_v1.AccessCriteria memory accessCriteria =
            _helper_createAccessCriteria(accessCriteriaEnum);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundNotCreated
                    .selector
            )
        );
        fundingPot.setAccessCriteriaForRound(roundId, accessCriteria);
    }

    function testFuzzSetAccessCriteria_revertsGivenRoundIsActive(
        uint8 accessCriteriaEnum
    ) public {
        vm.assume(accessCriteriaEnum >= 0 && accessCriteriaEnum <= 4);

        testCreateRound();
        uint64 roundId = fundingPot.getRoundCount();

        ILM_PC_FundingPot_v1.AccessCriteria memory accessCriteria =
            _helper_createAccessCriteria(accessCriteriaEnum);

        (uint roundStart,,,,,,) = fundingPot.getRoundGenericParameters(roundId);
        vm.warp(roundStart + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundAlreadyStarted
                    .selector
            )
        );
        fundingPot.setAccessCriteriaForRound(roundId, accessCriteria);
    }

    function testSetAccessCriteria_revertsGivenAccessCriteriaIdIsNFTAndNftContractIsZero(
    ) public {
        uint8 accessCriteriaEnum =
            uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.NFT);

        testCreateRound();
        uint64 roundId = fundingPot.getRoundCount();

        ILM_PC_FundingPot_v1.AccessCriteria memory accessCriteria =
            _helper_createAccessCriteria(accessCriteriaEnum);
        accessCriteria.nftContract = address(0);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__MissingRequiredAccessCriteriaData
                    .selector
            )
        );
        fundingPot.setAccessCriteriaForRound(roundId, accessCriteria);
    }

    function testSetAccessCriteria_revertsGivenAccessCriteriaIdIsMerkleAndMerkleRootIsZero(
    ) public {
        uint8 accessCriteriaEnum =
            uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.MERKLE);

        testCreateRound();
        uint64 roundId = fundingPot.getRoundCount();

        ILM_PC_FundingPot_v1.AccessCriteria memory accessCriteria =
            _helper_createAccessCriteria(accessCriteriaEnum);
        accessCriteria.merkleRoot = bytes32(uint(0x0));

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__MissingRequiredAccessCriteriaData
                    .selector
            )
        );
        fundingPot.setAccessCriteriaForRound(roundId, accessCriteria);
    }

    function testSetAccessCriteria_revertsGivenAccessCriteriaIdIsListAndAllowedAddressesIsEmpty(
    ) public {
        uint8 accessCriteriaEnum =
            uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.LIST);

        testCreateRound();
        uint64 roundId = fundingPot.getRoundCount();

        ILM_PC_FundingPot_v1.AccessCriteria memory accessCriteria =
            _helper_createAccessCriteria(accessCriteriaEnum);
        accessCriteria.allowedAddresses = new address[](0);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__MissingRequiredAccessCriteriaData
                    .selector
            )
        );
        fundingPot.setAccessCriteriaForRound(roundId, accessCriteria);
    }

    function testFuzzSetAccessCriteria(uint8 accessCriteriaEnum) public {
        vm.assume(accessCriteriaEnum >= 0 && accessCriteriaEnum <= 4);

        testCreateRound();
        uint64 roundId = fundingPot.getRoundCount();
        uint8 accessCriteriaId = 0;

        ILM_PC_FundingPot_v1.AccessCriteria memory accessCriteria =
            _helper_createAccessCriteria(accessCriteriaEnum);

        fundingPot.setAccessCriteriaForRound(roundId, accessCriteria);

        (
            bool isOpen,
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = fundingPot.getRoundAccessCriteria(roundId, accessCriteriaId);

        assertEq(isOpen, accessCriteriaEnum == 1);
        assertEq(nftContract, accessCriteria.nftContract);
        assertEq(merkleRoot, accessCriteria.merkleRoot);
        assertEq(allowedAddresses, accessCriteria.allowedAddresses);
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
    function testFuzzContributeToRound_revertsGivenRoundContributionCapReached(
        uint roundCap_
    ) public {
        testCreateRound(10);

    function testFuzzEditAccessCriteriaForRound_revertsGivenUserDoesNotHaveFundingPotAdminRole(
        uint8 accessCriteriaEnum,
        address user_
    ) public {
        vm.assume(accessCriteriaEnum >= 0 && accessCriteriaEnum <= 4);
        vm.assume(user_ != address(0) && user_ != address(this));

        _helper_setupRoundWithAccessCriteria(accessCriteriaEnum);
        uint64 roundId = fundingPot.getRoundCount();
        uint8 accessCriteriaId = 0;

        ILM_PC_FundingPot_v1.AccessCriteria memory accessCriteria =
            _helper_createAccessCriteria(accessCriteriaEnum);

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
            roundId, accessCriteriaId, accessCriteria
        );
        vm.stopPrank();
    }

    function testFuzzEditAccessCriteriaForRound_revertsGivenAccessCriteriaIdIsGreaterThanAccessCriteriaForTheRound(
        uint8 accessCriteriaEnum
    ) public {
        vm.assume(accessCriteriaEnum >= 0 && accessCriteriaEnum <= 4);

        _helper_setupRoundWithAccessCriteria(accessCriteriaEnum);
        uint64 roundId = fundingPot.getRoundCount();
        uint8 accessCriteriaId = 10; // Invalid ID

        ILM_PC_FundingPot_v1.AccessCriteria memory accessCriteria =
            _helper_createAccessCriteria(accessCriteriaEnum);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__InvalidAccessCriteriaId
                    .selector
            )
        );
        fundingPot.editAccessCriteriaForRound(
            roundId, accessCriteriaId, accessCriteria
        );
    }

    function testFuzzEditAccessCriteriaForRound_revertsGivenRoundDoesNotExist(
        uint8 accessCriteriaEnum
    ) public {
        vm.assume(accessCriteriaEnum >= 0 && accessCriteriaEnum <= 4);
        uint64 roundId = fundingPot.getRoundCount();
        uint8 accessCriteriaId = 0;

        ILM_PC_FundingPot_v1.AccessCriteria memory accessCriteria =
            _helper_createAccessCriteria(accessCriteriaEnum);

        vm.expectRevert();
        fundingPot.editAccessCriteriaForRound(
            roundId, accessCriteriaId, accessCriteria
        );
    }

    function testFuzzEditAccessCriteriaForRound_revertsGivenRoundIsActive(
        uint8 accessCriteriaEnum
    ) public {
        vm.assume(accessCriteriaEnum >= 0 && accessCriteriaEnum <= 4);

        _helper_setupRoundWithAccessCriteria(accessCriteriaEnum);
        uint64 roundId = fundingPot.getRoundCount();
        uint8 accessCriteriaId = 0;

        // Warp to make the round active
        (uint roundStart,,,,,,) = fundingPot.getRoundGenericParameters(roundId);
        vm.warp(roundStart + 1);

        // Approve
        vm.prank(contributor1_);
        fundingPotToken.approve(address(fundingPot), 110);

        vm.prank(contributor1_);
        fundingPot.contributeToRound(roundId, 10, accessId, new bytes32[](0));

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__PersonalCapReached
                    .selector
            )
        );

        vm.prank(contributor1_);
        fundingPot.contributeToRound(
            roundId, amount, accessId, new bytes32[](0)
        );
    }

    function testFuzzContributeToRound_revertsGivenContributionIsBeforeRoundStart(
    ) public {
        testCreateRound(1000);

        uint64 roundId = fundingPot.getRoundCount();
        uint8 accessId = 1;
        uint amount = 250;

        ILM_PC_FundingPot_v1.AccessCriteria memory accessCriteria =
            _helper_createAccessCriteria(0);

        fundingPot.setAccessCriteriaForRound(roundId, accessId, accessCriteria);

        (uint roundStart,,,,,,) = fundingPot.getRoundGenericParameters(roundId);

        // Approve
        vm.prank(contributor1_);
        fundingPotToken.approve(address(fundingPot), 500);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundHasNotStarted
                    .selector
            )
        );

        vm.prank(contributor1_);
        fundingPot.contributeToRound(
            roundId, amount, accessId, new bytes32[](0)
        );
    }

    function testFuzzContributeToRound_revertsGivenContributionIsAfterRoundEnd()
        public
    {
        testCreateRound(1000);

        uint64 roundId = fundingPot.getRoundCount();
        uint8 accessId = 1;
        uint amount = 250;

        ILM_PC_FundingPot_v1.AccessCriteria memory accessCriteria =
            _helper_createAccessCriteria(0);

        fundingPot.setAccessCriteriaForRound(roundId, accessId, accessCriteria);

        (uint roundStart,,,,,,) = fundingPot.getRoundGenericParameters(roundId);
        vm.warp(roundStart + 10 days);

        // Approve
        vm.prank(contributor1_);
        fundingPotToken.approve(address(fundingPot), 500);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundHasEnded
                    .selector
            )
        );

        vm.prank(contributor1_);
        fundingPot.contributeToRound(
            roundId, amount, accessId, new bytes32[](0)
        );
    }

    function testFuzzContributeToRound_revertsGivenNFTAccessCriteriaIsNotMet()
        public
    {
        testCreateRound(1000);

        uint64 roundId = fundingPot.getRoundCount();
        uint8 accessId = 1;
        uint amount = 250;

        ILM_PC_FundingPot_v1.AccessCriteria memory accessCriteria =
            _helper_createAccessCriteria(1);

        fundingPot.setAccessCriteriaForRound(roundId, accessId, accessCriteria);

        (uint roundStart,,,,,,) = fundingPot.getRoundGenericParameters(roundId);
        vm.warp(roundStart + 1);

        // Approve
        vm.prank(contributor1_);
        fundingPotToken.approve(address(fundingPot), amount);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__AccessCriteriaNftFailed
                    .selector
            )
        );

        vm.prank(contributor1_);
        fundingPot.contributeToRound(
            roundId, amount, accessId, new bytes32[](0)
        );
    }

    function testFuzzContributeToRound_revertsGivenMerkleRootAccessCriteriaIsNotMet(
    ) public {
        testCreateRound(1000);

        uint64 roundId = fundingPot.getRoundCount();
        uint8 accessId = 1;
        uint amount = 250;

        ILM_PC_FundingPot_v1.AccessCriteria memory accessCriteria =
            _helper_createAccessCriteria(2);

        fundingPot.setAccessCriteriaForRound(roundId, accessId, accessCriteria);

        (uint roundStart,,,,,,) = fundingPot.getRoundGenericParameters(roundId);
        vm.warp(roundStart + 1);

        // Approve
        vm.prank(contributor1_);
        fundingPotToken.approve(address(fundingPot), amount);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__AccessCriteriaMerkleFailed
                    .selector
            )
        );

        vm.prank(contributor1_);
        fundingPot.contributeToRound(roundId, amount, accessId, PROOF);
    }

    function testFuzzContributeToRound_revertsGivenAllowedListAccessCriteriaIsNotMet(
    ) public {
        testCreateRound(1000);

        uint64 roundId = fundingPot.getRoundCount();
        uint8 accessId = 1;
        uint amount = 250;

        ILM_PC_FundingPot_v1.AccessCriteria memory accessCriteria =
            _helper_createAccessCriteria(3);

        fundingPot.setAccessCriteriaForRound(roundId, accessId, accessCriteria);

        (uint roundStart,,,,,,) = fundingPot.getRoundGenericParameters(roundId);
        vm.warp(roundStart + 1);

        // Approve
        vm.prank(contributor1_);
        fundingPotToken.approve(address(fundingPot), amount);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__AccessCriteriaListFailed
                    .selector
            )
        );

        vm.prank(contributor1_);
        fundingPot.contributeToRound(
            roundId, amount, accessId, new bytes32[](0)
        );
    }

    function testFuzzContributeToRound_revertsGivenPreviousContributionExceedsPersonalCap(
    ) public {
        testCreateRound(1000);

        uint64 roundId = fundingPot.getRoundCount();
        uint8 accessId = 1;
        uint amount = 500;

        ILM_PC_FundingPot_v1.AccessCriteria memory accessCriteria =
            _helper_createAccessCriteria(1);

        fundingPot.setAccessCriteriaForRound(roundId, accessId, accessCriteria);

        mockNFTContract.mint(contributor1_);

        (uint roundStart,,,,,,) = fundingPot.getRoundGenericParameters(roundId);
        vm.warp(roundStart + 1);

        // Approve
        vm.prank(contributor1_);
        fundingPotToken.approve(address(fundingPot), 1000);

        vm.prank(contributor1_);
        fundingPot.contributeToRound(
            roundId, amount, accessId, new bytes32[](0)
        );

        // Get the base personal cap from the contract
        uint personalCap =
            fundingPot.exposed_getUserPersonalCap(roundId, contributor1_);

        // Attempt to contribute beyond personal cap
        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__PersonalCapReached
                    .selector
            )
        );
        vm.prank(contributor1_);

        uint remainingCap = personalCap - amount;
        fundingPot.contributeToRound(roundId, 251, accessId, new bytes32[](0));
    }

    /*
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
    function testFuzzContributeToRound_worksGivenAllConditionsMet() public {
        testCreateRound(1000);

        uint64 roundId = fundingPot.getRoundCount();
        uint8 accessId = 1;
        uint amount = 250;

        ILM_PC_FundingPot_v1.AccessCriteria memory accessCriteria =
            _helper_createAccessCriteria(1);

        fundingPot.setAccessCriteriaForRound(roundId, accessId, accessCriteria);

        mockNFTContract.mint(contributor1_);

        (uint roundStart,,,,,,) = fundingPot.getRoundGenericParameters(roundId);
        vm.warp(roundStart + 1);

        // Approve
        vm.prank(contributor1_);
        fundingPotToken.approve(address(fundingPot), 500);

        vm.prank(contributor1_);
        fundingPot.contributeToRound(
            roundId, amount, accessId, new bytes32[](0)
        );

        uint totalContributions =
            fundingPot.exposed_getTotalRoundContributions(roundId);

        assertEq(totalContributions, amount);

        uint personalContributions =
            fundingPot.exposed_getUserContribution(roundId, contributor1_);
        assertEq(personalContributions, amount);
    }

    function testFuzzContributeToRound_worksGivenUserCurrentContributionExceedsTheRoundCap(
        uint roundCap_
    ) public {
        vm.assume(accessCriteriaEnumOld >= 0 && accessCriteriaEnumOld <= 4);
        vm.assume(
            accessCriteriaEnumNew != accessCriteriaEnumOld
                && accessCriteriaEnumNew >= 0 && accessCriteriaEnumNew <= 4
        );

        _helper_setupRoundWithAccessCriteria(accessCriteriaEnumOld);
        uint64 roundId = fundingPot.getRoundCount();
        uint8 accessCriteriaId = 0;

        // Create and apply new access criteria
        ILM_PC_FundingPot_v1.AccessCriteria memory newAccessCriteria =
            _helper_createAccessCriteria(accessCriteriaEnumNew);

        fundingPot.setAccessCriteriaForRound(roundId, accessId, accessCriteria);

        (uint roundStart,, uint roundCap,,,,) =
            fundingPot.getRoundGenericParameters(roundId);
        vm.warp(roundStart + 1);

        // Approve
        vm.prank(contributor1_);
        fundingPotToken.approve(address(fundingPot), amount);

        vm.prank(contributor1_);
        fundingPot.contributeToRound(
            roundId, amount, accessId, new bytes32[](0)
        );

        // only the amount that does not exceed the roundcap is contributed
        assertEq(
            fundingPot.exposed_getUserContribution(roundId, contributor1_), 200
        );
    }

    function testFuzzContributeToRound_worksGivenContributionPartiallyExceedingPersonalCap(
    ) public {
        testCreateRound(1000);

        uint64 roundId = fundingPot.getRoundCount();
        uint8 accessId = 1;

        uint firstAmount = 400;

        ILM_PC_FundingPot_v1.AccessCriteria memory accessCriteria =
            _helper_createAccessCriteria(1);

        fundingPot.setAccessCriteriaForRound(roundId, accessId, accessCriteria);

        mockNFTContract.mint(contributor1_);

        (uint roundStart,,,,,,) = fundingPot.getRoundGenericParameters(roundId);
        vm.warp(roundStart + 1);

        // Approve
        vm.prank(contributor1_);
        fundingPotToken.approve(address(fundingPot), 1000 ether);

        // First contribution
        vm.prank(contributor1_);
        fundingPot.contributeToRound(
            roundId, firstAmount, accessId, new bytes32[](0)
        );

        // Get the personal cap
        uint personalCap =
            fundingPot.exposed_getUserPersonalCap(roundId, contributor1_);

        uint secondAmount = 200;

        vm.prank(contributor1_);
        fundingPot.contributeToRound(
            roundId, secondAmount, accessId, new bytes32[](0)
        );

        uint totalContribution =
            fundingPot.exposed_getUserContribution(roundId, contributor1_);
        assertEq(totalContribution, personalCap);
    }

    function testFuzzContributeToRound_worksGivenUserCanOverrideTimeConstraints(
    ) public {
        testCreateRound(1000);

        uint64 roundId = fundingPot.getRoundCount();
        uint8 accessId = 1;
        uint amount = 250;

        ILM_PC_FundingPot_v1.AccessCriteria memory accessCriteria =
            _helper_createAccessCriteria(1);

        fundingPot.setAccessCriteriaForRound(roundId, accessId, accessCriteria);

        // Set privileges with override capability
        fundingPot.setAccessCriteriaPrivileges(
            roundId,
            accessId,
            500, // personalCap
            true, // overrideCap (can override time constraints)
            0, // start
            0, // cliff
            0 // end
        );

        mockNFTContract.mint(contributor1_);

        (uint roundStart,,,,,,) = fundingPot.getRoundGenericParameters(roundId);

        vm.warp(roundStart + 10 days);

        // Approve
        vm.prank(contributor1_);
        fundingPotToken.approve(address(fundingPot), amount);

        // This should succeed despite being after round end, due to override privilege
        vm.prank(contributor1_);
        fundingPot.contributeToRound(
            roundId, amount, accessId, new bytes32[](0)
        );

        // Verify the contribution was recorded
        uint totalContribution =
            fundingPot.exposed_getTotalRoundContributions(roundId);
        assertEq(totalContribution, amount);
    }

    function testContributeToRound_worksGivenPersonalCapAccumulation() public {
        (
            uint roundStart,
            uint roundEnd,
            uint roundCap,
            address hookContract,
            bytes memory hookFunction,
            bool closureMechanism,
            bool globalAccumulativeCaps
        ) = _helper_createDefaultFundingRound(1000);
        globalAccumulativeCaps = true; // global accumulative caps enabled

        // Round 1
        fundingPot.createRound(
            roundStart,
            roundEnd,
            roundCap,
            hookContract,
            hookFunction,
            closureMechanism,
            globalAccumulativeCaps
        );
        uint64 round1Id = fundingPot.getRoundCount();

        uint8 accessId = 1;
        ILM_PC_FundingPot_v1.AccessCriteria memory accessCriteria =
            _helper_createAccessCriteria(1);
        fundingPot.setAccessCriteriaForRound(round1Id, accessId, accessCriteria);
        mockNFTContract.mint(contributor1_);

        // Create Round 2
        fundingPot.createRound(
            roundStart + 3 days,
            roundEnd + 3 days,
            roundCap,
            hookContract,
            hookFunction,
            closureMechanism,
            globalAccumulativeCaps
        );
        uint64 round2Id = fundingPot.getRoundCount();
        fundingPot.setAccessCriteriaForRound(round2Id, accessId, accessCriteria);

        vm.startPrank(contributor1_);
        fundingPotToken.approve(address(fundingPot), 1500);

        // Contribute to Round 1
        vm.warp(roundStart + 1);
        uint round1Contribution = 200;
        fundingPot.contributeToRound(
            round1Id, round1Contribution, accessId, new bytes32[](0)
        );

        // Move to Round 2
        vm.warp(roundStart + 3 days + 1);

        // Calculate unused capacity from Round 1
        uint basePersonalCap =
            fundingPot.exposed_getUserPersonalCap(round1Id, contributor1_);
        uint unusedCapacityFromRound1 = basePersonalCap - round1Contribution;

        uint round2MaxContribution = basePersonalCap + unusedCapacityFromRound1;
        fundingPot.contributeToRound(
            round2Id, round2MaxContribution, accessId, new bytes32[](0)
        );
        vm.stopPrank();

        assertEq(
            fundingPot.exposed_getUserContribution(round1Id, contributor1_),
            round1Contribution
        );
        assertEq(
            fundingPot.exposed_getUserContribution(round2Id, contributor1_),
            round2MaxContribution
        );
    }

    function testContributeToRound_worksGivenTotalRoundCapAccumulation()
        public
    {
        (
            uint roundStart,
            uint roundEnd,
            uint roundCap,
            address hookContract,
            bytes memory hookFunction,
            bool closureMechanism,
            bool globalAccumulativeCaps
        ) = _helper_createDefaultFundingRound(1000);
        globalAccumulativeCaps = true;

        // Create Round 1
        fundingPot.createRound(
            roundStart,
            roundEnd,
            roundCap,
            hookContract,
            hookFunction,
            closureMechanism,
            globalAccumulativeCaps
        );
        uint64 round1Id = fundingPot.getRoundCount();

        uint8 accessId = 0;
        ILM_PC_FundingPot_v1.AccessCriteria memory accessCriteria =
            _helper_createAccessCriteria(0);
        fundingPot.setAccessCriteriaForRound(round1Id, accessId, accessCriteria);

        // Round 2 with a different cap
        uint round2Cap = 500;
        fundingPot.createRound(
            roundStart + 3 days,
            roundEnd + 3 days,
            round2Cap,
            hookContract,
            hookFunction,
            closureMechanism,
            globalAccumulativeCaps
        );
        uint64 round2Id = fundingPot.getRoundCount();
        fundingPot.setAccessCriteriaForRound(round2Id, accessId, accessCriteria);
        // Round 1: Multiple users contribute, but don't reach the cap
        vm.warp(roundStart + 1);

        vm.startPrank(contributor1_);
        fundingPotToken.approve(address(fundingPot), 300);
        fundingPot.contributeToRound(round1Id, 300, accessId, new bytes32[](0));
        vm.stopPrank();

        vm.startPrank(contributor2_);
        fundingPotToken.approve(address(fundingPot), 200);
        fundingPot.contributeToRound(round1Id, 200, accessId, new bytes32[](0));
        vm.stopPrank();

        // Move to Round 2
        vm.warp(roundStart + 3 days + 1);

        uint unusedCapacityFromRound1 =
            roundCap - fundingPot.exposed_getTotalRoundContributions(round1Id);
        uint totalAvailableCapacityRound2 = round2Cap + unusedCapacityFromRound1;

        // Round 2: Contributors try to use the accumulated capacity

        vm.startPrank(contributor2_);
        fundingPotToken.approve(address(fundingPot), 400);
        fundingPot.contributeToRound(round2Id, 400, accessId, new bytes32[](0));
        vm.stopPrank();

        vm.startPrank(contributor3_);
        fundingPotToken.approve(address(fundingPot), 600);
        fundingPot.contributeToRound(round2Id, 600, accessId, new bytes32[](0));
        vm.stopPrank();

        // Verify Round 1 contributions
        assertEq(fundingPot.exposed_getTotalRoundContributions(round1Id), 500);
        assertEq(
            fundingPot.exposed_getUserContribution(round1Id, contributor1_), 300
        );
        assertEq(
            fundingPot.exposed_getUserContribution(round1Id, contributor2_), 200
        );

        // Verify Round 2 contributions
        assertEq(fundingPot.exposed_getTotalRoundContributions(round2Id), 1000);
        assertEq(
            fundingPot.exposed_getUserContribution(round2Id, contributor2_), 400
        );
        assertEq(
            fundingPot.exposed_getUserContribution(round2Id, contributor3_), 600
        );

        assertEq(
            fundingPot.exposed_getTotalRoundContributions(round2Id),
            totalAvailableCapacityRound2
        );
    }

    // -------------------------------------------------------------------------
    // Helper Functions

    // @notice Creates a default funding round
    function _helper_createDefaultFundingRound(uint roundCap_)
        internal
        returns (RoundParams memory)
    {
        return _defaultRoundParams;
    }

    // @notice Creates edit round parameters with customizable values
    function _helper_createEditRoundParams(
        uint roundStart_,
        uint roundEnd_,
        uint roundCap_,
        address hookContract_,
        bytes memory hookFunction_,
        bool autoClosure_,
        bool globalAccumulativeCaps_
    ) internal returns (RoundParams memory) {
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

    function _helper_createAccessCriteria(uint8 accessCriteriaEnum)
        internal
        returns (ILM_PC_FundingPot_v1.AccessCriteria memory)
    {
        {
            if (
                accessCriteriaEnum
                    == uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.OPEN)
            ) {
                return ILM_PC_FundingPot_v1.AccessCriteria(
                    ILM_PC_FundingPot_v1.AccessCriteriaType.OPEN,
                    address(0x0),
                    bytes32(uint(0x0)),
                    new address[](0)
                );
            } else if (
                accessCriteriaEnum
                    == uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.NFT)
            ) {
                address nftContract = address(mockNFTContract);

                return ILM_PC_FundingPot_v1.AccessCriteria(
                    ILM_PC_FundingPot_v1.AccessCriteriaType.NFT,
                    nftContract,
                    bytes32(uint(0x0)),
                    new address[](0)
                );
            } else if (
                accessCriteriaEnum
                    == uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.MERKLE)
            ) {
                bytes32 merkleRoot = ROOT;

                return ILM_PC_FundingPot_v1.AccessCriteria(
                    ILM_PC_FundingPot_v1.AccessCriteriaType.MERKLE,
                    address(0x0),
                    merkleRoot,
                    new address[](0)
                );
            } else if (
                accessCriteriaEnum
                    == uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.LIST)
            ) {
                address[] memory allowedAddresses = new address[](3);
                allowedAddresses[0] = address(0x1);
                allowedAddresses[1] = address(0x2);
                allowedAddresses[2] = address(0x3);

                return ILM_PC_FundingPot_v1.AccessCriteria(
                    ILM_PC_FundingPot_v1.AccessCriteriaType.LIST,
                    address(0x0),
                    bytes32(uint(0x0)),
                    allowedAddresses
                );
            }
        }
    }

    // Helper function to set up a round with access criteria
    function _helper_setupRoundWithAccessCriteria(uint8 accessCriteriaEnum)
        internal
    {
        testCreateRound();
        uint64 roundId = fundingPot.getRoundCount();

        ILM_PC_FundingPot_v1.AccessCriteria memory accessCriteria =
            _helper_createAccessCriteria(accessCriteriaEnum);

        fundingPot.setAccessCriteriaForRound(roundId, accessCriteria);
    }
}
