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
    StakingManager,
    IStakingManager,
    IERC20PaymentClient
} from "src/modules/logicModule/StakingManager.sol";

import {StakingManagerAccessMock} from
    "test/utils/mocks/modules/logicModules/StakingManagerAccessMock.sol";

// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

contract StakingManagerTest is ModuleTest {
    // SuT
    StakingManagerAccessMock stakingManager;

    ERC20Mock stakingToken = new ERC20Mock("Staking Mock Token", "STAKE MOCK");

    //Variables
    uint internal initialStakerMaxAmount = 100;

    //Events

    event RewardSet(
        uint rewardAmount, uint duration, uint newRewardRate, uint newRewardsEnd
    );
    event RewardsDurationUpdated(uint newDuration);
    event Staked(address indexed user, uint amount);
    event Withdrawn(address indexed user, uint amount);
    event RewardsDistributed(address indexed user, uint amount);

    function setUp() public {
        //Add Module to Mock Orchestrator
        address impl = address(new StakingManagerAccessMock());
        stakingManager = StakingManagerAccessMock(Clones.clone(impl));

        _setUpOrchestrator(stakingManager);
        _authorizer.setIsAuthorized(address(this), true);

        stakingManager.init(
            _orchestrator, _METADATA, abi.encode(address(stakingToken))
        );
    }

    //--------------------------------------------------------------------------
    // Test: Initialization

    //This function also tests all the getters
    function testInit() public override(ModuleTest) {
        assertEq(address(stakingToken), stakingManager.stakingToken());
    }

    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__AlreadyInitialized);
        stakingManager.init(
            _orchestrator, _METADATA, abi.encode(address(stakingToken))
        );
    }

    //--------------------------------------------------------------------------
    // Modifier

    function testValidDuration(uint duration) public {
        duration = bound(duration, 0, 31_536_000_000); //31536000000 = 1000 years in seconds
        if (duration == 0) {
            vm.expectRevert(
                IStakingManager.Module__StakingManager__InvalidDuration.selector
            );
        }
        stakingManager.setRewards(type(uint).max, duration);
    }

    //--------------------------------------------------------------------------
    // Getter

    function testEarned(uint seed) public {
        //Set up reasonable stakers
        setUpReasonableStakers(seed);

        address user = address(uint160(1)); //Addresslikely to have stake in setUpReasonableStakers()
        uint providedRewardValue = stakingManager.direct_calculateRewardValue();
        uint userRewardValue = stakingManager.getRewards(user);
        uint userBalance = stakingManager.balanceOf(user);
        uint previousUserRewards = stakingManager.getRewards(user);

        uint calculatedEarnings = calculateEarned(
            providedRewardValue,
            userRewardValue,
            userBalance,
            previousUserRewards
        );

        assertEq(calculatedEarnings, stakingManager.earned(user));
    }

    //--------------------------------------------------------------------------
    // Mutating Functions

    //-----------------------------------------
    //stake

    function testStake(uint seed) public {
        //Set up reasonable stakers
        setUpReasonableStakers(seed);

        //Because we potentially want to introduce a user that already staked I randomise a address that has a chance to already be a staker from the setUpReasonableStakers() function
        address staker =
            address(uint160(bound(seed, 1, initialStakerMaxAmount + 1)));

        //Set up reasonable rewards
        setUpReasonableRewards(seed);

        //Fund orchestrator
        _token.mint(address(_fundingManager), 12_960_000);

        if (staker == address(0)) {
            staker = address(uint160(1));
        }

        //reasonable stake amount
        uint stakeAmount = bound(seed, 1e18, 1_000_000_000 * 1e18);

        //Mint to user
        stakingToken.mint(staker, stakeAmount);

        //Approve usage
        vm.prank(staker);
        stakingToken.approve(address(stakingManager), stakeAmount);

        uint prevTotalAmount = stakingManager.totalSupply();
        uint prevBalance = stakingManager.balanceOf(staker);
        uint expectedEarnings = stakingManager.earned(staker);

        vm.expectEmit(true, true, true, true);
        emit Staked(staker, stakeAmount);

        vm.prank(staker);
        stakingManager.stake(stakeAmount);

        //Check _distributeRewards() is triggered
        if (expectedEarnings != 0) {
            assertEq(expectedEarnings, stakingManager.paymentOrders()[0].amount);
        }

        assertEq(prevBalance + stakeAmount, stakingManager.balanceOf(staker));
        assertEq(prevTotalAmount + stakeAmount, stakingManager.totalSupply());
        assertEq(
            stakingToken.balanceOf(address(stakingManager)),
            stakingManager.totalSupply()
        );
    }

    function testStakeModifierInPosition() public {
        //validAmount
        vm.expectRevert(
            IERC20PaymentClient
                .Module__ERC20PaymentClient__InvalidAmount
                .selector
        );

        stakingManager.stake(0);

        //@todo How to test nonReentrant?
    }

    //-----------------------------------------
    //withdraw

    function testWithdraw(uint seed, uint withdrawSeed, address staker)
        public
    {
        if (staker == address(0)) {
            staker = address(uint160(1));
        }

        //Set up reasonable rewards
        setUpReasonableRewards(seed);

        //Fund orchestrator
        _token.mint(address(_fundingManager), 12_960_000);

        //reasonable stake amount
        uint stakeAmount = bound(seed, 1e18, 1_000_000_000 * 1e18);

        //reasonable withdraw amount
        uint withdrawAmount = bound(withdrawSeed, 1e18, stakeAmount);

        //Mint to user
        stakingToken.mint(staker, stakeAmount);

        //Approve usage
        vm.prank(staker);
        stakingToken.approve(address(stakingManager), stakeAmount);

        //Stake
        vm.prank(staker);
        stakingManager.stake(stakeAmount);

        //Warp the chain by a reasonable amount
        vm.warp(bound(seed, 1 days, 30 days) + block.timestamp);

        uint prevTotalAmount = stakingManager.totalSupply();
        uint prevBalance = stakingManager.balanceOf(staker);
        uint expectedEarnings = stakingManager.earned(staker);

        vm.expectEmit(true, true, true, true);
        emit Withdrawn(staker, withdrawAmount);

        //Withdraw
        vm.prank(staker);
        stakingManager.withdraw(withdrawAmount);

        //Check _distributeRewards() is triggered
        if (expectedEarnings != 0) {
            assertEq(expectedEarnings, stakingManager.paymentOrders()[0].amount);
        }

        assertEq(prevBalance - withdrawAmount, stakingManager.balanceOf(staker));
        assertEq(prevTotalAmount - withdrawAmount, stakingManager.totalSupply());
        assertEq(
            stakingToken.balanceOf(address(stakingManager)),
            stakingManager.totalSupply()
        );
    }

    function testWithdrawModifierInPosition() public {
        //validAmount
        vm.expectRevert(
            IERC20PaymentClient
                .Module__ERC20PaymentClient__InvalidAmount
                .selector
        );

        stakingManager.withdraw(0);

        //@todo How to test nonReentrant?
        //internal set true
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    function test_update(uint seed, address trigger) public {
        //Set up reasonable stakers
        setUpReasonableStakers(seed);
        //Set up reasonable rewards
        setUpReasonableRewards(seed);
        //Warp the chain by a reasonable amount
        vm.warp(bound(seed, 1 days, 30 days) + block.timestamp);

        uint expectedRewards;
        uint expectedUserRewardValue;
        if (trigger != address(0)) {
            expectedRewards = stakingManager.getRewards(trigger)
                + stakingManager.earned(trigger);

            expectedUserRewardValue =
                stakingManager.direct_calculateRewardValue();
        }

        stakingManager.direct_update(trigger);

        //Check that values changed
        assertEq(
            stakingManager.direct_calculateRewardValue(), //works because time between last update and RewardDistributionTimestamp value is 0 and therefor just returns the older rewardValue
            stakingManager.getRewardValue()
        );
        assertEq(stakingManager.getLastUpdate(), stakingManager.getLastUpdate());

        if (trigger != address(0)) {
            assertEq(expectedRewards, stakingManager.getRewards(trigger));
            assertEq(
                expectedUserRewardValue,
                stakingManager.getUserRewardValue(trigger)
            );
        }
    }

    function test_calculateRewardValue(uint seed) public {
        //Set up reasonable stakers
        setUpReasonableStakers(seed);

        uint rewardDistributionTimestamp =
            stakingManager.direct_getRewardDistributionTimestamp();
        uint lastUpdate = stakingManager.getLastUpdate();
        uint rewardRate = stakingManager.rewardRate();
        uint totalSupply = stakingManager.totalSupply();
        uint rewardValue = stakingManager.getRewardValue();

        uint calculatedRewardValue = calculateRewardValue(
            rewardDistributionTimestamp,
            lastUpdate,
            rewardRate,
            totalSupply,
            rewardValue
        );

        assertEq(
            calculatedRewardValue, stakingManager.direct_calculateRewardValue()
        );
    }

    function test_getRewardDistributionTimestamp(uint seed) public {
        //Set up reasonable stakers
        setUpReasonableStakers(seed);

        uint newRewardsEnd = bound(seed, 1 days, 2 * 365 days); //setUpReasonableStakers() sets the current timestamp to some value between 1 day to 365 days.
        stakingManager.setRewardsEnd(newRewardsEnd);

        uint estimatedValue;
        if (newRewardsEnd >= block.timestamp) {
            estimatedValue = block.timestamp;
        } else {
            estimatedValue = newRewardsEnd;
        }
        assertEq(
            estimatedValue,
            stakingManager.direct_getRewardDistributionTimestamp()
        );
    }

    function test__distributeRewards(uint seed) public {
        //Warp the chain to a reasonable amount
        vm.warp(bound(seed, 1 days, 365 days));

        //fund orchestrator
        _token.mint(address(_fundingManager), 12_960_000);

        address user = address(uint160(1));

        //Mint to user
        stakingToken.mint(user, 1);

        //User stakes
        vm.startPrank(user);

        stakingToken.approve(address(stakingManager), 1);
        stakingManager.stake(1);

        vm.stopPrank();

        //Set up reasonable rewards
        setUpReasonableRewards(seed);

        //Warp the chain by a reasonable amount
        vm.warp(bound(seed, 1 days, 30 days) + block.timestamp);

        uint expectedPayout = stakingManager.earned(user);

        //For earned to work update had to be triggered
        stakingManager.direct_update(user);

        vm.expectEmit(true, true, true, true);
        emit RewardsDistributed(user, expectedPayout);

        stakingManager.direct_distributeRewards(user);

        //rewards are reset
        assertEq(0, stakingManager.getRewards(user));

        //Expect paymentOrder to be correct
        IERC20PaymentClient.PaymentOrder[] memory orders =
            stakingManager.paymentOrders();

        assertEq(1, orders.length);
        assertEq(user, orders[0].recipient);
        assertEq(expectedPayout, orders[0].amount);
        assertEq(block.timestamp, orders[0].createdAt);
        assertEq(block.timestamp, orders[0].dueTo);

        //Make sure payment Processor was triggered
        assertEq(1, _paymentProcessor.processPaymentsTriggered());
    }

    // =========================================================================

    //--------------------------------------------------------------------------
    // Helper

    function setUpReasonableStakers(uint seed) internal {
        //Warp the chain to a reasonable amount
        vm.warp(bound(seed, 1 days, 365 days));

        //Set up stakers
        //randomise amount of stakers
        uint stakerAmount = bound(seed, 0, initialStakerMaxAmount);

        uint stakeAmount;
        uint stakerNumber = 1;
        for (uint i = 0; i < stakerAmount; i++) {
            //randomise amount staked
            stakeAmount = bound(seed, 1e18, 1_000_000_000 * 1e18); //@todo 1e18 should be a variable so it can be changed properly
            //Mint to users
            stakingToken.mint(address(uint160(stakerNumber)), stakeAmount);

            //Users stake
            vm.startPrank(address(uint160(stakerNumber)));

            stakingToken.approve(address(stakingManager), stakeAmount);
            stakingManager.stake(stakeAmount);

            vm.stopPrank();

            //Increase stakerNumber to get a different address
            stakerNumber++;

            //Change seed to increase randomness
            unchecked {
                seed -= stakeAmount;
            }
        }
    }

    function setUpReasonableRewards(uint seed) internal {
        //Set up reasonable rewards
        stakingManager.setRewards(12_960_000, 30 days); //Thats 5 tokens per second
    }

    function calculateEarned(
        uint providedRewardValue,
        uint userRewardValue,
        uint userBalance,
        uint previousUserRewards
    ) internal pure returns (uint) {
        return (providedRewardValue - userRewardValue) * userBalance / 1e18
            + previousUserRewards;
    }

    function calculateRewardValue(
        uint rewardDistributionTimestamp,
        uint lastUpdate,
        uint rewardRate,
        uint totalSupply,
        uint rewardValue
    ) internal pure returns (uint) {
        if (totalSupply == 0) {
            return rewardValue;
        }

        return (rewardDistributionTimestamp - lastUpdate) * rewardRate * 1e18
            / totalSupply + rewardValue;
    }
}
