// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {
    DiscreteCurveMathLib_v1,
    PackedSegmentLib
} from "@fm/bondingCurve/formulas/DiscreteCurveMathLib_v1.sol";
import {PackedSegment} from "@fm/bondingCurve/types/PackedSegment_v1.sol";
import {IDiscreteCurveMathLib_v1} from
    "@fm/bondingCurve/interfaces/IDiscreteCurveMathLib_v1.sol";
import {DiscreteCurveMathLibV1_Exposed} from
    "@mocks/modules/fundingManager/bondingCurve/DiscreteCurveMathLibV1_Exposed.sol";

contract DiscreteCurveMathLib_v1_Test is Test {
    // Allow using PackedSegmentLib functions directly on PackedSegment type
    using PackedSegmentLib for PackedSegment;

    DiscreteCurveMathLibV1_Exposed internal exposedLib;

    // Default curve configuration
    PackedSegment[] internal defaultSegments;

    // Parameters for default curve segments (for clarity in setUp and tests)
    uint internal defaultSeg0_initialPrice;
    uint internal defaultSeg0_priceIncrease;
    uint internal defaultSeg0_supplyPerStep;
    uint internal defaultSeg0_numberOfSteps;
    uint internal defaultSeg0_capacity;
    uint internal defaultSeg0_reserve;

    uint internal defaultSeg1_initialPrice;
    uint internal defaultSeg1_priceIncrease;
    uint internal defaultSeg1_supplyPerStep;
    uint internal defaultSeg1_numberOfSteps;
    uint internal defaultSeg1_capacity;
    uint internal defaultSeg1_reserve;

    uint internal defaultCurve_totalCapacity;
    uint internal defaultCurve_totalReserve;

    // Default Bonding Curve Visualization (Price vs. Supply)
    // Based on defaultSegments initialized in setUp():
    // Seg0: P_init=1.0, P_inc=0.1, S_step=10, N_steps=3  (Prices: 1.0, 1.1, 1.2)
    // Seg1: P_init=1.5, P_inc=0.05, S_step=20, N_steps=2 (Prices: 1.5, 1.55)
    //
    //     Price (ether)
    //       ^
    //     1.55|                   +------+ (Supply: 70)
    //         |                   |      |
    //     1.50|           +-------+      | (Supply: 50)
    //         |           |              |
    //         |           |              |
    //     1.20|       +---+              | (Supply: 30)
    //         |       |                  |
    //     1.10|   +---+                  | (Supply: 20)
    //         |   |                      |
    //     1.00|---+                      | (Supply: 10)
    //         +---+---+---+------+-------+--> Supply (ether)
    //         0   10  20  30     50     70
    //
    //          Step Prices:
    //          Supply  0-10:  Price 1.00 (Segment 0, Step 0)
    //          Supply 10-20:  Price 1.10 (Segment 0, Step 1)
    //          Supply 20-30:  Price 1.20 (Segment 0, Step 2)
    //          Supply 30-50:  Price 1.50 (Segment 1, Step 0)
    //          Supply 50-70:  Price 1.55 (Segment 1, Step 1)

    function setUp() public virtual {
        exposedLib = new DiscreteCurveMathLibV1_Exposed();

        // Initialize default curve parameters
        // Segment 0 (Sloped)
        defaultSeg0_initialPrice = 1 ether;
        defaultSeg0_priceIncrease = 0.1 ether;
        defaultSeg0_supplyPerStep = 10 ether;
        defaultSeg0_numberOfSteps = 3; // Prices: 1.0, 1.1, 1.2
        defaultSeg0_capacity =
            defaultSeg0_supplyPerStep * defaultSeg0_numberOfSteps; // 30 ether
        defaultSeg0_reserve = 0;
        defaultSeg0_reserve += (
            defaultSeg0_supplyPerStep
                * (defaultSeg0_initialPrice + 0 * defaultSeg0_priceIncrease)
        ) / DiscreteCurveMathLib_v1.SCALING_FACTOR; // 10
        defaultSeg0_reserve += (
            defaultSeg0_supplyPerStep
                * (defaultSeg0_initialPrice + 1 * defaultSeg0_priceIncrease)
        ) / DiscreteCurveMathLib_v1.SCALING_FACTOR; // 11
        defaultSeg0_reserve += (
            defaultSeg0_supplyPerStep
                * (defaultSeg0_initialPrice + 2 * defaultSeg0_priceIncrease)
        ) / DiscreteCurveMathLib_v1.SCALING_FACTOR; // 12
        // Total reserve for seg0 = 10 + 11 + 12 = 33 ether

        // Segment 1 (Sloped)
        defaultSeg1_initialPrice = 1.5 ether;
        defaultSeg1_priceIncrease = 0.05 ether;
        defaultSeg1_supplyPerStep = 20 ether;
        defaultSeg1_numberOfSteps = 2; // Prices: 1.5, 1.55
        defaultSeg1_capacity =
            defaultSeg1_supplyPerStep * defaultSeg1_numberOfSteps; // 40 ether
        defaultSeg1_reserve = 0;
        defaultSeg1_reserve += (
            defaultSeg1_supplyPerStep
                * (defaultSeg1_initialPrice + 0 * defaultSeg1_priceIncrease)
        ) / DiscreteCurveMathLib_v1.SCALING_FACTOR; // 30
        defaultSeg1_reserve += (
            defaultSeg1_supplyPerStep
                * (defaultSeg1_initialPrice + 1 * defaultSeg1_priceIncrease)
        ) / DiscreteCurveMathLib_v1.SCALING_FACTOR; // 31
        // Total reserve for seg1 = 30 + 31 = 61 ether

        defaultCurve_totalCapacity = defaultSeg0_capacity + defaultSeg1_capacity; // 30 + 40 = 70 ether
        defaultCurve_totalReserve = defaultSeg0_reserve + defaultSeg1_reserve; // 33 + 61 = 94 ether

        // Create default segments array
        defaultSegments = new PackedSegment[](2);
        defaultSegments[0] = DiscreteCurveMathLib_v1.createSegment(
            defaultSeg0_initialPrice,
            defaultSeg0_priceIncrease,
            defaultSeg0_supplyPerStep,
            defaultSeg0_numberOfSteps
        );
        defaultSegments[1] = DiscreteCurveMathLib_v1.createSegment(
            defaultSeg1_initialPrice,
            defaultSeg1_priceIncrease,
            defaultSeg1_supplyPerStep,
            defaultSeg1_numberOfSteps
        );
    }

    function test_FindPositionForSupply_SingleSegment_WithinStep() public {
        PackedSegment[] memory segments = new PackedSegment[](1);
        uint initialPrice = 1 ether;
        uint priceIncrease = 0.1 ether;
        uint supplyPerStep = 10 ether; // 10 tokens with 18 decimals
        uint numberOfSteps = 5; // Total supply in segment = 50 tokens

        segments[0] = DiscreteCurveMathLib_v1.createSegment(
            initialPrice, priceIncrease, supplyPerStep, numberOfSteps
        );

        uint targetSupply = 25 ether; // Target 25 tokens

        IDiscreteCurveMathLib_v1.CurvePosition memory pos =
            exposedLib.findPositionForSupplyPublic(segments, targetSupply);

        assertEq(pos.segmentIndex, 0, "Segment index mismatch");
        // Step 0 covers 0-10. Step 1 covers 10-20. Step 2 covers 20-30.
        // Target 25 is within step 2.
        // supplyNeededFromThisSegment = 25. stepIndex = 25 / 10 = 2.
        assertEq(pos.stepIndexWithinSegment, 2, "Step index mismatch");
        uint expectedPrice = initialPrice + (2 * priceIncrease); // Price at step 2
        assertEq(pos.priceAtCurrentStep, expectedPrice, "Price mismatch");
        assertEq(
            pos.supplyCoveredUpToThisPosition,
            targetSupply,
            "Supply covered mismatch"
        );
    }

    function test_FindPositionForSupply_SingleSegment_EndOfSegment() public {
        PackedSegment[] memory segments = new PackedSegment[](1);
        uint initialPrice = 1 ether;
        uint priceIncrease = 0.1 ether;
        uint supplyPerStep = 10 ether;
        uint numberOfSteps = 2; // Total supply in segment = 20 tokens

        segments[0] = DiscreteCurveMathLib_v1.createSegment(
            initialPrice, priceIncrease, supplyPerStep, numberOfSteps
        );

        uint targetSupply = 20 ether; // Exactly fills the segment

        IDiscreteCurveMathLib_v1.CurvePosition memory pos =
            exposedLib.findPositionForSupplyPublic(segments, targetSupply);

        assertEq(pos.segmentIndex, 0, "Segment index mismatch");
        // Step 0 (0-10), Step 1 (10-20). Target 20 fills step 1.
        // supplyNeeded = 20. stepIndex = 20/10 = 2. Corrected to 2-1 = 1.
        assertEq(pos.stepIndexWithinSegment, 1, "Step index mismatch");
        uint expectedPrice = initialPrice + (1 * priceIncrease); // Price at step 1
        assertEq(pos.priceAtCurrentStep, expectedPrice, "Price mismatch");
        assertEq(
            pos.supplyCoveredUpToThisPosition,
            targetSupply,
            "Supply covered mismatch"
        );
    }

    function test_FindPositionForSupply_MultiSegment_Spanning() public {
        // Uses the `defaultSegments` initialized in setUp()
        // Default Seg0: initialPrice 1, increase 0.1, supplyPerStep 10, steps 3. Capacity 30.
        // Default Seg1: initialPrice 1.5, increase 0.05, supplyPerStep 20, steps 2. Capacity 40.

        // Target supply: 40 ether
        // Segment 0 (default) provides 30 ether (10*3).
        // Remaining needed: 40 - 30 = 10 ether from Segment 1.
        // Segment 1 (default): supplyPerStep = 20 ether.
        //   Step 0 of seg1 covers supply 0-20 (total 30-50 for the curve). Price 1.5 ether.
        //   Target 10 ether from Segment 1 falls into its step 0.
        uint targetSupply = defaultSeg0_capacity + 10 ether; // 30 + 10 = 40 ether

        IDiscreteCurveMathLib_v1.CurvePosition memory pos = exposedLib
            .findPositionForSupplyPublic(defaultSegments, targetSupply);

        assertEq(pos.segmentIndex, 1, "Segment index mismatch");
        // Supply from seg0 = 30. Supply needed from seg1 = 10.
        // Step 0 of seg1 covers supply 0-20 (relative to seg1 start).
        // 10 supply needed from seg1 falls into step 0 (0-indexed).
        // supplyNeededFromThisSegment (seg1) = 10. stepIndex = 10 / 20 (defaultSeg1_supplyPerStep) = 0.
        assertEq(
            pos.stepIndexWithinSegment, 0, "Step index mismatch for segment 1"
        );

        uint expectedPrice =
            defaultSeg1_initialPrice + (0 * defaultSeg1_priceIncrease); // Price at step 0 of segment 1
        assertEq(
            pos.priceAtCurrentStep,
            expectedPrice,
            "Price mismatch for segment 1"
        );
        assertEq(
            pos.supplyCoveredUpToThisPosition,
            targetSupply,
            "Supply covered mismatch"
        );
    }

    function test_FindPositionForSupply_TargetBeyondCapacity() public {
        // Uses defaultSegments
        // defaultCurve_totalCapacity = 70 ether
        uint targetSupply = defaultCurve_totalCapacity + 10 ether; // Beyond capacity (70 + 10 = 80)

        IDiscreteCurveMathLib_v1.CurvePosition memory pos = exposedLib
            .findPositionForSupplyPublic(defaultSegments, targetSupply);

        assertEq(
            pos.segmentIndex, 1, "Segment index should be last segment (1)"
        );
        assertEq(
            pos.stepIndexWithinSegment,
            defaultSeg1_numberOfSteps - 1,
            "Step index should be last step of last segment"
        );

        uint expectedPriceAtEndOfCurve = defaultSeg1_initialPrice
            + ((defaultSeg1_numberOfSteps - 1) * defaultSeg1_priceIncrease);
        assertEq(
            pos.priceAtCurrentStep,
            expectedPriceAtEndOfCurve,
            "Price should be at end of last segment"
        );
        assertEq(
            pos.supplyCoveredUpToThisPosition,
            defaultCurve_totalCapacity,
            "Supply covered should be total curve capacity"
        );
    }

    function test_FindPositionForSupply_TargetSupplyZero() public {
        // Using only the first segment of defaultSegments for simplicity
        PackedSegment[] memory segments = new PackedSegment[](1);
        segments[0] = defaultSegments[0];

        uint targetSupply = 0 ether;

        IDiscreteCurveMathLib_v1.CurvePosition memory pos =
            exposedLib.findPositionForSupplyPublic(segments, targetSupply);

        assertEq(
            pos.segmentIndex, 0, "Segment index should be 0 for target supply 0"
        );
        assertEq(
            pos.stepIndexWithinSegment,
            0,
            "Step index should be 0 for target supply 0"
        );
        assertEq(
            pos.priceAtCurrentStep,
            defaultSeg0_initialPrice,
            "Price should be initial price of first segment for target supply 0"
        );
        assertEq(
            pos.supplyCoveredUpToThisPosition,
            0,
            "Supply covered should be 0 for target supply 0"
        );
    }

    function test_FindPositionForSupply_NoSegments_Reverts() public {
        PackedSegment[] memory segments = new PackedSegment[](0); // Empty array
        uint targetSupply = 10 ether;

        vm.expectRevert(
            IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__NoSegmentsConfigured
                .selector
        );
        exposedLib.findPositionForSupplyPublic(segments, targetSupply);
    }

    function test_FindPositionForSupply_TooManySegments_Reverts() public {
        // MAX_SEGMENTS is 10 in the library
        PackedSegment[] memory segments =
            new PackedSegment[](DiscreteCurveMathLib_v1.MAX_SEGMENTS + 1);
        // Fill with dummy segments, actual content doesn't matter for this check
        for (uint i = 0; i < segments.length; ++i) {
            segments[i] = DiscreteCurveMathLib_v1.createSegment(1, 0, 1, 1);
        }
        uint targetSupply = 10 ether;

        vm.expectRevert(
            IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__TooManySegments
                .selector
        );
        exposedLib.findPositionForSupplyPublic(segments, targetSupply);
    }

    function test_FindPosition_Transition_FlatToSloped() public {
        PackedSegment[] memory segments = new PackedSegment[](2);

        // Segment 0: Flat, non-free
        uint flatInitialPrice = 0.2 ether;
        uint flatSupplyPerStep = 15 ether;
        uint flatNumberOfSteps = 1;
        uint flatCapacity = flatSupplyPerStep * flatNumberOfSteps;
        segments[0] = DiscreteCurveMathLib_v1.createSegment(
            flatInitialPrice, 0, flatSupplyPerStep, flatNumberOfSteps
        );

        // Segment 1: Sloped, paid
        uint slopedInitialPrice = 0.8 ether;
        uint slopedPriceIncrease = 0.1 ether;
        uint slopedSupplyPerStep = 8 ether;
        uint slopedNumberOfSteps = 3;
        segments[1] = DiscreteCurveMathLib_v1.createSegment(
            slopedInitialPrice,
            slopedPriceIncrease,
            slopedSupplyPerStep,
            slopedNumberOfSteps
        );

        // Scenario 1: Target supply exactly at the end of the flat segment
        uint targetSupplyAtBoundary = flatCapacity;
        IDiscreteCurveMathLib_v1.CurvePosition memory posBoundary = exposedLib
            .findPositionForSupplyPublic(segments, targetSupplyAtBoundary);

        // Expected: Position should be at the start of the next (sloped) segment
        assertEq(
            posBoundary.segmentIndex,
            1,
            "FlatBoundary: Segment index should be 1 (start of sloped)"
        );
        assertEq(
            posBoundary.stepIndexWithinSegment,
            0,
            "FlatBoundary: Step index should be 0 of sloped segment"
        );
        assertEq(
            posBoundary.priceAtCurrentStep,
            slopedInitialPrice,
            "FlatBoundary: Price should be initial price of sloped segment"
        );
        assertEq(
            posBoundary.supplyCoveredUpToThisPosition,
            targetSupplyAtBoundary,
            "FlatBoundary: Supply covered mismatch"
        );

        // Scenario 2: Target supply one unit into the sloped segment
        uint targetSupplyIntoSloped = flatCapacity + 1; // 1 wei into the sloped segment
        IDiscreteCurveMathLib_v1.CurvePosition memory posIntoSloped = exposedLib
            .findPositionForSupplyPublic(segments, targetSupplyIntoSloped);

        // Expected: Position should be within the first step of the sloped segment
        assertEq(
            posIntoSloped.segmentIndex,
            1,
            "FlatIntoSloped: Segment index should be 1"
        );
        assertEq(
            posIntoSloped.stepIndexWithinSegment,
            0,
            "FlatIntoSloped: Step index should be 0 of sloped segment"
        );
        uint expectedPriceIntoSloped = slopedInitialPrice; // Price at step 0 of sloped segment
        assertEq(
            posIntoSloped.priceAtCurrentStep,
            expectedPriceIntoSloped,
            "FlatIntoSloped: Price mismatch for sloped segment"
        );
        assertEq(
            posIntoSloped.supplyCoveredUpToThisPosition,
            targetSupplyIntoSloped,
            "FlatIntoSloped: Supply covered mismatch"
        );
    }

    // --- Tests for getCurrentPriceAndStep ---

    function test_GetCurrentPriceAndStep_SupplyZero() public {
        // Using defaultSegments
        uint currentSupply = 0 ether;
        (uint price, uint stepIdx, uint segmentIdx) = exposedLib
            .getCurrentPriceAndStepPublic(defaultSegments, currentSupply);

        assertEq(
            segmentIdx, 0, "Segment index should be 0 for current supply 0"
        );
        assertEq(stepIdx, 0, "Step index should be 0 for current supply 0");
        assertEq(
            price,
            defaultSeg0_initialPrice,
            "Price should be initial price of first segment for current supply 0"
        );
    }

    function test_GetCurrentPriceAndStep_WithinStep_NotBoundary() public {
        // Using defaultSegments
        // Default Seg0: initialPrice 1, increase 0.1, supplyPerStep 10, steps 3.
        // Step 0: 0-10 supply, price 1.0
        // Step 1: 10-20 supply, price 1.1.
        uint currentSupply = 15 ether; // Falls in step 1 of segment 0
        (uint price, uint stepIdx, uint segmentIdx) = exposedLib
            .getCurrentPriceAndStepPublic(defaultSegments, currentSupply);

        assertEq(segmentIdx, 0, "Segment index mismatch");
        assertEq(stepIdx, 1, "Step index mismatch - should be step 1");
        uint expectedPrice =
            defaultSeg0_initialPrice + (1 * defaultSeg0_priceIncrease); // Price of step 1
        assertEq(
            price, expectedPrice, "Price mismatch - should be price of step 1"
        );
    }

    function test_GetCurrentPriceAndStep_EndOfStep_NotEndOfSegment() public {
        // Using defaultSegments
        // Default Seg0: initialPrice 1, increase 0.1, supplyPerStep 10, steps 3.
        // Current supply is 10 ether, exactly at the end of step 0 of segment 0.
        // Price should be for step 1 of segment 0.
        uint currentSupply = defaultSeg0_supplyPerStep; // 10 ether
        (uint price, uint stepIdx, uint segmentIdx) = exposedLib
            .getCurrentPriceAndStepPublic(defaultSegments, currentSupply);

        assertEq(segmentIdx, 0, "Segment index mismatch");
        assertEq(stepIdx, 1, "Step index should advance to 1");
        uint expectedPrice =
            defaultSeg0_initialPrice + (1 * defaultSeg0_priceIncrease); // Price of step 1 (1.1)
        assertEq(price, expectedPrice, "Price should be for step 1");
    }

    function test_GetCurrentPriceAndStep_EndOfSegment_NotLastSegment() public {
        // Using defaultSegments
        // Current supply is 30 ether, exactly at the end of segment 0 (defaultSeg0_capacity).
        // Price/step should be for the start of segment 1.
        uint currentSupply = defaultSeg0_capacity;
        (uint price, uint stepIdx, uint segmentIdx) = exposedLib
            .getCurrentPriceAndStepPublic(defaultSegments, currentSupply);

        assertEq(segmentIdx, 1, "Segment index should advance to 1");
        assertEq(stepIdx, 0, "Step index should be 0 of segment 1");
        assertEq(
            price,
            defaultSeg1_initialPrice,
            "Price should be initial price of segment 1"
        );
    }

    function test_GetCurrentPriceAndStep_EndOfLastSegment() public {
        // Using defaultSegments
        // Current supply is total capacity of the curve (70 ether).
        uint currentSupply = defaultCurve_totalCapacity;

        (uint price, uint stepIdx, uint segmentIdx) = exposedLib
            .getCurrentPriceAndStepPublic(defaultSegments, currentSupply);

        assertEq(segmentIdx, 1, "Segment index should be last segment (1)");
        assertEq(
            stepIdx,
            defaultSeg1_numberOfSteps - 1,
            "Step index should be last step of last segment"
        );
        uint expectedPrice = defaultSeg1_initialPrice
            + ((defaultSeg1_numberOfSteps - 1) * defaultSeg1_priceIncrease);
        assertEq(
            price,
            expectedPrice,
            "Price should be price of last step of last segment"
        );
    }

    function test_GetCurrentPriceAndStep_SupplyBeyondCapacity_Reverts()
        public
    {
        // Using a single segment for simplicity, but based on defaultSeg0
        PackedSegment[] memory segments = new PackedSegment[](1);
        segments[0] = defaultSegments[0]; // Capacity 30 ether
        uint singleSegmentCapacity = defaultSeg0_capacity; // Use a local variable for clarity

        uint currentSupply = singleSegmentCapacity + 5 ether; // Beyond capacity of this single segment array

        // This will now be caught by _validateSupplyAgainstSegments called at the start of getCurrentPriceAndStep
        // The error should be DiscreteCurveMathLib__SupplyExceedsCurveCapacity
        bytes memory expectedError = abi.encodeWithSelector(
            IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__SupplyExceedsCurveCapacity
                .selector,
            currentSupply,
            singleSegmentCapacity // This should be the actual capacity of the 'segments' array passed
        );
        vm.expectRevert(expectedError);
        exposedLib.getCurrentPriceAndStepPublic(segments, currentSupply);
    }

    function test_GetCurrentPriceAndStep_NoSegments_SupplyPositive_Reverts()
        public
    {
        PackedSegment[] memory segments = new PackedSegment[](0);
        uint currentSupply = 1 ether;

        // This revert comes from _findPositionForSupply
        vm.expectRevert(
            IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__NoSegmentsConfigured
                .selector
        );
        exposedLib.getCurrentPriceAndStepPublic(segments, currentSupply);
    }

    // --- Tests for calculateReserveForSupply ---

    function test_CalculateReserveForSupply_TargetSupplyZero() public {
        // Using defaultSegments
        uint reserve =
            exposedLib.calculateReserveForSupplyPublic(defaultSegments, 0);
        assertEq(reserve, 0, "Reserve for 0 supply should be 0");
    }

    // Test: Calculate reserve for targetSupply = 30 on a single flat segment.
    // Curve: P_init=2.0, P_inc=0, S_step=10, N_steps=5 (Capacity 50)
    // Point T marks the targetSupply for which reserve is calculated.
    //
    //     Price (ether)
    //       ^
    //     2.0 |---+---+---T---+---+  (Price 2.0 for all steps)
    //         +---+---+---+---+---+--> Supply (ether)
    //         0  10  20  30  40  50
    //                     ^
    //                     T (targetSupply = 30)
    //
    //          Step Prices:
    //          Supply  0-10:  Price 2.00
    //          Supply 10-20:  Price 2.00
    //          Supply 20-30:  Price 2.00
    //          Supply 30-40:  Price 2.00
    //          Supply 40-50:  Price 2.00

    function test_CalculateReserveForSupply_SingleFlatSegment_Partial()
        public
    {
        PackedSegment[] memory segments = new PackedSegment[](1);
        uint initialPrice = 2 ether;
        uint priceIncrease = 0; // Flat segment
        uint supplyPerStep = 10 ether;
        uint numberOfSteps = 5; // Total capacity 50 ether
        segments[0] = DiscreteCurveMathLib_v1.createSegment(
            initialPrice, priceIncrease, supplyPerStep, numberOfSteps
        );

        // Target 3 steps (30 ether supply)
        uint targetSupply = 30 ether;
        // Expected reserve: 3 steps * 10 supply/step * 2 price/token = 60 ether (scaled)
        // (30 ether * 2 ether) / 1e18 = 60 ether
        uint expectedReserve =
            (30 ether * initialPrice) / DiscreteCurveMathLib_v1.SCALING_FACTOR;

        uint reserve =
            exposedLib.calculateReserveForSupplyPublic(segments, targetSupply);
        assertEq(
            reserve,
            expectedReserve,
            "Reserve for flat segment partial fill mismatch"
        );
    }

    // Test: Calculate reserve for targetSupply = 20 on a single sloped segment (defaultSeg0).
    // Curve: P_init=1.0, P_inc=0.1, S_step=10, N_steps=3 (Capacity 30)
    // Point T marks the targetSupply for which reserve is calculated.
    //
    //     Price (ether)
    //       ^
    //     1.20|       +---+ (Supply: 30, Price: 1.20)
    //         |       |
    //     1.10|   +---T     (Supply: 20, Price: 1.10)
    //         |   |
    //     1.00|---+         (Supply: 10, Price: 1.00)
    //         +---+---+---+--> Supply (ether)
    //         0  10  20  30
    //                 ^
    //                 T (targetSupply = 20)
    //
    //          Step Prices:
    //          Supply  0-10:  Price 1.00
    //          Supply 10-20:  Price 1.10
    //          Supply 20-30:  Price 1.20

    function test_CalculateReserveForSupply_SingleSlopedSegment_Partial()
        public
    {
        // Using only the first segment of defaultSegments (which is sloped)
        PackedSegment[] memory segments = new PackedSegment[](1);
        segments[0] = defaultSegments[0]; // initialPrice 1, increase 0.1, supplyPerStep 10, steps 3

        // Target 2 steps (20 ether supply) from defaultSeg0
        // Step 0: price 1.0, supply 10. Cost = 10 * 1.0 = 10
        // Step 1: price 1.1, supply 10. Cost = 10 * 1.1 = 11
        // Total reserve = (10 + 11) = 21 ether (scaled)
        uint targetSupply = 2 * defaultSeg0_supplyPerStep; // 20 ether

        uint expectedReserve = 0;
        expectedReserve += (
            defaultSeg0_supplyPerStep
                * (defaultSeg0_initialPrice + 0 * defaultSeg0_priceIncrease)
        ) / DiscreteCurveMathLib_v1.SCALING_FACTOR;
        expectedReserve += (
            defaultSeg0_supplyPerStep
                * (defaultSeg0_initialPrice + 1 * defaultSeg0_priceIncrease)
        ) / DiscreteCurveMathLib_v1.SCALING_FACTOR;
        // expectedReserve = 10 + 11 = 21 ether

        uint reserve =
            exposedLib.calculateReserveForSupplyPublic(segments, targetSupply);
        assertEq(
            reserve,
            expectedReserve,
            "Reserve for sloped segment partial fill mismatch"
        );
    }

    // --- Tests for calculatePurchaseReturn ---

    // Test: Reverts when currentTotalIssuanceSupply > curve capacity.
    // Curve: defaultSegments (Capacity C = 70)
    // Point S (currentTotalIssuanceSupply = 71) is beyond C.
    //
    //     Price (ether)
    //       ^
    //     1.55|                   +------+ C (Capacity)
    //         |                   |      |
    //     1.50|           +-------+      |
    //         |           |              |
    //         |           |              |
    //     1.20|       +---+              |
    //         |       |                  |
    //     1.10|   +---+                  |
    //         |   |                      |
    //     1.00|---+                      |
    //         +---+---+---+------+-------+--> Supply (ether)
    //         0  10  20  30     50     70 71
    //                                    ^  ^
    //                                    C  S (currentSupply > C)
    //
    //          Step Prices (defaultSegments):
    //          Supply  0-10:  Price 1.00
    //          Supply 10-20:  Price 1.10
    //          Supply 20-30:  Price 1.20
    //          Supply 30-50:  Price 1.50
    //          Supply 50-70:  Price 1.55

    function testRevert_CalculatePurchaseReturn_SupplyExceedsCapacity()
        public
    {
        uint supplyOverCapacity = defaultCurve_totalCapacity + 1 ether;
        bytes memory expectedRevertData = abi.encodeWithSelector(
            IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__SupplyExceedsCurveCapacity
                .selector,
            supplyOverCapacity,
            defaultCurve_totalCapacity
        );
        vm.expectRevert(expectedRevertData);
        exposedLib.calculatePurchaseReturnPublic(
            defaultSegments,
            1 ether, // collateralAmountIn
            supplyOverCapacity // currentTotalIssuanceSupply
        );
    }

    function testRevert_CalculatePurchaseReturn_NoSegments_SupplyPositive()
        public
    {
        PackedSegment[] memory noSegments = new PackedSegment[](0);
        vm.expectRevert(
            IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__NoSegmentsConfigured
                .selector
        );
        exposedLib.calculatePurchaseReturnPublic(
            noSegments,
            1 ether, // collateralAmountIn
            1 ether // currentTotalIssuanceSupply > 0
        );
    }

    function testPass_CalculatePurchaseReturn_NoSegments_SupplyZero() public {
        // This should pass the _validateSupplyAgainstSegments check,
        // but then revert later in calculatePurchaseReturn when getCurrentPriceAndStep is called with no segments.
        PackedSegment[] memory noSegments = new PackedSegment[](0);
        vm.expectRevert(
            IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__NoSegmentsConfigured
                .selector
        );
        exposedLib.calculatePurchaseReturnPublic(
            noSegments,
            1 ether, // collateralAmountIn
            0 // currentTotalIssuanceSupply
        );
    }

    function testRevert_CalculatePurchaseReturn_ZeroCollateralInput() public {
        vm.expectRevert(
            IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__ZeroCollateralInput
                .selector
        );
        exposedLib.calculatePurchaseReturnPublic(
            defaultSegments,
            0, // Zero collateral
            0 // currentTotalIssuanceSupply
        );
    }

    // Test: Purchase on a single flat segment, affording a partial amount.
    // Curve: P_init=2.0, P_inc=0, S_step=10, N_steps=5 (Capacity 50)
    // Start Supply (S) = 0. Collateral In = 45.
    // Expected Issuance Out = 22.5. End Supply (E) = 0 + 22.5 = 22.5.
    //
    //     Price (ether)
    //       ^
    //     2.0 |S--+---+-E-+---+---+  (Price 2.0 for all steps)
    //         +---+---+---+---+---+--> Supply (ether)
    //         0  10  20  30  40  50
    //         ^          ^
    //         S          E (22.5)
    //
    //          Step Prices:
    //          Supply  0-10:  Price 2.00
    //          Supply 10-20:  Price 2.00
    //          Supply 20-30:  Price 2.00 (Purchase ends in this step)
    //          Supply 30-40:  Price 2.00
    //          Supply 40-50:  Price 2.00
    function test_CalculatePurchaseReturn_SingleFlatSegment_PartialBuy_AffordSome(
    ) public {
        PackedSegment[] memory segments = new PackedSegment[](1);
        uint initialPrice = 2 ether;
        uint priceIncrease = 0; // Flat segment
        uint supplyPerStep = 10 ether;
        uint numberOfSteps = 5; // Total capacity 50 ether
        segments[0] = DiscreteCurveMathLib_v1.createSegment(
            initialPrice, priceIncrease, supplyPerStep, numberOfSteps
        );

        uint currentSupply = 0 ether;
        uint collateralIn = 45 ether; // Enough for 2 steps (40 ether cost), but not 3 (60 ether cost)

        // New logic: 2 full steps (20 issuance, 40 cost) + partial step (2.5 issuance, 5 cost)
        uint expectedIssuanceOut = 22_500_000_000_000_000_000; // 22.5 ether
        uint expectedCollateralSpent = 45_000_000_000_000_000_000; // 45 ether

        (uint issuanceOut, uint collateralSpent) = exposedLib
            .calculatePurchaseReturnPublic(segments, collateralIn, currentSupply);

        assertEq(
            issuanceOut,
            expectedIssuanceOut,
            "Flat partial buy: issuanceOut mismatch"
        );
        assertEq(
            collateralSpent,
            expectedCollateralSpent,
            "Flat partial buy: collateralSpent mismatch"
        );
    }

    // Test: Purchase on a single flat segment, affording all in a partial step.
    // Curve: P_init=2.0, P_inc=0, S_step=10, N_steps=5 (Capacity 50)
    // Start Supply (S) = 0. Collateral In = 50.
    // Expected Issuance Out = 25. End Supply (E) = 0 + 25 = 25.
    //
    //     Price (ether)
    //       ^
    //     2.0 |S--+---+-E-+---+---+  (Price 2.0 for all steps)
    //         +---+---+---+---+---+--> Supply (ether)
    //         0  10  20  30  40  50
    //         ^          ^
    //         S          E (25)
    //
    //          Step Prices:
    //          Supply  0-10:  Price 2.00
    //          Supply 10-20:  Price 2.00
    //          Supply 20-30:  Price 2.00 (Purchase ends in this step)
    //          Supply 30-40:  Price 2.00
    //          Supply 40-50:  Price 2.00
    function test_CalculatePurchaseReturn_SingleFlatSegment_PartialBuy_AffordAllInStep(
    ) public {
        PackedSegment[] memory segments = new PackedSegment[](1);
        uint initialPrice = 2 ether;
        uint priceIncrease = 0; // Flat segment
        uint supplyPerStep = 10 ether;
        uint numberOfSteps = 5; // Total capacity 50 ether
        segments[0] = DiscreteCurveMathLib_v1.createSegment(
            initialPrice, priceIncrease, supplyPerStep, numberOfSteps
        );

        uint currentSupply = 0 ether;
        // Collateral to buy exactly 2.5 steps (25 ether issuance) would be 50 ether.
        uint collateralIn = 50 ether;

        // Expected: buy 2.5 steps = 25 ether issuance.
        // The function buys in sPerStep increments.
        // 50 collateral / 2 price = 25 issuance. (25/10)*10 = 20. Cost 40.
        // The current implementation of calculatePurchaseReturn for flat segments:
        // issuanceBoughtThisSegment = (remainingCollateral * SCALING_FACTOR) / priceAtCurrentSegmentStartStep;
        // issuanceBoughtThisSegment = (issuanceBoughtThisSegment / sPerStepSeg) * sPerStepSeg;
        // So, (50e18 * 1e18) / 2e18 = 25e18.
        // (25e18 / 10e18) * 10e18 = 2 * 10e18 = 20e18.
        // collateralSpentThisSegment = (20e18 * 2e18) / 1e18 = 40e18.
        // This seems to be an issue with the test description vs implementation detail.
        // The test description implies it can buy partial steps, but the code rounds down to full sPerStep.
        // Let's adjust the expectation based on the code's logic for flat segments.
        // If collateralIn = 50 ether, it can buy 2 full steps (20 issuance) for 40 ether.
        // The binary search for sloped segments handles full steps. Flat segment logic is simpler.
        // The logic is: maxIssuance = collateral / price. Then round down to nearest multiple of supplyPerStep.
        // New logic: 2 full steps (20 issuance, 40 cost) + partial step (5 issuance, 10 cost)
        uint expectedIssuanceOut = 25_000_000_000_000_000_000; // 25 ether
        uint expectedCollateralSpent = 50_000_000_000_000_000_000; // 50 ether

        (uint issuanceOut, uint collateralSpent) = exposedLib
            .calculatePurchaseReturnPublic(segments, collateralIn, currentSupply);

        assertEq(
            issuanceOut,
            expectedIssuanceOut,
            "Flat partial buy (exact for steps): issuanceOut mismatch"
        );
        assertEq(
            collateralSpent,
            expectedCollateralSpent,
            "Flat partial buy (exact for steps): collateralSpent mismatch"
        );
    }

    // Test: Purchase on a single sloped segment, affording multiple full steps and a partial final step.
    // Curve: P_init=1.0, P_inc=0.1, S_step=10, N_steps=3 (Capacity 30, defaultSeg0)
    // Start Supply (S) = 0. Collateral In = 25.
    // Expected Issuance Out = 23.333... End Supply (E) = 23.333...
    //
    //     Price (ether)
    //       ^
    //     1.20|       +-E-+ (Supply: 30, Price: 1.20)
    //         |       |   |
    //     1.10|   +---+   | (Supply: 20, Price: 1.10)
    //         |   |       |
    //     1.00|S--+       | (Supply: 10, Price: 1.00)
    //         +---+---+---+--> Supply (ether)
    //         0  10  20  30
    //         ^        ^
    //         S        E (23.33...)
    //
    //          Step Prices:
    //          Supply  0-10:  Price 1.00 (Step 0)
    //          Supply 10-20:  Price 1.10 (Step 1)
    //          Supply 20-30:  Price 1.20 (Step 2 - purchase ends in this step)
    function test_CalculatePurchaseReturn_SingleSlopedSegment_AffordMultipleFullSteps(
    ) public {
        // Using only the first segment of defaultSegments (sloped)
        PackedSegment[] memory segments = new PackedSegment[](1);
        segments[0] = defaultSegments[0]; // initialPrice 1, increase 0.1, supplyPerStep 10, steps 3

        uint currentSupply = 0 ether;
        // Cost step 0 (price 1.0): 10 supply * 1.0 price = 10 collateral
        // Cost step 1 (price 1.1): 10 supply * 1.1 price = 11 collateral
        // Total cost for 2 steps (20 supply) = 10 + 11 = 21 collateral
        uint collateralIn = 25 ether; // Enough for 2 steps (cost 21), with 4 ether remaining

        // New logic: 2 full steps (20 issuance, 21 cost)
        // Remaining budget = 25 - 21 = 4 ether.
        // Next step price (step 2 of seg0) = 1 + (2 * 0.1) = 1.2 ether.
        // Partial issuance: budget 4e18, price 1.2e18. maxAffordableTokens = Math.mulDiv(4e18, 1e18, 1.2e18) = 3.333...e18.
        //   tokensToIssue (partial) = 3333333333333333333.
        // Partial cost: _mulDivUp(tokensToIssue_partial, 1.2e18, 1e18) = _mulDivUp(3.333...e18, 1.2e18, 1e18) = 4e18.
        // Total issuance = 20e18 (full) + 3.333...e18 (partial) = 23.333...e18.
        // Total cost = 21e18 (full) + 4e18 (partial, rounded up) = 25e18.
        uint expectedIssuanceOut = 23_333_333_333_333_333_333; // 23.333... ether
        uint expectedCollateralSpent = 25_000_000_000_000_000_000; // 25 ether

        (uint issuanceOut, uint collateralSpent) = exposedLib
            .calculatePurchaseReturnPublic(segments, collateralIn, currentSupply);

        assertEq(
            issuanceOut,
            expectedIssuanceOut,
            "Sloped multi-step buy: issuanceOut mismatch"
        );
        assertEq(
            collateralSpent,
            expectedCollateralSpent,
            "Sloped multi-step buy: collateralSpent mismatch"
        );
    }

    // --- Tests for calculateSaleReturn ---

    // Test: Reverts when currentTotalIssuanceSupply > curve capacity for a sale.
    // Curve: defaultSegments (Capacity C = 70)
    // Point S (currentTotalIssuanceSupply = 71) is beyond C.
    //
    //     Price (ether)
    //       ^
    //     1.55|                   +------+ C (Capacity)
    //         |                   |      |
    //     1.50|           +-------+      |
    //         |           |              |
    //         |           |              |
    //     1.20|       +---+              |
    //         |       |                  |
    //     1.10|   +---+                  |
    //         |   |                      |
    //     1.00|---+                      |
    //         +---+---+---+------+-------+--> Supply (ether)
    //         0  10  20  30     50     70 71
    //                                    ^  ^
    //                                    C  S (currentSupply > C)
    //
    //          Step Prices (defaultSegments):
    //          Supply  0-10:  Price 1.00
    //          Supply 10-20:  Price 1.10
    //          Supply 20-30:  Price 1.20
    //          Supply 30-50:  Price 1.50
    //          Supply 50-70:  Price 1.55
    function testRevert_CalculateSaleReturn_SupplyExceedsCapacity() public {
        uint supplyOverCapacity = defaultCurve_totalCapacity + 1 ether;
        bytes memory expectedRevertData = abi.encodeWithSelector(
            IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__SupplyExceedsCurveCapacity
                .selector,
            supplyOverCapacity,
            defaultCurve_totalCapacity
        );
        vm.expectRevert(expectedRevertData);
        exposedLib.calculateSaleReturnPublic(
            defaultSegments,
            1 ether, // issuanceAmountIn
            supplyOverCapacity // currentTotalIssuanceSupply
        );
    }

    // Test: Reverts when trying to calculate sale return with no segments configured
    // and currentTotalIssuanceSupply > 0.
    // Visualization is not applicable as there are no curve segments.
    function testRevert_CalculateSaleReturn_NoSegments_SupplyPositive()
        public
    {
        PackedSegment[] memory noSegments = new PackedSegment[](0);
        vm.expectRevert(
            IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__NoSegmentsConfigured
                .selector
        );
        exposedLib.calculateSaleReturnPublic(
            noSegments,
            1 ether, // issuanceAmountIn
            1 ether // currentTotalIssuanceSupply > 0
        );
    }

    // Test: Correctly handles selling 0 from 0 supply on an unconfigured (no segments) curve.
    // Expected to revert due to ZeroIssuanceInput, which takes precedence over no-segment logic here.
    // Visualization is not applicable as there are no curve segments.
    function testPass_CalculateSaleReturn_NoSegments_SupplyZero_IssuanceZero()
        public
    {
        // This specific case (selling 0 from 0 supply on an unconfigured curve)
        // is handled by the ZeroIssuanceInput revert, which takes precedence.
        // If ZeroIssuanceInput was not there, _validateSupplyAgainstSegments would pass (0 supply, 0 segments is fine),
        // then segments.length == 0 check in calculateSaleReturn would be met,
        // then issuanceAmountBurned would be 0, returning (0,0).
        PackedSegment[] memory noSegments = new PackedSegment[](0);
        vm.expectRevert(
            IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__ZeroIssuanceInput
                .selector
        );
        exposedLib.calculateSaleReturnPublic(
            noSegments,
            0, // issuanceAmountIn = 0
            0 // currentTotalIssuanceSupply = 0
        );
    }

    // Test: Correctly handles selling a positive amount from 0 supply on an unconfigured (no segments) curve.
    // Expected to return 0 collateral and 0 burned, as there's nothing to sell.
    // Visualization is not applicable as there are no curve segments.
    function testPass_CalculateSaleReturn_NoSegments_SupplyZero_IssuancePositive(
    ) public {
        // Selling 1 from 0 supply on an unconfigured curve.
        // _validateSupplyAgainstSegments passes (0 supply, 0 segments).
        // ZeroIssuanceInput is not hit.
        // segments.length == 0 is true.
        // issuanceAmountBurned becomes 0 (min(1, 0)).
        // Returns (0,0). This is correct.
        PackedSegment[] memory noSegments = new PackedSegment[](0);
        (uint collateralOut, uint burned) = exposedLib.calculateSaleReturnPublic(
            noSegments,
            1 ether, // issuanceAmountIn > 0
            0 // currentTotalIssuanceSupply = 0
        );
        assertEq(collateralOut, 0, "Collateral out should be 0");
        assertEq(burned, 0, "Issuance burned should be 0");
    }

    // Test: Reverts when issuanceAmountIn is zero for a sale.
    // Curve: defaultSegments
    // Current Supply (S) = 30. Attempting to sell 0 from this point.
    //
    //     Price (ether)
    //       ^
    //     1.55|                   +------+ (Supply: 70)
    //         |                   |      |
    //     1.50|           +-------+      | (Supply: 50)
    //         |           |              |
    //         |           |              |
    //     1.20|       +---S              | (Supply: 30, Price: 1.20)
    //         |       |                  |
    //     1.10|   +---+                  | (Supply: 20, Price: 1.10)
    //         |   |                      |
    //     1.00|---+                      | (Supply: 10, Price: 1.00)
    //         +---+---+---+------+-------+--> Supply (ether)
    //         0  10  20  30     50     70
    //                     ^
    //                     S (currentSupply = 30, selling 0)
    //
    //          Step Prices (defaultSegments):
    //          Supply  0-10:  Price 1.00
    //          Supply 10-20:  Price 1.10
    //          Supply 20-30:  Price 1.20
    //          Supply 30-50:  Price 1.50
    //          Supply 50-70:  Price 1.55
    function testRevert_CalculateSaleReturn_ZeroIssuanceInput() public {
        vm.expectRevert(
            IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__ZeroIssuanceInput
                .selector
        );
        exposedLib.calculateSaleReturnPublic(
            defaultSegments,
            0, // Zero issuanceAmountIn
            defaultSeg0_capacity // currentTotalIssuanceSupply
        );
    }

    // Test: Partial sale on a single sloped segment (defaultSeg0).
    // Curve: P_init=1.0, P_inc=0.1, S_step=10, N_steps=3 (Capacity 30)
    // Start Supply (S) = 30. Issuance to Sell = 10.
    // Expected Issuance Burned = 10. End Supply (E) = 30 - 10 = 20.
    //
    //     Price (ether)
    //       ^
    //     1.20|       +---S (Supply: 30, Price: 1.20)
    //         |       |   |
    //     1.10|   +---E   + (Supply: 20, Price: 1.10)
    //         |   |   |   |
    //     1.00|---+   |   | (Supply: 10, Price: 1.00)
    //         +---+---+---+--> Supply (ether)
    //         0  10  20  30
    //                 ^   ^
    //                 E   S
    //
    //          Step Prices:
    //          Supply  0-10:  Price 1.00 (Step 0)
    //          Supply 10-20:  Price 1.10 (Step 1 - sale ends here)
    //          Supply 20-30:  Price 1.20 (Step 2 - sale starts here)
    function test_CalculateSaleReturn_SingleSlopedSegment_PartialSell()
        public
    {
        // Using only the first segment of defaultSegments (sloped)
        PackedSegment[] memory segments = new PackedSegment[](1);
        segments[0] = defaultSegments[0]; // initialPrice 1, increase 0.1, supplyPerStep 10, steps 3

        // Current supply is 30 ether (3 steps minted from defaultSeg0)
        uint currentSupply = defaultSeg0_capacity; // 30 ether
        // Reserve for 30 supply (defaultSeg0_reserve) = 33 ether

        // Selling 10 ether issuance (the tokens from the last minted step, step 2 of defaultSeg0)
        uint issuanceToSell = defaultSeg0_supplyPerStep; // 10 ether

        // Expected: final supply after sale = 20 ether
        // Reserve for 20 supply (first 2 steps of defaultSeg0):
        // Step 0 (price 1.0): 10 coll
        // Step 1 (price 1.1): 11 coll
        // Total reserve for 20 supply = 10 + 11 = 21 ether
        uint reserveFor20Supply = 0;
        reserveFor20Supply += (
            defaultSeg0_supplyPerStep
                * (defaultSeg0_initialPrice + 0 * defaultSeg0_priceIncrease)
        ) / DiscreteCurveMathLib_v1.SCALING_FACTOR;
        reserveFor20Supply += (
            defaultSeg0_supplyPerStep
                * (defaultSeg0_initialPrice + 1 * defaultSeg0_priceIncrease)
        ) / DiscreteCurveMathLib_v1.SCALING_FACTOR;

        // Collateral out = Reserve(30) - Reserve(20) = 33 - 21 = 12 ether
        uint expectedCollateralOut = defaultSeg0_reserve - reserveFor20Supply;
        uint expectedIssuanceBurned = issuanceToSell;

        (uint collateralOut, uint issuanceBurned) = exposedLib
            .calculateSaleReturnPublic(segments, issuanceToSell, currentSupply);

        assertEq(
            collateralOut,
            expectedCollateralOut,
            "Sloped partial sell: collateralOut mismatch"
        );
        assertEq(
            issuanceBurned,
            expectedIssuanceBurned,
            "Sloped partial sell: issuanceBurned mismatch"
        );
    }

    // --- Additional calculateReserveForSupply tests ---

    function test_CalculateReserveForSupply_MultiSegment_FullCurve() public {
        // Using defaultSegments
        // defaultCurve_totalCapacity = 70 ether
        // defaultCurve_totalReserve = 94 ether
        uint actualReserve = exposedLib.calculateReserveForSupplyPublic(
            defaultSegments, defaultCurve_totalCapacity
        );
        assertEq(
            actualReserve,
            defaultCurve_totalReserve,
            "Reserve for full multi-segment curve mismatch"
        );
    }

    function test_CalculateReserveForSupply_MultiSegment_PartialFillLaterSegment(
    ) public {
        // Using defaultSegments
        // Default Seg0: capacity 30, reserve 33
        // Default Seg1: initialPrice 1.5, increase 0.05, supplyPerStep 20, steps 2.
        // Target supply: Full seg0 (30) + 1 step of seg1 (20) = 50 ether
        uint targetSupply = defaultSeg0_capacity + defaultSeg1_supplyPerStep; // 30 + 20 = 50 ether

        // Cost for the first step of segment 1:
        // 20 supply * (1.5 price + 0 * 0.05 increase) = 30 ether collateral
        uint costFirstStepSeg1 = (
            defaultSeg1_supplyPerStep
                * (defaultSeg1_initialPrice + 0 * defaultSeg1_priceIncrease)
        ) / DiscreteCurveMathLib_v1.SCALING_FACTOR;

        uint expectedTotalReserve = defaultSeg0_reserve + costFirstStepSeg1; // 33 + 30 = 63 ether

        uint actualReserve = exposedLib.calculateReserveForSupplyPublic(
            defaultSegments, targetSupply
        );
        assertEq(
            actualReserve,
            expectedTotalReserve,
            "Reserve for multi-segment partial fill mismatch"
        );
    }

    function test_CalculateReserveForSupply_TargetSupplyBeyondCurveCapacity()
        public
    {
        // Using defaultSegments
        // defaultCurve_totalCapacity = 70 ether
        // defaultCurve_totalReserve = 94 ether
        uint targetSupplyBeyondCapacity = defaultCurve_totalCapacity + 100 ether; // e.g., 70e18 + 100e18 = 170e18

        // Expect revert because targetSupplyBeyondCapacity > defaultCurve_totalCapacity
        bytes memory expectedError = abi.encodeWithSelector(
            IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__SupplyExceedsCurveCapacity
                .selector,
            targetSupplyBeyondCapacity,
            defaultCurve_totalCapacity
        );
        vm.expectRevert(expectedError);
        exposedLib.calculateReserveForSupplyPublic(
            defaultSegments, targetSupplyBeyondCapacity
        );
    }

    // TODO: Implement test
    // function test_CalculateReserveForSupply_MixedFlatAndSlopedSegments() public {
    // }

    function test_CalculatePurchaseReturn_Edge_CollateralForExactlyOneStep_Sloped(
    ) public {
        PackedSegment[] memory segments = new PackedSegment[](1);
        segments[0] = defaultSegments[0]; // Sloped segment from default setup

        uint currentSupply = 0 ether;
        // Cost of the first step of defaultSegments[0]
        // initialPrice = 1 ether, supplyPerStep = 10 ether
        uint costFirstStep = (
            defaultSeg0_supplyPerStep * defaultSeg0_initialPrice
        ) / DiscreteCurveMathLib_v1.SCALING_FACTOR; // 10 ether
        uint collateralIn = costFirstStep;

        uint expectedIssuanceOut = defaultSeg0_supplyPerStep; // 10 ether
        uint expectedCollateralSpent = costFirstStep; // 10 ether

        (uint issuanceOut, uint collateralSpent) = exposedLib
            .calculatePurchaseReturnPublic(segments, collateralIn, currentSupply);

        assertEq(
            issuanceOut,
            expectedIssuanceOut,
            "Issuance for exactly one sloped step mismatch"
        );
        assertEq(
            collateralSpent,
            expectedCollateralSpent,
            "Collateral for exactly one sloped step mismatch"
        );
    }

    function test_CalculatePurchaseReturn_Edge_CollateralLessThanOneStep_Flat()
        public
    {
        PackedSegment[] memory segments = new PackedSegment[](1);
        uint flatPrice = 2 ether;
        uint flatSupplyPerStep = 10 ether;
        uint flatNumSteps = 1;
        segments[0] = DiscreteCurveMathLib_v1.createSegment(
            flatPrice, 0, flatSupplyPerStep, flatNumSteps
        );

        uint currentSupply = 0 ether;
        uint costOneStep = (flatSupplyPerStep * flatPrice)
            / DiscreteCurveMathLib_v1.SCALING_FACTOR; // 20 ether
        uint collateralIn = costOneStep - 1 wei; // 19.99... ether, less than enough for one step

        // With partial purchases, it should buy what it can.
        // collateralIn = 19999999999999999999. flatPrice = 2e18.
        // issuanceOut = (collateralIn * SCALING_FACTOR) / flatPrice = 9999999999999999999.
        // collateralSpent = (issuanceOut * flatPrice) / SCALING_FACTOR = 19999999999999999998.
        uint expectedIssuanceOut = 9_999_999_999_999_999_999;
        uint expectedCollateralSpent = 19_999_999_999_999_999_998;

        (uint issuanceOut, uint collateralSpent) = exposedLib
            .calculatePurchaseReturnPublic(segments, collateralIn, currentSupply);

        assertEq(
            issuanceOut,
            expectedIssuanceOut,
            "Issuance for less than one flat step mismatch"
        );
        assertEq(
            collateralSpent,
            expectedCollateralSpent,
            "Collateral for less than one flat step mismatch"
        );
    }

    function test_CalculatePurchaseReturn_Edge_CollateralLessThanOneStep_Sloped(
    ) public {
        PackedSegment[] memory segments = new PackedSegment[](1);
        segments[0] = defaultSegments[0]; // Sloped segment from default setup

        uint currentSupply = 0 ether;
        // Cost of the first step of defaultSegments[0] is 10 ether
        uint costFirstStep = (
            defaultSeg0_supplyPerStep * defaultSeg0_initialPrice
        ) / DiscreteCurveMathLib_v1.SCALING_FACTOR;
        uint collateralIn = costFirstStep - 1 wei; // Just less than enough for the first step

        // With partial purchases.
        // collateralIn = 9999999999999999999. initialPrice (nextStepPrice) = 1e18.
        // issuanceOut = (collateralIn * SCALING_FACTOR) / initialPrice = 9999999999999999999.
        // collateralSpent = (issuanceOut * initialPrice) / SCALING_FACTOR = 9999999999999999999.
        uint expectedIssuanceOut = 9_999_999_999_999_999_999;
        uint expectedCollateralSpent = 9_999_999_999_999_999_999;

        (uint issuanceOut, uint collateralSpent) = exposedLib
            .calculatePurchaseReturnPublic(segments, collateralIn, currentSupply);

        assertEq(
            issuanceOut,
            expectedIssuanceOut,
            "Issuance for less than one sloped step mismatch"
        );
        assertEq(
            collateralSpent,
            expectedCollateralSpent,
            "Collateral for less than one sloped step mismatch"
        );
    }

    function test_CalculatePurchaseReturn_Edge_CollateralToBuyoutCurve()
        public
    {
        // Uses defaultSegments which has total capacity of defaultCurve_totalCapacity (70 ether)
        // and total reserve of defaultCurve_totalReserve (94 ether)
        uint currentSupply = 0 ether;

        // Test with exact collateral to buy out the curve
        uint collateralInExact = defaultCurve_totalReserve;
        uint expectedIssuanceOutExact = defaultCurve_totalCapacity;
        uint expectedCollateralSpentExact = defaultCurve_totalReserve;

        (uint issuanceOut, uint collateralSpent) = exposedLib
            .calculatePurchaseReturnPublic(
            defaultSegments, collateralInExact, currentSupply
        );

        assertEq(
            issuanceOut,
            expectedIssuanceOutExact,
            "Issuance for curve buyout (exact collateral) mismatch"
        );
        assertEq(
            collateralSpent,
            expectedCollateralSpentExact,
            "Collateral for curve buyout (exact collateral) mismatch"
        );

        // Test with slightly more collateral than needed to buy out the curve
        uint collateralInMore = defaultCurve_totalReserve + 100 ether;
        // Expected behavior: still only buys out the curve capacity and spends the required reserve.
        uint expectedIssuanceOutMore = defaultCurve_totalCapacity;
        uint expectedCollateralSpentMore = defaultCurve_totalReserve;

        (issuanceOut, collateralSpent) = exposedLib
            .calculatePurchaseReturnPublic(
            defaultSegments, collateralInMore, currentSupply
        );

        assertEq(
            issuanceOut,
            expectedIssuanceOutMore,
            "Issuance for curve buyout (more collateral) mismatch"
        );
        assertEq(
            collateralSpent,
            expectedCollateralSpentMore,
            "Collateral for curve buyout (more collateral) mismatch"
        );
    }

    // --- calculatePurchaseReturn current supply variation tests ---

    function test_CalculatePurchaseReturn_StartMidStep_Sloped() public {
        uint currentSupply = 5 ether; // Mid-step 0 of defaultSegments[0]

        // getCurrentPriceAndStep(defaultSegments, 5 ether) will yield:
        // priceAtPurchaseStart = 1.0 ether (price of step 0 of defaultSeg0)
        // stepAtPurchaseStart = 0 (index of step 0 of defaultSeg0)
        // segmentAtPurchaseStart = 0 (index of defaultSeg0)

        // Collateral to buy one full step (step 0 of segment 0, price 1.0)
        // Note: calculatePurchaseReturn's internal _calculatePurchaseForSingleSegment will attempt to buy
        // full steps from the identified startStep (step 0 of seg0 in this case).
        uint collateralIn = (
            defaultSeg0_supplyPerStep * defaultSeg0_initialPrice
        ) / DiscreteCurveMathLib_v1.SCALING_FACTOR; // 10 ether

        // Expected: Buys 1 full step (step 0 of segment 0)
        uint expectedIssuanceOut = defaultSeg0_supplyPerStep; // 10 ether
        uint expectedCollateralSpent = collateralIn; // 10 ether

        (uint issuanceOut, uint collateralSpent) = exposedLib
            .calculatePurchaseReturnPublic(
            defaultSegments, collateralIn, currentSupply
        );

        assertEq(issuanceOut, expectedIssuanceOut, "Issuance mid-step mismatch");
        assertEq(
            collateralSpent,
            expectedCollateralSpent,
            "Collateral mid-step mismatch"
        );
    }

    function test_CalculatePurchaseReturn_StartEndOfStep_Sloped() public {
        uint currentSupply = defaultSeg0_supplyPerStep; // 10 ether, end of step 0 of defaultSegments[0]

        // getCurrentPriceAndStep(defaultSegments, 10 ether) will yield:
        // priceAtPurchaseStart = 1.1 ether (price of step 1 of defaultSeg0)
        // stepAtPurchaseStart = 1 (index of step 1 of defaultSeg0)
        // segmentAtPurchaseStart = 0 (index of defaultSeg0)

        // Collateral to buy one full step (which will be step 1 of segment 0, price 1.1)
        uint priceOfStep1Seg0 =
            defaultSeg0_initialPrice + defaultSeg0_priceIncrease;
        uint collateralIn = (defaultSeg0_supplyPerStep * priceOfStep1Seg0)
            / DiscreteCurveMathLib_v1.SCALING_FACTOR; // 11 ether

        // Expected: Buys 1 full step (step 1 of segment 0)
        uint expectedIssuanceOut = defaultSeg0_supplyPerStep; // 10 ether (supply of step 1)
        uint expectedCollateralSpent = collateralIn; // 11 ether

        (uint issuanceOut, uint collateralSpent) = exposedLib
            .calculatePurchaseReturnPublic(
            defaultSegments, collateralIn, currentSupply
        );

        assertEq(
            issuanceOut, expectedIssuanceOut, "Issuance end-of-step mismatch"
        );
        assertEq(
            collateralSpent,
            expectedCollateralSpent,
            "Collateral end-of-step mismatch"
        );
    }

    function test_CalculatePurchaseReturn_StartEndOfSegment_MultiSegment()
        public
    {
        uint currentSupply = defaultSeg0_capacity; // 30 ether, end of segment 0

        // getCurrentPriceAndStep(defaultSegments, 30 ether) will yield:
        // priceAtPurchaseStart = 1.5 ether (initial price of segment 1)
        // stepAtPurchaseStart = 0 (index of step 0 in segment 1)
        // segmentAtPurchaseStart = 1 (index of segment 1)

        // Collateral to buy one full step from segment 1 (step 0 of seg1, price 1.5)
        uint collateralIn = (
            defaultSeg1_supplyPerStep * defaultSeg1_initialPrice
        ) / DiscreteCurveMathLib_v1.SCALING_FACTOR; // 30 ether

        // Expected: Buys 1 full step (step 0 of segment 1)
        uint expectedIssuanceOut = defaultSeg1_supplyPerStep; // 20 ether (supply of step 0 of seg1)
        uint expectedCollateralSpent = collateralIn; // 30 ether

        (uint issuanceOut, uint collateralSpent) = exposedLib
            .calculatePurchaseReturnPublic(
            defaultSegments, collateralIn, currentSupply
        );

        assertEq(
            issuanceOut, expectedIssuanceOut, "Issuance end-of-segment mismatch"
        );
        assertEq(
            collateralSpent,
            expectedCollateralSpent,
            "Collateral end-of-segment mismatch"
        );
    }

    function test_CalculatePurchaseReturn_SpanningSegments_EndsWithPartialInSecondSegment(
    ) public {
        // Objective: Buy out segment 0 completely, then buy a partial amount of the first step in segment 1.
        uint currentSupply = 0 ether;

        // Collateral needed for segment 0 is defaultSeg0_reserve (33 ether)
        // For segment 1:
        //   Price of first step = defaultSeg1_initialPrice (1.5 ether)
        //   Supply per step in seg1 = defaultSeg1_supplyPerStep (20 ether)
        //   Let's target buying 5 ether issuance from segment 1's first step.
        uint partialIssuanceInSeg1 = 5 ether;
        uint costForPartialInSeg1 = (
            partialIssuanceInSeg1 * defaultSeg1_initialPrice
        ) / DiscreteCurveMathLib_v1.SCALING_FACTOR; // (5 * 1.5) = 7.5 ether

        uint collateralIn = defaultSeg0_reserve + costForPartialInSeg1; // 33 + 7.5 = 40.5 ether

        uint expectedIssuanceOut = defaultSeg0_capacity + partialIssuanceInSeg1; // 30 + 5 = 35 ether
        // Due to how partial purchases are calculated, the spent collateral should exactly match collateralIn if it's utilized fully.
        uint expectedCollateralSpent = collateralIn;

        (uint issuanceOut, uint collateralSpent) = exposedLib
            .calculatePurchaseReturnPublic(
            defaultSegments, collateralIn, currentSupply
        );

        assertEq(
            issuanceOut,
            expectedIssuanceOut,
            "Spanning segments, partial end: issuanceOut mismatch"
        );
        assertEq(
            collateralSpent,
            expectedCollateralSpent,
            "Spanning segments, partial end: collateralSpent mismatch"
        );
    }

    // --- Tests for _linearSearchSloped direct revert ---

    function test_LinearSearchSloped_InvalidStartStep_Reverts() public {
        // Setup a simple segment
        PackedSegment segment = DiscreteCurveMathLib_v1.createSegment(
            1 ether, // initialPrice
            0.1 ether, // priceIncrease
            10 ether, // supplyPerStep
            3 // numberOfSteps
        );
        // totalStepsInSegment is 3 for this segment.

        uint totalBudget = 100 ether; // Arbitrary budget, won't be used due to revert
        uint priceAtPurchaseStartStep = 1 ether; // Arbitrary, won't be used

        // Case 1: purchaseStartStepInSegment == totalStepsInSegment
        uint invalidStartStep1 = 3;
        vm.expectRevert(
            IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__InvalidSegmentInitialStep
                .selector
        );
        exposedLib.linearSearchSlopedPublic(
            segment, totalBudget, invalidStartStep1, priceAtPurchaseStartStep
        );

        // Case 2: purchaseStartStepInSegment > totalStepsInSegment
        uint invalidStartStep2 = 4;
        vm.expectRevert(
            IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__InvalidSegmentInitialStep
                .selector
        );
        exposedLib.linearSearchSlopedPublic(
            segment, totalBudget, invalidStartStep2, priceAtPurchaseStartStep
        );
    }
}
