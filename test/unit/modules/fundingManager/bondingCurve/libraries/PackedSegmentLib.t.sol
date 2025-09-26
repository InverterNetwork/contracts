// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

import {Test, console2} from "forge-std/Test.sol";
import {PackedSegmentLib} from "@fm/bondingCurve/libraries/PackedSegmentLib.sol";
import {PackedSegment} from "@fm/bondingCurve/types/PackedSegment_v1.sol";
import {IDiscreteCurveMathLib_v1} from
    "@fm/bondingCurve/interfaces/IDiscreteCurveMathLib_v1.sol";
// DiscreteCurveMathLib_v1 is imported because test_PackAndUnpackSegment uses its createSegment function.
import {DiscreteCurveMathLib_v1} from
    "@fm/bondingCurve/formulas/DiscreteCurveMathLib_v1.sol";
// DiscreteCurveMathLibV1_Exposed is imported because the revert tests use its public createSegmentPublic,
// which internally calls PackedSegmentLib.create.
import {DiscreteCurveMathLibV1_Exposed} from
    "@mocks/modules/fundingManager/bondingCurve/DiscreteCurveMathLibV1_Exposed.sol";

contract PackedSegmentLib_Test is Test {
    using PackedSegmentLib for PackedSegment;

    DiscreteCurveMathLibV1_Exposed internal exposedLib;

    function setUp() public virtual {
        exposedLib = new DiscreteCurveMathLibV1_Exposed();
    }

    function test_PackAndUnpackSegment() public {
        uint expectedInitialPrice = 1 * 1e18;
        uint expectedPriceIncrease = 0.1 ether;
        uint expectedSupplyPerStep = 100 * 1e18;
        uint expectedNumberOfSteps = 50;

        PackedSegment segment = DiscreteCurveMathLib_v1._createSegment(
            expectedInitialPrice,
            expectedPriceIncrease,
            expectedSupplyPerStep,
            expectedNumberOfSteps
        );

        assertEq(
            segment._initialPrice(),
            expectedInitialPrice,
            "PackedSegment: initialPrice mismatch"
        );
        assertEq(
            segment._priceIncrease(),
            expectedPriceIncrease,
            "PackedSegment: priceIncrease mismatch"
        );
        assertEq(
            segment._supplyPerStep(),
            expectedSupplyPerStep,
            "PackedSegment: supplyPerStep mismatch"
        );
        assertEq(
            segment._numberOfSteps(),
            expectedNumberOfSteps,
            "PackedSegment: numberOfSteps mismatch"
        );

        (
            uint actualInitialPrice,
            uint actualPriceIncrease,
            uint actualSupplyPerStep,
            uint actualNumberOfSteps
        ) = segment._unpack();

        assertEq(
            actualInitialPrice,
            expectedInitialPrice,
            "Packedsegment._unpack: initialPrice mismatch"
        );
        assertEq(
            actualPriceIncrease,
            expectedPriceIncrease,
            "Packedsegment._unpack: priceIncrease mismatch"
        );
        assertEq(
            actualSupplyPerStep,
            expectedSupplyPerStep,
            "Packedsegment._unpack: supplyPerStep mismatch"
        );
        assertEq(
            actualNumberOfSteps,
            expectedNumberOfSteps,
            "Packedsegment._unpack: numberOfSteps mismatch"
        );
    }

    function test_CreateSegment_InitialPriceTooLarge_Reverts() public {
        uint tooLargePrice = (1 << 72);
        vm.expectRevert(
            IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__InitialPriceTooLarge
                .selector
        );
        exposedLib.exposed_createSegment(tooLargePrice, 0.1 ether, 100e18, 50);
    }

    function test_CreateSegment_PriceIncreaseTooLarge_Reverts() public {
        uint tooLargeIncrease = (1 << 72);
        vm.expectRevert(
            IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__PriceIncreaseTooLarge
                .selector
        );
        exposedLib.exposed_createSegment(1e18, tooLargeIncrease, 100e18, 50);
    }

    function test_CreateSegment_SupplyPerStepZero_Reverts() public {
        vm.expectRevert(
            IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__ZeroSupplyPerStep
                .selector
        );
        exposedLib.exposed_createSegment(1e18, 0.1 ether, 0, 50);
    }

    function test_CreateSegment_SupplyPerStepTooLarge_Reverts() public {
        uint tooLargeSupply = (1 << 96);
        vm.expectRevert(
            IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__SupplyPerStepTooLarge
                .selector
        );
        exposedLib.exposed_createSegment(1e18, 0.1 ether, tooLargeSupply, 50);
    }

    function test_CreateSegment_NumberOfStepsZero_Reverts() public {
        vm.expectRevert(
            IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__InvalidNumberOfSteps
                .selector
        );
        exposedLib.exposed_createSegment(1e18, 0.1 ether, 100e18, 0);
    }

    function test_CreateSegment_NumberOfStepsTooLarge_Reverts() public {
        uint tooLargeSteps = (1 << 16);
        vm.expectRevert(
            IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__InvalidNumberOfSteps
                .selector
        );
        exposedLib.exposed_createSegment(1e18, 0.1 ether, 100e18, tooLargeSteps);
    }

    function test_CreateSegment_FreeSegment_Reverts() public {
        // Test that creating a segment with initialPrice = 0 and priceIncrease = 0 reverts.
        // Other parameters should be valid.
        uint initialPrice = 0;
        uint priceIncrease = 0;
        uint supplyPerStep = 10e18; // Valid supply
        uint numberOfSteps = 10; // Valid number of steps

        vm.expectRevert(
            IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__SegmentIsFree
                .selector
        );
        exposedLib.exposed_createSegment(
            initialPrice, priceIncrease, supplyPerStep, numberOfSteps
        );
    }

    function test_CreateSegment_MultiStepFlat_Reverts() public {
        // Test that creating a segment with numberOfSteps > 1 and priceIncrease = 0 reverts.
        uint initialPrice = 1e18; // Valid price
        uint priceIncrease = 0; // Makes it flat
        uint supplyPerStep = 10e18; // Valid supply
        uint numberOfSteps = 2; // Invalid for a flat segment (must be 1)

        vm.expectRevert(
            IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__InvalidFlatSegment
                .selector
        );
        exposedLib.exposed_createSegment(
            initialPrice, priceIncrease, supplyPerStep, numberOfSteps
        );
    }

    function test_CreateSegment_SingleStepSloped_Reverts() public {
        // Test that creating a segment with numberOfSteps = 1 and priceIncrease > 0 reverts.
        uint initialPrice = 1e18; // Valid price
        uint priceIncrease = 0.1 ether; // Makes it sloped
        uint supplyPerStep = 10e18; // Valid supply
        uint numberOfSteps = 1; // Invalid for a sloped segment (must be > 1)

        vm.expectRevert(
            IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__InvalidPointSegment
                .selector
        );
        exposedLib.exposed_createSegment(
            initialPrice, priceIncrease, supplyPerStep, numberOfSteps
        );
    }
}
