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

    function testStake(uint seed, address staker) public {
        //Set up reasonable stakers
        setUpReasonableStakers(seed);

        //Set up reasonable rewards
        setUpReasonableRewards(seed);
        //Fund orchestrator
        _token.mint(address(_fundingManager), 12_960_000);

        if (staker == address(0)) {
            staker = address(uint160(1));
        }

        //reasonable stake amount
        uint stakeAmount = bound(seed, 1, 1_000_000_000_000 * 1e18);

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

        //Check _distributeRewards()
        assertEq(expectedEarnings, _token.balanceOf(staker));

        assertEq(prevBalance + stakeAmount, stakingManager.balanceOf(staker));
        assertEq(prevTotalAmount + stakeAmount, stakingManager.totalSupply());
        assertEq(
            stakingToken.balanceOf(address(stakingManager)),
            stakingManager.totalSupply()
        );
    }

    function testStakeModifierInPosition() public {
        /* vm.expectRevert(
            IStakingManager.Module__StakingManager__InvalidDuration.selector
        ); */

        //Module__ERC20PaymentClient__InvalidAmount
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    function test_update(uint seed, address trigger) public {
        //Set up reasonable stakers
        setUpReasonableStakers(seed);
        //Set up reasonable rewards
        setUpReasonableRewards(seed);

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

    // =========================================================================

    //--------------------------------------------------------------------------
    // Helper

    function setUpReasonableStakers(uint seed) internal {
        //Warp the chain to a reasonable amount
        vm.warp(bound(seed, 1 days, 365 days));

        //Set up stakers
        //randomise amount of stakers
        uint stakerAmount = bound(seed, 0, 100);

        uint stakeAmount;
        uint stakerNumber = 1;
        for (uint i = 0; i < stakerAmount; i++) {
            //randomise amount staked
            stakeAmount = bound(seed, 1, 1_000_000_000_000 * 1e18);
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

        //Warp the chain by a reasonable amount
        vm.warp(bound(seed, 0, 30 days) + block.timestamp);
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
