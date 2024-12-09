// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";
import {ClaimData} from
    "@lm/abstracts/oracleIntegrations/UMA_OptimisticOracleV3/optimistic-oracle-v3/ClaimData.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Internal Dependencies
import {
    ModuleTest,
    IModule_v1,
    IOrchestrator_v1
} from "test/modules/ModuleTest.sol";

import {IERC20PaymentClientBase_v1} from
    "src/modules/logicModule/interfaces/IERC20PaymentClientBase_v1.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

// SuT
import {
    LM_PC_KPIRewarder_v1,
    ILM_PC_KPIRewarder_v1,
    IOptimisticOracleIntegrator,
    ILM_PC_Staking_v1,
    OptimisticOracleV3CallbackRecipientInterface
} from "src/modules/logicModule/LM_PC_KPIRewarder_v1.sol";

import {
    OptimisticOracleV3Mock,
    OptimisticOracleV3Interface
} from "test/modules/logicModule/oracle/utils/OptimisiticOracleV3Mock.sol";

import {LM_PC_Staking_v1AccessMock} from
    "test/utils/mocks/modules/logicModules/LM_PC_Staking_v1AccessMock.sol";

// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

contract LM_PC_KPIRewarder_v1Test is ModuleTest {
    // SuT
    LM_PC_KPIRewarder_v1 kpiManager;

    OptimisticOracleV3Mock ooV3;

    uint64 immutable DEFAULT_LIVENESS = 25_000;

    // Mock data for assertions
    bytes32 constant MOCK_ASSERTION_DATA_ID = "0x1234";
    uint constant MOCK_ASSERTED_VALUE = 100;
    address constant MOCK_ASSERTER_ADDRESS = address(0x1);
    address USER_1 = address(0xA1BA);

    uint MAX_USER_AMOUNT = 10_000; // for testing purposes

    ERC20Mock stakingToken = new ERC20Mock("Staking Mock Token", "STAKE MOCK");
    // the reward token is _token from ModuleTest
    ERC20Mock feeToken = new ERC20Mock("OOV3 Fee Mock Token", "FEE MOCK");
    uint feeTokenBond;

    //=========================================================================================
    // Events for emission testing

    event Staked(address indexed user, uint amount);
    event DataAsserted(
        bytes32 indexed dataId,
        bytes32 data,
        address indexed asserter,
        bytes32 indexed assertionId
    );
    event DataAssertionResolved(
        bool assertedTruthfully,
        bytes32 indexed dataId,
        bytes32 data,
        address indexed asserter,
        bytes32 indexed assertionId
    );
    event RewardSet(
        uint amount, uint duration, uint rewardRate, uint rewardsEnd
    );

    event KPICreated(
        uint indexed KPI_Id,
        uint numOfTranches,
        uint totalKPIRewards,
        bool continuous,
        uint[] trancheValues,
        uint[] trancheRewards
    );

    event RewardRoundConfigured(
        bytes32 indexed assertionId,
        uint creationTime,
        uint assertedValue,
        uint indexed KpiToUse
    );

    event PaymentOrderAdded(
        address indexed recipient,
        address indexed token,
        uint amount,
        uint originChainId,
        uint targetChainId,
        bytes32 flags,
        bytes32[] data
    );

    event DeletedStuckAssertion(bytes32 indexed assertionId);

    //=========================================================================================
    // Setup

    function setUp() public {
        ooV3 = new OptimisticOracleV3Mock(feeToken, DEFAULT_LIVENESS);
        // we whitelist the default currency
        ooV3.whitelistCurrency(address(feeToken), 5e17);
        feeTokenBond = ooV3.getMinimumBond(address(feeToken));

        // Add Module to Mock Orchestrator
        address impl = address(new LM_PC_KPIRewarder_v1());
        kpiManager = LM_PC_KPIRewarder_v1(Clones.clone(impl));

        _setUpOrchestrator(kpiManager);

        _authorizer.setIsAuthorized(address(this), true);

        bytes memory configData = abi.encode(
            address(stakingToken),
            address(feeToken),
            feeTokenBond,
            ooV3,
            DEFAULT_LIVENESS
        );

        kpiManager.init(_orchestrator, _METADATA, configData);

        // Perform initial deposit of reward tokens:
        address depositor_1 = address(0x42);
        _token.mint(depositor_1, 10_000e18);
        vm.startPrank(depositor_1);
        _token.approve(address(_fundingManager), 10_000e18);
        _fundingManager.deposit(10_000e18);
        vm.stopPrank();
    }

    //--------------------------------------------------------------------------
    // Test: Initialization

    function testInit() public override(ModuleTest) {
        address impl = address(new LM_PC_KPIRewarder_v1());
        kpiManager = LM_PC_KPIRewarder_v1(Clones.clone(impl));

        _setUpOrchestrator(kpiManager);

        bytes memory configData = abi.encode(
            address(stakingToken), address(_token), ooV3, DEFAULT_LIVENESS
        );

        // Init Module wrongly
        vm.expectRevert(IModule_v1.Module__InvalidOrchestratorAddress.selector);
        kpiManager.init(IOrchestrator_v1(address(0)), _METADATA, configData);

        // Test invalid staking token
        vm.expectRevert(
            ILM_PC_Staking_v1
                .Module__LM_PC_Staking_v1__InvalidStakingToken
                .selector
        );
        kpiManager.init(
            _orchestrator,
            _METADATA,
            abi.encode(
                address(0),
                address(_token),
                feeTokenBond,
                address(ooV3),
                DEFAULT_LIVENESS
            )
        );

        // Test invalid reward token
        vm.expectRevert(
            IOptimisticOracleIntegrator
                .Module__OptimisticOracleIntegrator__InvalidDefaultCurrency
                .selector
        );
        kpiManager.init(
            _orchestrator,
            _METADATA,
            abi.encode(
                address(stakingToken),
                address(0),
                feeTokenBond,
                address(ooV3),
                DEFAULT_LIVENESS
            )
        );

        // Test invalid token bond
        vm.expectRevert(
            IOptimisticOracleIntegrator
                .Module__OptimisticOracleIntegrator__CurrencyBondTooLow
                .selector
        );
        kpiManager.init(
            _orchestrator,
            _METADATA,
            abi.encode(
                address(stakingToken),
                address(feeToken),
                0,
                address(ooV3),
                DEFAULT_LIVENESS
            )
        );

        // Test invalid OOAddress. See comment in OOIntegrator contract
        vm.expectRevert();
        kpiManager.init(
            _orchestrator,
            _METADATA,
            abi.encode(address(stakingToken), address(0))
        );
    }

    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        kpiManager.init(_orchestrator, _METADATA, bytes(""));
    }

    function test_InterfaceInheritanceTree() public view {
        kpiManager.supportsInterface(type(ILM_PC_KPIRewarder_v1).interfaceId);
        kpiManager.supportsInterface(type(ILM_PC_Staking_v1).interfaceId);
        kpiManager.supportsInterface(
            type(IOptimisticOracleIntegrator).interfaceId
        );
        kpiManager.supportsInterface(
            type(OptimisticOracleV3CallbackRecipientInterface).interfaceId
        );
        kpiManager.supportsInterface(type(IModule_v1).interfaceId);
    }

    // Creates  dummy incontinuous KPI with 3 tranches, a max value of 300 and 300e18 tokens for rewards
    function createDummyIncontinuousKPI() public {
        uint[] memory trancheValues = new uint[](3);
        uint[] memory trancheRewards = new uint[](3);

        trancheValues[0] = 100e18;
        trancheValues[1] = 200e18;
        trancheValues[2] = 300e18;

        trancheRewards[0] = 100e32;
        trancheRewards[1] = 100e32;
        trancheRewards[2] = 100e32;

        kpiManager.createKPI(false, trancheValues, trancheRewards);
    }

    // Creates  dummy continuous KPI with 3 tranches, a max value of 300 and 300e18 tokens for rewards
    function createDummyContinuousKPI() public {
        uint[] memory trancheValues = new uint[](3);
        uint[] memory trancheRewards = new uint[](3);

        trancheValues[0] = 100e18;
        trancheValues[1] = 200e18;
        trancheValues[2] = 300e18;

        trancheRewards[0] = 100e32;
        trancheRewards[1] = 100e32;
        trancheRewards[2] = 100e32;

        kpiManager.createKPI(true, trancheValues, trancheRewards);
    }

    // Stakes a set of users and their amounts
    function setUpStakers(address[] memory users, uint[] memory amounts)
        public
        returns (
            address[] memory cappedUsers,
            uint[] memory cappedAmounts,
            uint totalUserFunds
        )
    {
        vm.assume(amounts.length >= users.length);

        uint maxLength = MAX_USER_AMOUNT;

        if (users.length > maxLength) {
            cappedUsers = new address[](maxLength);
            cappedAmounts = new uint[](maxLength);
            for (uint i = 0; i < maxLength; i++) {
                cappedUsers[i] = users[i];
                cappedAmounts[i] = bound(amounts[i], 1, 100_000_000e18);
            }
        } else {
            cappedUsers = new address[](users.length);
            cappedAmounts = new uint[](users.length);
            for (uint i = 0; i < users.length; i++) {
                cappedUsers[i] = users[i];
                cappedAmounts[i] = bound(amounts[i], 1, 100_000_000e18);
            }
        }

        _assumeValidAddresses(cappedUsers);

        totalUserFunds = 0;

        for (uint i = 0; i < cappedUsers.length; i++) {
            stakingToken.mint(cappedUsers[i], cappedAmounts[i]);
            vm.startPrank(cappedUsers[i]);
            stakingToken.approve(address(kpiManager), cappedAmounts[i]);
            vm.expectEmit(true, true, true, true, address(kpiManager));
            emit Staked(cappedUsers[i], cappedAmounts[i]);
            kpiManager.stake(cappedAmounts[i]);
            totalUserFunds += cappedAmounts[i];
            vm.stopPrank();
        }

        // (returns cappedUsers, cappedAmounts, totalUserFunds)
    }

    function setUpStateForAssertionResolution(
        address[] memory users,
        uint[] memory amounts,
        uint valueToAssert,
        bool continuous
    )
        public
        returns (
            bytes32 assertionId,
            address[] memory cappedUsers,
            uint[] memory cappedAmounts,
            uint totalUserFunds
        )
    {
        // it should stake all orders in the stakingQueue
        (users, amounts, totalUserFunds) = setUpStakers(users, amounts);

        // prepare conditions
        if (continuous) createDummyContinuousKPI();
        else createDummyIncontinuousKPI();

        // prepare  bond and asserter authorization
        kpiManager.grantModuleRole(
            kpiManager.ASSERTER_ROLE(), MOCK_ASSERTER_ADDRESS
        );

        feeToken.mint(
            address(MOCK_ASSERTER_ADDRESS),
            ooV3.getMinimumBond(address(feeToken))
        );
        vm.startPrank(address(MOCK_ASSERTER_ADDRESS));
        feeToken.approve(
            address(kpiManager), ooV3.getMinimumBond(address(feeToken))
        );

        vm.warp(block.timestamp + 3);

        // SuT

        vm.expectEmit(true, false, false, false, address(kpiManager));
        emit DataAsserted(
            MOCK_ASSERTION_DATA_ID,
            bytes32(valueToAssert),
            MOCK_ASSERTER_ADDRESS,
            0x0
        ); // we don't know the last one

        assertionId = kpiManager.postAssertion(
            MOCK_ASSERTION_DATA_ID, valueToAssert, MOCK_ASSERTER_ADDRESS, 0
        );
        vm.stopPrank();

        return (assertionId, users, amounts, totalUserFunds);
    }
}

/*
postAssertionTest
├── when the Asserter is the Module itself
│   └── when the default currency is the same as the staking token
│        └── it should revert  
├── when there is an unresolved assertion live
│   └── it should revert
├── when there are no stored KPIs
│   └── it should revert 
├── when the specified KPI does not exist
│   └── it should revert 
├── when there aren't enough funds to pay the assertion fee
│   └── it should revert
└── when there are enough funds to pay the assertion fee
    ├── it should post a valid assertion in the UMA oracle
    ├── it should store the RewardRound configuration
    └── it should return a correct assertionId
*/

contract LM_PC_KPIRewarder_v1_postAssertionTest is LM_PC_KPIRewarder_v1Test {
    function test_RevertWhen_TheBondConfigurationIsInvalid() external {
        // Since the setup has a correct KPI MAnager, we create a new one with stakingToken == FeeToken

        address impl = address(new LM_PC_KPIRewarder_v1());
        LM_PC_KPIRewarder_v1 alt_kpiManager =
            LM_PC_KPIRewarder_v1(Clones.clone(impl));

        bytes memory configData = abi.encode(
            address(feeToken),
            address(feeToken),
            feeTokenBond,
            ooV3,
            DEFAULT_LIVENESS
        );

        alt_kpiManager.init(_orchestrator, _METADATA, configData);

        // it should revert

        vm.expectRevert(
            ILM_PC_KPIRewarder_v1
                .Module__LM_PC_KPIRewarder_v1__ModuleCannotUseStakingTokenAsBond
                .selector
        );
        alt_kpiManager.postAssertion(
            MOCK_ASSERTION_DATA_ID, 100, address(alt_kpiManager), 0
        );
    }

    function test_RevertWhen_ThereAreNoKPIs() external {
        // it should revert
        vm.expectRevert(
            ILM_PC_KPIRewarder_v1
                .Module__LM_PC_KPIRewarder_v1__InvalidKPINumber
                .selector
        );
        kpiManager.postAssertion(
            MOCK_ASSERTION_DATA_ID, 100, MOCK_ASSERTER_ADDRESS, 99_999
        );
    }

    function test_RevertWhen_TheTargetKPIIsNotValid() external {
        createDummyContinuousKPI();

        // it should revert
        vm.expectRevert(
            ILM_PC_KPIRewarder_v1
                .Module__LM_PC_KPIRewarder_v1__InvalidKPINumber
                .selector
        );
        kpiManager.postAssertion(
            MOCK_ASSERTION_DATA_ID, 100, MOCK_ASSERTER_ADDRESS, 99_999
        );
    }

    function test_RevertWhen_ThereIsALiveUnresolvedAssertion() external {
        // prepare conditions
        createDummyIncontinuousKPI();

        // prepare  bond and asserter authorization
        kpiManager.grantModuleRole(
            kpiManager.ASSERTER_ROLE(), MOCK_ASSERTER_ADDRESS
        );
        feeToken.mint(
            address(MOCK_ASSERTER_ADDRESS),
            ooV3.getMinimumBond(address(feeToken))
        );
        vm.startPrank(address(MOCK_ASSERTER_ADDRESS));
        feeToken.approve(
            address(kpiManager), ooV3.getMinimumBond(address(feeToken))
        );
        vm.stopPrank();

        // SuT
        vm.expectEmit(true, false, false, false, address(kpiManager));
        emit DataAsserted(
            MOCK_ASSERTION_DATA_ID,
            bytes32(MOCK_ASSERTED_VALUE),
            MOCK_ASSERTER_ADDRESS,
            0x0
        );
        vm.prank(address(MOCK_ASSERTER_ADDRESS));
        bytes32 assertionId = kpiManager.postAssertion(
            MOCK_ASSERTION_DATA_ID,
            MOCK_ASSERTED_VALUE,
            MOCK_ASSERTER_ADDRESS,
            0
        );

        // state after
        assertEq(kpiManager.getAssertionPending(), true);

        // Posting another assertion should now fail
        vm.expectRevert(
            ILM_PC_KPIRewarder_v1
                .Module__LM_PC_KPIRewarder_v1__UnresolvedAssertionExists
                .selector
        );
        vm.prank(address(MOCK_ASSERTER_ADDRESS));
        assertionId = kpiManager.postAssertion(
            MOCK_ASSERTION_DATA_ID,
            MOCK_ASSERTED_VALUE,
            MOCK_ASSERTER_ADDRESS,
            0
        );

        // created one is still pending
        assertEq(kpiManager.getAssertionPending(), true);
    }

    function test_SuccessfulAssertion(
        address[] memory users,
        uint[] memory amounts
    ) external {
        // it should stake all orders in the stakingQueue
        uint totalUserFunds;
        (users, amounts, totalUserFunds) = setUpStakers(users, amounts);

        // prepare conditions
        createDummyIncontinuousKPI();

        // prepare  bond and asserter authorization
        kpiManager.grantModuleRole(
            kpiManager.ASSERTER_ROLE(), MOCK_ASSERTER_ADDRESS
        );
        feeToken.mint(
            address(MOCK_ASSERTER_ADDRESS),
            ooV3.getMinimumBond(address(feeToken))
        );
        vm.startPrank(address(MOCK_ASSERTER_ADDRESS));
        feeToken.approve(
            address(kpiManager), ooV3.getMinimumBond(address(feeToken))
        );

        // SuT
        vm.expectEmit(true, false, false, false, address(kpiManager));
        emit DataAsserted(
            MOCK_ASSERTION_DATA_ID,
            bytes32(MOCK_ASSERTED_VALUE),
            MOCK_ASSERTER_ADDRESS,
            0x0
        ); // we don't know the last one

        vm.expectEmit(false, true, true, true, address(kpiManager));
        emit RewardRoundConfigured(0x0, block.timestamp, 100, 0); // we don't know the generated ID

        bytes32 assertionId = kpiManager.postAssertion(
            MOCK_ASSERTION_DATA_ID, 100, MOCK_ASSERTER_ADDRESS, 0
        );
        vm.stopPrank();

        // state after
        for (uint i = 0; i < users.length; i++) {
            assertEq(stakingToken.balanceOf(users[i]), 0);
        }

        assertEq(feeToken.balanceOf(MOCK_ASSERTER_ADDRESS), 0);

        // check mock for stored data
        IOptimisticOracleIntegrator.DataAssertion memory assertion =
            kpiManager.getAssertion(assertionId);
        ILM_PC_KPIRewarder_v1.RewardRoundConfiguration memory rewardRoundConfig =
            kpiManager.getAssertionConfig(assertionId);

        assertEq(assertion.dataId, MOCK_ASSERTION_DATA_ID);
        assertEq(assertion.data, bytes32(MOCK_ASSERTED_VALUE));
        assertEq(assertion.asserter, MOCK_ASSERTER_ADDRESS);

        assertEq(rewardRoundConfig.creationTime, block.timestamp);
        assertEq(rewardRoundConfig.assertedValue, 100);
        assertEq(rewardRoundConfig.KpiToUse, 0);
        assertEq(rewardRoundConfig.distributed, false);
    }

    function test_RevertWhen_ThereArentEnoughFundsToPayTheAssertionFee(
        address[] memory users,
        uint[] memory amounts
    ) external {
        // it should revert

        uint totalUserFunds;
        (users, amounts, totalUserFunds) = setUpStakers(users, amounts);

        // prepare conditions
        createDummyIncontinuousKPI();

        // prepare  bond and asserter authorization
        kpiManager.grantModuleRole(
            kpiManager.ASSERTER_ROLE(), MOCK_ASSERTER_ADDRESS
        );
        feeToken.mint(
            address(MOCK_ASSERTER_ADDRESS),
            ooV3.getMinimumBond(address(feeToken)) - 1
        );
        vm.startPrank(address(MOCK_ASSERTER_ADDRESS));
        feeToken.approve(
            address(kpiManager), ooV3.getMinimumBond(address(feeToken))
        );
        vm.stopPrank();

        // SuT
        vm.prank(address(MOCK_ASSERTER_ADDRESS));
        vm.expectRevert(); // ERC20 insufficient balance revert
        kpiManager.postAssertion(
            MOCK_ASSERTION_DATA_ID, 100, MOCK_ASSERTER_ADDRESS, 0
        );

        // state after
        assertEq(
            feeToken.balanceOf(MOCK_ASSERTER_ADDRESS),
            ooV3.getMinimumBond(address(feeToken)) - 1
        );
    }
}

/*
createKPITest
├── when the number of tranches is 0
│   └── it should revert
├── when the number of tranches is bigger than 20
│   └── it should revert
├── when the length of the trancheValue array and the trancheReward array don't match
│   └── it should revert
├── when the values in the trancheValue array aren't incremental
│   └── it should revert
└── when the input is valid
    └── it should create a KPI struct with the currentKPI counter as ID and increase the counter


*/

contract LM_PC_KPIRewarder_v1_createKPITest is LM_PC_KPIRewarder_v1Test {
    function test_RevertWhen_TheNumberOfTranchesIs0() external {
        // it should revert

        uint[] memory trancheValues;
        uint[] memory trancheRewards;

        vm.expectRevert(
            ILM_PC_KPIRewarder_v1
                .Module__LM_PC_KPIRewarder_v1__InvalidTrancheNumber
                .selector
        );
        kpiManager.createKPI(true, trancheValues, trancheRewards);
    }

    function test_RevertWhen_TheNumberOfTranchesIsBiggerThan20(
        uint[] calldata trancheValues,
        uint[] calldata trancheRewards
    ) external {
        // it should revert
        vm.assume(trancheValues.length >= 21);

        vm.expectRevert(
            ILM_PC_KPIRewarder_v1
                .Module__LM_PC_KPIRewarder_v1__InvalidTrancheNumber
                .selector
        );
        kpiManager.createKPI(true, trancheValues, trancheRewards);
    }

    function test_RevertWhen_TheLengthOfTheTrancheValueArrayAndTheTrancheRewardArrayDontMatch(
        uint rewardLength,
        uint valueLength
    ) external {
        // it should revert
        rewardLength = bound(rewardLength, 1, 20);
        valueLength = bound(valueLength, 1, 20);

        vm.assume(rewardLength != valueLength);

        if (rewardLength != valueLength) {
            vm.expectRevert(
                ILM_PC_KPIRewarder_v1
                    .Module__LM_PC_KPIRewarder_v1__InvalidKPIValueLengths
                    .selector
            );
            kpiManager.createKPI(
                true, new uint[](valueLength), new uint[](rewardLength)
            );
        }
    }

    function test_RevertWhen_TheValuesInTheTrancheValueArrayArentIncremental(
        uint[] calldata trancheValues,
        uint[] calldata trancheRewards
    ) external {
        // it should revert

        vm.assume(trancheValues.length >= 2);
        vm.assume(trancheRewards.length >= trancheValues.length);

        uint length = bound(trancheValues.length, 2, 20);

        uint[] memory valuesCapped = trancheValues[0:length];
        uint[] memory rewardsCapped = trancheRewards[0:length];

        for (uint i = 0; i < length; i++) {
            // bound values to avoid overflows
            valuesCapped[i] =
                bound(valuesCapped[i], 1, 1_000_000_000_000_000e18);
            rewardsCapped[i] =
                bound(rewardsCapped[i], 1e18, 1_000_000_000_000_000e18);
        }

        // Guarantee wrong value in the last tranche.
        valuesCapped[length - 1] = valuesCapped[length - 2] / 2;
        vm.expectRevert(
            ILM_PC_KPIRewarder_v1
                .Module__LM_PC_KPIRewarder_v1__InvalidKPITrancheValues
                .selector
        );
        kpiManager.createKPI(true, valuesCapped, rewardsCapped);
    }

    function test_WhenTheInputIsValid(
        bool continuous,
        uint numOfTranches,
        uint trancheSeed,
        uint rewardSeed
    ) external {
        // it should create a KPI struct with the currentKPI counter as ID and increase the counter

        numOfTranches = bound(numOfTranches, 1, 20);
        trancheSeed = bound(trancheSeed, 1, 10_000);
        rewardSeed = bound(rewardSeed, 1e18, 1000e18);

        uint[] memory trancheValues = new uint[](numOfTranches);
        uint[] memory trancheRewards = new uint[](numOfTranches);

        uint totalRewards;

        for (uint i = 0; i < numOfTranches; i++) {
            trancheValues[i] = trancheSeed * (i + 1);
            trancheRewards[i] = rewardSeed * (i + 1);
            totalRewards += trancheRewards[i];
        }

        vm.expectEmit(true, true, true, true, address(kpiManager));
        emit KPICreated(
            0,
            numOfTranches,
            totalRewards,
            continuous,
            trancheValues,
            trancheRewards
        );

        uint kpiNum =
            kpiManager.createKPI(continuous, trancheValues, trancheRewards);

        ILM_PC_KPIRewarder_v1.KPI memory generatedKPI =
            kpiManager.getKPI(kpiNum);

        assertEq(generatedKPI.trancheValues.length, numOfTranches);
        assertEq(generatedKPI.trancheRewards.length, numOfTranches);
        assertEq(generatedKPI.continuous, continuous);

        for (uint i = 0; i < numOfTranches; i++) {
            assertEq(generatedKPI.trancheValues[i], trancheValues[i]);
            assertEq(generatedKPI.trancheRewards[i], trancheRewards[i]);
        }
    }
}

/*
stakeTest
├── when the staked amount is 0
│   └── it should revert
├── when there is an unresolved assertion live
│   └── it should revert
├── when the caller does not have sufficient funds
│   └── it should revert
└── when the caller has sufficient funds
    ├── it should take the funds from the user
    └── it should stake the funds
*/
contract LM_PC_KPIRewarder_v1_stakeTest is LM_PC_KPIRewarder_v1Test {
    function test_RevertWhen_TheStakedAmountIs0() external {
        // it should revert

        stakingToken.mint(USER_1, 1000e18);
        vm.startPrank(USER_1);
        stakingToken.approve(address(kpiManager), 1000e18);
        vm.expectRevert(
            IERC20PaymentClientBase_v1
                .Module__ERC20PaymentClientBase__InvalidAmount
                .selector
        );
        kpiManager.stake(0);
    }

    function test_RevertWhen_ThereIsAPendingAssertion(uint stakeAmount)
        external
    {
        // it should revert

        vm.assume(stakeAmount > 0);

        // Create an assertion
        // prepare conditions
        createDummyIncontinuousKPI();

        // prepare  bond and asserter authorization
        kpiManager.grantModuleRole(
            kpiManager.ASSERTER_ROLE(), MOCK_ASSERTER_ADDRESS
        );
        feeToken.mint(
            address(MOCK_ASSERTER_ADDRESS),
            ooV3.getMinimumBond(address(feeToken))
        );
        vm.startPrank(address(MOCK_ASSERTER_ADDRESS));
        feeToken.approve(
            address(kpiManager), ooV3.getMinimumBond(address(feeToken))
        );
        vm.stopPrank();

        // SuT
        vm.expectEmit(true, false, false, false, address(kpiManager));
        emit DataAsserted(
            MOCK_ASSERTION_DATA_ID,
            bytes32(MOCK_ASSERTED_VALUE),
            MOCK_ASSERTER_ADDRESS,
            0x0
        );
        vm.prank(address(MOCK_ASSERTER_ADDRESS));
        kpiManager.postAssertion(
            MOCK_ASSERTION_DATA_ID,
            MOCK_ASSERTED_VALUE,
            MOCK_ASSERTER_ADDRESS,
            0
        );
        assertEq(kpiManager.getAssertionPending(), true);

        // Staking should now fail

        stakingToken.mint(USER_1, stakeAmount);
        vm.startPrank(USER_1);
        stakingToken.approve(address(kpiManager), stakeAmount);
        vm.expectRevert(
            ILM_PC_KPIRewarder_v1
                .Module__LM_PC_KPIRewarder_v1__CannotStakeWhenAssertionPending
                .selector
        );
        kpiManager.stake(stakeAmount);
    }

    function test_RevertWhen_TheCallerDoesNotHaveSufficientFunds() external {
        // it should revert

        address USER = address(0x1337);
        stakingToken.mint(USER, 1e18);
        vm.startPrank(USER);
        stakingToken.approve(address(kpiManager), 1000e18);
        vm.expectRevert();
        kpiManager.stake(1000e18);
        vm.stopPrank();
    }

    function test_WhenTheCallerHasSufficientFunds(uint amount) external {
        // it should stake the funds normally

        vm.assume(amount > 0);

        uint userBalanceBefore = stakingToken.balanceOf(USER_1);
        uint contractBalanceBefore = stakingToken.balanceOf(address(kpiManager));

        stakingToken.mint(USER_1, amount);
        vm.startPrank(USER_1);
        stakingToken.approve(address(kpiManager), amount);
        kpiManager.stake(amount);
        vm.stopPrank();

        assertEq(stakingToken.balanceOf(USER_1), userBalanceBefore);
        assertEq(
            stakingToken.balanceOf(address(kpiManager)),
            contractBalanceBefore + amount
        );
        assertEq(kpiManager.getBalance(USER_1), amount);
        assertEq(kpiManager.getTotalSupply(), contractBalanceBefore + amount);
    }
}

/*
assertionresolvedCallbackTest
├── when the caller is not the Optimistic Oracle
│   └── it should revert
├── when the assertionId does not exist
│   └── it should revert
├── when the assertion resolved to false
│   └── it should emit an event
└── when the assertion resolved to true
    ├── it will go through all tranches until reaching the asserted amount
    ├── when the rewardType is continuous
    │   └── it should pay out an amount from the last tranche proportional to its level of completion
    ├── when the rewardType is not continuous
    │   └── it should not pay out any amount from the uncompleted tranche at all
    ├── it should set the staking rewards to the calculated value with a duration of 1
    └── it should emit an event
*/

contract LM_PC_KPIRewarder_v1_assertionresolvedCallbackTest is
    LM_PC_KPIRewarder_v1Test
{
    function test_WhenTheAssertionResolvedToFalse(
        address[] memory users,
        uint[] memory amounts
    ) external {
        uint assertedIntermediateValue = 250;

        // it should emit an event
        bytes32 createdID;
        uint totalStakedFunds;
        (createdID, users, amounts, totalStakedFunds) =
        setUpStateForAssertionResolution(
            users, amounts, assertedIntermediateValue, true
        );

        vm.startPrank(address(ooV3));
        vm.expectEmit(true, true, true, true, address(kpiManager));
        // vm.expectEmit(false, false, false, false);

        emit DataAssertionResolved(
            false,
            MOCK_ASSERTION_DATA_ID,
            bytes32(assertedIntermediateValue),
            MOCK_ASSERTER_ADDRESS,
            createdID
        );
        kpiManager.assertionResolvedCallback(createdID, false);
        vm.stopPrank();

        // Check assertion data is deleted
        assertEq(kpiManager.getAssertion(createdID).asserter, address(0)); // address(0) asserters are not possible in the system
        assertEq(kpiManager.getAssertionConfig(createdID).creationTime, 0);
    }

    modifier whenTheAssertionResolvedToTrue() {
        // it will go through all tranches until reaching the asserted amount
        // it should set the staking rewards to the calculated value with a duration of 1
        // it should emit an event

        _;
    }

    function test_WhenTheRewardTypeIsContinuous(
        address[] memory users,
        uint[] memory amounts
    ) external whenTheAssertionResolvedToTrue {
        // it should pay out an amount from the last tranche proportional to its level of completion
        // it should not pay out any amount from the uncompleted tranche at all

        vm.assume(users.length > 1);

        uint assertedIntermediateValue = 250e18;

        bytes32 createdID;
        uint totalStakedFunds;
        (createdID, users, amounts, totalStakedFunds) =
        setUpStateForAssertionResolution(
            users, amounts, assertedIntermediateValue, true
        );

        vm.startPrank(address(ooV3));

        vm.expectEmit(true, true, true, true, address(kpiManager));
        emit DataAssertionResolved(
            true,
            MOCK_ASSERTION_DATA_ID,
            bytes32(assertedIntermediateValue),
            MOCK_ASSERTER_ADDRESS,
            createdID
        );

        vm.expectEmit(true, true, true, true, address(kpiManager));
        emit RewardSet(250e32, 1, 250e32, block.timestamp + 1);

        kpiManager.assertionResolvedCallback(createdID, true);
        vm.stopPrank();

        // Check storage state is modified
        assertEq(kpiManager.getAssertion(createdID).resolved, true);
        assertEq(kpiManager.getAssertionConfig(createdID).distributed, true);

        vm.warp(block.timestamp + 3);

        uint length = users.length;
        if (length > MAX_USER_AMOUNT) {
            length = MAX_USER_AMOUNT;
        }

        // check earned rewards are correct
        for (uint i; i < length; i++) {
            assertEq(kpiManager.getBalance(users[i]), amounts[i]);

            //=========================================================
            // This is the place where imprecision issues arise. Needs review
            //=========================================================

            uint userReward =
                amounts[i] * kpiManager.getRewardRate() / totalStakedFunds;
            console.log(userReward);

            // Asserts a is approximately equal to b with delta in percentage, where 1e18 is 100%
            assertApproxEqAbs(
                kpiManager.getEarned(users[i]),
                userReward,
                1e8 // Below this it reverts due to precision error
            );
        }

        for (uint i; i < length; i++) {
            vm.startPrank(users[i]);
            uint earnedReward = kpiManager.getEarned(users[i]);

            if (earnedReward > 0) {
                vm.expectEmit(true, true, true, true, address(kpiManager));
                emit PaymentOrderAdded(
                    users[i],
                    address(_token),
                    earnedReward,
                    block.chainid,
                    block.chainid,
                    bytes32(0),
                    new bytes32[](0)
                );
            }

            kpiManager.unstake(amounts[i]);

            assertEq(kpiManager.getBalance(users[i]), 0);
            assertEq(kpiManager.getEarned(users[i]), 0);
            assertEq(stakingToken.balanceOf(users[i]), amounts[i]);

            vm.stopPrank();
        }
    }

    function test_WhenTheRewardTypeIsNotContinuous(
        address[] memory users,
        uint[] memory amounts
    ) external whenTheAssertionResolvedToTrue {
        // it should not pay out any amount from the uncompleted tranche at all

        uint assertedIntermediateValue = 250e18;

        bytes32 createdID;
        uint totalStakedFunds;
        (createdID, users, amounts, totalStakedFunds) =
        setUpStateForAssertionResolution(
            users, amounts, assertedIntermediateValue, false
        );

        vm.warp(block.timestamp + 5);

        vm.startPrank(address(ooV3));

        vm.expectEmit(true, true, true, true, address(kpiManager));
        emit DataAssertionResolved(
            true,
            MOCK_ASSERTION_DATA_ID,
            bytes32(assertedIntermediateValue),
            MOCK_ASSERTER_ADDRESS,
            createdID
        );

        vm.expectEmit(true, true, true, true, address(kpiManager));
        emit RewardSet(200e32, 1, 200e32, block.timestamp + 1);

        kpiManager.assertionResolvedCallback(createdID, true);
        vm.stopPrank();

        // Check storage state is modified
        assertEq(kpiManager.getAssertion(createdID).resolved, true);
        assertEq(kpiManager.getAssertionConfig(createdID).distributed, true);
        vm.warp(block.timestamp + 3);

        uint length = users.length;
        if (length > MAX_USER_AMOUNT) {
            length = MAX_USER_AMOUNT;
        }

        // check earned rewards are correct
        for (uint i; i < length; i++) {
            assertEq(kpiManager.getBalance(users[i]), amounts[i]);

            //=========================================================
            // This is the place where imprecision issues arise. Needs review
            //=========================================================

            uint userReward =
                amounts[i] * kpiManager.getRewardRate() / totalStakedFunds;
            console.log(userReward);

            // Asserts a is approximately equal to b with delta in percentage, where 1e18 is 100%
            assertApproxEqAbs(
                kpiManager.getEarned(users[i]),
                userReward,
                1e8 // Below this it reverts due to precision error
            );
        }

        for (uint i; i < length; i++) {
            vm.startPrank(users[i]);
            uint earnedReward = kpiManager.getEarned(users[i]);

            if (earnedReward > 0) {
                vm.expectEmit(true, true, true, true, address(kpiManager));
                emit PaymentOrderAdded(
                    users[i],
                    address(_token),
                    earnedReward,
                    block.chainid,
                    block.chainid,
                    bytes32(0),
                    new bytes32[](0)
                );
            }

            kpiManager.unstake(amounts[i]);

            assertEq(kpiManager.getBalance(users[i]), 0);
            assertEq(kpiManager.getEarned(users[i]), 0);
            assertEq(stakingToken.balanceOf(users[i]), amounts[i]);

            vm.stopPrank();
        }
    }

    function test_RevertWhen_TheCallerIsNotOO(
        address[] memory users,
        uint[] memory amounts
    ) external {
        // it should not pay out any amount from the uncompleted tranche at all

        bytes32 createdID;
        uint totalStakedFunds;
        (createdID, users, amounts, totalStakedFunds) =
            setUpStateForAssertionResolution(users, amounts, 250, false);

        vm.expectRevert(
            IOptimisticOracleIntegrator
                .Module__OptimisticOracleIntegrator__CallerNotOO
                .selector
        );
        kpiManager.assertionResolvedCallback(createdID, true);
    }

    function test_RevertWhen_TheAssertionIdDoesNotExist(
        address[] memory users,
        uint[] memory amounts
    ) external {
        // it should revert

        // Create different assertion in OOV3 with callback to SuT
        address ALBA = address(0xA1BA);
        vm.startPrank(ALBA);
        feeToken.mint(ALBA, 1e22);
        feeToken.approve(address(ooV3), 1e22);
        bytes32 fake_ID = ooV3.assertTruth(
            abi.encodePacked(
                "Data asserted: 0x", // in the example data is type bytes32 so we add the hex prefix 0x.
                ClaimData.toUtf8Bytes(bytes32(MOCK_ASSERTED_VALUE)),
                " for dataId: 0x",
                ClaimData.toUtf8Bytes(MOCK_ASSERTION_DATA_ID),
                " and asserter: 0x",
                ClaimData.toUtf8BytesAddress(ALBA),
                " at timestamp: ",
                ClaimData.toUtf8BytesUint(block.timestamp),
                " in the DataAsserter contract at 0x",
                ClaimData.toUtf8BytesAddress(address(0)),
                " is valid."
            ),
            ALBA,
            address(kpiManager),
            address(0),
            DEFAULT_LIVENESS,
            IERC20(feeToken),
            kpiManager.defaultBond(),
            kpiManager.defaultIdentifier(),
            bytes32(0)
        );
        vm.stopPrank();

        // We now create a legitimate assertion so the callback is "listening"

        bytes32 createdID;
        uint totalStakedFunds;
        (createdID, users, amounts, totalStakedFunds) =
            setUpStateForAssertionResolution(users, amounts, 250, false);

        vm.prank(address(ooV3));
        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_KPIRewarder_v1
                    .Module__LM_PC_KPIRewarder_v1__NonExistentAssertionId
                    .selector,
                fake_ID
            )
        );
        kpiManager.assertionResolvedCallback(fake_ID, true);

        // the other assertion is still open
        (bool assertionResolved, bytes32 data) = kpiManager.getData(createdID);

        assertEq(assertionResolved, false);
        assertEq(data, 0);
    }
}

/*
    testDeleteStuckAssertion
    ├── When the assertion isn't stored locally
    │    └── It should revert
    |── When the assertion hasn't expired yet
    │    └── It should revert
    ├── When the assertion CAN be resolved
    │    └── It should revert
    └── When the assertion CAN NOT be resolved
        ├── It should delete the assertion config
        ├── It should delete the assertion data
        ├── IT should set assertionPending to false
        └── It should emit an event
    */

contract LM_PC_KPIRewarder_v1_deleteStuckAssertionTest is
    LM_PC_KPIRewarder_v1Test
{
    function test_RevertWhen_TheAssertionIsntStoredLocally(bytes32 assertionId)
        external
    {
        // it should revert

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_KPIRewarder_v1
                    .Module__LM_PC_KPIRewarder_v1__NonExistentAssertionId
                    .selector,
                assertionId
            )
        );
        kpiManager.deleteStuckAssertion(assertionId);
    }

    function test_RevertWhen_TheAssertionHasNotExpired(
        address[] memory users,
        uint[] memory amounts
    ) external {
        // it should revert

        vm.assume(users.length > 1);

        uint assertedIntermediateValue = 250;

        bytes32 createdID;
        uint totalStakedFunds;
        (createdID, users, amounts, totalStakedFunds) =
        setUpStateForAssertionResolution(
            users, amounts, assertedIntermediateValue, true
        );

        // Assertion hasn't expired yet
        vm.warp(block.timestamp + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_KPIRewarder_v1
                    .Module__LM_PC_KPIRewarder_v1__AssertionNotStuck
                    .selector,
                createdID
            )
        );
        kpiManager.deleteStuckAssertion(createdID);
    }

    function test_RevertWhen_TheAssertionCanBeResolved(
        address[] memory users,
        uint[] memory amounts
    ) external {
        // it should revert

        vm.assume(users.length > 1);

        uint assertedIntermediateValue = 250;

        bytes32 createdID;
        uint totalStakedFunds;
        (createdID, users, amounts, totalStakedFunds) =
        setUpStateForAssertionResolution(
            users, amounts, assertedIntermediateValue, true
        );

        // Assertion could now be resolved
        vm.warp(block.timestamp + DEFAULT_LIVENESS + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_KPIRewarder_v1
                    .Module__LM_PC_KPIRewarder_v1__AssertionNotStuck
                    .selector,
                createdID
            )
        );
        kpiManager.deleteStuckAssertion(createdID);
    }

    function test_deleteStuckAssertion_WhenTheAssertionCannotBeResolved(
        address[] memory users,
        uint[] memory amounts
    ) external {
        // it should revert

        vm.assume(users.length > 1);

        uint assertedIntermediateValue = 250;

        bytes32 createdID;
        uint totalStakedFunds;
        (createdID, users, amounts, totalStakedFunds) =
        setUpStateForAssertionResolution(
            users, amounts, assertedIntermediateValue, true
        );

        // Assertion could now be resolved
        vm.warp(block.timestamp + DEFAULT_LIVENESS + 1);

        // BUT: we burn the asserter's bond in the oov3, so the transfer will revert.
        feeToken.burn(address(ooV3), ooV3.getMinimumBond(address(feeToken)));

        vm.expectEmit(true, true, true, true, address(kpiManager));
        emit DeletedStuckAssertion(createdID);
        kpiManager.deleteStuckAssertion(createdID);

        // Check assertion data is deleted
        assertEq(kpiManager.getAssertion(createdID).asserter, address(0)); // address(0) asserters are not possible in the system
        assertEq(kpiManager.getAssertionConfig(createdID).creationTime, 0);
    }
}
