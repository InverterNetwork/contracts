// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

//Internal Dependencies
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
    ILM_PC_Staking_v1
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

    event PaymentOrderAdded(address indexed recipient, uint amount);

    //=========================================================================================
    // Setup

    function setUp() public {
        ooV3 = new OptimisticOracleV3Mock(feeToken, DEFAULT_LIVENESS);
        // we whitelist the default currency
        ooV3.whitelistCurrency(address(feeToken), 5e17);
        feeTokenBond = ooV3.getMinimumBond(address(feeToken));

        //Add Module to Mock Orchestrator
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

        //Init Module wrongly
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

    // Creates  dummy incontinuous KPI with 3 tranches, a max value of 300 and 300e18 tokens for rewards
    function createDummyIncontinuousKPI() public {
        uint[] memory trancheValues = new uint[](3);
        uint[] memory trancheRewards = new uint[](3);

        trancheValues[0] = 100;
        trancheValues[1] = 200;
        trancheValues[2] = 300;

        trancheRewards[0] = 100e18;
        trancheRewards[1] = 100e18;
        trancheRewards[2] = 100e18;

        kpiManager.createKPI(false, trancheValues, trancheRewards);
    }

    // Creates  dummy continuous KPI with 3 tranches, a max value of 300 and 300e18 tokens for rewards
    function createDummyContinuousKPI() public {
        uint[] memory trancheValues = new uint[](3);
        uint[] memory trancheRewards = new uint[](3);

        trancheValues[0] = 100;
        trancheValues[1] = 200;
        trancheValues[2] = 300;

        trancheRewards[0] = 100e18;
        trancheRewards[1] = 100e18;
        trancheRewards[2] = 100e18;

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

        uint maxLength = kpiManager.MAX_QUEUE_LENGTH();

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
            kpiManager.stake(cappedAmounts[i]);
            totalUserFunds += cappedAmounts[i];
            vm.stopPrank();
        }

        // (returns cappedUsers, cappedAmounts, totalUserFunds)
    }
}

/*
postAssertionTest
├── when the Asserter is the Module itself
│   └── when the default currency is the same as the staking token
│        └── it should revert  
├── when there are no stored KPIs
│   └── it should revert 
├── when the specified KPI does not exist
│   └── it should revert 
├── when there is an unresolved assertion live
│   └── it should revert 
├── when stakingQueue length is bigger than 0
│   ├── it should stake all orders in the stakingQueue
│   └── it should remove the amount form the queued funds
├── it should delete the stakingQueue
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
        ); //
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
        assertEq(kpiManager.assertionPending(), true);

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
        assertEq(kpiManager.assertionPending(), true);
    }

    function test_WhenStakingQueueLengthIsBiggerThan0(
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
        ); //
        vm.startPrank(address(MOCK_ASSERTER_ADDRESS));
        feeToken.approve(
            address(kpiManager), ooV3.getMinimumBond(address(feeToken))
        );
        vm.stopPrank();

        // SuT
        vm.startPrank(address(MOCK_ASSERTER_ADDRESS));
        for (uint i = 0; i < users.length; i++) {
            vm.expectEmit(true, true, true, true, address(kpiManager));
            emit Staked(users[i], amounts[i]);
        }
        vm.expectEmit(true, false, false, false, address(kpiManager));
        emit DataAsserted(
            MOCK_ASSERTION_DATA_ID,
            bytes32(MOCK_ASSERTED_VALUE),
            MOCK_ASSERTER_ADDRESS,
            0x0
        ); //we don't know the last one

        bytes32 assertionId = kpiManager.postAssertion(
            MOCK_ASSERTION_DATA_ID, 100, MOCK_ASSERTER_ADDRESS, 0
        );
        vm.stopPrank();

        // state after
        assertEq(kpiManager.getStakingQueue().length, 0);
        assertEq(kpiManager.totalQueuedFunds(), 0);

        for (uint i = 0; i < users.length; i++) {
            assertEq(stakingToken.balanceOf(users[i]), 0);
        }

        assertEq(feeToken.balanceOf(MOCK_ASSERTER_ADDRESS), 0);

        //check mock for stored data
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

    function test_WhenStakingQueueLengthIsEmpty() external {
        // prepare conditions
        createDummyIncontinuousKPI();

        // prepare  bond and asserter authorization
        kpiManager.grantModuleRole(
            kpiManager.ASSERTER_ROLE(), MOCK_ASSERTER_ADDRESS
        );
        feeToken.mint(
            address(MOCK_ASSERTER_ADDRESS),
            ooV3.getMinimumBond(address(feeToken))
        ); //
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
            MOCK_ASSERTION_DATA_ID, 100, MOCK_ASSERTER_ADDRESS, 0
        );

        // state after
        assertEq(kpiManager.getStakingQueue().length, 0);
        assertEq(kpiManager.totalQueuedFunds(), 0);

        assertEq(feeToken.balanceOf(MOCK_ASSERTER_ADDRESS), 0);

        //check mock for posted data
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
        ); //
        vm.startPrank(address(MOCK_ASSERTER_ADDRESS));
        feeToken.approve(
            address(kpiManager), ooV3.getMinimumBond(address(feeToken))
        );
        vm.stopPrank();

        // SuT
        vm.prank(address(MOCK_ASSERTER_ADDRESS));
        vm.expectRevert(); // ERC20 insufficient balance revert
        bytes32 assertionId = kpiManager.postAssertion(
            MOCK_ASSERTION_DATA_ID, 100, MOCK_ASSERTER_ADDRESS, 0
        );

        // state after
        assertEq(kpiManager.getStakingQueue().length, users.length);
        assertEq(kpiManager.totalQueuedFunds(), totalUserFunds);

        for (uint i = 0; i < users.length; i++) {
            assertEq(kpiManager.stakingQueueAmounts(users[i]), amounts[i]);
        }

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
            //bound values to avoid overflows
            valuesCapped[i] =
                bound(valuesCapped[i], 1, 1_000_000_000_000_000e18);
            rewardsCapped[i] =
                bound(rewardsCapped[i], 1e18, 1_000_000_000_000_000e18);
        }

        // Guarantee wrong value in the last tranche.
        valuesCapped[length - 1] = valuesCapped[length - 2] / 2; //
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
├── when the staked amount is below the minimum stake
│   └── it should revert
├── when the length of the staking Queue is already at MAX_QUEUE_LENGTH
│   └── it should revert
├── when the caller does not have sufficient funds
│   └── it should revert
└── when the caller has sufficient funds
    └── it should store the amount + caller in the staking Queue and increase the value of totalQueuedFunds by the staked amount
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

    function test_RevertWhen_TheStakedAmountIsBelowMinimum(
        uint minAmount,
        uint stakeAmount
    ) external {
        // it should revert
        vm.assume(minAmount > 1);
        stakeAmount = bound(stakeAmount, 1, minAmount - 1);

        kpiManager.setMinimumStake(minAmount);

        stakingToken.mint(USER_1, stakeAmount);
        vm.startPrank(USER_1);
        stakingToken.approve(address(kpiManager), stakeAmount);
        vm.expectRevert(
            ILM_PC_KPIRewarder_v1
                .Module__LM_PC_KPIRewarder_v1__InvalidStakeAmount
                .selector
        );
        kpiManager.stake(stakeAmount);
    }

    function test_RevertWhen_TheLengthOfTheStakingQueueIsAlreadyAtMAX_QUEUE_LENGTH(
        uint[] calldata amounts
    ) external {
        // it should revert
        address USER;
        vm.assume(amounts.length > kpiManager.MAX_QUEUE_LENGTH());
        for (uint i = 0; i < kpiManager.MAX_QUEUE_LENGTH(); i++) {
            USER = address(uint160(i + 1));
            uint amount = bound(amounts[i], 1, 1_000_000e18);
            stakingToken.mint(USER, amount);
            vm.startPrank(USER);
            stakingToken.approve(address(kpiManager), amount);

            kpiManager.stake(amount);
            vm.stopPrank();
        }

        USER = address(0x1337);
        stakingToken.mint(USER, 1000e18);
        vm.startPrank(USER);
        stakingToken.approve(address(kpiManager), 1000e18);
        vm.expectRevert(
            ILM_PC_KPIRewarder_v1
                .Module__LM_PC_KPIRewarder_v1__StakingQueueIsFull
                .selector
        );
        kpiManager.stake(1000e18);
        vm.stopPrank();
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
        // it should store the amount + caller in the staking Queue and increase the value of totalQueuedFunds by the staked amount

        amount = bound(amount, 1, 100_000e18);
        address USER = address(0x1337);

        // state before
        uint stakingQueueLengthBefore = kpiManager.getStakingQueue().length;
        uint userStakeBalanceBefore = kpiManager.stakingQueueAmounts(USER);
        uint totalQueuedFundsBefore = kpiManager.totalQueuedFunds();

        stakingToken.mint(USER, amount);
        vm.startPrank(USER);
        stakingToken.approve(address(kpiManager), amount);
        kpiManager.stake(amount);
        vm.stopPrank();

        // state after
        assertEq(
            kpiManager.getStakingQueue().length, stakingQueueLengthBefore + 1
        );
        assertEq(
            kpiManager.stakingQueueAmounts(USER),
            userStakeBalanceBefore + amount
        );
        assertEq(kpiManager.totalQueuedFunds(), totalQueuedFundsBefore + amount);
    }
}

/*
assertionresolvedCallbackTest
├── when the caller is not the Optimistic Oracle
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
        ); //
        vm.startPrank(address(MOCK_ASSERTER_ADDRESS));
        feeToken.approve(
            address(kpiManager), ooV3.getMinimumBond(address(feeToken))
        );
        vm.stopPrank();

        vm.warp(block.timestamp + 3);

        // SuT
        vm.startPrank(address(MOCK_ASSERTER_ADDRESS));
        for (uint i = 0; i < users.length; i++) {
            vm.expectEmit(true, true, true, true, address(kpiManager));
            emit Staked(users[i], amounts[i]);
        }

        vm.expectEmit(true, false, false, false, address(kpiManager));
        emit DataAsserted(
            MOCK_ASSERTION_DATA_ID,
            bytes32(valueToAssert),
            MOCK_ASSERTER_ADDRESS,
            0x0
        ); //we don't know the last one

        assertionId = kpiManager.postAssertion(
            MOCK_ASSERTION_DATA_ID, valueToAssert, MOCK_ASSERTER_ADDRESS, 0
        );
        vm.stopPrank();

        return (assertionId, users, amounts, totalUserFunds);
    }

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
        //vm.expectEmit(false, false, false, false);

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

        uint assertedIntermediateValue = 250;

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
        emit RewardSet(250e18, 1, 250e18, block.timestamp + 1);

        kpiManager.assertionResolvedCallback(createdID, true);
        vm.stopPrank();

        // Check storage state is modified
        assertEq(kpiManager.getAssertion(createdID).resolved, true);
        assertEq(kpiManager.getAssertionConfig(createdID).distributed, true);

        vm.warp(block.timestamp + 3);

        uint length = users.length;
        if (length > kpiManager.MAX_QUEUE_LENGTH()) {
            length = kpiManager.MAX_QUEUE_LENGTH();
        }

        // check earned rewards are correct
        for (uint i; i < length; i++) {
            assertEq(kpiManager.balanceOf(users[i]), amounts[i]);

            //=========================================================
            // This is the place where imprecision issues arise. Needs review
            //=========================================================

            uint userReward =
                amounts[i] * kpiManager.rewardRate() / totalStakedFunds;
            console.log(userReward);

            //Asserts a is approximately equal to b with delta in percentage, where 1e18 is 100%
            assertApproxEqAbs(
                kpiManager.earned(users[i]),
                userReward,
                1e8 // Below this it reverts due to precision error
            );
        }

        for (uint i; i < length; i++) {
            vm.startPrank(users[i]);
            uint earnedReward = kpiManager.earned(users[i]);

            if (earnedReward > 0) {
                vm.expectEmit(true, true, true, true, address(kpiManager));
                emit PaymentOrderAdded(users[i], earnedReward);
            }

            kpiManager.unstake(amounts[i]);

            assertEq(kpiManager.balanceOf(users[i]), 0);
            assertEq(kpiManager.earned(users[i]), 0);
            assertEq(stakingToken.balanceOf(users[i]), amounts[i]);

            vm.stopPrank();
        }
    }

    function test_WhenTheRewardTypeIsNotContinuous(
        address[] memory users,
        uint[] memory amounts
    ) external whenTheAssertionResolvedToTrue {
        // it should not pay out any amount from the uncompleted tranche at all

        uint assertedIntermediateValue = 250;

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
        emit RewardSet(200e18, 1, 200e18, block.timestamp + 1);

        kpiManager.assertionResolvedCallback(createdID, true);
        vm.stopPrank();

        // Check storage state is modified
        assertEq(kpiManager.getAssertion(createdID).resolved, true);
        assertEq(kpiManager.getAssertionConfig(createdID).distributed, true);
        vm.warp(block.timestamp + 3);

        uint length = users.length;
        if (length > kpiManager.MAX_QUEUE_LENGTH()) {
            length = kpiManager.MAX_QUEUE_LENGTH();
        }

        // check earned rewards are correct
        for (uint i; i < length; i++) {
            assertEq(kpiManager.balanceOf(users[i]), amounts[i]);

            //=========================================================
            // This is the place where imprecision issues arise. Needs review
            //=========================================================

            uint userReward =
                amounts[i] * kpiManager.rewardRate() / totalStakedFunds;
            console.log(userReward);

            //Asserts a is approximately equal to b with delta in percentage, where 1e18 is 100%
            assertApproxEqAbs(
                kpiManager.earned(users[i]),
                userReward,
                1e8 // Below this it reverts due to precision error
            );
        }

        for (uint i; i < length; i++) {
            vm.startPrank(users[i]);
            uint earnedReward = kpiManager.earned(users[i]);

            if (earnedReward > 0) {
                vm.expectEmit(true, true, true, true, address(kpiManager));
                emit PaymentOrderAdded(users[i], earnedReward);
            }

            kpiManager.unstake(amounts[i]);

            assertEq(kpiManager.balanceOf(users[i]), 0);
            assertEq(kpiManager.earned(users[i]), 0);
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
}

/*
testDequeue
├── When the user has no funds in queue
│   └── It should do nothing
└── When the user has funds in queue
    ├── It should set the queued amount to zero
    ├── It should reduce the total queued amount
    ├── It should remove the user from the queue
    ├── It should emit an event
    └── It should transfer the funds back
*/
contract LM_PC_KPIRewarder_v1_dequeueTest is LM_PC_KPIRewarder_v1Test {
    function test_WhenTheUserHasNoFundsInQueue() external {
        address[] memory users = new address[](3);
        uint[] memory amounts = new uint[](3);

        users[0] = address(0x1);
        amounts[0] = 1000e18;

        users[1] = address(0x2);
        amounts[1] = 1000e18;

        users[2] = address(0x3);
        amounts[2] = 1000e18;

        setUpStakers(users, amounts);

        // It should do nothing

        address USER = address(0x1337);

        // state before
        uint stakingQueueLengthBefore = kpiManager.getStakingQueue().length;
        uint userStakeBalanceBefore = kpiManager.stakingQueueAmounts(USER);
        uint totalQueuedFundsBefore = kpiManager.totalQueuedFunds();

        // SuT
        vm.prank(USER);
        kpiManager.dequeueStake();

        // state after
        assertEq(kpiManager.getStakingQueue().length, stakingQueueLengthBefore);
        assertEq(kpiManager.stakingQueueAmounts(USER), userStakeBalanceBefore);
        assertEq(kpiManager.totalQueuedFunds(), totalQueuedFundsBefore);
    }

    function test_WhenTheUserHasFundsInQueue(
        address[] memory users,
        uint[] memory amounts
    ) external {
        (users, amounts, /* totalQueuedFunds*/ ) = setUpStakers(users, amounts);

        for (uint i; i < users.length; i++) {
            // state before
            uint totalQueuedFundsBefore = kpiManager.totalQueuedFunds();
            uint userStakeBalanceBefore =
                kpiManager.stakingQueueAmounts(users[i]);
            uint userTokenBalanceBefore = stakingToken.balanceOf(users[i]);
            uint stakingQueueLengthBefore = kpiManager.getStakingQueue().length;

            vm.startPrank(users[i]);
            kpiManager.dequeueStake();
            vm.stopPrank();

            // state after
            assertEq(
                kpiManager.totalQueuedFunds(),
                totalQueuedFundsBefore - userStakeBalanceBefore
            );
            assertEq(kpiManager.stakingQueueAmounts(users[i]), 0);
            assertEq(
                stakingToken.balanceOf(users[i]),
                userTokenBalanceBefore + userStakeBalanceBefore
            );
            assertEq(
                kpiManager.getStakingQueue().length,
                stakingQueueLengthBefore - 1
            );
        }
    }
}
