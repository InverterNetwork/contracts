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
import {KPIRewarder, IOptimisticOracleIntegrator, IStakingManagercarg} from "src/modules/logicModule/KPIRewarder.sol";

import {OptimisticOracleV3Mock} from
    "test/modules/logicModule/oracle/utils/OptimisiticOracleV3Mock.sol";

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
    address constant MOCK_ASSERTER_ADDRESS = address(0x0);

    ERC20Mock stakingToken = new ERC20Mock("Staking Mock Token", "STAKE MOCK");
    ERC20Mock rewardToken =
        new ERC20Mock("KPI Reward Mock Token", "REWARD MOCK");

    function setUp() public {
        ooV3 = new OptimisticOracleV3Mock(_token, DEFAULT_LIVENESS);
        // we whitelist the default currency
        ooV3.whitelistCurrency(address(_token), 5e17);

        //Add Module to Mock Orchestrator
        address impl = address(new KPIRewarder());
        kpiManager = KPIRewarder(Clones.clone(impl));

        _setUpOrchestrator(kpiManager);

        _authorizer.setIsAuthorized(address(this), true);

        bytes memory configData =
            abi.encode(address(stakingToken), address(rewardToken), ooV3);

        kpiManager.init(_orchestrator, _METADATA, configData);
    
    }

    //--------------------------------------------------------------------------
    // Test: Initialization

    function testInit() public override(ModuleTest) {
        address impl = address(new KPIRewarder());
        kpiManager = KPIRewarder(Clones.clone(impl));

        _setUpOrchestrator(kpiManager);

        bytes memory configData =
            abi.encode(address(stakingToken), address(rewardToken), ooV3);

        //Init Module wrongly
        vm.expectRevert(IModule.Module__InvalidOrchestratorAddress.selector);
        kpiManager.init(IOrchestrator(address(0)), _METADATA, configData);

        // Test invalid staking token
        vm.expectRevert(
            IStakingManager
                .Module__StakingManager__InvalidStakingToken
                .selector
        );
        kpiManager.init(
            _orchestrator,
            _METADATA,
            abi.encode(address(0), address(rewardToken), address(ooV3))
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
            _orchestrator, _METADATA, abi.encode(address(_token), address(0))
        );
    }

    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__AlreadyInitialized);
        kpiManager.init(_orchestrator, _METADATA, bytes(""));
    }
}
