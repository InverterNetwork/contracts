// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import "forge-std/console.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

//Internal Dependencies
import {
    ModuleTest,
    IModule,
    IProposal,
    LibString
} from "test/modules/ModuleTest.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

// SuT
import {
    SpecificFundingManager,
    ISpecificFundingManager
} from "src/modules/milestoneSubModules/SpecificFundingManager.sol";

contract SpecificFundingManagerTest is ModuleTest {
    using LibString for string;

    address milestoneModule = address(0xBeef);

    // SuT
    SpecificFundingManager specificFundingManager;

    function setUp() public {
        //Add Module to Mock Proposal

        address impl = address(new SpecificFundingManager());
        specificFundingManager = SpecificFundingManager(Clones.clone(impl));

        _setUpProposal(specificFundingManager);

        //Init Module
        specificFundingManager.init(
            _proposal, _METADATA, abi.encode(milestoneModule)
        );
    }

    //--------------------------------------------------------------------------
    // Test: Initialization

    //This function also tests all the getters
    function testInit() public override(ModuleTest) {}

    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__AlreadyInitialized);
        specificFundingManager.init(_proposal, _METADATA, bytes(""));
    }

    //--------------------------------------------------------------------------
    // Helper - Functions

    function assertSomething() private {}

    // =========================================================================
}
