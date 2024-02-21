// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

//Internal Dependencies
import {ModuleTest, IModule, IOrchestrator} from "test/modules/ModuleTest.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

// SuT
import {
    KPIRewarder,
    IKPIRewarder,
    IOptimisticOracleIntegrator,
    IStakingManager,
    IERC20PaymentClient
} from "src/modules/logicModule/KPIRewarder.sol";

import {
    OptimisticOracleV3Mock,
    OptimisticOracleV3Interface
} from "test/modules/logicModule/oracle/utils/OptimisiticOracleV3Mock.sol";

import {StakingManagerAccessMock} from
    "test/utils/mocks/modules/logicModules/StakingManagerAccessMock.sol";

// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

contract KPIRewarderTest is ModuleTest {
    // SuT
    KPIRewarder kpiManager;

    OptimisticOracleV3Mock ooV3;

    uint64 immutable DEFAULT_LIVENESS = 5000;

    // Mock data for assertions
    bytes32 constant MOCK_ASSERTION_DATA_ID = "0x1234";
    bytes32 constant MOCK_ASSERTION_DATA = "This is test data";
    address constant MOCK_ASSERTER_ADDRESS = address(0x1);
    address USER_1 = address(0xA1BA);

    ERC20Mock stakingToken = new ERC20Mock("Staking Mock Token", "STAKE MOCK");
    // the reward token is _token from ModuleTest
    ERC20Mock feeToken = new ERC20Mock("OOV3 Fee Mock Token", "FEE MOCK");

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
        uint KPI_Id,
        uint numOfTranches,
        uint totalKPIRewards,
        bool continuous,
        uint[] trancheValues,
        uint[] trancheRewards
    );

    //=========================================================================================
    // Setup

    function setUp() public {
        ooV3 = new OptimisticOracleV3Mock(feeToken, DEFAULT_LIVENESS);
        // we whitelist the default currency
        ooV3.whitelistCurrency(address(feeToken), 5e17);

        //Add Module to Mock Orchestrator
        address impl = address(new KPIRewarder());
        kpiManager = KPIRewarder(Clones.clone(impl));

        _setUpOrchestrator(kpiManager);

        _authorizer.setIsAuthorized(address(this), true);

        bytes memory configData =
            abi.encode(address(stakingToken), address(feeToken), ooV3);

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
        address impl = address(new KPIRewarder());
        kpiManager = KPIRewarder(Clones.clone(impl));

        _setUpOrchestrator(kpiManager);

        bytes memory configData =
            abi.encode(address(stakingToken), address(_token), ooV3);

        //Init Module wrongly
        vm.expectRevert(IModule.Module__InvalidOrchestratorAddress.selector);
        kpiManager.init(IOrchestrator(address(0)), _METADATA, configData);

        // Test invalid staking token
        vm.expectRevert(
            IStakingManager.Module__StakingManager__InvalidStakingToken.selector
        );
        kpiManager.init(
            _orchestrator,
            _METADATA,
            abi.encode(address(0), address(_token), address(ooV3))
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
            abi.encode(address(stakingToken), address(0), address(ooV3))
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
        vm.expectRevert(OZErrors.Initializable__AlreadyInitialized);
        kpiManager.init(_orchestrator, _METADATA, bytes(""));
    }

    // Creates  dummy incontnuous KPI with 3 tranches, a max value of 300 and 300e18 tokens for rewards
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

    // Creates  dummy incontnuous KPI with 3 tranches, a max value of 300 and 300e18 tokens for rewards
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
        returns (uint totalUserFunds)
    {
        uint maxLength = kpiManager.MAX_QUEUE_LENGTH();

        if (users.length > maxLength) {
            for (uint i = maxLength; i < users.length; i++) {
                delete users[i];
            }
        }
        vm.assume(amounts.length >= users.length);

        _assumeValidAddresses(users);

        totalUserFunds = 0;

        for (uint i = 0; i < users.length; i++) {
            amounts[i] = bound(amounts[i], 1, 100_000_000e18);
            stakingToken.mint(users[i], amounts[i]);
            vm.startPrank(users[i]);
            stakingToken.approve(address(kpiManager), amounts[i]);
            kpiManager.stake(amounts[i]);
            totalUserFunds += amounts[i];
            vm.stopPrank();
        }

        // (returns totalUserFunds)
    }
}

/*
postAssertionTest
├── when stakingQueue length is bigger than 0
│   └── it should stake all orders in the stakingQueue
├── it should delete the stakingQueue
├── it should set the queued funds to zero
├── when there aren't enough funds to pay the assertion fee
│   └── it should revert
└── when there are enough funds to pay the assertion fee
    ├── it should post a valid assertion in the UMA oracle
    ├── it should store the RewardRound configuration
    └── it should return a correct assertionId
*/
contract KPIRewarder_postAssertionTest is KPIRewarderTest {
    function test_WhenStakingQueueLengthIsBiggerThan0(
        address[] memory users,
        uint[] memory amounts
    ) external {
        // it should stake all orders in the stakingQueue
        uint totalUserFunds = setUpStakers(users, amounts);

        // prepare conditions
        createDummyIncontinuousKPI();

        kpiManager.prepareAssertion(
            MOCK_ASSERTION_DATA_ID,
            MOCK_ASSERTION_DATA,
            MOCK_ASSERTER_ADDRESS,
            100,
            0
        );

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
            MOCK_ASSERTION_DATA,
            MOCK_ASSERTER_ADDRESS,
            0x0
        ); //we don't know the last one

        bytes32 assertionId = kpiManager.postAssertion();
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
        IKPIRewarder.RewardRoundConfiguration memory rewardRoundConfig =
            kpiManager.getAssertionConfig(assertionId);

        assertEq(assertion.dataId, MOCK_ASSERTION_DATA_ID);
        assertEq(assertion.data, MOCK_ASSERTION_DATA);
        assertEq(assertion.asserter, MOCK_ASSERTER_ADDRESS);

        assertEq(rewardRoundConfig.creationTime, block.timestamp);
        assertEq(rewardRoundConfig.assertedValue, 100);
        assertEq(rewardRoundConfig.KpiToUse, 0);
        assertEq(rewardRoundConfig.distributed, false);
    }

    function test_WhenStakingQueueLengthIsEmpty() external {
        // prepare conditions
        createDummyIncontinuousKPI();

        kpiManager.prepareAssertion(
            MOCK_ASSERTION_DATA_ID,
            MOCK_ASSERTION_DATA,
            MOCK_ASSERTER_ADDRESS,
            100,
            0
        );

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
            MOCK_ASSERTION_DATA,
            MOCK_ASSERTER_ADDRESS,
            0x0
        );
        vm.prank(address(MOCK_ASSERTER_ADDRESS));
        bytes32 assertionId = kpiManager.postAssertion();

        // state after
        assertEq(kpiManager.getStakingQueue().length, 0);
        assertEq(kpiManager.totalQueuedFunds(), 0);

        assertEq(feeToken.balanceOf(MOCK_ASSERTER_ADDRESS), 0);

        //check mock for posted data
        IOptimisticOracleIntegrator.DataAssertion memory assertion =
            kpiManager.getAssertion(assertionId);
        IKPIRewarder.RewardRoundConfiguration memory rewardRoundConfig =
            kpiManager.getAssertionConfig(assertionId);

        assertEq(assertion.dataId, MOCK_ASSERTION_DATA_ID);
        assertEq(assertion.data, MOCK_ASSERTION_DATA);
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

        uint totalUserFunds = setUpStakers(users, amounts);

        // prepare conditions
        createDummyIncontinuousKPI();

        kpiManager.prepareAssertion(
            MOCK_ASSERTION_DATA_ID,
            MOCK_ASSERTION_DATA,
            MOCK_ASSERTER_ADDRESS,
            100,
            0
        );

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
        bytes32 assertionId = kpiManager.postAssertion();

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

contract KPIRewarder_createKPITest is KPIRewarderTest {
    function test_RevertWhen_TheNumberOfTranchesIs0() external {
        // it should revert

        uint[] memory trancheValues;
        uint[] memory trancheRewards;

        vm.expectRevert(
            IKPIRewarder.Module__KPIRewarder__InvalidTrancheNumber.selector
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
            IKPIRewarder.Module__KPIRewarder__InvalidTrancheNumber.selector
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
                IKPIRewarder
                    .Module__KPIRewarder__InvalidKPIValueLengths
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
            IKPIRewarder.Module__KPIRewarder__InvalidKPITrancheValues.selector
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

        uint kpiNum =
            kpiManager.createKPI(continuous, trancheValues, trancheRewards);

        IKPIRewarder.KPI memory generatedKPI = kpiManager.getKPI(kpiNum);

        assertEq(generatedKPI.creationTime, block.timestamp);
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
setKPITest
├── when the KPI number is above the current KPI
│   └── it should revert
└── when the KPI number is among the existing KPIs
    └── it should change the activeKPI to the given KPI
*/

contract KPIRewarder_setKPITest is KPIRewarderTest {
    function test_RevertWhen_TheKPINumberIsAboveTheCurrentKPI(uint KPInum)
        external
    {
        // it should revert
        vm.assume(KPInum > kpiManager.KPICounter());

        vm.expectRevert(
            IKPIRewarder.Module__KPIRewarder__InvalidKPINumber.selector
        );
        kpiManager.setKPI(KPInum);
    }

    function test_WhenTheKPINumberIsAmongTheExistingKPIs(uint KPInum)
        external
    {
        for (uint i = 0; i < 5; i++) {
            createDummyIncontinuousKPI();
        }
        // it should change the activeKPI to the given KPI
        KPInum = bound(KPInum, 0, kpiManager.KPICounter() - 1);

        kpiManager.setKPI(KPInum);

        assertEq(kpiManager.activeKPI(), KPInum);
    }
}

/*
stakeTest
├── when the staked amount is 0
│   └── it should revert
├── when the length of the staking Queue is already at MAX_QUEUE_LENGTH
│   └── it should revert
├── when the caller does not have sufficient funds
│   └── it should revert
└── when the caller has sufficient funds
    └── it should store the amount + caller in the staking Queue and increase the value of totalQueuedFunds by the staked amount
*/
contract KPIRewarder_stakeTest is KPIRewarderTest {
    function test_RevertWhen_TheStakedAmountIs0() external {
        // it should revert

        stakingToken.mint(USER_1, 1000e18);
        vm.startPrank(USER_1);
        stakingToken.approve(address(kpiManager), 1000e18);
        vm.expectRevert(
            IERC20PaymentClient
                .Module__ERC20PaymentClient__InvalidAmount
                .selector
        );
        kpiManager.stake(0);
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
            IKPIRewarder.Module__KPIRewarder__StakingQueueIsFull.selector
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

contract KPIRewarder_assertionresolvedCallbackTest is KPIRewarderTest {
    function setUpStateForAssertionResolution(
        address[] memory users,
        uint[] memory amounts,
        uint valueToAssert,
        bool continuous
    ) public returns (bytes32 assertionId, uint totalUserFunds) {
        // it should stake all orders in the stakingQueue
        totalUserFunds = setUpStakers(users, amounts);

        // prepare conditions
        if (continuous) createDummyContinuousKPI();
        else createDummyIncontinuousKPI();

        kpiManager.prepareAssertion(
            MOCK_ASSERTION_DATA_ID,
            MOCK_ASSERTION_DATA,
            MOCK_ASSERTER_ADDRESS,
            valueToAssert,
            0
        );

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
            MOCK_ASSERTION_DATA,
            MOCK_ASSERTER_ADDRESS,
            0x0
        ); //we don't know the last one

        assertionId = kpiManager.postAssertion();
        vm.stopPrank();

        return (assertionId, totalUserFunds);
    }

    function test_WhenTheAssertionResolvedToFalse(
        address[] memory users,
        uint[] memory amounts
    ) external {
        // it should emit an event
        bytes32 createdID;
        uint totalStakedFunds;
        (createdID, totalStakedFunds) =
            setUpStateForAssertionResolution(users, amounts, 250, true);

        vm.startPrank(address(ooV3));
        vm.expectEmit(true, true, true, true, address(kpiManager));
        //vm.expectEmit(false, false, false, false);

        emit DataAssertionResolved(
            false,
            MOCK_ASSERTION_DATA_ID,
            MOCK_ASSERTION_DATA,
            MOCK_ASSERTER_ADDRESS,
            createdID
        );
        kpiManager.assertionResolvedCallback(createdID, false);
        vm.stopPrank();
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

        //vm.assume(users.length > 1);

        bytes32 createdID;
        uint totalStakedFunds;
        (createdID, totalStakedFunds) =
            setUpStateForAssertionResolution(users, amounts, 250, true);

        vm.startPrank(address(ooV3));

        vm.expectEmit(true, true, true, true, address(kpiManager));
        emit RewardSet(250e18, 1, 250e18, block.timestamp + 1);

        vm.expectEmit(true, true, true, true, address(kpiManager));
        emit DataAssertionResolved(
            true,
            MOCK_ASSERTION_DATA_ID,
            MOCK_ASSERTION_DATA,
            MOCK_ASSERTER_ADDRESS,
            createdID
        );

        kpiManager.assertionResolvedCallback(createdID, true);
        vm.stopPrank();

        vm.warp(block.timestamp + 3);

        uint length = users.length;
        if (length > kpiManager.MAX_QUEUE_LENGTH()) {
            length = kpiManager.MAX_QUEUE_LENGTH();
        }

        for (uint i; i < length; i++) {
            //uint userReward =
            //   ((200e18 * 1e18 * amounts[i]) / totalStakedFunds) / 1e18;
            uint userReward =
                kpiManager.estimateReward(kpiManager.balanceOf(users[i]), 1);
            console.log(userReward);

            //assertEq(kpiManager.balanceOf(users[i]), amounts[i]);
            assertEq(kpiManager.earned(users[i]), userReward);

            vm.prank(users[i]);
            kpiManager.unstake(amounts[i]);

            assertEq(kpiManager.balanceOf(users[i]), 0);
            assertEq(kpiManager.earned(users[i]), 0);
            assertEq(stakingToken.balanceOf(users[i]), amounts[i]);

            // NOTE TODO: CRITICAL ISSUE FOR THE INTEGRATION TEST: APPARENTLY THE REWARDS ARE NOT BEING SENT OUT
            // The internal accounting gets updated, but the reward in _token from the Manager does not get sent and fails silently along the way. This may be because of the mocks, but needs to be solved
            //assertEq(_token.balanceOf(users[i]), userReward);
        }
    }

    function test_WhenTheRewardTypeIsNotContinuous(
        address[] memory users,
        uint[] memory amounts
    ) external whenTheAssertionResolvedToTrue {
        // it should not pay out any amount from the uncompleted tranche at all

        bytes32 createdID;
        uint totalStakedFunds;
        (createdID, totalStakedFunds) =
            setUpStateForAssertionResolution(users, amounts, 250, false);

        vm.warp(block.timestamp + 5);

        vm.startPrank(address(ooV3));

        vm.expectEmit(true, true, true, true, address(kpiManager));
        emit RewardSet(200e18, 1, 200e18, block.timestamp + 1);

        vm.expectEmit(true, true, true, true, address(kpiManager));
        emit DataAssertionResolved(
            true,
            MOCK_ASSERTION_DATA_ID,
            MOCK_ASSERTION_DATA,
            MOCK_ASSERTER_ADDRESS,
            createdID
        );

        kpiManager.assertionResolvedCallback(createdID, true);
        vm.stopPrank();

        vm.warp(block.timestamp + 3);

        for (uint i; i < users.length; i++) {
            uint userReward =
                ((200e18 * 1e18 * amounts[i]) / totalStakedFunds) / 1e18;

            //assertEq(kpiManager.balanceOf(users[i]), amounts[i]);
            //assertEq(kpiManager.earned(users[i]), userReward);

            vm.prank(users[i]);
            kpiManager.unstake(amounts[i]);

            assertEq(kpiManager.balanceOf(users[i]), 0);
            assertEq(kpiManager.earned(users[i]), 0);
            assertEq(stakingToken.balanceOf(users[i]), amounts[i]);

            // TODO track created paymentOrder as subsititute for token payout (since we are using mocks)
            //assertEq(_token.balanceOf(users[i]), userReward);
        }
    }

    function test_RevertWhen_TheCallerIsNotOO(
        address[] memory users,
        uint[] memory amounts
    ) external {
        // it should not pay out any amount from the uncompleted tranche at all

        bytes32 createdID;
        uint totalStakedFunds;
        (createdID, totalStakedFunds) =
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
prepareAsertionTest
├── when the target KPI is not valid
│   └── it should revert
└── when the asserter targetValue is not valid
    └── it should revert
*/

contract KPIRewarder_setAssertionTest is KPIRewarderTest {
    function test_RevertWhen_TheTargetKPIIsNotValid() external {
        // it should revert
        vm.expectRevert(
            IKPIRewarder.Module__KPIRewarder__InvalidKPINumber.selector
        );
        kpiManager.prepareAssertion(
            MOCK_ASSERTION_DATA_ID,
            MOCK_ASSERTION_DATA,
            MOCK_ASSERTER_ADDRESS,
            100,
            99_999
        );
    }

    function test_RevertWhen_TheTargetValueIsNotValid() external {
        // it should revert
        vm.expectRevert(
            IKPIRewarder.Module__KPIRewarder__InvalidTargetValue.selector
        );
        kpiManager.prepareAssertion(
            MOCK_ASSERTION_DATA_ID,
            MOCK_ASSERTION_DATA,
            MOCK_ASSERTER_ADDRESS,
            0,
            0
        );
    }
}
