// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import "forge-std/console.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

//Internal Dependencies
import {ModuleTest, IModule, IProposal} from "test/modules/ModuleTest.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

// SuT
import {
    ReocurringPaymentManager,
    IReocurringPaymentManager
} from "src/modules/LogicModule/ReocurringPaymentManager.sol";

contract ReocurringPaymentManagerTest is ModuleTest {
    // SuT
    ReocurringPaymentManager reocurringPaymentManager;

    function setUp() public {
        //Add Module to Mock Proposal

        address impl = address(new ReocurringPaymentManager());
        reocurringPaymentManager = ReocurringPaymentManager(Clones.clone(impl));

        _setUpProposal(reocurringPaymentManager);
    }

    //--------------------------------------------------------------------------
    // Test: Initialization

    //This function also tests all the getters
    function testInit() public override(ModuleTest) {
        vm.expectRevert(
            IReocurringPaymentManager
                .Module__ReocurringPaymentManager__EpochLengthToShort
                .selector
        );

        //Init Module wrongly
        reocurringPaymentManager.init(
            _proposal, _METADATA, abi.encode(1 weeks - 1)
        );

        //Init Module wrongly
        reocurringPaymentManager.init(_proposal, _METADATA, abi.encode(1 weeks));

        assertEq(reocurringPaymentManager.getEpochLength(), 1 weeks);
    }

    function testReinitFails() public override(ModuleTest) {
        reocurringPaymentManager.init(_proposal, _METADATA, abi.encode(1 weeks));

        vm.expectRevert(OZErrors.Initializable__AlreadyInitialized);
        reocurringPaymentManager.init(_proposal, _METADATA, bytes(""));
    }

    // =========================================================================
}
