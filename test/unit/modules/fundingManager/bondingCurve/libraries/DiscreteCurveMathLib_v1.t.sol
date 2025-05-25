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

    function test_FindPositionForSupply_SingleSegment_WithinStep() public {
        PackedSegment[] memory segments = new PackedSegment[](1);
        uint256 initialPrice = 1 ether;
        uint256 priceIncrease = 0.1 ether;
        uint256 supplyPerStep = 10 ether; // 10 tokens with 18 decimals
        uint256 numberOfSteps = 5;       // Total supply in segment = 50 tokens

        segments[0] = DiscreteCurveMathLib_v1.createSegment(
            initialPrice,
            priceIncrease,
            supplyPerStep,
            numberOfSteps
        );

        uint256 targetSupply = 25 ether; // Target 25 tokens

        DiscreteCurveMathLib_v1.CurvePosition memory pos = exposedLib.findPositionForSupplyPublic(segments, targetSupply);

        assertEq(pos.segmentIndex, 0, "Segment index mismatch");
        // Step 0 covers 0-10. Step 1 covers 10-20. Step 2 covers 20-30.
        // Target 25 is within step 2.
        // supplyNeededFromThisSegment = 25. stepIndex = 25 / 10 = 2.
        assertEq(pos.stepIndexWithinSegment, 2, "Step index mismatch");
        uint256 expectedPrice = initialPrice + (2 * priceIncrease); // Price at step 2
        assertEq(pos.priceAtCurrentStep, expectedPrice, "Price mismatch");
        assertEq(pos.supplyCoveredUpToThisPosition, targetSupply, "Supply covered mismatch");
    }

    function test_FindPositionForSupply_SingleSegment_EndOfSegment() public {
        PackedSegment[] memory segments = new PackedSegment[](1);
        uint256 initialPrice = 1 ether;
        uint256 priceIncrease = 0.1 ether;
        uint256 supplyPerStep = 10 ether; 
        uint256 numberOfSteps = 2;       // Total supply in segment = 20 tokens

        segments[0] = DiscreteCurveMathLib_v1.createSegment(
            initialPrice,
            priceIncrease,
            supplyPerStep,
            numberOfSteps
        );

        uint256 targetSupply = 20 ether; // Exactly fills the segment

        DiscreteCurveMathLib_v1.CurvePosition memory pos = exposedLib.findPositionForSupplyPublic(segments, targetSupply);

        assertEq(pos.segmentIndex, 0, "Segment index mismatch");
        // Step 0 (0-10), Step 1 (10-20). Target 20 fills step 1.
        // supplyNeeded = 20. stepIndex = 20/10 = 2. Corrected to 2-1 = 1.
        assertEq(pos.stepIndexWithinSegment, 1, "Step index mismatch"); 
        uint256 expectedPrice = initialPrice + (1 * priceIncrease); // Price at step 1
        assertEq(pos.priceAtCurrentStep, expectedPrice, "Price mismatch");
        assertEq(pos.supplyCoveredUpToThisPosition, targetSupply, "Supply covered mismatch");
    }

    function test_FindPositionForSupply_MultiSegment_Spanning() public {
        PackedSegment[] memory segments = new PackedSegment[](2);

        // Segment 0
        uint256 initialPrice0 = 1 ether;
        uint256 priceIncrease0 = 0.1 ether;
        uint256 supplyPerStep0 = 10 ether;
        uint256 numberOfSteps0 = 2; // Total supply in segment 0 = 20 ether
        segments[0] = DiscreteCurveMathLib_v1.createSegment(initialPrice0, priceIncrease0, supplyPerStep0, numberOfSteps0);

        // Segment 1
        uint256 initialPrice1 = 1.2 ether; // Price after segment 0 (1 + 2*0.1 = 1.2, or price of step index 1 is 1.1)
                                          // Price of step 0 is 1.0, price of step 1 is 1.1. Max supply is 20.
                                          // Next segment starts at 1.2
        uint256 priceIncrease1 = 0.05 ether;
        uint256 supplyPerStep1 = 5 ether;
        uint256 numberOfSteps1 = 3; // Total supply in segment 1 = 15 ether
        segments[1] = DiscreteCurveMathLib_v1.createSegment(initialPrice1, priceIncrease1, supplyPerStep1, numberOfSteps1);

        // Target supply: 28 ether
        // Segment 0 provides 20 ether.
        // Remaining needed: 28 - 20 = 8 ether from Segment 1.
        // Segment 1, step 0 (supply 5 ether, total 20+5=25), price 1.2 ether
        // Segment 1, step 1 (supply 5 ether, total 25+5=30), price 1.25 ether. Target 28 falls here.
        uint256 targetSupply = 28 ether;

        DiscreteCurveMathLib_v1.CurvePosition memory pos = exposedLib.findPositionForSupplyPublic(segments, targetSupply);

        assertEq(pos.segmentIndex, 1, "Segment index mismatch");
        // Supply from seg0 = 20. Supply needed from seg1 = 8.
        // Step 0 of seg1 covers supply 0-5 (total 20-25).
        // Step 1 of seg1 covers supply 5-10 (total 25-30).
        // 8 supply needed from seg1 falls into step 1 (0-indexed).
        // supplyNeededFromThisSegment (seg1) = 8. stepIndex = 8 / 5 = 1.
        assertEq(pos.stepIndexWithinSegment, 1, "Step index mismatch for segment 1");
        
        uint256 expectedPrice = initialPrice1 + (1 * priceIncrease1); // Price at step 1 of segment 1
        assertEq(pos.priceAtCurrentStep, expectedPrice, "Price mismatch for segment 1");
        assertEq(pos.supplyCoveredUpToThisPosition, targetSupply, "Supply covered mismatch");
    }

    function test_FindPositionForSupply_TargetBeyondCapacity() public {
        PackedSegment[] memory segments = new PackedSegment[](2);

        // Segment 0
        uint256 initialPrice0 = 1 ether;
        uint256 priceIncrease0 = 0.1 ether;
        uint256 supplyPerStep0 = 10 ether;
        uint256 numberOfSteps0 = 2; // Total supply in segment 0 = 20 ether
        segments[0] = DiscreteCurveMathLib_v1.createSegment(initialPrice0, priceIncrease0, supplyPerStep0, numberOfSteps0);

        // Segment 1
        uint256 initialPrice1 = 1.2 ether;
        uint256 priceIncrease1 = 0.05 ether;
        uint256 supplyPerStep1 = 5 ether;
        uint256 numberOfSteps1 = 3; // Total supply in segment 1 = 15 ether
        segments[1] = DiscreteCurveMathLib_v1.createSegment(initialPrice1, priceIncrease1, supplyPerStep1, numberOfSteps1);
        
        // Total curve capacity = 20 (seg0) + 15 (seg1) = 35 ether.
        uint256 totalCurveCapacity = (supplyPerStep0 * numberOfSteps0) + (supplyPerStep1 * numberOfSteps1);
        uint256 targetSupply = 40 ether; // Beyond capacity

        DiscreteCurveMathLib_v1.CurvePosition memory pos = exposedLib.findPositionForSupplyPublic(segments, targetSupply);

        assertEq(pos.segmentIndex, 1, "Segment index should be last segment");
        assertEq(pos.stepIndexWithinSegment, numberOfSteps1 - 1, "Step index should be last step of last segment");
        
        uint256 expectedPriceAtEndOfCurve = initialPrice1 + ((numberOfSteps1 - 1) * priceIncrease1);
        assertEq(pos.priceAtCurrentStep, expectedPriceAtEndOfCurve, "Price should be at end of last segment");
        assertEq(pos.supplyCoveredUpToThisPosition, totalCurveCapacity, "Supply covered should be total curve capacity");
    }

    function test_FindPositionForSupply_TargetSupplyZero() public {
        PackedSegment[] memory segments = new PackedSegment[](1);
        uint256 initialPrice = 1 ether;
        uint256 priceIncrease = 0.1 ether;
        uint256 supplyPerStep = 10 ether;
        uint256 numberOfSteps = 5;

        segments[0] = DiscreteCurveMathLib_v1.createSegment(
            initialPrice,
            priceIncrease,
            supplyPerStep,
            numberOfSteps
        );

        uint256 targetSupply = 0 ether;

        DiscreteCurveMathLib_v1.CurvePosition memory pos = exposedLib.findPositionForSupplyPublic(segments, targetSupply);

        assertEq(pos.segmentIndex, 0, "Segment index should be 0 for target supply 0");
        assertEq(pos.stepIndexWithinSegment, 0, "Step index should be 0 for target supply 0");
        assertEq(pos.priceAtCurrentStep, initialPrice, "Price should be initial price of first segment for target supply 0");
        assertEq(pos.supplyCoveredUpToThisPosition, 0, "Supply covered should be 0 for target supply 0");
    }

    function test_FindPositionForSupply_NoSegments_Reverts() public {
        PackedSegment[] memory segments = new PackedSegment[](0); // Empty array
        uint256 targetSupply = 10 ether;

        vm.expectRevert(IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__NoSegmentsConfigured.selector);
        exposedLib.findPositionForSupplyPublic(segments, targetSupply);
    }

    function test_FindPositionForSupply_TooManySegments_Reverts() public {
        // MAX_SEGMENTS is 10 in the library
        PackedSegment[] memory segments = new PackedSegment[](DiscreteCurveMathLib_v1.MAX_SEGMENTS + 1);
        // Fill with dummy segments, actual content doesn't matter for this check
        for (uint256 i = 0; i < segments.length; ++i) {
            segments[i] = DiscreteCurveMathLib_v1.createSegment(1,0,1,1);
        }
        uint256 targetSupply = 10 ether;

        vm.expectRevert(IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__TooManySegments.selector);
        exposedLib.findPositionForSupplyPublic(segments, targetSupply);
    }

    // --- Tests for getCurrentPriceAndStep ---

    function test_GetCurrentPriceAndStep_SupplyZero() public {
        PackedSegment[] memory segments = new PackedSegment[](1);
        uint256 initialPrice = 1 ether;
        uint256 priceIncrease = 0.1 ether;
        uint256 supplyPerStep = 10 ether;
        uint256 numberOfSteps = 5;

        segments[0] = DiscreteCurveMathLib_v1.createSegment(
            initialPrice,
            priceIncrease,
            supplyPerStep,
            numberOfSteps
        );

        uint256 currentSupply = 0 ether;
        (uint256 price, uint256 stepIdx, uint256 segmentIdx) = exposedLib.getCurrentPriceAndStepPublic(segments, currentSupply);

        assertEq(segmentIdx, 0, "Segment index should be 0 for current supply 0");
        assertEq(stepIdx, 0, "Step index should be 0 for current supply 0");
        assertEq(price, initialPrice, "Price should be initial price of first segment for current supply 0");
    }

    function test_GetCurrentPriceAndStep_WithinStep_NotBoundary() public {
        PackedSegment[] memory segments = new PackedSegment[](1);
        uint256 initialPrice = 1 ether;
        uint256 priceIncrease = 0.1 ether;
        uint256 supplyPerStep = 10 ether;
        uint256 numberOfSteps = 5; // Segment capacity 50 ether

        segments[0] = DiscreteCurveMathLib_v1.createSegment(
            initialPrice,
            priceIncrease,
            supplyPerStep,
            numberOfSteps
        );

        // Current supply is 15 ether.
        // Step 0: 0-10 supply, price 1.0
        // Step 1: 10-20 supply, price 1.1. 15 ether falls in this step.
        uint256 currentSupply = 15 ether;
        (uint256 price, uint256 stepIdx, uint256 segmentIdx) = exposedLib.getCurrentPriceAndStepPublic(segments, currentSupply);

        assertEq(segmentIdx, 0, "Segment index mismatch");
        assertEq(stepIdx, 1, "Step index mismatch - should be step 1"); // _findPositionForSupply gives stepIndex 1 for supply 15
        uint256 expectedPrice = initialPrice + (1 * priceIncrease); // Price of step 1
        assertEq(price, expectedPrice, "Price mismatch - should be price of step 1");
    }

    function test_GetCurrentPriceAndStep_EndOfStep_NotEndOfSegment() public {
        PackedSegment[] memory segments = new PackedSegment[](1);
        uint256 initialPrice = 1 ether;
        uint256 priceIncrease = 0.1 ether;
        uint256 supplyPerStep = 10 ether;
        uint256 numberOfSteps = 5; // Segment capacity 50 ether

        segments[0] = DiscreteCurveMathLib_v1.createSegment(
            initialPrice,
            priceIncrease,
            supplyPerStep,
            numberOfSteps
        );

        // Current supply is 10 ether, exactly at the end of step 0.
        // Price should be for step 1.
        uint256 currentSupply = 10 ether;
        (uint256 price, uint256 stepIdx, uint256 segmentIdx) = exposedLib.getCurrentPriceAndStepPublic(segments, currentSupply);

        assertEq(segmentIdx, 0, "Segment index mismatch");
        assertEq(stepIdx, 1, "Step index should advance to 1"); 
        uint256 expectedPrice = initialPrice + (1 * priceIncrease); // Price of step 1
        assertEq(price, expectedPrice, "Price should be for step 1");
    }

    function test_GetCurrentPriceAndStep_EndOfSegment_NotLastSegment() public {
        PackedSegment[] memory segments = new PackedSegment[](2);

        // Segment 0
        uint256 initialPrice0 = 1 ether;
        uint256 priceIncrease0 = 0.1 ether;
        uint256 supplyPerStep0 = 10 ether;
        uint256 numberOfSteps0 = 2; // Total supply in segment 0 = 20 ether
        segments[0] = DiscreteCurveMathLib_v1.createSegment(initialPrice0, priceIncrease0, supplyPerStep0, numberOfSteps0);

        // Segment 1
        uint256 initialPrice1 = 1.2 ether;
        uint256 priceIncrease1 = 0.05 ether;
        uint256 supplyPerStep1 = 5 ether;
        uint256 numberOfSteps1 = 3; 
        segments[1] = DiscreteCurveMathLib_v1.createSegment(initialPrice1, priceIncrease1, supplyPerStep1, numberOfSteps1);

        // Current supply is 20 ether, exactly at the end of segment 0.
        // Price/step should be for the start of segment 1.
        uint256 currentSupply = 20 ether; 
        (uint256 price, uint256 stepIdx, uint256 segmentIdx) = exposedLib.getCurrentPriceAndStepPublic(segments, currentSupply);

        assertEq(segmentIdx, 1, "Segment index should advance to 1");
        assertEq(stepIdx, 0, "Step index should be 0 of segment 1"); 
        assertEq(price, initialPrice1, "Price should be initial price of segment 1");
    }

    function test_GetCurrentPriceAndStep_EndOfLastSegment() public {
        PackedSegment[] memory segments = new PackedSegment[](2);
        // Segment 0
        uint256 initialPrice0 = 1 ether;
        uint256 priceIncrease0 = 0.1 ether;
        uint256 supplyPerStep0 = 10 ether;
        uint256 numberOfSteps0 = 2; // Capacity 20
        segments[0] = DiscreteCurveMathLib_v1.createSegment(initialPrice0, priceIncrease0, supplyPerStep0, numberOfSteps0);
        // Segment 1
        uint256 initialPrice1 = 1.2 ether;
        uint256 priceIncrease1 = 0.05 ether;
        uint256 supplyPerStep1 = 5 ether;
        uint256 numberOfSteps1 = 3; // Capacity 15
        segments[1] = DiscreteCurveMathLib_v1.createSegment(initialPrice1, priceIncrease1, supplyPerStep1, numberOfSteps1);
        
        uint256 totalCurveCapacity = (supplyPerStep0 * numberOfSteps0) + (supplyPerStep1 * numberOfSteps1); // 35 ether
        uint256 currentSupply = totalCurveCapacity;

        (uint256 price, uint256 stepIdx, uint256 segmentIdx) = exposedLib.getCurrentPriceAndStepPublic(segments, currentSupply);

        assertEq(segmentIdx, 1, "Segment index should be last segment (1)");
        assertEq(stepIdx, numberOfSteps1 - 1, "Step index should be last step of last segment"); // step 2
        uint256 expectedPrice = initialPrice1 + ((numberOfSteps1 - 1) * priceIncrease1); // 1.2 + 2*0.05 = 1.3
        assertEq(price, expectedPrice, "Price should be price of last step of last segment");
    }

    function test_GetCurrentPriceAndStep_SupplyBeyondCapacity_Reverts() public {
        PackedSegment[] memory segments = new PackedSegment[](1);
        segments[0] = DiscreteCurveMathLib_v1.createSegment(1 ether, 0, 10 ether, 2); // Capacity 20
        
        uint256 currentSupply = 25 ether; // Beyond capacity

        vm.expectRevert(IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__TargetSupplyBeyondCurveCapacity.selector);
        exposedLib.getCurrentPriceAndStepPublic(segments, currentSupply);
    }

    function test_GetCurrentPriceAndStep_NoSegments_SupplyPositive_Reverts() public {
        PackedSegment[] memory segments = new PackedSegment[](0);
        uint256 currentSupply = 1 ether;

        // This revert comes from _findPositionForSupply
        vm.expectRevert(IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__NoSegmentsConfigured.selector);
        exposedLib.getCurrentPriceAndStepPublic(segments, currentSupply);
    }

    // --- Tests for calculateReserveForSupply ---

    function test_CalculateReserveForSupply_TargetSupplyZero() public {
        PackedSegment[] memory segments = new PackedSegment[](1);
        segments[0] = DiscreteCurveMathLib_v1.createSegment(1 ether, 0.1 ether, 10 ether, 5);
        
        uint256 reserve = exposedLib.calculateReserveForSupplyPublic(segments, 0);
        assertEq(reserve, 0, "Reserve for 0 supply should be 0");
    }

    function test_CalculateReserveForSupply_SingleFlatSegment_Partial() public {
        PackedSegment[] memory segments = new PackedSegment[](1);
        uint256 initialPrice = 2 ether;
        uint256 priceIncrease = 0; // Flat segment
        uint256 supplyPerStep = 10 ether;
        uint256 numberOfSteps = 5; // Total capacity 50 ether
        segments[0] = DiscreteCurveMathLib_v1.createSegment(initialPrice, priceIncrease, supplyPerStep, numberOfSteps);

        // Target 3 steps (30 ether supply)
        uint256 targetSupply = 30 ether; 
        // Expected reserve: 3 steps * 10 supply/step * 2 price/token = 60 ether (scaled)
        // (30 ether * 2 ether) / 1e18 = 60 ether
        uint256 expectedReserve = (30 ether * initialPrice) / DiscreteCurveMathLib_v1.SCALING_FACTOR;

        uint256 reserve = exposedLib.calculateReserveForSupplyPublic(segments, targetSupply);
        assertEq(reserve, expectedReserve, "Reserve for flat segment partial fill mismatch");
    }

    function test_CalculateReserveForSupply_SingleSlopedSegment_Partial() public {
        PackedSegment[] memory segments = new PackedSegment[](1);
        uint256 initialPrice = 1 ether;
        uint256 priceIncrease = 0.1 ether; 
        uint256 supplyPerStep = 10 ether;
        uint256 numberOfSteps = 5; // Total capacity 50 ether
        segments[0] = DiscreteCurveMathLib_v1.createSegment(initialPrice, priceIncrease, supplyPerStep, numberOfSteps);

        // Target 2 steps (20 ether supply)
        // Step 0: price 1.0, supply 10. Cost = 10 * 1.0 = 10
        // Step 1: price 1.1, supply 10. Cost = 10 * 1.1 = 11
        // Total reserve = (10 + 11) = 21 ether (scaled)
        uint256 targetSupply = 20 ether; 
        
        // Manual calculation:
        // Cost step 0: (10 ether * 1.0 ether) / 1e18 = 10 ether
        // Cost step 1: (10 ether * 1.1 ether) / 1e18 = 11 ether
        // Total = 21 ether
        uint256 expectedReserve = ((10 ether * (initialPrice + 0 * priceIncrease)) + (10 ether * (initialPrice + 1 * priceIncrease))) / DiscreteCurveMathLib_v1.SCALING_FACTOR;

        uint256 reserve = exposedLib.calculateReserveForSupplyPublic(segments, targetSupply);
        assertEq(reserve, expectedReserve, "Reserve for sloped segment partial fill mismatch");
    }
}
