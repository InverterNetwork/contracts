// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {
    DiscreteCurveMathLib_v1,
    PackedSegmentLib
} from "@fm/bondingCurve/libraries/DiscreteCurveMathLib_v1.sol";
import {PackedSegment} from "@fm/bondingCurve/types/PackedSegment_v1.sol";
import {IDiscreteCurveMathLib_v1} from "@fm/bondingCurve/interfaces/IDiscreteCurveMathLib_v1.sol";
import {DiscreteCurveMathLibV1_Exposed} from "@mocks/modules/fundingManager/bondingCurve/DiscreteCurveMathLibV1_Exposed.sol";

contract DiscreteCurveMathLib_v1_Test is Test {
    // Allow using PackedSegmentLib functions directly on PackedSegment type
    using PackedSegmentLib for PackedSegment;

    DiscreteCurveMathLibV1_Exposed internal exposedLib;

    function setUp() public virtual {
        exposedLib = new DiscreteCurveMathLibV1_Exposed();
    }

    function test_PackAndUnpackSegment() public {
        uint256 expectedInitialPrice = 1 * 1e18; // 1 scaled
        uint256 expectedPriceIncrease = 0.1 ether; // 0.1 scaled (ether keyword is equivalent to 1e18)
        uint256 expectedSupplyPerStep = 100 * 1e18; // 100 tokens
        uint256 expectedNumberOfSteps = 50;

        // Create the packed segment
        // DiscreteCurveMathLib_v1.createSegment is an alias for PackedSegmentLib.create
        PackedSegment segment = DiscreteCurveMathLib_v1.createSegment(
            expectedInitialPrice,
            expectedPriceIncrease,
            expectedSupplyPerStep,
            expectedNumberOfSteps
        );

        // Test individual accessors
        assertEq(segment.initialPrice(), expectedInitialPrice, "PackedSegment: initialPrice mismatch");
        assertEq(segment.priceIncrease(), expectedPriceIncrease, "PackedSegment: priceIncrease mismatch");
        assertEq(segment.supplyPerStep(), expectedSupplyPerStep, "PackedSegment: supplyPerStep mismatch");
        assertEq(segment.numberOfSteps(), expectedNumberOfSteps, "PackedSegment: numberOfSteps mismatch");

        // Test batch unpack
        (
            uint256 actualInitialPrice,
            uint256 actualPriceIncrease,
            uint256 actualSupplyPerStep,
            uint256 actualNumberOfSteps
        ) = segment.unpack();

        assertEq(actualInitialPrice, expectedInitialPrice, "PackedSegment.unpack: initialPrice mismatch");
        assertEq(actualPriceIncrease, expectedPriceIncrease, "PackedSegment.unpack: priceIncrease mismatch");
        assertEq(actualSupplyPerStep, expectedSupplyPerStep, "PackedSegment.unpack: supplyPerStep mismatch");
        assertEq(actualNumberOfSteps, expectedNumberOfSteps, "PackedSegment.unpack: numberOfSteps mismatch");
    }

    // Test validation in createSegment (which calls PackedSegmentLib.create)
    function test_CreateSegment_InitialPriceTooLarge_Reverts() public {
        uint256 tooLargePrice = (1 << 72); // Exceeds INITIAL_PRICE_MASK
        vm.expectRevert(IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__InitialPriceTooLarge.selector);
        exposedLib.createSegmentPublic(
            tooLargePrice,
            0.1 ether,
            100e18,
            50
        );
    }

    function test_CreateSegment_PriceIncreaseTooLarge_Reverts() public {
        uint256 tooLargeIncrease = (1 << 72); // Exceeds PRICE_INCREASE_MASK
        vm.expectRevert(IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__PriceIncreaseTooLarge.selector);
        exposedLib.createSegmentPublic(
            1e18,
            tooLargeIncrease,
            100e18,
            50
        );
    }

    function test_CreateSegment_SupplyPerStepZero_Reverts() public {
        vm.expectRevert(IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__ZeroSupplyPerStep.selector);
        exposedLib.createSegmentPublic(
            1e18,
            0.1 ether,
            0, // Zero supplyPerStep
            50
        );
    }

    function test_CreateSegment_SupplyPerStepTooLarge_Reverts() public {
        uint256 tooLargeSupply = (1 << 96); // Exceeds SUPPLY_MASK
        vm.expectRevert(IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__SupplyPerStepTooLarge.selector);
        exposedLib.createSegmentPublic(
            1e18,
            0.1 ether,
            tooLargeSupply,
            50
        );
    }
    
    function test_CreateSegment_NumberOfStepsZero_Reverts() public {
        vm.expectRevert(IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__InvalidNumberOfSteps.selector);
        exposedLib.createSegmentPublic(
            1e18,
            0.1 ether,
            100e18,
            0 // Zero numberOfSteps
        );
    }

    function test_CreateSegment_NumberOfStepsTooLarge_Reverts() public {
        uint256 tooLargeSteps = (1 << 16); // Exceeds STEPS_MASK
        vm.expectRevert(IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__InvalidNumberOfSteps.selector);
        exposedLib.createSegmentPublic(
            1e18,
            0.1 ether,
            100e18,
            tooLargeSteps
        );
    }
}
