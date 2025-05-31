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

    // Bit masks for fuzzed parameters, derived from PackedSegmentLib
    uint internal constant INITIAL_PRICE_MASK = (1 << 72) - 1;
    uint internal constant PRICE_INCREASE_MASK = (1 << 72) - 1;
    uint internal constant SUPPLY_PER_STEP_MASK = (1 << 96) - 1;
    uint internal constant NUMBER_OF_STEPS_MASK = (1 << 16) - 1;

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
        defaultSegments[0] = DiscreteCurveMathLib_v1._createSegment(
            defaultSeg0_initialPrice,
            defaultSeg0_priceIncrease,
            defaultSeg0_supplyPerStep,
            defaultSeg0_numberOfSteps
        );
        defaultSegments[1] = DiscreteCurveMathLib_v1._createSegment(
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

        segments[0] = DiscreteCurveMathLib_v1._createSegment(
            initialPrice, priceIncrease, supplyPerStep, numberOfSteps
        );

        uint targetSupply = 25 ether; // Target 25 tokens

        IDiscreteCurveMathLib_v1.CurvePosition memory pos =
            exposedLib.exposed_findPositionForSupply(segments, targetSupply);

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

        segments[0] = DiscreteCurveMathLib_v1._createSegment(
            initialPrice, priceIncrease, supplyPerStep, numberOfSteps
        );

        uint targetSupply = 20 ether; // Exactly fills the segment

        IDiscreteCurveMathLib_v1.CurvePosition memory pos =
            exposedLib.exposed_findPositionForSupply(segments, targetSupply);

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
            .exposed_findPositionForSupply(defaultSegments, targetSupply);

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
            .exposed_findPositionForSupply(defaultSegments, targetSupply);

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
            exposedLib.exposed_findPositionForSupply(segments, targetSupply);

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
        exposedLib.exposed_findPositionForSupply(segments, targetSupply);
    }

    function test_FindPositionForSupply_TooManySegments_Reverts() public {
        // MAX_SEGMENTS is 10 in the library
        PackedSegment[] memory segments =
            new PackedSegment[](DiscreteCurveMathLib_v1.MAX_SEGMENTS + 1);
        // Fill with dummy segments, actual content doesn't matter for this check
        for (uint i = 0; i < segments.length; ++i) {
            segments[i] = DiscreteCurveMathLib_v1._createSegment(1, 0, 1, 1);
        }
        uint targetSupply = 10 ether;

        vm.expectRevert(
            IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__TooManySegments
                .selector
        );
        exposedLib.exposed_findPositionForSupply(segments, targetSupply);
    }

    function test_FindPosition_Transition_FlatToSloped() public {
        PackedSegment[] memory segments = new PackedSegment[](2);

        // Segment 0: Flat, non-free
        uint flatInitialPrice = 0.2 ether;
        uint flatSupplyPerStep = 15 ether;
        uint flatNumberOfSteps = 1;
        uint flatCapacity = flatSupplyPerStep * flatNumberOfSteps;
        segments[0] = DiscreteCurveMathLib_v1._createSegment(
            flatInitialPrice, 0, flatSupplyPerStep, flatNumberOfSteps
        );

        // Segment 1: Sloped, paid
        uint slopedInitialPrice = 0.8 ether;
        uint slopedPriceIncrease = 0.1 ether;
        uint slopedSupplyPerStep = 8 ether;
        uint slopedNumberOfSteps = 3;
        segments[1] = DiscreteCurveMathLib_v1._createSegment(
            slopedInitialPrice,
            slopedPriceIncrease,
            slopedSupplyPerStep,
            slopedNumberOfSteps
        );

        // Scenario 1: Target supply exactly at the end of the flat segment
        uint targetSupplyAtBoundary = flatCapacity;
        IDiscreteCurveMathLib_v1.CurvePosition memory posBoundary = exposedLib
            .exposed_findPositionForSupply(segments, targetSupplyAtBoundary);

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
            .exposed_findPositionForSupply(segments, targetSupplyIntoSloped);

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
            .exposed_getCurrentPriceAndStep(defaultSegments, currentSupply);

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
            .exposed_getCurrentPriceAndStep(defaultSegments, currentSupply);

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
            .exposed_getCurrentPriceAndStep(defaultSegments, currentSupply);

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
            .exposed_getCurrentPriceAndStep(defaultSegments, currentSupply);

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
            .exposed_getCurrentPriceAndStep(defaultSegments, currentSupply);

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
        exposedLib.exposed_getCurrentPriceAndStep(segments, currentSupply);
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
        exposedLib.exposed_getCurrentPriceAndStep(segments, currentSupply);
    }

    // --- Tests for calculateReserveForSupply ---

    function test_CalculateReserveForSupply_TargetSupplyZero() public {
        // Using defaultSegments
        uint reserve =
            exposedLib.exposed_calculateReserveForSupply(defaultSegments, 0);
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
        uint numberOfSteps = 1; // CORRECTED: True Flat segment
        segments[0] = DiscreteCurveMathLib_v1._createSegment(
            initialPrice, priceIncrease, supplyPerStep, numberOfSteps
        );

        // Target the full capacity of the single step
        uint targetSupply = 10 ether; // New capacity is 10 ether
        // Expected reserve: 1 step * 10 supply/step * 2 price/token = 20 ether (scaled)
        uint expectedReserve =
            (10 ether * initialPrice) / DiscreteCurveMathLib_v1.SCALING_FACTOR; // (10 * 2) = 20

        uint reserve =
            exposedLib.exposed_calculateReserveForSupply(segments, targetSupply);
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
            exposedLib.exposed_calculateReserveForSupply(segments, targetSupply);
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

    function testRevert_CalculatePurchaseReturn_NoSegments_SupplyPositive()
        public
    {
        PackedSegment[] memory noSegments = new PackedSegment[](0);
        vm.expectRevert(
            IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__NoSegmentsConfigured
                .selector
        );
        exposedLib.exposed_calculatePurchaseReturn(
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
        exposedLib.exposed_calculatePurchaseReturn(
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
        exposedLib.exposed_calculatePurchaseReturn(
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
        uint numberOfSteps = 1; // CORRECTED: True Flat segment
        segments[0] = DiscreteCurveMathLib_v1._createSegment(
            initialPrice, priceIncrease, supplyPerStep, numberOfSteps
        );

        uint currentSupply = 0 ether;
        uint collateralIn = 45 ether; 
        // New segment: 1 step, 10 supply, price 2. Cost to buy out = 20 ether.
        // Collateral 45 ether is more than enough.
        uint expectedIssuanceOut = 10 ether; 
        uint expectedCollateralSpent = (10 ether * 2 ether) / DiscreteCurveMathLib_v1.SCALING_FACTOR; // 20 ether

        (uint issuanceOut, uint collateralSpent) = exposedLib
            .exposed_calculatePurchaseReturn(segments, collateralIn, currentSupply);

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
        uint numberOfSteps = 1; // CORRECTED: True Flat segment
        segments[0] = DiscreteCurveMathLib_v1._createSegment(
            initialPrice, priceIncrease, supplyPerStep, numberOfSteps
        );

        uint currentSupply = 0 ether;
        uint collateralIn = 50 ether;
        // New segment: 1 step, 10 supply, price 2. Cost to buy out = 20 ether.
        // Collateral 50 ether is more than enough.
        uint expectedIssuanceOut = 10 ether; 
        uint expectedCollateralSpent = (10 ether * 2 ether) / DiscreteCurveMathLib_v1.SCALING_FACTOR; // 20 ether

        (uint issuanceOut, uint collateralSpent) = exposedLib
            .exposed_calculatePurchaseReturn(segments, collateralIn, currentSupply);

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
            .exposed_calculatePurchaseReturn(segments, collateralIn, currentSupply);

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
        exposedLib.exposed_calculateSaleReturn(
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
        exposedLib.exposed_calculateSaleReturn(
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
        exposedLib.exposed_calculateSaleReturn(
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
        (uint collateralOut, uint burned) = exposedLib
            .exposed_calculateSaleReturn(
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
        exposedLib.exposed_calculateSaleReturn(
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
            .exposed_calculateSaleReturn(segments, issuanceToSell, currentSupply);

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
        uint actualReserve = exposedLib.exposed_calculateReserveForSupply(
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

        uint actualReserve = exposedLib.exposed_calculateReserveForSupply(
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
        exposedLib.exposed_calculateReserveForSupply(
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
            .exposed_calculatePurchaseReturn(segments, collateralIn, currentSupply);

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
        segments[0] = DiscreteCurveMathLib_v1._createSegment(
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
            .exposed_calculatePurchaseReturn(segments, collateralIn, currentSupply);

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
            .exposed_calculatePurchaseReturn(segments, collateralIn, currentSupply);

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
            .exposed_calculatePurchaseReturn(
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
            .exposed_calculatePurchaseReturn(
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

        // Expected: Buys remaining 5e18 of step 0 (cost 5e18), remaining budget 5e18.
        // Next step price 1.1e18. Buys 5/1.1 = 4.545...e18 tokens.
        // Total issuance = 5e18 + 4.545...e18 = 9.545...e18
        uint expectedIssuanceOut = 9_545_454_545_454_545_454; // 9.545... ether
        uint expectedCollateralSpent = collateralIn; // 10 ether (budget fully spent)

        (uint issuanceOut, uint collateralSpent) = exposedLib
            .exposed_calculatePurchaseReturn(
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
            .exposed_calculatePurchaseReturn(
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
            .exposed_calculatePurchaseReturn(
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
            .exposed_calculatePurchaseReturn(
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
        PackedSegment segment = DiscreteCurveMathLib_v1._createSegment(
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
        exposedLib.exposed_linearSearchSloped(
            segment, totalBudget, invalidStartStep1, priceAtPurchaseStartStep
        );

        // Case 2: purchaseStartStepInSegment > totalStepsInSegment
        uint invalidStartStep2 = 4;
        vm.expectRevert(
            IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__InvalidSegmentInitialStep
                .selector
        );
        exposedLib.exposed_linearSearchSloped(
            segment, totalBudget, invalidStartStep2, priceAtPurchaseStartStep
        );
    }

    // --- Test for _createSegment ---

    function testFuzz_CreateSegment_ValidProperties(
        uint initialPrice,
        uint priceIncrease,
        uint supplyPerStep,
        uint numberOfSteps
    ) public {
        // Constrain inputs to valid ranges based on bitmasks and logic
        vm.assume(initialPrice <= INITIAL_PRICE_MASK);
        vm.assume(priceIncrease <= PRICE_INCREASE_MASK);
        vm.assume(supplyPerStep <= SUPPLY_PER_STEP_MASK);
        vm.assume(numberOfSteps <= NUMBER_OF_STEPS_MASK);

        vm.assume(supplyPerStep > 0); // Must be positive
        vm.assume(numberOfSteps > 0); // Must be positive

        // Not a free segment
        vm.assume(!(initialPrice == 0 && priceIncrease == 0));

        // Ensure "True Flat" or "True Sloped"
        // numberOfSteps is already assumed > 0
        if (numberOfSteps == 1) {
            vm.assume(priceIncrease == 0); // True Flat: 1 step, 0 priceIncrease
        } else { // numberOfSteps > 1
            vm.assume(priceIncrease > 0);  // True Sloped: >1 steps, >0 priceIncrease
        }

        PackedSegment segment = exposedLib.exposed_createSegment(
            initialPrice, priceIncrease, supplyPerStep, numberOfSteps
        );

        (
            uint actualInitialPrice,
            uint actualPriceIncrease,
            uint actualSupplyPerStep,
            uint actualNumberOfSteps
        ) = segment._unpack();

        assertEq(
            actualInitialPrice,
            initialPrice,
            "Fuzz Valid CreateSegment: Initial price mismatch"
        );
        assertEq(
            actualPriceIncrease,
            priceIncrease,
            "Fuzz Valid CreateSegment: Price increase mismatch"
        );
        assertEq(
            actualSupplyPerStep,
            supplyPerStep,
            "Fuzz Valid CreateSegment: Supply per step mismatch"
        );
        assertEq(
            actualNumberOfSteps,
            numberOfSteps,
            "Fuzz Valid CreateSegment: Number of steps mismatch"
        );
    }

    function testFuzz_CreateSegment_Revert_InitialPriceTooLarge(
        uint priceIncrease,
        uint supplyPerStep,
        uint numberOfSteps
    ) public {
        uint initialPrice = INITIAL_PRICE_MASK + 1; // Exceeds mask

        vm.assume(priceIncrease <= PRICE_INCREASE_MASK);
        vm.assume(supplyPerStep <= SUPPLY_PER_STEP_MASK && supplyPerStep > 0);
        vm.assume(numberOfSteps <= NUMBER_OF_STEPS_MASK && numberOfSteps > 0);
        // Ensure this specific revert is not masked by "free segment" if priceIncrease is also 0
        vm.assume(!(initialPrice == 0 && priceIncrease == 0));

        vm.expectRevert(
            IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__InitialPriceTooLarge
                .selector
        );
        exposedLib.exposed_createSegment(
            initialPrice, priceIncrease, supplyPerStep, numberOfSteps
        );
    }

    function testFuzz_CreateSegment_Revert_PriceIncreaseTooLarge(
        uint initialPrice,
        uint supplyPerStep,
        uint numberOfSteps
    ) public {
        uint priceIncrease = PRICE_INCREASE_MASK + 1; // Exceeds mask

        vm.assume(initialPrice <= INITIAL_PRICE_MASK);
        vm.assume(supplyPerStep <= SUPPLY_PER_STEP_MASK && supplyPerStep > 0);
        vm.assume(numberOfSteps <= NUMBER_OF_STEPS_MASK && numberOfSteps > 0);
        vm.assume(!(initialPrice == 0 && priceIncrease == 0));

        vm.expectRevert(
            IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__PriceIncreaseTooLarge
                .selector
        );
        exposedLib.exposed_createSegment(
            initialPrice, priceIncrease, supplyPerStep, numberOfSteps
        );
    }

    function testFuzz_CreateSegment_Revert_SupplyPerStepTooLarge(
        uint initialPrice,
        uint priceIncrease,
        uint numberOfSteps
    ) public {
        uint supplyPerStep = SUPPLY_PER_STEP_MASK + 1; // Exceeds mask

        vm.assume(initialPrice <= INITIAL_PRICE_MASK);
        vm.assume(priceIncrease <= PRICE_INCREASE_MASK);
        vm.assume(numberOfSteps <= NUMBER_OF_STEPS_MASK && numberOfSteps > 0);
        vm.assume(!(initialPrice == 0 && priceIncrease == 0));

        vm.expectRevert(
            IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__SupplyPerStepTooLarge
                .selector
        );
        exposedLib.exposed_createSegment(
            initialPrice, priceIncrease, supplyPerStep, numberOfSteps
        );
    }

    function testFuzz_CreateSegment_Revert_NumberOfStepsTooLarge(
        uint initialPrice,
        uint priceIncrease,
        uint supplyPerStep
    ) public {
        uint numberOfSteps = NUMBER_OF_STEPS_MASK + 1; // Exceeds mask

        vm.assume(initialPrice <= INITIAL_PRICE_MASK);
        vm.assume(priceIncrease <= PRICE_INCREASE_MASK);
        vm.assume(supplyPerStep <= SUPPLY_PER_STEP_MASK && supplyPerStep > 0);
        vm.assume(!(initialPrice == 0 && priceIncrease == 0));

        vm.expectRevert(
            IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__InvalidNumberOfSteps
                .selector
        );
        exposedLib.exposed_createSegment(
            initialPrice, priceIncrease, supplyPerStep, numberOfSteps
        );
    }

    function testFuzz_CreateSegment_Revert_ZeroSupplyPerStep(
        uint initialPrice,
        uint priceIncrease,
        uint numberOfSteps
    ) public {
        uint supplyPerStep = 0;

        vm.assume(initialPrice <= INITIAL_PRICE_MASK);
        vm.assume(priceIncrease <= PRICE_INCREASE_MASK);
        vm.assume(numberOfSteps <= NUMBER_OF_STEPS_MASK && numberOfSteps > 0);
        // No need to check for free segment here as ZeroSupplyPerStep should take precedence or be orthogonal

        vm.expectRevert(
            IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__ZeroSupplyPerStep
                .selector
        );
        exposedLib.exposed_createSegment(
            initialPrice, priceIncrease, supplyPerStep, numberOfSteps
        );
    }

    function testFuzz_CreateSegment_Revert_ZeroNumberOfSteps(
        uint initialPrice,
        uint priceIncrease,
        uint supplyPerStep
    ) public {
        uint numberOfSteps = 0;

        vm.assume(initialPrice <= INITIAL_PRICE_MASK);
        vm.assume(priceIncrease <= PRICE_INCREASE_MASK);
        vm.assume(supplyPerStep <= SUPPLY_PER_STEP_MASK && supplyPerStep > 0);

        vm.expectRevert(
            IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__InvalidNumberOfSteps
                .selector
        );
        exposedLib.exposed_createSegment(
            initialPrice, priceIncrease, supplyPerStep, numberOfSteps
        );
    }

    function testFuzz_CreateSegment_Revert_FreeSegment(
        uint supplyPerStep,
        uint numberOfSteps
    ) public {
        uint initialPrice = 0;
        uint priceIncrease = 0;

        vm.assume(supplyPerStep <= SUPPLY_PER_STEP_MASK && supplyPerStep > 0);
        vm.assume(numberOfSteps <= NUMBER_OF_STEPS_MASK && numberOfSteps > 0);

        vm.expectRevert(
            IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__SegmentIsFree
                .selector
        );
        exposedLib.exposed_createSegment(
            initialPrice, priceIncrease, supplyPerStep, numberOfSteps
        );
    }

    // --- Tests for _validateSegmentArray ---

    function test_ValidateSegmentArray_Pass_SingleSegment() public view {
        PackedSegment[] memory segments = new PackedSegment[](1);
        segments[0] = exposedLib.exposed_createSegment(1 ether, 0, 10 ether, 1); // Corrected: True Flat
        exposedLib.exposed_validateSegmentArray(segments); // Should not revert
    }

    function test_ValidateSegmentArray_Pass_MultipleValidSegments_CorrectProgression(
    ) public view {
        // Uses defaultSegments which are set up with correct progression
        exposedLib.exposed_validateSegmentArray(defaultSegments); // Should not revert
    }

    function test_ValidateSegmentArray_Revert_NoSegmentsConfigured() public {
        PackedSegment[] memory segments = new PackedSegment[](0);
        vm.expectRevert(
            IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__NoSegmentsConfigured
                .selector
        );
        exposedLib.exposed_validateSegmentArray(segments);
    }

    function testFuzz_ValidateSegmentArray_Revert_TooManySegments(
        uint initialPrice,
        uint priceIncrease,
        uint supplyPerStep,
        uint numberOfSteps // Changed from uint16 to uint256 for direct use with masks
    ) public {
        // Constrain individual segment parameters to be valid to avoid unrelated reverts
        vm.assume(initialPrice <= INITIAL_PRICE_MASK);
        vm.assume(priceIncrease <= PRICE_INCREASE_MASK);
        vm.assume(supplyPerStep <= SUPPLY_PER_STEP_MASK && supplyPerStep > 0);
        vm.assume(numberOfSteps <= NUMBER_OF_STEPS_MASK && numberOfSteps > 0);
        vm.assume(!(initialPrice == 0 && priceIncrease == 0)); // Not a free segment

        // Ensure "True Flat" or "True Sloped" for the template
        // numberOfSteps is already assumed > 0
        if (numberOfSteps == 1) {
            vm.assume(priceIncrease == 0); // True Flat: 1 step, 0 priceIncrease
        } else { // numberOfSteps > 1
            vm.assume(priceIncrease > 0);  // True Sloped: >1 steps, >0 priceIncrease
        }

        PackedSegment validSegmentTemplate = exposedLib.exposed_createSegment(
            initialPrice, priceIncrease, supplyPerStep, numberOfSteps
        );

        uint numSegmentsToCreate = DiscreteCurveMathLib_v1.MAX_SEGMENTS + 1;
        PackedSegment[] memory segments =
            new PackedSegment[](numSegmentsToCreate);
        for (uint i = 0; i < numSegmentsToCreate; ++i) {
            // Fill with the same valid segment template.
            // Price progression is not the focus here, only the count.
            segments[i] = validSegmentTemplate;
        }

        vm.expectRevert(
            IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__TooManySegments
                .selector
        );
        exposedLib.exposed_validateSegmentArray(segments);
    }

    function testFuzz_ValidateSegmentArray_Revert_InvalidPriceProgression(
        uint ip0,
        uint pi0,
        uint ss0,
        uint ns0, // Segment 0 params
        uint ip1,
        uint pi1,
        uint ss1,
        uint ns1 // Segment 1 params
    ) public {
        // Constrain segment 0 params to be valid
        vm.assume(ip0 <= INITIAL_PRICE_MASK);
        vm.assume(pi0 <= PRICE_INCREASE_MASK);
        vm.assume(ss0 <= SUPPLY_PER_STEP_MASK && ss0 > 0);
        vm.assume(ns0 <= NUMBER_OF_STEPS_MASK && ns0 > 0);
        vm.assume(!(ip0 == 0 && pi0 == 0)); // Not free

        // Ensure segment0 is "True Flat" or "True Sloped"
        if (ns0 == 1) {
            vm.assume(pi0 == 0);
        } else { // ns0 > 1
            vm.assume(pi0 > 0);
        }

        // Constrain segment 1 params to be individually valid
        vm.assume(ip1 <= INITIAL_PRICE_MASK);
        vm.assume(pi1 <= PRICE_INCREASE_MASK);
        vm.assume(ss1 <= SUPPLY_PER_STEP_MASK && ss1 > 0);
        vm.assume(ns1 <= NUMBER_OF_STEPS_MASK && ns1 > 0);
        vm.assume(!(ip1 == 0 && pi1 == 0)); // Not free

        // Ensure segment1 is "True Flat" or "True Sloped"
        if (ns1 == 1) {
            vm.assume(pi1 == 0);
        } else { // ns1 > 1
            vm.assume(pi1 > 0);
        }

        PackedSegment segment0 =
            exposedLib.exposed_createSegment(ip0, pi0, ss0, ns0);

        uint finalPriceSeg0;
        if (ns0 == 0) {
            // Should be caught by assume(ns0 > 0) but defensive
            finalPriceSeg0 = ip0;
        } else {
            finalPriceSeg0 = ip0 + (ns0 - 1) * pi0;
        }

        // Ensure ip1 is strictly less than finalPriceSeg0 for invalid progression
        // Also ensure finalPriceSeg0 is large enough for ip1 to be smaller (and ip1 is valid)
        vm.assume(finalPriceSeg0 > ip1 && finalPriceSeg0 > 0); // Ensures ip1 < finalPriceSeg0 is possible and meaningful

        PackedSegment segment1 =
            exposedLib.exposed_createSegment(ip1, pi1, ss1, ns1);

        PackedSegment[] memory segments = new PackedSegment[](2);
        segments[0] = segment0;
        segments[1] = segment1;

        bytes memory expectedError = abi.encodeWithSelector(
            IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__InvalidPriceProgression
                .selector,
            0, // segment index i_ (always 0 for a 2-segment array check)
            finalPriceSeg0, // previousFinal
            ip1 // nextInitial
        );
        vm.expectRevert(expectedError);
        exposedLib.exposed_validateSegmentArray(segments);
    }

    function testFuzz_ValidateSegmentArray_Pass_ValidProperties(
        uint8 numSegmentsToFuzz, // Max 255, but we'll cap at MAX_SEGMENTS
        uint initialPriceTpl, // Template parameters
        uint priceIncreaseTpl,
        uint supplyPerStepTpl,
        uint numberOfStepsTpl
    ) public view {
        vm.assume(
            numSegmentsToFuzz >= 1
                && numSegmentsToFuzz <= DiscreteCurveMathLib_v1.MAX_SEGMENTS
        );

        // Constrain template segment parameters to be valid
        vm.assume(initialPriceTpl <= INITIAL_PRICE_MASK);
        vm.assume(priceIncreaseTpl <= PRICE_INCREASE_MASK);
        vm.assume(
            supplyPerStepTpl <= SUPPLY_PER_STEP_MASK && supplyPerStepTpl > 0
        );
        vm.assume(
            numberOfStepsTpl <= NUMBER_OF_STEPS_MASK && numberOfStepsTpl > 0
        );
        // Ensure template is not free, unless it's the only segment and we allow non-free single segments
        // For simplicity, let's ensure template is not free if initialPriceTpl is 0
        if (initialPriceTpl == 0) {
            vm.assume(priceIncreaseTpl > 0);
        }

        // Ensure template parameters adhere to new "True Flat" / "True Sloped" rules
        // numberOfStepsTpl is already assumed > 0
        if (numberOfStepsTpl == 1) {
            vm.assume(priceIncreaseTpl == 0); // True Flat template: 1 step, 0 priceIncrease
        } else { // numberOfStepsTpl > 1
            vm.assume(priceIncreaseTpl > 0);  // True Sloped template: >1 steps, >0 priceIncrease
        }

        PackedSegment[] memory segments = new PackedSegment[](numSegmentsToFuzz);
        uint lastFinalPrice = 0;

        for (uint8 i = 0; i < numSegmentsToFuzz; ++i) {
            // Create segments with a simple valid progression
            // Ensure initial price is at least the last final price and also not too large itself.
            uint currentInitialPrice = initialPriceTpl + i * 1e10; // Increment to ensure progression and uniqueness
            vm.assume(currentInitialPrice <= INITIAL_PRICE_MASK);
            if (i > 0) {
                vm.assume(currentInitialPrice >= lastFinalPrice);
            }
            // Ensure the segment itself is not free
            vm.assume(!(currentInitialPrice == 0 && priceIncreaseTpl == 0));

            segments[i] = exposedLib.exposed_createSegment(
                currentInitialPrice,
                priceIncreaseTpl,
                supplyPerStepTpl,
                numberOfStepsTpl
            );

            if (numberOfStepsTpl == 0) {
                // Should be caught by assume but defensive
                lastFinalPrice = currentInitialPrice;
            } else {
                lastFinalPrice = currentInitialPrice
                    + (numberOfStepsTpl - 1) * priceIncreaseTpl;
            }
        }
        exposedLib.exposed_validateSegmentArray(segments); // Should not revert
    }

    function test_ValidateSegmentArray_Pass_PriceProgression_ExactMatch()
        public
        view
    {
        PackedSegment[] memory segments = new PackedSegment[](2);
        // Segment 0: P_init=1.0, P_inc=0.1, S_step=10, N_steps=3. Final price = 1.2
        segments[0] =
            exposedLib.exposed_createSegment(1 ether, 0.1 ether, 10 ether, 3);
        // Segment 1: P_init=1.2 (exact match), P_inc=0.05, S_step=20, N_steps=2
        segments[1] =
            exposedLib.exposed_createSegment(1.2 ether, 0.05 ether, 20 ether, 2);
        exposedLib.exposed_validateSegmentArray(segments); // Should not revert
    }

    function test_ValidateSegmentArray_Pass_PriceProgression_FlatThenSloped()
        public
        view
    {
        PackedSegment[] memory segments = new PackedSegment[](2);
        // Segment 0: Flat. P_init=1.0, P_inc=0, N_steps=1. Final price = 1.0
        segments[0] = exposedLib.exposed_createSegment(1 ether, 0, 10 ether, 1); // Corrected: True Flat
        // Segment 1: Sloped. P_init=1.0 (match), P_inc=0.1, N_steps=2.
        segments[1] =
            exposedLib.exposed_createSegment(1 ether, 0.1 ether, 10 ether, 2); // This is True Sloped
        exposedLib.exposed_validateSegmentArray(segments); // Should not revert
    }

    function test_ValidateSegmentArray_Pass_PriceProgression_SlopedThenFlat()
        public
        view
    {
        PackedSegment[] memory segments = new PackedSegment[](2);
        // Segment 0: Sloped. P_init=1.0, P_inc=0.1, N_steps=2. Final price = 1.0 + (2-1)*0.1 = 1.1
        segments[0] =
            exposedLib.exposed_createSegment(1 ether, 0.1 ether, 10 ether, 2); // This is True Sloped
        // Segment 1: Flat. P_init=1.1 (match), P_inc=0, N_steps=1.
        segments[1] =
            exposedLib.exposed_createSegment(1.1 ether, 0, 10 ether, 1); // Corrected: True Flat
        exposedLib.exposed_validateSegmentArray(segments); // Should not revert
    }

    // --- Fuzz tests for _findPositionForSupply ---

    function _generateFuzzedValidSegmentsAndCapacity(
        uint8 numSegmentsToFuzz,
        uint initialPriceTpl,
        uint priceIncreaseTpl,
        uint supplyPerStepTpl,
        uint numberOfStepsTpl
    )
        internal
        view
        returns (PackedSegment[] memory segments, uint totalCurveCapacity)
    {
        vm.assume(
            numSegmentsToFuzz >= 1
                && numSegmentsToFuzz <= DiscreteCurveMathLib_v1.MAX_SEGMENTS
        );

        // Constrain template segment parameters for individual validity
        vm.assume(initialPriceTpl <= INITIAL_PRICE_MASK);
        vm.assume(priceIncreaseTpl <= PRICE_INCREASE_MASK);
        vm.assume(
            supplyPerStepTpl <= SUPPLY_PER_STEP_MASK && supplyPerStepTpl > 0
        );
        vm.assume(
            numberOfStepsTpl <= NUMBER_OF_STEPS_MASK && numberOfStepsTpl > 0
        );
        if (initialPriceTpl == 0) {
            vm.assume(priceIncreaseTpl > 0); // Avoid free template if it's the base
        }

        // Ensure template parameters adhere to new "True Flat" / "True Sloped" rules
        if (numberOfStepsTpl == 1) {
            vm.assume(priceIncreaseTpl == 0); // If 1 step, must be flat (True Flat)
        } else { // numberOfStepsTpl > 1 because we assume numberOfStepsTpl > 0 earlier
            vm.assume(priceIncreaseTpl > 0);  // If >1 steps, must be sloped (True Sloped)
        }

        segments = new PackedSegment[](numSegmentsToFuzz);
        uint lastSegFinalPrice = 0; // Final price of the previously added segment (i-1)
        // totalCurveCapacity is a named return, initialized to 0

        for (uint8 i = 0; i < numSegmentsToFuzz; ++i) {
            uint currentSegInitialPrice;
            if (i == 0) {
                currentSegInitialPrice = initialPriceTpl;
            } else {
                // For subsequent segments, ensure initial price is >= last segment's final price
                // and also <= INITIAL_PRICE_MASK.
                // This implies lastSegFinalPrice must have been <= INITIAL_PRICE_MASK.
                vm.assume(lastSegFinalPrice <= INITIAL_PRICE_MASK);
                currentSegInitialPrice = lastSegFinalPrice;
            }
            // Ensure the current segment about to be created is not free
            // Use priceIncreaseTpl as all segments share this template parameter here.
            vm.assume(currentSegInitialPrice > 0 || priceIncreaseTpl > 0);

            segments[i] = exposedLib.exposed_createSegment(
                currentSegInitialPrice,
                priceIncreaseTpl,
                supplyPerStepTpl,
                numberOfStepsTpl
            );

            totalCurveCapacity +=
                segments[i]._supplyPerStep() * segments[i]._numberOfSteps();

            // Calculate the final price of this current segment for the next iteration's progression check
            uint currentSegPriceRange;
            if (numberOfStepsTpl > 0) {
                // numberOfStepsTpl is assumed > 0
                uint term = numberOfStepsTpl - 1;
                if (priceIncreaseTpl > 0 && term > 0) {
                    // Check for overflow before multiplication
                    if (PRICE_INCREASE_MASK / priceIncreaseTpl < term) {
                        vm.assume(false);
                    } // term * pi would overflow
                }
                currentSegPriceRange = term * priceIncreaseTpl;
            } else {
                // Should not be reached due to assume(numberOfStepsTpl > 0)
                currentSegPriceRange = 0;
            }

            if (currentSegInitialPrice > type(uint).max - currentSegPriceRange)
            {
                // Check for overflow before addition
                vm.assume(false);
            }
            lastSegFinalPrice = currentSegInitialPrice + currentSegPriceRange;
        }

        // After generating all segments, validate the entire array.
        // This ensures the progression logic within the loop (currentInitialPrice >= lastSegFinalPrice)
        // combined with individual segment validity, results in a valid curve.
        exposedLib.exposed_validateSegmentArray(segments);
        return (segments, totalCurveCapacity);
    }

    function testFuzz_FindPositionForSupply_WithinOrAtCapacity(
        uint8 numSegmentsToFuzz,
        uint initialPriceTpl,
        uint priceIncreaseTpl,
        uint supplyPerStepTpl,
        uint numberOfStepsTpl,
        uint targetSupplyRatio // Ratio from 0 to 100
    ) public {
        // Bound inputs to valid ranges instead of using assume
        numSegmentsToFuzz = uint8(bound(numSegmentsToFuzz, 1, 10)); // Ensure valid segment count
        targetSupplyRatio = bound(targetSupplyRatio, 0, 100); // Ensure valid ratio

        // Bound template values to reasonable ranges that are likely to pass validation
        initialPriceTpl = bound(initialPriceTpl, 1e15, 1e20); // 0.001 to 100 tokens at 1e18 scale
        priceIncreaseTpl = bound(priceIncreaseTpl, 0, 1e18); // 0 to 1 token increase
        supplyPerStepTpl = bound(supplyPerStepTpl, 1e15, 1e22); // Reasonable supply range
        numberOfStepsTpl = bound(numberOfStepsTpl, 1, 1000); // Reasonable step count

        // Generate segments - this should now be much more likely to succeed
        (PackedSegment[] memory segments, uint totalCurveCapacity) =
        _generateFuzzedValidSegmentsAndCapacity(
            numSegmentsToFuzz,
            initialPriceTpl,
            priceIncreaseTpl,
            supplyPerStepTpl,
            numberOfStepsTpl
        );

        // Skip test if generation failed (instead of using assume)
        if (segments.length == 0 || totalCurveCapacity == 0) {
            return;
        }

        // Calculate target supply deterministically
        uint targetSupply;
        if (targetSupplyRatio == 100) {
            targetSupply = totalCurveCapacity;
        } else {
            targetSupply = (totalCurveCapacity * targetSupplyRatio) / 100;
        }

        // Ensure we don't exceed capacity due to rounding
        if (targetSupply > totalCurveCapacity) {
            targetSupply = totalCurveCapacity;
        }

        IDiscreteCurveMathLib_v1.CurvePosition memory pos =
            exposedLib.exposed_findPositionForSupply(segments, targetSupply);

        // Assertions
        assertTrue(
            pos.segmentIndex < segments.length, "W: Seg idx out of bounds"
        );
        PackedSegment currentSegment = segments[pos.segmentIndex];
        uint currentSegNumSteps = currentSegment._numberOfSteps();

        if (currentSegNumSteps > 0) {
            assertTrue(
                pos.stepIndexWithinSegment < currentSegNumSteps,
                "W: Step idx out of bounds"
            );
        } else {
            assertEq(
                pos.stepIndexWithinSegment,
                0,
                "W: Step idx non-zero for 0-step seg"
            );
        }

        uint expectedPrice = currentSegment._initialPrice()
            + pos.stepIndexWithinSegment * currentSegment._priceIncrease();
        assertEq(pos.priceAtCurrentStep, expectedPrice, "W: Price mismatch");
        assertEq(
            pos.supplyCoveredUpToThisPosition,
            targetSupply,
            "W: Supply covered mismatch"
        );

        if (targetSupply == 0) {
            assertEq(pos.segmentIndex, 0, "W: Seg idx for supply 0");
            assertEq(pos.stepIndexWithinSegment, 0, "W: Step idx for supply 0");
            assertEq(
                pos.priceAtCurrentStep,
                segments[0]._initialPrice(),
                "W: Price for supply 0"
            );
        }
    }

    function testFuzz_FindPositionForSupply_BeyondCapacity(
        uint8 numSegmentsToFuzz,
        uint initialPriceTpl,
        uint priceIncreaseTpl,
        uint supplyPerStepTpl,
        uint numberOfStepsTpl,
        uint targetSupplyRatioOffset // Ratio from 1 to 50 (to add to 100)
    ) public {
        // Bound inputs to valid ranges instead of using assume
        numSegmentsToFuzz = uint8(bound(numSegmentsToFuzz, 1, 10)); // Ensure valid segment count
        targetSupplyRatioOffset = bound(targetSupplyRatioOffset, 1, 50); // Ensure valid offset ratio

        // Bound template values to reasonable ranges that are likely to pass validation
        initialPriceTpl = bound(initialPriceTpl, 1e15, 1e20); // 0.001 to 100 tokens at 1e18 scale
        priceIncreaseTpl = bound(priceIncreaseTpl, 0, 1e18); // 0 to 1 token increase
        supplyPerStepTpl = bound(supplyPerStepTpl, 1e15, 1e22); // Reasonable supply range
        numberOfStepsTpl = bound(numberOfStepsTpl, 1, 1000); // Reasonable step count

        // Generate segments - this should now be much more likely to succeed
        (PackedSegment[] memory segments, uint totalCurveCapacity) =
        _generateFuzzedValidSegmentsAndCapacity(
            numSegmentsToFuzz,
            initialPriceTpl,
            priceIncreaseTpl,
            supplyPerStepTpl,
            numberOfStepsTpl
        );

        // Skip test if generation failed or capacity is 0
        if (segments.length == 0 || totalCurveCapacity == 0) {
            return;
        }

        // Calculate target supply deterministically - always beyond capacity
        uint targetSupply = totalCurveCapacity
            + (totalCurveCapacity * targetSupplyRatioOffset / 100);

        // Ensure it's strictly beyond capacity (handle edge case where calculation might equal capacity)
        if (targetSupply <= totalCurveCapacity) {
            targetSupply = totalCurveCapacity + 1;
        }

        IDiscreteCurveMathLib_v1.CurvePosition memory pos =
            exposedLib.exposed_findPositionForSupply(segments, targetSupply);

        // Assertions
        assertTrue(
            pos.segmentIndex < segments.length, "B: Seg idx out of bounds"
        );
        assertEq(
            pos.supplyCoveredUpToThisPosition,
            totalCurveCapacity,
            "B: Supply covered mismatch"
        );
        assertEq(pos.segmentIndex, segments.length - 1, "B: Seg idx not last");

        PackedSegment lastSeg = segments[segments.length - 1];
        if (lastSeg._numberOfSteps() > 0) {
            assertEq(
                pos.stepIndexWithinSegment,
                lastSeg._numberOfSteps() - 1,
                "B: Step idx not last"
            );
            assertEq(
                pos.priceAtCurrentStep,
                lastSeg._initialPrice()
                    + (lastSeg._numberOfSteps() - 1) * lastSeg._priceIncrease(),
                "B: Price mismatch at end"
            );
        } else {
            // Last segment has 0 steps (should be caught by createSegment constraints ideally)
            assertEq(
                pos.stepIndexWithinSegment,
                0,
                "B: Step idx not 0 for 0-step last seg"
            );
            assertEq(
                pos.priceAtCurrentStep,
                lastSeg._initialPrice(),
                "B: Price mismatch for 0-step last seg"
            );
        }
    }
    // --- Fuzz tests for _getCurrentPriceAndStep ---

    function testFuzz_GetCurrentPriceAndStep_Properties(
        uint8 numSegmentsToFuzz,
        uint initialPriceTpl,
        uint priceIncreaseTpl,
        uint supplyPerStepTpl,
        uint numberOfStepsTpl,
        uint currentSupplyRatio // Ratio from 0 to 100 to determine currentSupply based on total capacity
    ) public {
        // Bound inputs for segment generation
        numSegmentsToFuzz = uint8(
            bound(numSegmentsToFuzz, 1, DiscreteCurveMathLib_v1.MAX_SEGMENTS)
        );
        initialPriceTpl = bound(initialPriceTpl, 1e15, 1e20);
        priceIncreaseTpl = bound(priceIncreaseTpl, 0, 1e18);
        supplyPerStepTpl = bound(supplyPerStepTpl, 1e15, 1e22);
        numberOfStepsTpl = bound(numberOfStepsTpl, 1, 1000);

        (PackedSegment[] memory segments, uint totalCurveCapacity) =
        _generateFuzzedValidSegmentsAndCapacity(
            numSegmentsToFuzz,
            initialPriceTpl,
            priceIncreaseTpl,
            supplyPerStepTpl,
            numberOfStepsTpl
        );

        if (segments.length == 0) {
            return;
        }

        uint currentTotalIssuanceSupply;
        if (totalCurveCapacity == 0) {
            // If capacity is 0, only test with supply 0. currentSupplyRatio is ignored.
            currentTotalIssuanceSupply = 0;
            // If currentSupplyRatio was >0, we might want to skip, but _findPositionForSupply handles 0 capacity, 0 supply.
            if (currentSupplyRatio > 0) return; // Avoid division by zero if totalCurveCapacity is 0 but ratio isn't.
        } else {
            currentSupplyRatio = bound(currentSupplyRatio, 0, 100); // 0% to 100% of capacity
            currentTotalIssuanceSupply =
                (totalCurveCapacity * currentSupplyRatio) / 100;
            if (currentSupplyRatio == 100) {
                currentTotalIssuanceSupply = totalCurveCapacity;
            }
            if (currentTotalIssuanceSupply > totalCurveCapacity) {
                // Ensure it doesn't exceed due to rounding
                currentTotalIssuanceSupply = totalCurveCapacity;
            }
        }

        // Call _getCurrentPriceAndStep
        (uint price, uint stepIdx, uint segmentIdx) = exposedLib
            .exposed_getCurrentPriceAndStep(segments, currentTotalIssuanceSupply);

        // Call _findPositionForSupply for comparison
        IDiscreteCurveMathLib_v1.CurvePosition memory pos = exposedLib
            .exposed_findPositionForSupply(segments, currentTotalIssuanceSupply);

        // Assertions
        assertTrue(
            segmentIdx < segments.length, "GCPS: Segment index out of bounds"
        );
        PackedSegment currentSegmentFromGet = segments[segmentIdx]; // Renamed to avoid clash
        uint currentSegNumStepsFromGet = currentSegmentFromGet._numberOfSteps();

        if (currentSegNumStepsFromGet > 0) {
            assertTrue(
                stepIdx < currentSegNumStepsFromGet,
                "GCPS: Step index out of bounds for segment"
            );
        } else {
            assertEq(
                stepIdx, 0, "GCPS: Step index should be 0 for zero-step segment"
            );
        }

        uint expectedPriceAtStep = currentSegmentFromGet._initialPrice()
            + stepIdx * currentSegmentFromGet._priceIncrease();
        assertEq(
            price,
            expectedPriceAtStep,
            "GCPS: Price mismatch based on its own step/segment"
        );

        // Consistency with _findPositionForSupply
        assertEq(
            segmentIdx,
            pos.segmentIndex,
            "GCPS: Segment index mismatch with findPosition"
        );
        assertEq(
            stepIdx,
            pos.stepIndexWithinSegment,
            "GCPS: Step index mismatch with findPosition"
        );
        assertEq(
            price,
            pos.priceAtCurrentStep,
            "GCPS: Price mismatch with findPosition"
        );

        if (currentTotalIssuanceSupply == 0 && segments.length > 0) {
            // Added segments.length > 0 for safety
            assertEq(segmentIdx, 0, "GCPS: Seg idx for supply 0");
            assertEq(stepIdx, 0, "GCPS: Step idx for supply 0");
            assertEq(
                price, segments[0]._initialPrice(), "GCPS: Price for supply 0"
            );
        }
    }

    // --- Fuzz tests for _calculateReserveForSupply ---

    // function testFuzz_CalculateReserveForSupply_Properties(
    //     uint8 numSegmentsToFuzz,
    //     uint initialPriceTpl,
    //     uint priceIncreaseTpl,
    //     uint supplyPerStepTpl,
    //     uint numberOfStepsTpl,
    //     uint targetSupplyRatio // Ratio from 0 to 110 (0=0%, 100=100% capacity, 110=110% capacity)
    // ) public {
    //     // Bound inputs for segment generation
    //     numSegmentsToFuzz = uint8(bound(numSegmentsToFuzz, 1, DiscreteCurveMathLib_v1.MAX_SEGMENTS));
    //     initialPriceTpl = bound(initialPriceTpl, 0, INITIAL_PRICE_MASK); // Allow 0 initial price if PI > 0
    //     priceIncreaseTpl = bound(priceIncreaseTpl, 0, PRICE_INCREASE_MASK);
    //     supplyPerStepTpl = bound(supplyPerStepTpl, 1, SUPPLY_PER_STEP_MASK); // Must be > 0
    //     numberOfStepsTpl = bound(numberOfStepsTpl, 1, NUMBER_OF_STEPS_MASK); // Must be > 0

    //     // Ensure template is not free if initialPriceTpl is 0
    //     if (initialPriceTpl == 0) {
    //         vm.assume(priceIncreaseTpl > 0);
    //     }

    //     (
    //         PackedSegment[] memory segments,
    //         uint totalCurveCapacity
    //     ) = _generateFuzzedValidSegmentsAndCapacity(
    //         numSegmentsToFuzz, initialPriceTpl, priceIncreaseTpl, supplyPerStepTpl, numberOfStepsTpl
    //     );

    //     // If segment generation resulted in an empty array (e.g. due to internal vm.assume failures in helper)
    //     // or if totalCurveCapacity is 0 (which can happen if supplyPerStep or numberOfSteps are fuzzed to 0
    //     // despite bounding, or if numSegments is 0 - though we bound numSegmentsToFuzz >= 1),
    //     // then we can't meaningfully proceed with ratio-based targetSupply.
    //     if (segments.length == 0) { // Helper ensures numSegmentsToFuzz >=1, so this is defensive
    //         return;
    //     }

    //     targetSupplyRatio = bound(targetSupplyRatio, 0, 110); // 0% to 110%

    //     uint targetSupply;
    //     if (totalCurveCapacity == 0) {
    //         // If curve capacity is 0 (e.g. 1 segment with 0 supply/steps, though createSegment prevents this)
    //         // only test targetSupply = 0.
    //         if (targetSupplyRatio == 0) {
    //             targetSupply = 0;
    //         } else {
    //             // Cannot test ratios against 0 capacity other than 0 itself.
    //             return;
    //         }
    //     } else {
    //         if (targetSupplyRatio == 0) {
    //             targetSupply = 0;
    //         } else if (targetSupplyRatio <= 100) {
    //             targetSupply = (totalCurveCapacity * targetSupplyRatio) / 100;
    //             // Ensure targetSupply does not exceed totalCurveCapacity due to rounding,
    //             // especially if targetSupplyRatio is 100.
    //             if (targetSupply > totalCurveCapacity) {
    //                 targetSupply = totalCurveCapacity;
    //             }
    //         } else { // targetSupplyRatio > 100 (e.g., 101 to 110)
    //             // Calculate supply beyond capacity. Add 1 wei to ensure it's strictly greater if ratio calculation results in equality.
    //             targetSupply = (totalCurveCapacity * (targetSupplyRatio - 100) / 100) + totalCurveCapacity + 1;
    //         }
    //     }

    //     if (targetSupply > totalCurveCapacity && totalCurveCapacity > 0) {
    //         // This check is for when we intentionally set targetSupply > totalCurveCapacity
    //         // and the curve actually has capacity.
    //         // _validateSupplyAgainstSegments (called by _calculateReserveForSupply) should revert.
    //         bytes memory expectedError = abi.encodeWithSelector(
    //             IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__SupplyExceedsCurveCapacity.selector,
    //             targetSupply,
    //             totalCurveCapacity
    //         );
    //         vm.expectRevert(expectedError);
    //         exposedLib.exposed_calculateReserveForSupply(segments, targetSupply);
    //     } else {
    //         // Conditions where it should not revert with SupplyExceedsCurveCapacity:
    //         // 1. targetSupply <= totalCurveCapacity
    //         // 2. totalCurveCapacity == 0 (and thus targetSupply must also be 0 to reach here)

    //         uint reserve = exposedLib.exposed_calculateReserveForSupply(segments, targetSupply);

    //         if (targetSupply == 0) {
    //             assertEq(reserve, 0, "FCR_P: Reserve for 0 supply should be 0");
    //         }

    //         // Further property: If the curve consists of a single flat segment, and targetSupply is within its capacity
    //         if (numSegmentsToFuzz == 1 && priceIncreaseTpl == 0 && initialPriceTpl > 0 && targetSupply <= totalCurveCapacity) {
    //             // Calculate expected reserve for a single flat segment
    //             // uint expectedReserve = (targetSupply * initialPriceTpl) / DiscreteCurveMathLib_v1.SCALING_FACTOR; // Original calculation before _mulDivUp consideration
    //             // Note: The library uses _mulDivUp for reserve calculation in flat segments if initialPrice > 0.
    //             // So, if (targetSupply * initialPriceTpl) % SCALING_FACTOR > 0, it rounds up.
    //             uint directCalc = (targetSupply * initialPriceTpl) / DiscreteCurveMathLib_v1.SCALING_FACTOR;
    //             if ( (targetSupply * initialPriceTpl) % DiscreteCurveMathLib_v1.SCALING_FACTOR > 0) {
    //                 directCalc++;
    //             }
    //             assertEq(reserve, directCalc, "FCR_P: Reserve for single flat segment mismatch");
    //         }
    //         // Add more specific assertions based on fuzzed segment properties if complex invariants can be derived.
    //         // For now, primarily testing reverts and zero conditions.
    //         assertTrue(true, "FCR_P: Passed without unexpected revert"); // Placeholder if no specific value check
    //     }
    // }

    // // --- Fuzz tests for _calculatePurchaseReturn ---

    // function testFuzz_CalculatePurchaseReturn_Properties(
    //     uint8 numSegmentsToFuzz,
    //     uint initialPriceTpl,
    //     uint priceIncreaseTpl,
    //     uint supplyPerStepTpl,
    //     uint numberOfStepsTpl,
    //     uint collateralToSpendProvidedRatio, // Ratio of totalCurveReserve, 0 to 150 (0=0, 100=totalReserve, 150=1.5*totalReserve)
    //     uint currentSupplyRatio // Ratio of totalCurveCapacity, 0 to 100
    // ) public {
    //     numSegmentsToFuzz = uint8(bound(numSegmentsToFuzz, 1, DiscreteCurveMathLib_v1.MAX_SEGMENTS));
    //     initialPriceTpl = bound(initialPriceTpl, 0, INITIAL_PRICE_MASK);
    //     priceIncreaseTpl = bound(priceIncreaseTpl, 0, PRICE_INCREASE_MASK);
    //     supplyPerStepTpl = bound(supplyPerStepTpl, 1, SUPPLY_PER_STEP_MASK);
    //     numberOfStepsTpl = bound(numberOfStepsTpl, 1, NUMBER_OF_STEPS_MASK);

    //     if (initialPriceTpl == 0) {
    //         vm.assume(priceIncreaseTpl > 0);
    //     }

    //     (
    //         PackedSegment[] memory segments,
    //         uint totalCurveCapacity
    //     ) = _generateFuzzedValidSegmentsAndCapacity(
    //         numSegmentsToFuzz, initialPriceTpl, priceIncreaseTpl, supplyPerStepTpl, numberOfStepsTpl
    //     );

    //     if (segments.length == 0) {
    //         return;
    //     }

    //     currentSupplyRatio = bound(currentSupplyRatio, 0, 100);
    //     uint currentTotalIssuanceSupply;
    //     if (totalCurveCapacity == 0) {
    //         if (currentSupplyRatio > 0) return; // Cannot have supply if capacity is 0
    //         currentTotalIssuanceSupply = 0;
    //     } else {
    //         currentTotalIssuanceSupply = (totalCurveCapacity * currentSupplyRatio) / 100;
    //         if (currentTotalIssuanceSupply > totalCurveCapacity) currentTotalIssuanceSupply = totalCurveCapacity;
    //     }

    //     uint totalCurveReserve = exposedLib.exposed_calculateReserveForSupply(segments, totalCurveCapacity);

    //     collateralToSpendProvidedRatio = bound(collateralToSpendProvidedRatio, 0, 150);
    //     uint collateralToSpendProvided;
    //     if (totalCurveReserve == 0 && collateralToSpendProvidedRatio > 0) {
    //         // If total reserve is 0 (e.g. fully free curve), but trying to spend, use a nominal amount
    //         // or handle specific free mint logic if applicable. For now, use a small non-zero amount.
    //         collateralToSpendProvided = bound(collateralToSpendProvidedRatio, 1, 100 ether); // Use ratio as a small absolute value
    //     } else if (totalCurveReserve == 0 && collateralToSpendProvidedRatio == 0) {
    //         collateralToSpendProvided = 0;
    //     } else {
    //         collateralToSpendProvided = (totalCurveReserve * collateralToSpendProvidedRatio) / 100;
    //          if (collateralToSpendProvidedRatio > 100 && totalCurveReserve > 0) { // Spending more than total reserve
    //             collateralToSpendProvided = totalCurveReserve + (totalCurveReserve * (collateralToSpendProvidedRatio - 100) / 100) + 1;
    //         }
    //     }

    //     if (collateralToSpendProvided == 0) {
    //         vm.expectRevert(IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__ZeroCollateralInput.selector);
    //         exposedLib.exposed_calculatePurchaseReturn(segments, collateralToSpendProvided, currentTotalIssuanceSupply);
    //     } else if (currentTotalIssuanceSupply > totalCurveCapacity && totalCurveCapacity > 0) {
    //         // This case should be caught by _validateSupplyAgainstSegments in _calculatePurchaseReturn
    //         // Note: _generateFuzzedValidSegmentsAndCapacity ensures currentTotalIssuanceSupply <= totalCurveCapacity
    //         // So this branch is more for logical completeness if inputs were constructed differently.
    //         // For this test structure, currentTotalIssuanceSupply is derived from totalCurveCapacity.
    //         // The primary test for SupplyExceeds is in its own dedicated unit/fuzz test.
    //         // However, if totalCurveCapacity is 0, currentTotalIssuanceSupply must also be 0.
    //         // If currentTotalIssuanceSupply > 0 and totalCurveCapacity is 0, _validateSupplyAgainstSegments will revert.
    //         // This specific condition (currentSupply > capacity > 0) is less likely here due to setup.
    //          bytes memory expectedError = abi.encodeWithSelector(
    //             IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__SupplyExceedsCurveCapacity.selector,
    //             currentTotalIssuanceSupply,
    //             totalCurveCapacity
    //         );
    //         vm.expectRevert(expectedError);
    //         exposedLib.exposed_calculatePurchaseReturn(segments, collateralToSpendProvided, currentTotalIssuanceSupply);
    //     } else {
    //         (uint tokensToMint, uint collateralSpentByPurchaser) = exposedLib.exposed_calculatePurchaseReturn(
    //             segments, collateralToSpendProvided, currentTotalIssuanceSupply
    //         );

    //         assertTrue(collateralSpentByPurchaser <= collateralToSpendProvided, "FCPR_P: Spent more than provided");

    //         if (totalCurveCapacity > 0) { // Avoid division by zero if capacity is 0
    //              assertTrue(tokensToMint <= (totalCurveCapacity - currentTotalIssuanceSupply), "FCPR_P: Minted more than available capacity");
    //         } else { // totalCurveCapacity is 0
    //             assertEq(tokensToMint, 0, "FCPR_P: Minted tokens when capacity is 0");
    //         }

    //         if (currentTotalIssuanceSupply == totalCurveCapacity && totalCurveCapacity > 0) {
    //             assertEq(tokensToMint, 0, "FCPR_P: Minted tokens at full capacity");
    //             // Collateral spent might be > 0 if it tries to buy into a non-existent next step of a 0-price segment.
    //             // However, _calculatePurchaseForSingleSegment should handle startStepInCurrentSegment_ >= currentSegmentTotalSteps_
    //         }

    //         // If the entire curve is free (initialPrice and priceIncrease are 0 for all segments)
    //         // This is hard to set up with _generateFuzzedValidSegmentsAndCapacity due to `assume(initialPriceTpl > 0 || priceIncreaseTpl > 0)`
    //         // and `assume(currentSegInitialPrice > 0 || priceIncreaseTpl > 0)`.
    //         // A dedicated test for fully free curves might be needed if that's a valid state.

    //         // If collateralSpentByPurchaser is 0, tokensToMint should also be 0, unless it's a free portion.
    //         bool isPotentiallyFree = false;
    //         if (tokensToMint > 0 && segments.length > 0) {
    //             (,,uint segIdxAtPurchase) = exposedLib.exposed_getCurrentPriceAndStep(segments, currentTotalIssuanceSupply);
    //             (uint initialP, uint increaseP,,) = segments[segIdxAtPurchase]._unpack();
    //             if (initialP == 0 && increaseP == 0) { // This segment is free
    //                 isPotentiallyFree = true;
    //             }
    //         }

    //         if (collateralSpentByPurchaser == 0 && !isPotentiallyFree) {
    //             assertEq(tokensToMint, 0, "FCPR_P: Minted tokens without spending collateral on non-free segment");
    //         }
    //          assertTrue(true, "FCPR_P: Passed without unexpected revert");
    //     }
    // }
}
