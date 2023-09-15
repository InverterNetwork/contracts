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

        //Initially mint 10_000 token for testing
        _token.mint(address(this), 10_000);
        _token.approve(address(stakingManager), 10_000);
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

    function testValidAmount(uint amount) public {
        amount = bound(amount, 0, 10_000);

        if (amount == 0) {
            vm.expectRevert(
                IStakingManager.Module__StakingManager__InvalidAmount.selector
            );
        }

        stakingManager.deposit(amount);
    }

    function testValidStakeId(uint usedIds, uint id) public {
        usedIds = bound(usedIds, 0, 1000);

        for (uint i; i < usedIds; i++) {
            stakingManager.deposit(1);
        }

        if (id > usedIds || id == 0) {
            vm.expectRevert(
                IStakingManager.Module__StakingManager__InvalidStakeId.selector
            );
        }

        stakingManager.withdraw(id, 1);
    }

    function testValidWithdrawAmount(uint amount, uint withdrawAmount) public {
        amount = bound(amount, 1, 10_000);
        if (withdrawAmount == 0) {
            withdrawAmount = 1;
        }

        uint id = stakingManager.deposit(amount);

        if (withdrawAmount > amount) {
            vm.expectRevert(
                IStakingManager
                    .Module__StakingManager__InvalidWithdrawAmount
                    .selector
            );
        }

        stakingManager.withdraw(id, withdrawAmount);
    }

    //--------------------------------------------------------------------------
    // Getter

    function testGetStakeForAddressModifierInPosition() public {
        vm.expectRevert(
            IStakingManager.Module__StakingManager__InvalidStakeId.selector
        );
        stakingManager.getStakeForAddress(address(0xBEEF), 1);
    }

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
