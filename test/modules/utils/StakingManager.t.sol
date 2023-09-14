// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

//Internal Dependencies
import {ModuleTest, IModule, IOrchestrator} from "test/modules/ModuleTest.sol";

// SuT
import {
    StakingManager,
    IStakingManager
} from "src/modules/utils/StakingManager.sol";

contract StakingManagerTest is ModuleTest {
    // SuT
    StakingManager stakingManager;

    function setUp() public {
        //Add Module to Mock Orchestrator
        address impl = address(new StakingManager());
        stakingManager = StakingManager(Clones.clone(impl));

        _setUpOrchestrator(stakingManager);

        // Authorize this contract for the tests
        _authorizer.setIsAuthorized(address(this), true);

        //Init Module
        stakingManager.init(
            _orchestrator, _METADATA, abi.encode(address(_token))
        );
    }

    //--------------------------------------------------------------------------
    // Test: Initialization

    //This function also tests all the getters
    function testInit() public override(ModuleTest) {
        assertEq(address(_token), address(stakingManager.token()));
    }

    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__AlreadyInitialized);
        stakingManager.init(_orchestrator, _METADATA, bytes(""));
    }

    //--------------------------------------------------------------------------
    // Modifier

    //--------------------------------------------------------------------------
    // Getter

    //--------------------------------------------------------------------------
    // Mutating Functions

    //-----------------------------------------
    //AddBounty

    //--------------------------------------------------------------------------
    // Helper - Functions

    /*  function assertMemberMetadataEqual(
        IMetadataManager.MemberMetadata memory firstMemberMetadata,
        IMetadataManager.MemberMetadata memory secondMemberMetadata_
    ) private {
        assertEq(firstMemberMetadata.name, secondMemberMetadata_.name);
        assertEq(firstMemberMetadata.account, secondMemberMetadata_.account);
        assertEq(firstMemberMetadata.url, secondMemberMetadata_.url);
    } */

    // =========================================================================
}
