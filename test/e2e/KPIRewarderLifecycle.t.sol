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

/*
Fork testing necessary:

forge test --match-contract KPIRewarderLifecycle -vvv --fork-url $SEPOLIA_RPC_URL

*/

contract KPIRewarderLifecycle is E2eTest {

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
    // Constants
    address ooV3 = 0xFd9e2642a170aDD10F53Ee14a93FcF2F31924944; 
    //OptimisticOracleV3Interface oracle = new OptimisticOracleV3Interface(ooV3);

    ERC20Mock USDC =
        ERC20Mock(address(0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238)); //Sepolia USDC address
    address USDC_Minter = 0x39B3756655A34F869208c72b661f1afdEc1d428F; // Sepolia USDC Master Minter
    ERC20Mock rewardToken =
        new ERC20Mock("Project Reward Mock Token", "REWARD MOCK");
    ERC20Mock stakingToken = new ERC20Mock("Staking Mock Token", "STAKE MOCK");
    address OWNER = address(0x1); //Workflow owner
    address AUTOMATION_SERVICE = address(0x6E1A70); // The automation service that will post the assertion and do the callback

    // Mock data for assertions
    bytes32 constant MOCK_ASSERTION_DATA_ID = "0x1234";
    bytes32 constant MOCK_ASSERTION_DATA = "This is test data";
    address constant MOCK_ASSERTER_ADDRESS = address(0x1);
    uint constant MOCK_ASSERTED_VALUE = 50_000_000; // TODO remove when generalizing

    IOrchestrator orchestrator;
    RebasingFundingManager fundingManager;
    KPIRewarder kpiRewarder;

    // Mock data for the KPI

    // How do we approach this.

    /*
    - This needs to be a fork test using an actual UMA instance.
    - Where are the UMA test deployments? => https://github.com/UMAprotocol/protocol/tree/master/packages/core/networks
    - Sepolia:  
        {
            "contractName": "OptimisticOracleV3",
            "address": "0xFd9e2642a170aDD10F53Ee14a93FcF2F31924944"
        },
    - What Tokens are whitelisted? Which ones could we mint freely for non-fork tests? =>
    


    */

    function test_e2e_KPIRewarderLifecycle(
        address[] memory users,
        uint[] memory amounts,
        uint rounds,
        uint[] calldata assertedData
    ) public {
        _createOrchestratorAndSaveModules();

        // TODO actually do the capping here, and then set up stake separately
        //address[] memory users;
        //uint[] memory amounts;
        (users, amounts) = _validateAddressesAndAmounts(users, amounts);

        console.log("Users: %s", users[0]);
        console.log("Amounts: %s", amounts[0]);
        console.log("Users.length: %s", users.length);

        _setupUSDC();

        _prepareKPIRewarder();
        // give the automation service the rights to post assertions

        // Initialize KPIRewarder setup:
        USDC.approve(address(fundingManager), 50_000_000e18);
        fundingManager.deposit(50_000_000e18);

        // TODO refactor to avoid slices (use % 2)
        uint halfOfUsers = users.length / 2;
        uint totalUserFunds_round1;
        uint totalUserFunds_round2;
        address[] memory users_round1 = new address[](halfOfUsers);
        address[] memory users_round2 = new address[](halfOfUsers);
        uint[] memory amounts_round1 = new uint[](halfOfUsers);
        uint[] memory amounts_round2 = new uint[](halfOfUsers);

        for (uint i; i < users.length; i += 2) {
            console.log("i: %s", i);
            if (i % 2 == 0) {
                users_round1[i] = users[i];
                amounts_round1[i] = amounts[i];
                totalUserFunds_round1 += amounts[i];
            } else {
                users_round2[i] = users[i];
                amounts_round2[i] = amounts[i];
                totalUserFunds_round2 += amounts[i];
            }
        }

        // Perform user staking with half of the users
        _setUpStakers(users_round1, amounts_round1);

        // - Start an assertion with assertedData[0]
        vm.prank(AUTOMATION_SERVICE);
        bytes32 assertionId = kpiRewarder.postAssertion(
            MOCK_ASSERTION_DATA_ID,
            MOCK_ASSERTION_DATA,
            MOCK_ASSERTER_ADDRESS,
            MOCK_ASSERTED_VALUE,
            0 // target KPI
        );

        // - Deposit the others
        _setUpStakers(users_round2, amounts_round2);

        // - Resolve the assertion
        vm.prank(AUTOMATION_SERVICE);
        OptimisticOracleV3Interface(ooV3).settleAssertion(assertionId);
        // - Check the rewards

        for (uint i; i < users_round1.length; i++) {
            uint reward = rewardToken.balanceOf(users_round1[i]);
            console.log("User %s has a reward of %s", users_round1[i], reward);
        }
        // - Repeat for the next rounds
        //          - This time all should get rewards

        // Withdraw all funds and check balances
    }

    function _validateAddressesAndAmounts(
        address[] memory users,
        uint[] memory amounts
    )
        private
        returns (address[] memory cappedUsers, uint[] memory cappedAmounts)
    {
        vm.assume(amounts.length > 1 && amounts.length >= users.length);

        uint maxLength = kpiRewarder.MAX_QUEUE_LENGTH();
        console.log(".");
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
console.log("..");
        _assumeValidAddresses(cappedUsers);
console.log("...");
        // (returns cappedUsers, cappedAmounts)
    }

    // Stakes a set of users and their amounts
    function _setUpStakers(address[] memory users, uint[] memory amounts)
        private
    {
        for (uint i = 0; i < users.length; i++) {
            stakingToken.mint(users[i], amounts[i]);
            vm.startPrank(users[i]);
            stakingToken.approve(address(kpiRewarder), amounts[i]);
            kpiRewarder.stake(amounts[i]);
            vm.stopPrank();
        }
    }

    function _createOrchestratorAndSaveModules() internal {
        // PRE-Steps: register KPI Rewarder in factory

        // -----------INIT
        // address(this) creates a new orchestrator.
        IOrchestratorFactory.OrchestratorConfig memory orchestratorConfig =
        IOrchestratorFactory.OrchestratorConfig({
            owner: address(this),
            token: USDC
        });

        orchestrator = _createNewOrchestratorWithAllModules_withKPIRewarder(
            orchestratorConfig, address(stakingToken), address(USDC), ooV3
        );

        fundingManager =
            RebasingFundingManager(address(orchestrator.fundingManager()));

        // Find KPIRewarder
        address[] memory modulesList = orchestrator.listModules();
        for (uint i; i < modulesList.length; ++i) {
            try KPIRewarder(modulesList[i]).KPICounter() returns (uint) {
                kpiRewarder = KPIRewarder(modulesList[i]);
                break;
            } catch {
                continue;
            }
        }
    }

    function _setupUSDC() internal {
        vm.prank(address(USDC_Minter));
        USDC.mint(address(this), 100_000_000e18);
        // - Seed Automation service with Bond tokens and funds for execution
        USDC.transfer(address(AUTOMATION_SERVICE), 1_000_000e18);
        // - Ensure allowances
        /*    feeToken.approve(
            address(kpiRewarder), ooV3.getMinimumBond(address(feeToken))
        );*/

        // Add USDC to UMA whitelist:
        //address Whitelist_Owner = 0x9A8f92a830A5cB89a3816e3D267CB7791c16b04D;
    }

    function _prepareKPIRewarder() internal {
        kpiRewarder.grantModuleRole(
            kpiRewarder.ASSERTER_ROLE(), AUTOMATION_SERVICE
        );
        _createDummyContinuousKPI(address(kpiRewarder));
    }

    // Creates  dummy incontinuous KPI with 3 tranches, a max value of 300 and 300e18 tokens for rewards
    function _createDummyContinuousKPI(address kpiManager) internal {
        uint[] memory trancheValues = new uint[](3);
        uint[] memory trancheRewards = new uint[](3);

        trancheValues[0] = 100;
        trancheValues[1] = 200;
        trancheValues[2] = 300;

        trancheRewards[0] = 100e18;
        trancheRewards[1] = 100e18;
        trancheRewards[2] = 100e18;

        IKPIRewarder(kpiManager).createKPI(true, trancheValues, trancheRewards);
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
