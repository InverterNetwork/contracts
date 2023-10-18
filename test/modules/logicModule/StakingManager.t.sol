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

// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

contract StakingManagerTest is ModuleTest {
    // SuT
    StakingManager stakingManager;

    ERC20Mock stakingToken = new ERC20Mock("Staking Mock Token", "STAKE MOCK");

    function setUp() public {
        //Add Module to Mock Orchestrator
        address impl = address(new StakingManager());
        stakingManager = StakingManager(Clones.clone(impl));

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

    function testGet() public {}

    //--------------------------------------------------------------------------
    // Mutating Functions

    //-----------------------------------------
    //Stake

    // =========================================================================

    //--------------------------------------------------------------------------
    // Helper
}
