// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {E2ETest} from "test/e2e/E2ETest.sol";
import "forge-std/console.sol";

//Internal Dependencies
import {ModuleTest, IOrchestrator} from "test/modules/ModuleTest.sol";
import {IModule, ERC165} from "src/modules/base/Module.sol";
import {IOrchestratorFactory} from "src/factories/OrchestratorFactory.sol";
import {AuthorizerMock} from "test/utils/mocks/modules/AuthorizerMock.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

import {RebasingFundingManager} from
    "src/modules/fundingManager/RebasingFundingManager.sol";

import {
    SimplePaymentProcessor,
    IPaymentProcessor
} from "src/modules/paymentProcessor/SimplePaymentProcessor.sol";

import {
    KPIRewarder,
    IKPIRewarder,
    IOptimisticOracleIntegrator,
    OptimisticOracleV3Interface,
    IStakingManager,
    IERC20PaymentClient
} from "src/modules/logicModule/KPIRewarder.sol";

// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";
import {ERC20} from "@oz/token/ERC20/ERC20.sol";
import {IERC20Metadata} from "@oz/token/ERC20/extensions/IERC20Metadata.sol";

/*
Fork testing necessary:

forge test --match-contract KPIRewarderLifecycle -vvv --fork-url $SEPOLIA_RPC_URL

*/

contract KPIRewarderLifecycle is E2ETest {
    /*
    - This needs to be a fork test using an actual UMA instance.
    - Where are the UMA test deployments? => https://github.com/UMAprotocol/protocol/tree/master/packages/core/networks
    - Sepolia:  
        {
            "contractName": "OptimisticOracleV3",
            "address": "0xFd9e2642a170aDD10F53Ee14a93FcF2F31924944"
        },
    - What Tokens are whitelisted? Which ones could we mint freely for non-fork tests? =>
        USDC clone: 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238
        Minter for impersonation: 0x39B3756655A34F869208c72b661f1afdEc1d428F
    


    */

    //--------------------------------------------------------------------------------
    // Chain Configuration
    //--------------------------------------------------------------------------------

    uint sepoliaForkId;

    // Constants
    address ooV3_address = 0xFd9e2642a170aDD10F53Ee14a93FcF2F31924944; // Sepolia Optimistic Oracle V3
    address USDC_address = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238; // Sepolia USDC address
    address USDC_Minter = 0x39B3756655A34F869208c72b661f1afdEc1d428F; // Sepolia USDC Master Minter

    //--------------------------------------------------------------------------------
    // Global Variables
    //--------------------------------------------------------------------------------

    // Module Configurations for the current E2E test. Should be filled during setUp() call.
    IOrchestratorFactory.ModuleConfig[] moduleConfigurations;

    IOrchestrator orchestrator;
    RebasingFundingManager fundingManager;
    KPIRewarder kpiRewarder;

    ERC20Mock USDC;
    ERC20Mock rewardToken;
    ERC20Mock stakingToken;

    address[] users;
    uint[] amounts;

    //--------------------------------------------------------------------------------
    // Mock Data
    //--------------------------------------------------------------------------------

    address OWNER = address(0x1); //Workflow owner
    address AUTOMATION_SERVICE = address(0x6E1A70); // The automation service that will post the assertion and do the callback

    // Assertion mock data
    uint64 constant ASSERTION_LIVENESS = 5000;
    bytes32 constant MOCK_ASSERTION_DATA_ID = "0x1234";
    bytes32 constant MOCK_ASSERTION_DATA = "This is test data";
    address constant MOCK_ASSERTER_ADDRESS = address(0x1);
    uint constant MOCK_ASSERTED_VALUE = 250;

    // KPI mock data
    uint constant NUM_OF_TRANCHES = 4;
    uint[NUM_OF_TRANCHES] trancheValues = [100, 200, 300, 400];
    uint[NUM_OF_TRANCHES] trancheRewards = [100e18, 100e18, 100e18, 100e18];

    //--------------------------------------------------------------------------------
    // Test Run Parameters
    //--------------------------------------------------------------------------------

    uint constant REWARD_DEPOSIT_AMOUNT = 50_000_000e18;

    uint constant DEPOSIT_ROUNDS = 3;
    uint constant USERS_PER_ROUND = 25;
    uint constant TOTAL_USERS = USERS_PER_ROUND * DEPOSIT_ROUNDS;

    function setUp() public override {
        // Pin tests to a block o save in RPC calls
        uint forkBlock = 5_723_995; //April 18 2024 12:15 EST
        sepoliaForkId = vm.createSelectFork(vm.rpcUrl("sepolia"), forkBlock);

        // We deploy and label the necessary tokens for the tests
        USDC = ERC20Mock(USDC_address); //we use it  mock so we can call mint functions TODO: Replace with real USDC contract?
        rewardToken = new ERC20Mock("Project Reward Mock Token", "REWARD MOCK");
        stakingToken = new ERC20Mock("Staking Mock Token", "STAKE MOCK");

        vm.label({
            account: USDC_address,
            newLabel: IERC20Metadata(address(USDC_address)).symbol()
        });
        vm.label({
            account: address(rewardToken),
            newLabel: IERC20Metadata(address(rewardToken)).symbol()
        });
        vm.label({
            account: address(stakingToken),
            newLabel: IERC20Metadata(address(stakingToken)).symbol()
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
            IOrchestratorFactory.ModuleConfig(
                rebasingFundingManagerMetadata,
                abi.encode(address(rewardToken)),
                abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
            )
        );

        // Authorizer
        setUpRoleAuthorizer();
        moduleConfigurations.push(
            IOrchestratorFactory.ModuleConfig(
                roleAuthorizerMetadata,
                abi.encode(address(this), address(this)),
                abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
            )
        );

        // PaymentProcessor
        setUpSimplePaymentProcessor();
        moduleConfigurations.push(
            IOrchestratorFactory.ModuleConfig(
                simplePaymentProcessorMetadata,
                bytes(""),
                abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
            )
        );

        // Additional Logic Modules

        // KPI Rewarder

        setUpKPIRewarder();
        moduleConfigurations.push(
            IOrchestratorFactory.ModuleConfig(
                kpiRewarderMetadata,
                abi.encode(
                    address(stakingToken),
                    USDC_address,
                    ooV3_address,
                    ASSERTION_LIVENESS
                ),
                abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
            )
        );
    }

    function test_e2e_KPIRewarderLifecycle() public {
        //--------------------------------------------------------------------------------
        // Orchestrator Initialization
        //--------------------------------------------------------------------------------

        IOrchestratorFactory.OrchestratorConfig memory orchestratorConfig =
        IOrchestratorFactory.OrchestratorConfig({
            owner: address(this),
            token: rewardToken
        });

        orchestrator =
            _create_E2E_Orchestrator(orchestratorConfig, moduleConfigurations);

        fundingManager =
            RebasingFundingManager(address(orchestrator.fundingManager()));

        // Get the KPIRewarder module
        bytes4 kpiRewarderInterfaceId = type(IKPIRewarder).interfaceId;
        address[] memory modulesList = orchestrator.listModules();
        for (uint i; i < modulesList.length; ++i) {
            if (
                ERC165(modulesList[i]).supportsInterface(kpiRewarderInterfaceId)
            ) {
                kpiRewarder = KPIRewarder(modulesList[i]);
                break;
            }
        }

        //--------------------------------------------------------------------------------
        // Test Context Setup
        //--------------------------------------------------------------------------------

        // Generate Users and Amounts
        users = new address[](TOTAL_USERS);
        amounts = new uint[](TOTAL_USERS);

        for (uint i = 0; i < TOTAL_USERS; i++) {
            users[i] = vm.addr(i + 1);
            amounts[i] = bound((i * 1000e18), 1, 100_000_000e18);
        }
        _assumeValidAddresses(users);

        // Mint enough USDC to the participants
        _setupUSDC();

        // give the automation service the rights to post assertions
        _prepareKPIRewarder();

        // Initialize KPIRewarder setup:
        rewardToken.mint(address(this), REWARD_DEPOSIT_AMOUNT);
        rewardToken.approve(address(fundingManager), REWARD_DEPOSIT_AMOUNT);
        fundingManager.deposit(REWARD_DEPOSIT_AMOUNT);

        //--------------------------------------------------------------------------------
        // Test Rounds
        //--------------------------------------------------------------------------------

        // Now we loop through the rounds. First round happens with no stakers and the rewards are not distributed, but the reward value is modified. Since the funds stay in the FundingManager until claiming, there are no locked funds in the KPIRewarder.

        uint roundCounter = 0;
        uint[] memory accumulatedRewards = new uint[](TOTAL_USERS);

        uint totalDistributed = 0;
        uint totalExpectedRewardsDistributed;

        do {
            (uint rewardsDistributed, uint expectedDistributed) =
                _processRound(accumulatedRewards, roundCounter);
            totalDistributed += rewardsDistributed;
            totalExpectedRewardsDistributed += expectedDistributed;

            roundCounter++;
        } while (roundCounter < DEPOSIT_ROUNDS);

        // Withdraw all funds and check balances

        for (uint i; i < TOTAL_USERS; i++) {
            vm.prank(users[i]);
            kpiRewarder.unstake(amounts[i]);

            /*console.log(
                "Current staking Balance:",
                stakingToken.balanceOf(address(kpiRewarder))
            );*/

            assertEq(kpiRewarder.balanceOf(users[i]), 0);
            assertEq(stakingToken.balanceOf(users[i]), amounts[i]);
            assertEq(rewardToken.balanceOf(users[i]), accumulatedRewards[i]);
        }

        // Check final invariants

        assertEq(
            rewardToken.balanceOf(address(fundingManager)),
            (REWARD_DEPOSIT_AMOUNT - totalDistributed)
        );

        // TODO: Fix Staking precision bug
        assertApproxEqAbs(
            totalDistributed, totalExpectedRewardsDistributed, 1e6
        );

        /*
        console.log("Final Rewards Distributed: ", totalDistributed);
        console.log(
            "Final Expected Rewards Distributed: ",
            totalExpectedRewardsDistributed
        );

        console.log(
            "Final Reward Balance:",
            rewardToken.balanceOf(address(fundingManager))
        );
        */
    }

    function _processRound(uint[] memory accumulatedRewards, uint roundCounter)
        internal
        returns (uint distributedInRound, uint expectedDistributed)
    {
        // Perform user staking with current batch of users
        _setUpStakers(
            (roundCounter * USERS_PER_ROUND),
            ((roundCounter * USERS_PER_ROUND) + USERS_PER_ROUND)
        );

        // - Start an assertion with assertedData[0]
        vm.prank(AUTOMATION_SERVICE);
        bytes32 assertionId = kpiRewarder.postAssertion(
            MOCK_ASSERTION_DATA_ID,
            MOCK_ASSERTION_DATA,
            MOCK_ASSERTER_ADDRESS,
            MOCK_ASSERTED_VALUE,
            0 // target KPI
        );

        // - Warp to the end of the assertion liveness
        vm.warp(block.timestamp + ASSERTION_LIVENESS + 1);

        // - Resolve the assertion
        vm.prank(AUTOMATION_SERVICE);
        OptimisticOracleV3Interface(ooV3_address).settleAssertion(assertionId);

        vm.warp(block.timestamp + 1);

        // - Check the rewards
        uint rewardBalanceBefore =
            rewardToken.balanceOf(address(fundingManager));

        distributedInRound = 0;

        expectedDistributed =
            _getExpectedRewardAmount(kpiRewarder.getKPI(0), MOCK_ASSERTED_VALUE);

        for (uint i; i < TOTAL_USERS; i++) {
            uint currentUserBalance = rewardToken.balanceOf(users[i]);
            uint reward = kpiRewarder.earned(users[i]);
            /*console.log(
                    "User %s has a pre-balance of %s",
                    users[i],
                    rewardToken.balanceOf(users[i])
                );*/
            if (reward > 0) {
                vm.prank(users[i]);
                kpiRewarder.claimRewards();
                accumulatedRewards[i] += reward;
                distributedInRound += reward;

                assertEq(
                    (currentUserBalance + reward),
                    rewardToken.balanceOf(users[i])
                );
            }
            //console.log("User %s has a reward of %s", users[i], reward);
        }

        uint rewardBalanceAfter = rewardToken.balanceOf(address(fundingManager));

        assertEq(rewardBalanceAfter, (rewardBalanceBefore - distributedInRound));

        //return (distributedInRound, expectedDistributed);
    }

    //--------------------------------------------------------------------------------
    // E2E Helper Functions
    //--------------------------------------------------------------------------------

    function _getExpectedRewardAmount(
        IKPIRewarder.KPI memory resolvedKPI,
        uint assertedValue
    ) internal view returns (uint) {
        uint rewardAmount;

        for (uint i; i < resolvedKPI.numOfTranches; i++) {
            if (resolvedKPI.trancheValues[i] <= assertedValue) {
                //the asserted value is above tranche end
                rewardAmount += resolvedKPI.trancheRewards[i];
            } else {
                //tranche was not completed
                if (resolvedKPI.continuous) {
                    //continuous distribution
                    uint trancheRewardValue = resolvedKPI.trancheRewards[i];
                    uint trancheStart =
                        i == 0 ? 0 : resolvedKPI.trancheValues[i - 1];

                    // console.log("assertedValue:", assertedValue);
                    // console.log("trancheReward:", trancheStart);
                    uint achievedReward = assertedValue - trancheStart;
                    uint trancheEnd =
                        resolvedKPI.trancheValues[i] - trancheStart;

                    rewardAmount +=
                        achievedReward * (trancheRewardValue / trancheEnd); // since the trancheRewardValue will be a very big number.
                }
                //else -> no reward

                //exit the loop
                break;
            }
        }

        return rewardAmount;
    }

    // Stakes a set of users and their amounts
    function _setUpStakers(uint start, uint end) private {
        for (uint i = start; i < end; i++) {
            //console.log("SetupStakers: Staking %s for %s", amounts[i], users[i]);

            stakingToken.mint(users[i], amounts[i]);
            vm.startPrank(users[i]);
            stakingToken.approve(address(kpiRewarder), amounts[i]);
            kpiRewarder.stake(amounts[i]);
            vm.stopPrank();
        }
    }

    function _setupUSDC() internal {
        vm.prank(address(USDC_Minter));
        USDC.mint(address(this), 100_000_000e18);
        // - Seed Automation service with Bond tokens and funds for execution
        USDC.transfer(address(AUTOMATION_SERVICE), 1_000_000e18);
        // - Ensure allowances
        USDC.approve(
            address(kpiRewarder),
            OptimisticOracleV3Interface(ooV3_address).getMinimumBond(
                USDC_address
            )
        );
    }

    function _prepareKPIRewarder() internal {
        kpiRewarder.grantModuleRole(
            kpiRewarder.ASSERTER_ROLE(), AUTOMATION_SERVICE
        );
        _createDummyContinuousKPI(address(kpiRewarder));
    }

    // Creates  dummy incontinuous KPI with 3 tranches, a max value of 300 and 300e18 tokens for rewards
    function _createDummyContinuousKPI(address kpiManager) internal {
        uint[] memory _trancheValues = new uint[](4);
        uint[] memory _trancheRewards = new uint[](4);

        for (uint i; i < NUM_OF_TRANCHES; i++) {
            _trancheValues[i] = trancheValues[i];
            _trancheRewards[i] = trancheRewards[i];
        }

        IKPIRewarder(kpiManager).createKPI(
            true, _trancheValues, _trancheRewards
        );
    }
    // =========================================================================
    // Helper to use fuzzed addresses

    // Address Sanity Checkers
    mapping(address => bool) addressCache;

    function _assumeValidAddresses(address[] memory addresses) internal {
        for (uint i; i < addresses.length; ++i) {
            _assumeValidAddress(addresses[i]);

            // Assume address unique.
            vm.assume(!addressCache[addresses[i]]);

            // Add address to cache.
            addressCache[addresses[i]] = true;
        }
    }

    function _assumeValidAddress(address user) internal view {
        address[] memory invalids = _createInvalidAddresses();

        for (uint i; i < invalids.length; ++i) {
            vm.assume(user != invalids[i]);
        }
    }

    function _createInvalidAddresses()
        internal
        view
        returns (address[] memory)
    {
        address[] memory modules = orchestrator.listModules();

        address[] memory invalids = new address[](modules.length + 9);

        for (uint i; i < modules.length; ++i) {
            invalids[i] = modules[i];
        }

        invalids[invalids.length - 1] = address(0);
        invalids[invalids.length - 2] = address(this);
        invalids[invalids.length - 3] = address(orchestrator);
        invalids[invalids.length - 4] = address(USDC);
        invalids[invalids.length - 5] = address(USDC_Minter);
        invalids[invalids.length - 6] = address(rewardToken);
        invalids[invalids.length - 7] = address(stakingToken);
        invalids[invalids.length - 8] = address(OWNER);
        invalids[invalids.length - 9] = address(AUTOMATION_SERVICE);

        return invalids;
    }
}
