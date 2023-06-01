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
    IReocurringPaymentManager,
    IPaymentClient
} from "src/modules/LogicModule/ReocurringPaymentManager.sol";

contract ReocurringPaymentManagerTest is ModuleTest {
    // SuT
    ReocurringPaymentManager reocurringPaymentManager;

    uint private constant _SENTINEL = type(uint).max;

    event ReocurringPaymentAdded(
        uint indexed reocurringPaymentId,
        uint amount,
        uint startEpoch,
        uint lastTriggeredEpoch,
        address recipient
    );
    event ReocurringPaymentRemoved(uint indexed reocurringPaymentId);
    event ReocurringPaymentsTriggered(uint indexed currentEpoch);

    function setUp() public {
        //Add Module to Mock Proposal
        address impl = address(new ReocurringPaymentManager());
        reocurringPaymentManager = ReocurringPaymentManager(Clones.clone(impl));

        _setUpProposal(reocurringPaymentManager);
        _authorizer.setIsAuthorized(address(this), true);
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
                1, reocurringPaymentManager.getCurrentEpoch(), address(0xBEEF)
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
    // Just test if Modifier is in position, because otherwise trivial

    function testGetReocurringPaymentInformationModifierInPosition() public {
        vm.expectRevert(
            IReocurringPaymentManager
                .Module__ReocurringPaymentManager__InvalidReocurringPaymentId
                .selector
        );
        reocurringPaymentManager.getReocurringPaymentInformation(0);
    }

    //--------------------------------------------------------------------------
    // Epoch Functions
    //@todo Kinda trivial to test, should I do it anyway?

    //--------------------------------------------------------------------------
    // Mutating Functions

    //-----------------------------------------
    //AddReocurringPayment

    function testAddReocurringPayment(
        uint seed,
        uint amount,
        uint startEpoch,
        address recipient
    ) public {
        reasonableWarpAndInit(seed);

        //Assume correct inputs
        vm.assume(
            recipient != address(0)
                && recipient != address(reocurringPaymentManager)
        );
        amount = bound(amount, 1, type(uint).max);
        uint currentEpoch = reocurringPaymentManager.getCurrentEpoch();
        startEpoch = bound(startEpoch, currentEpoch, type(uint).max);

        vm.expectEmit(true, true, true, true);
        emit ReocurringPaymentAdded(
            1, //Id starts at 1
            amount,
            startEpoch,
            startEpoch - 1, //lastTriggeredEpoch has to be startEpoch - 1
            recipient
        );
        reocurringPaymentManager.addReocurringPayment(
            amount, startEpoch, recipient
        );

        assertEqualReocurringPayment(
            1, amount, startEpoch, startEpoch - 1, recipient
        );

        //Check for multiple Adds
        uint id;
        uint length = bound(amount, 1, 30); //Reasonable amount
        for (uint i = 2; i < length + 2; i++) {
            vm.expectEmit(true, true, true, true);
            emit ReocurringPaymentAdded(
                i, //Id starts at 1
                1,
                currentEpoch,
                currentEpoch - 1, //lastTriggeredEpoch has to be startEpoch - 1
                address(0xBEEF)
            );
            id = reocurringPaymentManager.addReocurringPayment(
                1, currentEpoch, address(0xBEEF)
            );
            assertEq(id, i); //Maybe a bit overtested, that id is correct but ¯\_(ツ)_/¯
            assertEqualReocurringPayment(
                i, 1, currentEpoch, currentEpoch - 1, address(0xBEEF)
            );
        }
    }

    function testAddReocurringPaymentModifierInPosition() public {
        //Init Module
        reocurringPaymentManager.init(_proposal, _METADATA, abi.encode(1 weeks));

        //Warp to a reasonable time
        vm.warp(2 weeks);

        //onlyAuthorizedOrManager
        vm.prank(address(0xBEEF)); //Not Authorized

        vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
        reocurringPaymentManager.addReocurringPayment(
            1, 2 weeks, address(0xBEEF)
        );

        //validAmount
        vm.expectRevert(
            IPaymentClient.Module__PaymentClient__InvalidAmount.selector
        );
        reocurringPaymentManager.addReocurringPayment(
            0, 2 weeks, address(0xBEEF)
        );

        //validStartEpoch

        vm.expectRevert(
            IReocurringPaymentManager
                .Module__ReocurringPaymentManager__InvalidStartEpoch
                .selector
        );
        reocurringPaymentManager.addReocurringPayment(1, 0, address(0xBEEF));

        //validRecipient

        vm.expectRevert(
            IPaymentClient.Module__PaymentClient__InvalidRecipient.selector
        );
        reocurringPaymentManager.addReocurringPayment(1, 2 weeks, address(0));
    }

    //-----------------------------------------
    //RemoveReocurringPayment

    function testRemoveReocurringPayment(uint seed, uint amount) public {
        reasonableWarpAndInit(seed);
        amount = bound(amount, 1, 30); //Reasonable number of repetitions

        uint currentEpoch = reocurringPaymentManager.getCurrentEpoch();

        // Fill list with ReocurringPayments.
        for (uint i; i < amount; ++i) {
            reocurringPaymentManager.addReocurringPayment(
                1, currentEpoch, address(0xBEEF)
            );
        }

        // Remove ReocurringPayments from the front, i.e. lowest ReocurringPayment id, until
        // list is empty.
        for (uint i; i < amount; ++i) {
            uint id = i + 1; // Note that id's start at 1.

            vm.expectEmit(true, true, true, true);
            emit ReocurringPaymentRemoved(id);

            reocurringPaymentManager.removeReocurringPayment(_SENTINEL, id);
            assertEq(
                reocurringPaymentManager.listReocurringPaymentIds().length,
                amount - i - 1
            );
        }

        // Fill list again with milestones.
        for (uint i; i < amount; ++i) {
            reocurringPaymentManager.addReocurringPayment(
                1, currentEpoch, address(0xBEEF)
            );
        }

        // Remove milestones from the back, i.e. highest milestone id, until
        // list is empty.
        for (uint i; i < amount; ++i) {
            // Note that id's start at amount, because they have been created before.
            uint prevId = 2 * amount - i - 1;
            uint id = 2 * amount - i;

            // Note that removing the last milestone requires the sentinel as
            // prevId.
            if (prevId == amount) {
                prevId = _SENTINEL;
            }

            vm.expectEmit(true, true, true, true);
            emit ReocurringPaymentRemoved(id);

            reocurringPaymentManager.removeReocurringPayment(prevId, id);
            assertEq(
                reocurringPaymentManager.listReocurringPaymentIds().length,
                amount - i - 1
            );
        }
    }

    function testRemoveReocurringPaymentModifierInPosition() public {
        //Init Module
        reocurringPaymentManager.init(_proposal, _METADATA, abi.encode(1 weeks));

        //onlyAuthorizedOrManager
        vm.prank(address(0xBEEF)); //Not Authorized

        vm.expectRevert(IModule.Module__CallerNotAuthorized.selector);
        reocurringPaymentManager.removeReocurringPayment(0, 1);
    }

    // =========================================================================

    //--------------------------------------------------------------------------
    // Helper

    function reasonableWarpAndInit(uint seed) internal {
        uint epochLength = bound(seed, 1 weeks, 52 weeks); //@todo I might be able to randomise this even better -> thinking about doing a bitshift split in the middle and get left side and right side

        //with this were at least in epoch 2 and there is enough time to go on from that time (3_153_600_000 seconds are 100 years)
        uint currentTimestamp = bound(seed, 52 weeks + 1, 3_153_600_000);

        //Warp to a reasonable time
        vm.warp(currentTimestamp);

        //Init Module
        reocurringPaymentManager.init(
            _proposal, _METADATA, abi.encode(epochLength)
        );
    }

    function assertEqualReocurringPayment(
        uint idToProve,
        uint amount,
        uint startEpoch,
        uint lastTriggeredEpoch,
        address recipient
    ) internal {
        IReocurringPaymentManager.ReocurringPayment memory payment =
            reocurringPaymentManager.getReocurringPaymentInformation(idToProve);

        assertEq(payment.amount, amount);
        assertEq(payment.startEpoch, startEpoch);
        assertEq(payment.lastTriggeredEpoch, lastTriggeredEpoch);
        assertEq(payment.recipient, recipient);
    }
}
