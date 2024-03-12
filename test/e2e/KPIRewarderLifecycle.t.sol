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

import {SimplePaymentProcessor, IPaymentProcessor} from
    "src/modules/paymentProcessor/SimplePaymentProcessor.sol";

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

contract KPIRewarderLifecycle is E2eTest {

    // Constants
    address ooV3 = 0x9923D42eF695B5dd9911D05Ac944d4cAca3c4EAB;
    //OptimisticOracleV3Interface oracle = new OptimisticOracleV3Interface(ooV3);

    ERC20 USDC= address(0x1234);
    ERC20 rewardToken = address(0x4567);
    ERC20 stakingToken = address(0x5678);
    address OWNER = address(0x1); //Workflow owner
    address AUTOMATION_SERVICE = address(0x6E1A70); // The automation service that will post the assertion and do the callback

        // Mock data for assertions
    bytes32 constant MOCK_ASSERTION_DATA_ID = "0x1234";
    bytes32 constant MOCK_ASSERTION_DATA = "This is test data";
    address constant MOCK_ASSERTER_ADDRESS = address(0x1);
    uint constant MOCK_ASSERTED_VALUE = 50_000_000; // TODO remove when generalizing

    KPIRewarder kpiRewarder;

    // Mock data for the KPI


    // How do we approach this.

    /*
    - This needs to be a fork test using an actual UMA instance.
    - Where are the UMA test deployments? => https://github.com/UMAprotocol/protocol/tree/master/packages/core/networks
    - Goerli:  
            {
                "contractName": "OptimisticOracleV3",
                "address": "0x9923D42eF695B5dd9911D05Ac944d4cAca3c4EAB"
            },
    - What Tokens are whitelisted? Which ones could we mint freely for non-fork tests? =>
    


    */


    function test_e2e_KPIRewarderLifecycle(address[] calldata users, address[] calldata amounts, uint rounds, uint[] calldata assertedData ) public {





        // -----------INIT
        // address(this) creates a new orchestrator.
        IOrchestratorFactory.OrchestratorConfig memory orchestratorConfig =
        IOrchestratorFactory.OrchestratorConfig({
            owner: address(this),
            token: address(USDC)
        });

        IOrchestrator orchestrator =
        _createNewOrchestratorWithAllModules_withKPIRewarder(
            orchestratorConfig,
            address(USDC),
            address(stakingToken),
            ooV3
        );

        RebasingFundingManager fundingManager =
            RebasingFundingManager(address(orchestrator.fundingManager()));



        // Find KPIRewarder
        address[] memory modulesList = orchestrator.listModules();
        for (uint i; i < modulesList.length; ++i) {
            try IKPIRewarder(modulesList[i]).KPICounter() returns (uint) {
                kpiRewarder = KPIRewarder(modulesList[i]);
                break;
            } catch {
                continue;
            }
        }

        // we authorize the deployer of the orchestrator as the bounty admin
        kpiRewarder.grantModuleRole(
            kpiRewarder.ASSERTER_ROLE(), AUTOMATION_SERVICE
        );


        // Initialize KPIRewarder setup:
        // - Connect to UMA 
        // - Seed FundingManager with lots of rewards
        USDC.mint(address(this), 100_000_000e18);
        fundingManager.deposit(50_000_000e18);
        // - Seed Automation service with Bond tokens and funds for execution
        USDC.transfer(address(AUTOMATION_SERVICE), 1_000_000e18);
        // - Ensure allowances
            /*    feeToken.approve(
            address(kpiRewarder), ooV3.getMinimumBond(address(feeToken))
        );*/

        // Perform user staking with half of the users
                // validate and bound addresses/amounts
        uint halfOfUsers = users.length / 2;
        uint totalUserFunds_round1;
        address[] memory users_round1;
        uint[] memory amounts_round1;
        (users_round1, amounts_round1, totalUserFunds_round1) = _setUpStakers(users[:halfOfUsers], amounts);


        // Create continuous  KPI
        uint[] memory trancheValues = new uint[](3);
        uint[] memory trancheRewards = new uint[](3);

        trancheValues[0] = 20_000_000;
        trancheValues[1] = 40_000_000;
        trancheValues[2] = 60_000_000;

        trancheRewards[0] = 100_000e18;
        trancheRewards[1] = 100_000e18;
        trancheRewards[2] = 100_000e18;

        kpiRewarder.createKPI(true, trancheValues, trancheRewards);

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

        uint totalUserFunds_round2;
        address[] memory users_round2;
        uint[] memory amounts_round2;
        (users_round2, amounts_round2, totalUserFunds_round2) = _setUpStakers(users[halfOfUsers:], amounts);

        // - Resolve the assertion
        vm.prank(AUTOMATION_SERVICE);
        OptimisticOracleV3Interface(ooV3).settleAssertion(assertionId);
        // - Check the rewards

        for(uint i; i < users_round1.length; i++) {
            uint reward = rewardToken.balanceOf(users_round1[i]);
            console.log("User %s has a reward of %s", users_round1[i], reward);
        }
        // - Repeat for the next rounds
        //          - This time all should get rewards

        // Withdraw all funds and check balances




    }

    // Stakes a set of users and their amounts
    function _setUpStakers(address[] memory users, uint[] memory amounts)
        private
        returns (
            address[] memory cappedUsers,
            uint[] memory cappedAmounts,
            uint totalUserFunds
        )
    {
        vm.assume(amounts.length >= users.length);

        uint maxLength = kpiRewarder.MAX_QUEUE_LENGTH();

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

//        _assumeValidAddresses(cappedUsers);

        totalUserFunds = 0;

        for (uint i = 0; i < cappedUsers.length; i++) {
            stakingToken.mint(cappedUsers[i], cappedAmounts[i]);
            vm.startPrank(cappedUsers[i]);
            stakingToken.approve(address(kpiRewarder), cappedAmounts[i]);
            kpiRewarder.stake(cappedAmounts[i]);
            totalUserFunds += cappedAmounts[i];
            vm.stopPrank();
        }

        // (returns cappedUsers, cappedAmounts, totalUserFunds)
    }
/*

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
        address[] memory modules = _orchestrator.listModules();

        address[] memory invalids = new address[](modules.length + 4);

        for (uint i; i < modules.length; ++i) {
            invalids[i] = modules[i];
        }

        invalids[invalids.length - 4] = address(0);
        invalids[invalids.length - 3] = address(this);
        invalids[invalids.length - 2] = address(_orchestrator);
        invalids[invalids.length - 1] = address(_token);

        return invalids;
    }
*/
}