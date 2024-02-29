// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {E2eTest} from "test/e2e/E2eTest.sol";
import "forge-std/console.sol";

//Internal Dependencies
import {ModuleTest, IModule, IOrchestrator} from "test/modules/ModuleTest.sol";
import {IOrchestratorFactory} from "src/factories/OrchestratorFactory.sol";
import {AuthorizerMock} from "test/utils/mocks/modules/AuthorizerMock.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

import {RebasingFundingManager} from
    "src/modules/fundingManager/RebasingFundingManager.sol";
// SuT
import {
    StakingManager,
    IStakingManager
} from "src/modules/logicModule/StakingManager.sol";

// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

contract StakingManagerLifecycle is E2eTest {
    // Let's create a list of staker
    address staker1 = makeAddr("staker1");
    address staker2 = makeAddr("staker 2");
    address staker3 = makeAddr("staker 3");
    address staker4 = makeAddr("staker 4");

    // Parameters for distributed rewards
    //lets do multiple ones
    uint duration1 = 1 weeks;
    uint amount1 = 10 * 1 weeks; //This should represent 10 tokens per second -> 10 * 1 weeks / 1 weeks = 10
    uint duration2 = 4 weeks;
    uint amount2 = 20 * 4 weeks; //This should represent 10 tokens per second -> 10 * 1 weeks / 1 weeks = 10
    uint duration3 = 2 weeks;
    uint amount3 = 40 * 2 weeks; //This should represent 10 tokens per second -> 10 * 1 weeks / 1 weeks = 10

    // Constants

    ERC20Mock rewardToken = new ERC20Mock("Mock", "MOCK");
    ERC20Mock stakingToken = new ERC20Mock("Mock", "MOCK");

    function test_e2e_StakingManagerLifecycle() public {
        StakingManager stakingManager;

        // -----------INIT
        // address(this) creates a new orchestrator.
        IOrchestratorFactory.OrchestratorConfig memory orchestratorConfig =
        IOrchestratorFactory.OrchestratorConfig({
            owner: address(this),
            token: rewardToken
        });

        IOrchestrator orchestrator =
        _createNewOrchestratorWithAllModules_StakingManager(
            orchestratorConfig, address(stakingToken)
        );

        RebasingFundingManager fundingManager =
            RebasingFundingManager(address(orchestrator.fundingManager()));

        // ------------------ FROM ModuleTest.sol
        address[] memory modulesList = orchestrator.listModules();
        for (uint i; i < modulesList.length; ++i) {
            try IStakingManager(modulesList[i]).earned(address(1)) returns (
                uint
            ) {
                stakingManager = StakingManager(modulesList[i]);
                break;
            } catch {
                continue;
            }
        }

        //Warp to reasonable time
        vm.warp(52 weeks);

        // ----------------

        // 1. deopsit some funds to fundingManager
        uint initialDeposit = amount1 + amount2 + amount3 * 2;
        rewardToken.mint(address(this), initialDeposit);
        rewardToken.approve(address(fundingManager), initialDeposit);
        fundingManager.deposit(initialDeposit);

        // 2. fund the stakers
        stakingToken.mint(address(staker1), 10);
        stakingToken.mint(address(staker2), 10);
        stakingToken.mint(address(staker3), 5);
        stakingToken.mint(address(staker4), 10);

        // 3. Approve that stakingManager can use stakingToken
        vm.prank(staker1);
        stakingToken.approve(address(stakingManager), 10);
        vm.prank(staker2);
        stakingToken.approve(address(stakingManager), 10);
        vm.prank(staker3);
        stakingToken.approve(address(stakingManager), 5);
        vm.prank(staker4);
        stakingToken.approve(address(stakingManager), 10);

        // 4. Set up reward period 1

        stakingManager.setRewards(amount1, duration1);

        // 5. Stake some for stakers 1 and 2
        vm.prank(staker1);
        stakingManager.stake(10);

        vm.prank(staker2);
        stakingManager.stake(10);

        //Value staked  |   Value earned            |   Rewards claimed
        //Staker 1:10   |   Staker 1:               |   Staker 1:
        //Staker 2:10   |   Staker 2:               |   Staker 2:
        //Staker 3:     |   Staker 3:               |   Staker 3:
        //Staker 4:     |   Staker 4:               |   Staker 4:

        //Check if values are accurate

        // 6. Warp time to end it

        vm.warp(block.timestamp + duration1);

        // 7. Withdraw for Staker 2
        vm.prank(staker2);
        stakingManager.unstake(10);

        //Value staked  |   Value earned            |   Rewards claimed
        //Staker 1:10   |   Staker 1: 1/2 amount1   |   Staker 1:
        //Staker 2:     |   Staker 2:               |   Staker 2: 1/2 amount1
        //Staker 3:     |   Staker 3:               |   Staker 3:
        //Staker 4:     |   Staker 4:               |   Staker 4:

        //Check if values are accurate
        assertEq(amount1 / 2, stakingManager.earned(staker1));
        assertEq(amount1 / 2, rewardToken.balanceOf(staker2));

        // 8. Set up reward period 2

        stakingManager.setRewards(amount2, duration2);

        // 9. Warp time to halve

        vm.warp(block.timestamp + duration2 / 2);

        //Value staked  |   Value earned            |   Rewards claimed
        //Staker 1:10   |   Staker 1: 1/2 amount1 + 1/2 amount2   |   Staker 1:
        //Staker 2:     |   Staker 2:               |   Staker 2: 1/2 amount1
        //Staker 3:     |   Staker 3:               |   Staker 3:
        //Staker 4:     |   Staker 4:               |   Staker 4:

        //Check if values are accurate
        assertEq(amount1 / 2 + amount2 / 2, stakingManager.earned(staker1));

        // 10. Let staker 3 and 4 into it

        vm.prank(staker3);
        stakingManager.stake(5);

        vm.prank(staker4);
        stakingManager.stake(5);

        //Value staked  |   Value earned                        |   Rewards claimed
        //Staker 1:10   |   Staker 1: 1/2 amount1 + 1/2 amount2 |   Staker 1:
        //Staker 2:     |   Staker 2:                           |   Staker 2: 1/2 amount1
        //Staker 3: 5   |   Staker 3:                           |   Staker 3:
        //Staker 4: 5   |   Staker 4:                           |   Staker 4:

        // 11. Finish it

        vm.warp(block.timestamp + duration2 / 2);

        // 12. Let 3 withdraw

        vm.prank(staker3);
        stakingManager.unstake(5);

        //Value staked  |   Value earned                        |   Rewards claimed
        //Staker 1:10   |   Staker 1: 1/2 amount1 + 3/4 amount2 |   Staker 1:
        //Staker 2:     |   Staker 2:                           |   Staker 2: 1/2 amount1
        //Staker 3:     |   Staker 3:                           |   Staker 3: 1/8 amount2
        //Staker 4: 5   |   Staker 4: 1/8 amount2               |   Staker 4:

        //Check if values are accurate
        assertEq(amount1 / 2 + amount2 * 3 / 4, stakingManager.earned(staker1));
        assertEq(amount2 * 1 / 8, rewardToken.balanceOf(staker3));
        assertEq(amount2 * 1 / 8, stakingManager.earned(staker4));

        // 13. Let 4 stake more

        vm.prank(staker4);
        stakingManager.stake(5);

        //Value staked  |   Value earned                        |   Rewards claimed
        //Staker 1:10   |   Staker 1: 1/2 amount1 + 3/4 amount2 |   Staker 1:
        //Staker 2:     |   Staker 2:                           |   Staker 2: 1/2 amount1
        //Staker 3:     |   Staker 3:                           |   Staker 3: 1/8 amount2
        //Staker 4: 10  |   Staker 4:                           |   Staker 4: 1/8 amount2

        //Check if values are accurate
        assertEq(amount2 * 1 / 8, rewardToken.balanceOf(staker4));

        // 14. Set up reward period 3

        stakingManager.setRewards(amount3, duration3);

        //Use case: The reward period wasnt long enough
        //Extend it by setting up reward period 3 again

        stakingManager.setRewards(amount3, duration3);

        // 15. Warp time to end it
        //Because the amount and the duration get added on top of each other we need to duble the duration to get the end of the reward period
        vm.warp(block.timestamp + duration3 * 2);

        //Value staked  |   Value earned                                        |   Rewards claimed
        //Staker 1:10   |   Staker 1: 1/2 amount1 + 3/4 amount2 + 1 amount3     |   Staker 1:
        //Staker 2:     |   Staker 2:                                           |   Staker 2: 1/2 amount1
        //Staker 3:     |   Staker 3:                                           |   Staker 3: 1/8 amount2
        //Staker 4: 10  |   Staker 4: 1 amount3                                 |   Staker 4: 1/8 amount2

        assertEq(
            amount1 / 2 + amount2 * 3 / 4 + amount3,
            stakingManager.earned(staker1)
        );
        assertEq(amount3, stakingManager.earned(staker4));

        // 16. Let 1 withdraw half and 4 withdraw full

        vm.prank(staker1);
        stakingManager.unstake(5);

        vm.prank(staker4);
        stakingManager.unstake(10);

        //Value staked  |   Value earned    |   Rewards claimed
        //Staker 1: 5   |   Staker 1:       |   Staker 1: 1/2 amount1 + 3/4 amount2 + 1 amount3
        //Staker 2:     |   Staker 2:       |   Staker 2: 1/2 amount1
        //Staker 3:     |   Staker 3:       |   Staker 3: 1/8 amount2
        //Staker 4:     |   Staker 4:       |   Staker 4: 1/8 amount2 + 1 amount3

        //Check if values are accurate

        assertEq(5, stakingManager.balanceOf(staker1));
        assertEq(
            amount1 / 2 + amount2 * 3 / 4 + amount3,
            rewardToken.balanceOf(staker1)
        );
        assertEq(amount2 * 1 / 8 + amount3, rewardToken.balanceOf(staker4));
    }
}