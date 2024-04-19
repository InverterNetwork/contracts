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
    // Module Configurations for the current E2E test. Should be filled during setUp() call.
    IOrchestratorFactory.ModuleConfig[] moduleConfigurations;

    uint sepoliaForkId;

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
    address ooV3_address = 0xFd9e2642a170aDD10F53Ee14a93FcF2F31924944; // Sepolia Optimistic Oracle V3
    address USDC_address = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238; // Sepolia USDC address
    address USDC_Minter = 0x39B3756655A34F869208c72b661f1afdEc1d428F; // Sepolia USDC Master Minter

    address OWNER = address(0x1); //Workflow owner
    address AUTOMATION_SERVICE = address(0x6E1A70); // The automation service that will post the assertion and do the callback

    // Mock data for assertions
    uint64 constant ASSERTION_LIVENESS = 5000;
    bytes32 constant MOCK_ASSERTION_DATA_ID = "0x1234";
    bytes32 constant MOCK_ASSERTION_DATA = "This is test data";
    address constant MOCK_ASSERTER_ADDRESS = address(0x1);
    uint constant MOCK_ASSERTED_VALUE = 50_000_000; // TODO remove when generalizing

    IOrchestrator orchestrator;
    RebasingFundingManager fundingManager;
    KPIRewarder kpiRewarder;

    ERC20Mock USDC;
    ERC20Mock rewardToken;
    ERC20Mock stakingToken;
    // Mock data for the KPI

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
        address[] memory _users = new address[](25);
        uint[] memory _amounts = new uint[](25);

        for (uint i = 0; i < 25; i++) {
            _users[i] = vm.addr(i * 2 + 1);
            _amounts[i] = i * 1_000_000e18;
        }

        uint rounds;
        uint[] calldata assertedData;

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

        // ------------------ FROM ModuleTest.sol
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

        // TODO actually do the capping here, and then set up stake separately
        //address[] memory users;
        //uint[] memory amounts;
        (address[] memory users, uint[] memory amounts) =
            _validateAddressesAndAmounts(_users, _amounts);

        //console.log("Users: %s", users[0]);
        //console.log("Amounts: %s", amounts[0]);
        //console.log("Users.length: %s", users.length);

        _setupUSDC();

        _prepareKPIRewarder();
        // give the automation service the rights to post assertions

        // Initialize KPIRewarder setup:
        rewardToken.mint(address(this), 50_000_000e18);
        rewardToken.approve(address(fundingManager), 50_000_000e18);
        fundingManager.deposit(50_000_000e18);

        uint halfOfUsers = users.length / 2;

        address[] memory users_round1 = new address[](halfOfUsers);
        uint[] memory amounts_round1 = new uint[](halfOfUsers);
        uint totalUserFunds_round1;

        address[] memory users_round2 =
            new address[](users.length - halfOfUsers);
        uint[] memory amounts_round2 = new uint[](users.length - halfOfUsers);
        uint totalUserFunds_round2;

        for (uint i; i < users.length; i++) {
            if (i < halfOfUsers) {
                users_round1[i] = users[i];
                amounts_round1[i] = amounts[i];
                totalUserFunds_round1 += amounts[i];
                //console.log("user1[%s]: %s", i, users[i]);
            } else {
                users_round2[i - halfOfUsers] = users[i];
                amounts_round2[i - halfOfUsers] = amounts[i];
                totalUserFunds_round2 += amounts[i];
                //console.log("user2[%s]: %s", i - halfOfUsers, users[i]);
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

        vm.warp(block.timestamp + ASSERTION_LIVENESS + 1);

        // - Resolve the assertion
        vm.prank(AUTOMATION_SERVICE);
        OptimisticOracleV3Interface(ooV3_address).settleAssertion(assertionId);
        // - Check the rewards

        vm.warp(block.timestamp + 5);

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
        vm.assume(users.length > 1 && amounts.length >= users.length);

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

        _assumeValidAddresses(cappedUsers);

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
