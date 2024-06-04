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

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

// SuT
import {
    LM_PC_Staking_v1,
    ILM_PC_Staking_v1,
    ReentrancyGuard,
    IERC20PaymentClientBase_v1
} from "@lm/LM_PC_Staking_v1.sol";

import {LM_PC_Staking_v1AccessMock} from
    "test/utils/mocks/modules/logicModules/LM_PC_Staking_v1AccessMock.sol";

// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

contract LM_PC_Staking_v1Test is ModuleTest {
    // SuT
    LM_PC_Staking_v1AccessMock stakingManager;

    ERC20Mock stakingToken = new ERC20Mock("Staking Mock Token", "STAKE MOCK");

    //Variables
    uint internal initialStakerMaxAmount = 100;
    uint internal tokenMultiplicator = 1e18;

    //Events

    event RewardSet(
        uint rewardAmount, uint duration, uint newRewardRate, uint newRewardsEnd
    );
    event Staked(address indexed user, uint amount);
    event Unstaked(address indexed user, uint amount);
    event RewardsDistributed(address indexed user, uint amount);

    function setUp() public {
        //Add Module to Mock Orchestrator
        address impl = address(new LM_PC_Staking_v1AccessMock());
        stakingManager = LM_PC_Staking_v1AccessMock(Clones.clone(impl));

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
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
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
                ILM_PC_Staking_v1
                    .Module__LM_PC_Staking_v1__InvalidDuration
                    .selector
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

    function testEstimateReward(
        uint seed,
        uint amount,
        uint duration,
        uint warp
    ) public {
        amount = bound(amount, 1, 1_000_000_000 * tokenMultiplicator);
        duration = bound(duration, 1, 31_536_000_000);

        //Set up reasonable stakers
        setUpReasonableStakers(seed);

        //Set up reasonable rewards
        stakingManager.setRewards(
            bound(seed, 1, 10_000) * 30 days, //This guarantees that 1 to 10_000 tokesn per second are distributed
            30 days
        );

        //There is a chance that the warp is higher than the reward period
        vm.warp(bound(warp, 0, 35 days));

        uint rewardRate = stakingManager.rewardRate();
        uint totalSupply = stakingManager.totalSupply();

        if (block.timestamp > stakingManager.rewardsEnd()) {
            //Assume that calculated reward is 0
            assertEq(0, stakingManager.estimateReward(amount, duration));
        } else {
            uint calculatedEstimation;

            //If duration went over rewardsend
            if (block.timestamp + duration > stakingManager.rewardsEnd()) {
                //Change duration so that it goes until rewardsend
                duration = stakingManager.rewardsEnd() - block.timestamp;
            }

            if (totalSupply == 0) {
                calculatedEstimation = amount * duration * rewardRate;
            } else {
                calculatedEstimation =
                    amount * duration * rewardRate / totalSupply;
            }

            assertEq(
                calculatedEstimation,
                stakingManager.estimateReward(amount, duration)
            );
        }
    }

    function testEstimateRewardModifierInPosition() public {
        //validAmount
        vm.expectRevert(
            IERC20PaymentClientBase_v1
                .Module__ERC20PaymentClientBase__InvalidAmount
                .selector
        );

        stakingManager.estimateReward(0, 1);

        //validDuration
        vm.expectRevert(
            ILM_PC_Staking_v1.Module__LM_PC_Staking_v1__InvalidDuration.selector
        );

        stakingManager.estimateReward(1, 0);
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
        uint stakeAmount =
            bound(seed, tokenMultiplicator, 1_000_000_000 * tokenMultiplicator);

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
            IERC20PaymentClientBase_v1
                .Module__ERC20PaymentClientBase__InvalidAmount
                .selector
        );

        stakingManager.stake(0);

        //Check for reentrancy

        //Set it so that the stakingToken does a reentrancy call on the stakingManager
        stakingToken.setReentrancyOnTransfer(
            abi.encodeWithSignature("stake(uint256)", 1)
        );

        //Mint to user
        stakingToken.mint(address(0xBeef), 1);

        //Approve
        vm.prank(address(0xBeef));
        stakingToken.approve(address(stakingManager), 1);

        vm.prank(address(0xBeef));
        stakingManager.stake(1);

        //Check if the call failed
        assertFalse(stakingToken.callSuccessful());

        //Check if return error was correct
        assertEq(
            abi.encodeWithSelector(
                ReentrancyGuard.ReentrancyGuardReentrantCall.selector
            ),
            stakingToken.callData()
        );
    }

    //-----------------------------------------
    //unstake

    function testUnstake(uint seed, uint unstakeSeed, address staker) public {
        if (staker == address(0) || staker == address(stakingManager)) {
            staker = address(uint160(1));
        }

        //Set up reasonable rewards
        setUpReasonableRewards(seed);

        //Fund orchestrator
        _token.mint(address(_fundingManager), 12_960_000);

        //reasonable stake amount
        uint stakeAmount =
            bound(seed, tokenMultiplicator, 1_000_000_000 * tokenMultiplicator);

        //reasonable withdraw amount
        uint unstakeAmount = bound(unstakeSeed, tokenMultiplicator, stakeAmount);

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
        emit Unstaked(staker, unstakeAmount);

        //Withdraw
        vm.prank(staker);
        stakingManager.unstake(unstakeAmount);

        //Check _distributeRewards() is triggered
        if (expectedEarnings != 0) {
            assertEq(expectedEarnings, stakingManager.paymentOrders()[0].amount);
        }

        assertEq(prevBalance - unstakeAmount, stakingManager.balanceOf(staker));
        assertEq(prevTotalAmount - unstakeAmount, stakingManager.totalSupply());
        assertEq(
            stakingToken.balanceOf(address(stakingManager)),
            stakingManager.totalSupply()
        );
    }

    function testUnstakeModifierInPosition() public {
        //validAmount
        vm.expectRevert(
            IERC20PaymentClientBase_v1
                .Module__ERC20PaymentClientBase__InvalidAmount
                .selector
        );

        stakingManager.unstake(0);

        //Check for reentrancy

        //Set it so that the stakingToken does a reentrancy call on the stakingManager
        stakingToken.setReentrancyOnTransfer(
            abi.encodeWithSignature("stake(uint256)", 1)
        );

        //Warp time appropriately
        vm.warp(365 days);

        //Fund orchestrator
        _token.mint(address(_fundingManager), 12_960_000);

        //Set up reasonable rewards
        setUpReasonableRewards(0);

        //Mint to user
        stakingToken.mint(address(0xBeef), 1);

        //Approve
        vm.prank(address(0xBeef));
        stakingToken.approve(address(stakingManager), 1);

        //Stake tokens
        vm.prank(address(0xBeef));
        stakingManager.stake(1);

        //Warp so staker would get rewarded
        vm.warp(block.timestamp + 1 days);

        vm.prank(address(0xBeef));
        stakingManager.unstake(1);

        //Check if the call failed
        assertFalse(stakingToken.callSuccessful());

        //Check if return error was correct
        assertEq(
            abi.encodeWithSelector(
                ReentrancyGuard.ReentrancyGuardReentrantCall.selector
            ),
            stakingToken.callData()
        );
    }

    function testSetRewards(
        uint seed,
        uint amount,
        uint duration,
        uint secondAmount,
        uint secondDuration
    ) public {
        duration = bound(duration, 1, 365 days);
        amount = bound(amount, 1, 1_000_000_000_000_000 * tokenMultiplicator);

        secondAmount =
            bound(secondAmount, 1, 1_000_000_000_000_000 * tokenMultiplicator);
        secondDuration = bound(secondDuration, 1, 365 days);

        //Intial timestamp cant be 0
        //Warp the chain by a reasonable amount
        vm.warp(bound(seed, 1 days, 30 days));

        uint expectedRewardRate = calculateRewardRate(amount, duration, 0, 0);
        uint expectedRewardsEnd = block.timestamp + duration;

        if (expectedRewardRate == 0) {
            vm.expectRevert(
                ILM_PC_Staking_v1
                    .Module__LM_PC_Staking_v1__InvalidRewardRate
                    .selector
            );
            stakingManager.setRewards(amount, duration);
            //No need to test further, because the rest of the unit test doesnt make sense otherwise
            return;
        }

        vm.expectEmit(true, true, true, true);
        emit RewardSet(amount, duration, expectedRewardRate, expectedRewardsEnd);

        stakingManager.setRewards(amount, duration);

        assertEq(expectedRewardRate, stakingManager.rewardRate());
        assertEq(expectedRewardsEnd, stakingManager.rewardsEnd());

        //Test when rewards were already set

        //Warp the chain by a reasonable amount, but reward period should still be active
        vm.warp(bound(seed, 0, duration - 1) + block.timestamp);

        expectedRewardRate = calculateRewardRate(
            secondAmount, secondDuration, expectedRewardsEnd, expectedRewardRate
        );
        expectedRewardsEnd = block.timestamp + secondDuration;

        if (expectedRewardRate == 0) {
            vm.expectRevert(
                ILM_PC_Staking_v1
                    .Module__LM_PC_Staking_v1__InvalidRewardRate
                    .selector
            );
            stakingManager.setRewards(secondAmount, secondDuration);
            //No need to test further, because the rest of the unit test doesnt make sense otherwise
            return;
        }

        vm.expectEmit(true, true, true, true);
        emit RewardSet(
            secondAmount, secondDuration, expectedRewardRate, expectedRewardsEnd
        );

        stakingManager.setRewards(secondAmount, secondDuration);

        assertEq(expectedRewardRate, stakingManager.rewardRate());
        assertEq(expectedRewardsEnd, stakingManager.rewardsEnd());
    }

    function testSetRewardsModifierInPosition() public {
        //onlyOrchestratorOwnerOrManager
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector,
                _authorizer.getOwnerRole(),
                address(0xBEEF)
            )
        );

        vm.prank(address(0xBEEF));
        stakingManager.setRewards(1, 1);

        //validAmount
        vm.expectRevert(
            IERC20PaymentClientBase_v1
                .Module__ERC20PaymentClientBase__InvalidAmount
                .selector
        );

        stakingManager.setRewards(0, 1);

        //validDuration
        vm.expectRevert(
            ILM_PC_Staking_v1.Module__LM_PC_Staking_v1__InvalidDuration.selector
        );

        stakingManager.setRewards(1, 0);
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

    function test_distributeRewards(uint seed) public {
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
        IERC20PaymentClientBase_v1.PaymentOrder[] memory orders =
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
            stakeAmount = bound(
                seed, tokenMultiplicator, 1_000_000_000 * tokenMultiplicator
            );
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
        uint tokens = bound(
            seed,
            12_960_000, //Thats 5 tokens per second
            1e22 * 12_960_000 //Thats 5000 tokens per second
        );
        //Set up reasonable rewards
        stakingManager.setRewards(tokens, 1 seconds);
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

    function calculateRewardRate(
        uint amount,
        uint duration,
        uint rewardsEnd,
        uint alreadyExistingRewardRate
    ) internal view returns (uint) {
        if (block.timestamp >= rewardsEnd) {
            return amount / duration;
        } else {
            //Calculate remaind rewards supposed to go into the pool
            uint remainingRewards =
                (rewardsEnd - block.timestamp) * alreadyExistingRewardRate;
            //Add new Amount to previous amount and calculate rate
            return (amount + remainingRewards) / duration;
        }
    }
}
