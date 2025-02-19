// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {E2ETest} from "test/e2e/E2ETest.sol";
import "forge-std/console.sol";

// Internal Dependencies
import {
    ModuleTest,
    IModule_v1,
    IOrchestrator_v1
} from "test/modules/ModuleTest.sol";
import {IOrchestratorFactory_v1} from "src/factories/OrchestratorFactory_v1.sol";
import {AuthorizerV1Mock} from "test/utils/mocks/modules/AuthorizerV1Mock.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

import {FM_Rebasing_v1} from
    "src/modules/fundingManager/rebasing/FM_Rebasing_v1.sol";
// SuT
import {LM_PC_Staking_v1, ILM_PC_Staking_v1} from "@lm/LM_PC_Staking_v1.sol";

// Mocks
// import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";
import {ERC20Mock} from
    "test/modules/fundingManager/rebasing/utils/mocks/ERC20Mock.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

contract LM_PC_Staking_v1Lifecycle is E2ETest {
    using SafeERC20 for ERC20Mock;

    // Module Configurations for the current E2E test. Should be filled during setUp() call.
    IOrchestratorFactory_v1.ModuleConfig[] moduleConfigurations;

    // Let's create a list of staker
    address staker1 = makeAddr("staker1");
    address staker2 = makeAddr("staker 2");
    address staker3 = makeAddr("staker 3");
    address staker4 = makeAddr("staker 4");

    // Parameters for distributed rewards
    // lets do multiple ones
    uint duration1 = 1 weeks;
    uint amount1 = 10 * 1 weeks; // This should represent 10 tokens per second -> 10 * 1 weeks / 1 weeks = 10
    uint duration2 = 4 weeks;
    uint amount2 = 20 * 4 weeks; // This should represent 10 tokens per second -> 10 * 1 weeks / 1 weeks = 10
    uint duration3 = 2 weeks;
    uint amount3 = 40 * 2 weeks; // This should represent 10 tokens per second -> 10 * 1 weeks / 1 weeks = 10

    // Constants

    ERC20Mock rewardToken = new ERC20Mock("Reward Mock", "R_MOCK");
    ERC20Mock stakingToken = new ERC20Mock("Staking Mock", "S_MOCK");

    function setUp() public override {
        vm.label({
            account: address(rewardToken),
            newLabel: ERC20Mock(address(rewardToken)).symbol()
        });
        vm.label({
            account: address(stakingToken),
            newLabel: ERC20Mock(address(stakingToken)).symbol()
        });
        // Setup common E2E framework
        super.setUp();

        // Set Up individual Modules the E2E test is going to use and store their configurations:
        // NOTE: It's important to store the module configurations in order, since _create_E2E_Orchestrator() will copy from the array.
        // The order should be:
        //      moduleConfigurations[0]  => FundingManager
        //      moduleConfigurations[1]  => Authorizer
        //      moduleConfigurations[2]  => PaymentProcessor
        //      moduleConfigurations[3:] => Additional Logic Modules

        // FundingManager
        setUpRebasingFundingManager();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                rebasingFundingManagerMetadata, abi.encode(address(rewardToken))
            )
        );

        // Authorizer
        setUpRoleAuthorizer();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                roleAuthorizerMetadata, abi.encode(address(this))
            )
        );

        // PaymentProcessor
        setUpSimplePaymentProcessor();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                simplePaymentProcessorMetadata, bytes("")
            )
        );

        // Additional Logic Modules
        setUpLM_PC_Staking_v1();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                LM_PC_Staking_v1Metadata, abi.encode(stakingToken)
            )
        );
    }

    function test_e2e_LM_PC_Staking_v1Lifecycle() public {
        //--------------------------------------------------------------------------
        // Orchestrator Initialization
        //--------------------------------------------------------------------------

        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig =
        IOrchestratorFactory_v1.WorkflowConfig({
            independentUpdates: false,
            independentUpdateAdmin: address(0)
        });

        IOrchestrator_v1 orchestrator =
            _create_E2E_Orchestrator(workflowConfig, moduleConfigurations);

        FM_Rebasing_v1 fundingManager =
            FM_Rebasing_v1(address(orchestrator.fundingManager()));

        LM_PC_Staking_v1 stakingManager;
        // ------------------ FROM ModuleTest.sol
        address[] memory modulesList = orchestrator.listModules();
        for (uint i; i < modulesList.length; ++i) {
            if (
                ERC165Upgradeable(modulesList[i]).supportsInterface(
                    type(ILM_PC_Staking_v1).interfaceId
                )
            ) {
                stakingManager = LM_PC_Staking_v1(modulesList[i]);
                break;
            }
        }

        // Warp to reasonable time
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

        // Value staked  |   Value earned            |   Rewards claimed
        // Staker 1:10   |   Staker 1:               |   Staker 1:
        // Staker 2:10   |   Staker 2:               |   Staker 2:
        // Staker 3:     |   Staker 3:               |   Staker 3:
        // Staker 4:     |   Staker 4:               |   Staker 4:

        // Check if values are accurate

        // 6. Warp time to end it

        vm.warp(block.timestamp + duration1);

        // 7. Withdraw for Staker 2
        vm.prank(staker2);
        stakingManager.unstake(10);

        // Value staked  |   Value earned            |   Rewards claimed
        // Staker 1:10   |   Staker 1: 1/2 amount1   |   Staker 1:
        // Staker 2:     |   Staker 2:               |   Staker 2: 1/2 amount1
        // Staker 3:     |   Staker 3:               |   Staker 3:
        // Staker 4:     |   Staker 4:               |   Staker 4:

        // Check if values are accurate
        assertEq(amount1 / 2, stakingManager.getEarned(staker1));
        assertEq(amount1 / 2, rewardToken.balanceOf(staker2));

        // 8. Set up reward period 2

        stakingManager.setRewards(amount2, duration2);

        // 9. Warp time to halve

        vm.warp(block.timestamp + duration2 / 2);

        // Value staked  |   Value earned            |   Rewards claimed
        // Staker 1:10   |   Staker 1: 1/2 amount1 + 1/2 amount2   |   Staker 1:
        // Staker 2:     |   Staker 2:               |   Staker 2: 1/2 amount1
        // Staker 3:     |   Staker 3:               |   Staker 3:
        // Staker 4:     |   Staker 4:               |   Staker 4:

        // Check if values are accurate
        assertEq(amount1 / 2 + amount2 / 2, stakingManager.getEarned(staker1));

        // 10. Let staker 3 and 4 into it

        vm.prank(staker3);
        stakingManager.stake(5);

        vm.prank(staker4);
        stakingManager.stake(5);

        // Value staked  |   Value earned                        |   Rewards claimed
        // Staker 1:10   |   Staker 1: 1/2 amount1 + 1/2 amount2 |   Staker 1:
        // Staker 2:     |   Staker 2:                           |   Staker 2: 1/2 amount1
        // Staker 3: 5   |   Staker 3:                           |   Staker 3:
        // Staker 4: 5   |   Staker 4:                           |   Staker 4:

        // 11. Finish it

        vm.warp(block.timestamp + duration2 / 2);

        // 12. Let 3 withdraw

        vm.prank(staker3);
        stakingManager.unstake(5);

        // Value staked  |   Value earned                        |   Rewards claimed
        // Staker 1:10   |   Staker 1: 1/2 amount1 + 3/4 amount2 |   Staker 1:
        // Staker 2:     |   Staker 2:                           |   Staker 2: 1/2 amount1
        // Staker 3:     |   Staker 3:                           |   Staker 3: 1/8 amount2
        // Staker 4: 5   |   Staker 4: 1/8 amount2               |   Staker 4:

        // Check if values are accurate
        assertEq(
            amount1 / 2 + amount2 * 3 / 4, stakingManager.getEarned(staker1)
        );
        assertEq(amount2 * 1 / 8, rewardToken.balanceOf(staker3));
        assertEq(amount2 * 1 / 8, stakingManager.getEarned(staker4));

        // 13. Let 4 stake more

        vm.prank(staker4);
        stakingManager.stake(5);

        // Value staked  |   Value earned                        |   Rewards claimed
        // Staker 1:10   |   Staker 1: 1/2 amount1 + 3/4 amount2 |   Staker 1:
        // Staker 2:     |   Staker 2:                           |   Staker 2: 1/2 amount1
        // Staker 3:     |   Staker 3:                           |   Staker 3: 1/8 amount2
        // Staker 4: 10  |   Staker 4:                           |   Staker 4: 1/8 amount2

        // Check if values are accurate
        assertEq(amount2 * 1 / 8, rewardToken.balanceOf(staker4));

        // 14. Set up reward period 3

        stakingManager.setRewards(amount3, duration3);

        // Use case: The reward period wasnt long enough
        // Extend it by setting up reward period 3 again

        stakingManager.setRewards(amount3, duration3);

        // 15. Warp time to end it
        // Because the amount and the duration get added on top of each other we need to duble the duration to get the end of the reward period
        vm.warp(block.timestamp + duration3 * 2);

        // Value staked  |   Value earned                                        |   Rewards claimed
        // Staker 1:10   |   Staker 1: 1/2 amount1 + 3/4 amount2 + 1 amount3     |   Staker 1:
        // Staker 2:     |   Staker 2:                                           |   Staker 2: 1/2 amount1
        // Staker 3:     |   Staker 3:                                           |   Staker 3: 1/8 amount2
        // Staker 4: 10  |   Staker 4: 1 amount3                                 |   Staker 4: 1/8 amount2

        assertEq(
            amount1 / 2 + amount2 * 3 / 4 + amount3,
            stakingManager.getEarned(staker1)
        );
        assertEq(amount3, stakingManager.getEarned(staker4));

        // 16. Let 1 withdraw half and 4 withdraw full

        vm.prank(staker1);
        stakingManager.unstake(5);

        vm.prank(staker4);
        stakingManager.unstake(10);

        // Value staked  |   Value earned    |   Rewards claimed
        // Staker 1: 5   |   Staker 1:       |   Staker 1: 1/2 amount1 + 3/4 amount2 + 1 amount3
        // Staker 2:     |   Staker 2:       |   Staker 2: 1/2 amount1
        // Staker 3:     |   Staker 3:       |   Staker 3: 1/8 amount2
        // Staker 4:     |   Staker 4:       |   Staker 4: 1/8 amount2 + 1 amount3

        // Check if values are accurate

        assertEq(5, stakingManager.getBalance(staker1));
        assertEq(
            amount1 / 2 + amount2 * 3 / 4 + amount3,
            rewardToken.balanceOf(staker1)
        );
        assertEq(amount2 * 1 / 8 + amount3, rewardToken.balanceOf(staker4));
    }
}
