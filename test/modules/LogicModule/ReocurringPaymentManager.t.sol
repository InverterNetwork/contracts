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

        //Init Module correct
        reocurringPaymentManager.init(_proposal, _METADATA, abi.encode(1 weeks));

        assertEq(reocurringPaymentManager.getEpochLength(), 1 weeks);
    }

    function testReinitFails() public override(ModuleTest) {
        reocurringPaymentManager.init(_proposal, _METADATA, abi.encode(1 weeks));

        vm.expectRevert(OZErrors.Initializable__AlreadyInitialized);
        reocurringPaymentManager.init(_proposal, _METADATA, bytes(""));
    }

    //--------------------------------------------------------------------------
    // Modifier

    function testValidId(uint seed, uint usedIds, uint id) public {
        vm.assume(usedIds < 1000); //Reasonable size

        reasonableWarpAndInit(seed);

        for (uint i = 0; i < usedIds; i++) {
            reocurringPaymentManager.addReocurringPayment(
                1, 3 weeks, address(0xBEEF)
            );
        }

        if (id > usedIds || id == 0) {
            vm.expectRevert(
                IReocurringPaymentManager
                    .Module__ReocurringPaymentManager__InvalidReocurringPaymentId
                    .selector
            );
        }

        reocurringPaymentManager.getReocurringPaymentInformation(id);
    }

    function testValidStartEpoch(uint seed, uint startEpoch) public {
        reasonableWarpAndInit(seed);

        uint currentEpoch = reocurringPaymentManager.getCurrentEpoch();

        if (currentEpoch > startEpoch) {
            vm.expectRevert(
                IReocurringPaymentManager
                    .Module__ReocurringPaymentManager__InvalidStartEpoch
                    .selector
            );
        }

        reocurringPaymentManager.addReocurringPayment(
            1, startEpoch, address(0xBeef)
        );
    }

    //--------------------------------------------------------------------------
    // Getter

    function testGetReocurringPaymentInformationModifierInPosition() public {
        vm.expectRevert(
            IReocurringPaymentManager
                .Module__ReocurringPaymentManager__InvalidReocurringPaymentId
                .selector
        );
        reocurringPaymentManager.getReocurringPaymentInformation(0);
    }

    // =========================================================================

    //--------------------------------------------------------------------------
    // Helper

    function reasonableWarpAndInit(uint seed) internal {
        uint epochLength = bound(seed, 1 weeks, 52 weeks);

        //with this were at least in epoch 2 and there is enough time to go on from that time (3_153_600_000 seconds are 100 years)
        uint currentTimestamp = bound(seed, 52 weeks + 1, 3_153_600_000);

        //Warp to a reasonable time
        vm.warp(currentTimestamp);

        //Init Module
        reocurringPaymentManager.init(
            _proposal, _METADATA, abi.encode(epochLength)
        );
    }
}
