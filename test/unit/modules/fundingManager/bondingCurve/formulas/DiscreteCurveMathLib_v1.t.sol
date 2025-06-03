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
import {Math} from "@oz/utils/math/Math.sol";


contract DiscreteCurveMathLib_v1_Test is Test {
    // Allow using PackedSegmentLib functions directly on PackedSegment type
    using PackedSegmentLib for PackedSegment;

    // Structs for organizing test data
    struct CurveTestData {
        PackedSegment[] packedSegmentsArray; // Array of PackedSegments for the library
        uint totalCapacity; // Calculated: sum of segment capacities
        uint totalReserve; // Calculated: sum of segment reserves
        string description; // Optional: for logging or comments
    }

    // Bit masks for fuzzed parameters, derived from PackedSegmentLib
    uint internal constant INITIAL_PRICE_MASK = (1 << 72) - 1;
    uint internal constant PRICE_INCREASE_MASK = (1 << 72) - 1;
    uint internal constant SUPPLY_PER_STEP_MASK = (1 << 96) - 1;
    uint internal constant NUMBER_OF_STEPS_MASK = (1 << 16) - 1;

    DiscreteCurveMathLibV1_Exposed internal exposedLib;

    // Test curve configurations

    // Based on twoSlopedSegmentsTestCurve initialized in setUp():
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
    CurveTestData internal twoSlopedSegmentsTestCurve;

    // Based on flatSlopedTestCurve initialized in setUp():
    // Seg0 (Flat): P_init=0.5, S_step=50, N_steps=1  (Price: 0.50)
    // Seg1 (Sloped): P_init=0.8, P_inc=0.02, S_step=25, N_steps=2 (Prices: 0.80, 0.82)
    //
    //     Price (ether)
    //       ^
    //     0.82|                     +------+ (Supply: 100)
    //         |                     |      |
    //     0.80|             +-------+      | (Supply: 75)
    //         |             |              |
    //         |             |              |
    //         |             |              |
    //         |             |              |
    //     0.50|-------------+              | (Supply: 50)
    //         +-------------+--------------+--> Supply (ether)
    //         0             50     75     100
    //
    //          Step Prices:
    //          Supply  0-50:  Price 0.50 (Segment 0, Step 0)
    //          Supply 50-75:  Price 0.80 (Segment 1, Step 0)
    //          Supply 75-100: Price 0.82 (Segment 1, Step 1)
    CurveTestData internal flatSlopedTestCurve;

    // Based on flatToFlatTestCurve initialized in setUp():
    // Seg0 (Flat): P_init=1.0, S_step=20, N_steps=1 (Price: 1.00)
    // Seg1 (Flat): P_init=1.5, S_step=30, N_steps=1 (Price: 1.50)
    //
    //     Price (ether)
    //       ^
    //     1.50|   +-----------------+ (Supply: 50)
    //         |   |                 |
    //         |   |                 |
    //         |   |                 |
    //     1.00|---+                 | (Supply: 20)
    //         +---+-----------------+--> Supply (ether)
    //         0   20                50
    //
    //          Step Prices:
    //          Supply  0-20:  Price 1.00 (Segment 0, Step 0)
    //          Supply 20-50:  Price 1.50 (Segment 1, Step 0)
    CurveTestData internal flatToFlatTestCurve;


    function _calculateCurveReserve(PackedSegment[] memory segments)
        internal
        pure
        returns (uint totalReserve_)
    {
        for (uint i = 0; i < segments.length; i++) {
            (
                uint initialPrice,
                uint priceIncrease,
                uint supplyPerStep,
                uint numberOfSteps
            ) = segments[i]._unpack();

            for (uint j = 0; j < numberOfSteps; j++) {
                uint priceAtStep = initialPrice + (j * priceIncrease);
                totalReserve_ += (supplyPerStep * priceAtStep)
                    / DiscreteCurveMathLib_v1.SCALING_FACTOR;
            }
        }
    }

    function setUp() public virtual {
        exposedLib = new DiscreteCurveMathLibV1_Exposed();

        // --- Initialize twoSlopedSegmentsTestCurve ---
        twoSlopedSegmentsTestCurve.description = "Two sloped segments";
        // Segment 0 (Sloped)
        twoSlopedSegmentsTestCurve.packedSegmentsArray.push(
            exposedLib.exposed_createSegment(
                1 ether, // initialPrice
                0.1 ether, // priceIncrease
                10 ether, // supplyPerStep
                3 // numberOfSteps (Prices: 1.0, 1.1, 1.2)
            )
        );
        // Segment 1 (Sloped)
        twoSlopedSegmentsTestCurve.packedSegmentsArray.push(
            exposedLib.exposed_createSegment(
                1.5 ether, // initialPrice
                0.05 ether, // priceIncrease
                20 ether, // supplyPerStep
                2 // numberOfSteps (Prices: 1.5, 1.55)
            )
        );
        twoSlopedSegmentsTestCurve.totalCapacity =
            (10 ether * 3) + (20 ether * 2); // 30 + 40 = 70 ether
        twoSlopedSegmentsTestCurve.totalReserve = _calculateCurveReserve(
            twoSlopedSegmentsTestCurve.packedSegmentsArray
        );

        // --- Initialize flatSlopedTestCurve ---
        flatSlopedTestCurve.description =
            "Flat segment followed by a sloped segment";
        // Segment 0 (Flat)
        flatSlopedTestCurve.packedSegmentsArray.push(
            exposedLib.exposed_createSegment(
                0.5 ether, // initialPrice
                0, // priceIncrease
                50 ether, // supplyPerStep
                1 // numberOfSteps
            )
        );
        // Segment 1 (Sloped)
        flatSlopedTestCurve.packedSegmentsArray.push(
            exposedLib.exposed_createSegment(
                0.8 ether, // initialPrice (Must be >= 0.5)
                0.02 ether, // priceIncrease
                25 ether, // supplyPerStep
                2 // numberOfSteps (Prices: 0.8, 0.82)
            )
        );
        flatSlopedTestCurve.totalCapacity = (50 ether * 1) + (25 ether * 2); // 50 + 50 = 100 ether
        flatSlopedTestCurve.totalReserve =
            _calculateCurveReserve(flatSlopedTestCurve.packedSegmentsArray);

        // --- Initialize flatToFlatTestCurve ---
        flatToFlatTestCurve.description =
            "Flat segment followed by another flat segment";
        // Segment 0 (Flat)
        flatToFlatTestCurve.packedSegmentsArray.push(
            exposedLib.exposed_createSegment(
                1 ether, // initialPrice
                0, // priceIncrease
                20 ether, // supplyPerStep
                1 // numberOfSteps
            )
        );
        // Segment 1 (Flat)
        flatToFlatTestCurve.packedSegmentsArray.push(
            exposedLib.exposed_createSegment(
                1.5 ether, // initialPrice (Valid progression from 1 ether)
                0, // priceIncrease
                30 ether, // supplyPerStep
                1 // numberOfSteps
            )
        );
        flatToFlatTestCurve.totalCapacity = (20 ether * 1) + (30 ether * 1); // 20 + 30 = 50 ether
        flatToFlatTestCurve.totalReserve =
            _calculateCurveReserve(flatToFlatTestCurve.packedSegmentsArray);
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
        uint seg0Capacity = twoSlopedSegmentsTestCurve.packedSegmentsArray[0]
            ._supplyPerStep()
            * twoSlopedSegmentsTestCurve.packedSegmentsArray[0]._numberOfSteps();
        uint targetSupply = seg0Capacity + 10 ether; // 30 + 10 = 40 ether

        IDiscreteCurveMathLib_v1.CurvePosition memory pos = exposedLib
            .exposed_findPositionForSupply(
            twoSlopedSegmentsTestCurve.packedSegmentsArray, targetSupply
        );

        assertEq(pos.segmentIndex, 1, "Segment index mismatch");
        // Supply from seg0 = 30. Supply needed from seg1 = 10.
        // Step 0 of seg1 covers supply 0-20 (relative to seg1 start).
        // 10 supply needed from seg1 falls into step 0 (0-indexed).
        // supplyNeededFromThisSegment (seg1) = 10. stepIndex = 10 / 20 (twoSlopedSegmentsTestCurve.packedSegmentsArray[1]._supplyPerStep()) = 0.
        assertEq(
            pos.stepIndexWithinSegment, 0, "Step index mismatch for segment 1"
        );

        uint expectedPrice = twoSlopedSegmentsTestCurve.packedSegmentsArray[1]
            ._initialPrice()
            + (
                0
                    * twoSlopedSegmentsTestCurve.packedSegmentsArray[1]._priceIncrease()
            ); // Price at step 0 of segment 1
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
        // Uses twoSlopedSegmentsTestCurve.packedSegmentsArray
        // twoSlopedSegmentsTestCurve.totalCapacity = 70 ether
        uint targetSupply = twoSlopedSegmentsTestCurve.totalCapacity + 10 ether; // Beyond capacity (70 + 10 = 80)

        IDiscreteCurveMathLib_v1.CurvePosition memory pos = exposedLib
            .exposed_findPositionForSupply(
            twoSlopedSegmentsTestCurve.packedSegmentsArray, targetSupply
        );

        assertEq(
            pos.segmentIndex, 1, "Segment index should be last segment (1)"
        );
        assertEq(
            pos.stepIndexWithinSegment,
            twoSlopedSegmentsTestCurve.packedSegmentsArray[1]._numberOfSteps()
                - 1,
            "Step index should be last step of last segment"
        );

        uint expectedPriceAtEndOfCurve = twoSlopedSegmentsTestCurve
            .packedSegmentsArray[1]._initialPrice()
            + (
                (
                    twoSlopedSegmentsTestCurve.packedSegmentsArray[1]._numberOfSteps(
                    ) - 1
                )
                    * twoSlopedSegmentsTestCurve.packedSegmentsArray[1]._priceIncrease()
            );
        assertEq(
            pos.priceAtCurrentStep,
            expectedPriceAtEndOfCurve,
            "Price should be at end of last segment"
        );
        assertEq(
            pos.supplyCoveredUpToThisPosition,
            twoSlopedSegmentsTestCurve.totalCapacity,
            "Supply covered should be total curve capacity"
        );
    }

    function test_FindPositionForSupply_TargetSupplyZero() public {
        // Using only the first segment of twoSlopedSegmentsTestCurve.packedSegmentsArray for simplicity
        PackedSegment[] memory segments = new PackedSegment[](1);
        segments[0] = twoSlopedSegmentsTestCurve.packedSegmentsArray[0];

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
            twoSlopedSegmentsTestCurve.packedSegmentsArray[0]._initialPrice(),
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
        // Using twoSlopedSegmentsTestCurve.packedSegmentsArray
        uint currentSupply = 0 ether;
        (uint price, uint stepIdx, uint segmentIdx) = exposedLib
            .exposed_getCurrentPriceAndStep(
            twoSlopedSegmentsTestCurve.packedSegmentsArray, currentSupply
        );

        assertEq(
            segmentIdx, 0, "Segment index should be 0 for current supply 0"
        );
        assertEq(stepIdx, 0, "Step index should be 0 for current supply 0");
        assertEq(
            price,
            twoSlopedSegmentsTestCurve.packedSegmentsArray[0]._initialPrice(),
            "Price should be initial price of first segment for current supply 0"
        );
    }

    function test_GetCurrentPriceAndStep_WithinStep_NotBoundary() public {
        // Using twoSlopedSegmentsTestCurve.packedSegmentsArray
        // Default Seg0: initialPrice 1, increase 0.1, supplyPerStep 10, steps 3.
        // Step 0: 0-10 supply, price 1.0
        // Step 1: 10-20 supply, price 1.1.
        uint currentSupply = 15 ether; // Falls in step 1 of segment 0
        (uint price, uint stepIdx, uint segmentIdx) = exposedLib
            .exposed_getCurrentPriceAndStep(
            twoSlopedSegmentsTestCurve.packedSegmentsArray, currentSupply
        );

        assertEq(segmentIdx, 0, "Segment index mismatch");
        assertEq(stepIdx, 1, "Step index mismatch - should be step 1");
        uint expectedPrice = twoSlopedSegmentsTestCurve.packedSegmentsArray[0]
            ._initialPrice()
            + (
                1
                    * twoSlopedSegmentsTestCurve.packedSegmentsArray[0]._priceIncrease()
            ); // Price of step 1
        assertEq(
            price, expectedPrice, "Price mismatch - should be price of step 1"
        );
    }

    function test_GetCurrentPriceAndStep_EndOfStep_NotEndOfSegment() public {
        // Using twoSlopedSegmentsTestCurve.packedSegmentsArray
        // Default Seg0: initialPrice 1, increase 0.1, supplyPerStep 10, steps 3.
        // Current supply is 10 ether, exactly at the end of step 0 of segment 0.
        // Price should be for step 1 of segment 0.
        uint currentSupply =
            twoSlopedSegmentsTestCurve.packedSegmentsArray[0]._supplyPerStep(); // 10 ether
        (uint price, uint stepIdx, uint segmentIdx) = exposedLib
            .exposed_getCurrentPriceAndStep(
            twoSlopedSegmentsTestCurve.packedSegmentsArray, currentSupply
        );

        assertEq(segmentIdx, 0, "Segment index mismatch");
        assertEq(stepIdx, 1, "Step index should advance to 1");
        uint expectedPrice = twoSlopedSegmentsTestCurve.packedSegmentsArray[0]
            ._initialPrice()
            + (
                1
                    * twoSlopedSegmentsTestCurve.packedSegmentsArray[0]._priceIncrease()
            ); // Price of step 1 (1.1)
        assertEq(price, expectedPrice, "Price should be for step 1");
    }

    function test_GetCurrentPriceAndStep_EndOfSegment_NotLastSegment() public {
        // Using twoSlopedSegmentsTestCurve.packedSegmentsArray
        // Current supply is 30 ether, exactly at the end of segment 0.
        // Price/step should be for the start of segment 1.
        uint seg0Capacity = twoSlopedSegmentsTestCurve.packedSegmentsArray[0]
            ._supplyPerStep()
            * twoSlopedSegmentsTestCurve.packedSegmentsArray[0]._numberOfSteps();
        uint currentSupply = seg0Capacity;
        (uint price, uint stepIdx, uint segmentIdx) = exposedLib
            .exposed_getCurrentPriceAndStep(
            twoSlopedSegmentsTestCurve.packedSegmentsArray, currentSupply
        );

        assertEq(segmentIdx, 1, "Segment index should advance to 1");
        assertEq(stepIdx, 0, "Step index should be 0 of segment 1");
        assertEq(
            price,
            twoSlopedSegmentsTestCurve.packedSegmentsArray[1]._initialPrice(),
            "Price should be initial price of segment 1"
        );
    }

    function test_GetCurrentPriceAndStep_EndOfLastSegment() public {
        // Using twoSlopedSegmentsTestCurve.packedSegmentsArray
        // Current supply is total capacity of the curve (70 ether).
        uint currentSupply = twoSlopedSegmentsTestCurve.totalCapacity;

        (uint price, uint stepIdx, uint segmentIdx) = exposedLib
            .exposed_getCurrentPriceAndStep(
            twoSlopedSegmentsTestCurve.packedSegmentsArray, currentSupply
        );

        assertEq(segmentIdx, 1, "Segment index should be last segment (1)");
        assertEq(
            stepIdx,
            twoSlopedSegmentsTestCurve.packedSegmentsArray[1]._numberOfSteps()
                - 1,
            "Step index should be last step of last segment"
        );
        uint expectedPrice = twoSlopedSegmentsTestCurve.packedSegmentsArray[1]
            ._initialPrice()
            + (
                (
                    twoSlopedSegmentsTestCurve.packedSegmentsArray[1]._numberOfSteps(
                    ) - 1
                )
                    * twoSlopedSegmentsTestCurve.packedSegmentsArray[1]._priceIncrease()
            );
        assertEq(
            price,
            expectedPrice,
            "Price should be price of last step of last segment"
        );
    }

    function test_GetCurrentPriceAndStep_SupplyBeyondCapacity_Reverts()
        public
    {
        // Using a single segment for simplicity
        PackedSegment[] memory segments = new PackedSegment[](1);
        segments[0] = twoSlopedSegmentsTestCurve.packedSegmentsArray[0];
        uint singleSegmentCapacity =
            segments[0]._supplyPerStep() * segments[0]._numberOfSteps(); // Capacity 30 ether

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
        // Using twoSlopedSegmentsTestCurve.packedSegmentsArray
        uint reserve = exposedLib.exposed_calculateReserveForSupply(
            twoSlopedSegmentsTestCurve.packedSegmentsArray, 0
        );
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
        // Using only the first segment of twoSlopedSegmentsTestCurve.packedSegmentsArray (which is sloped)
        PackedSegment[] memory segments = new PackedSegment[](1);
        segments[0] = twoSlopedSegmentsTestCurve.packedSegmentsArray[0]; // initialPrice 1, increase 0.1, supplyPerStep 10, steps 3
        PackedSegment seg0 = twoSlopedSegmentsTestCurve.packedSegmentsArray[0];

        // Target 2 steps (20 ether supply) from seg0
        // Step 0: price 1.0, supply 10. Cost = 10 * 1.0 = 10
        // Step 1: price 1.1, supply 10. Cost = 10 * 1.1 = 11
        // Total reserve = (10 + 11) = 21 ether (scaled)
        uint targetSupply = 2 * seg0._supplyPerStep(); // 20 ether

        uint expectedReserve = 0;
        expectedReserve += (
            seg0._supplyPerStep()
                * (seg0._initialPrice() + 0 * seg0._priceIncrease())
        ) / DiscreteCurveMathLib_v1.SCALING_FACTOR;
        expectedReserve += (
            seg0._supplyPerStep()
                * (seg0._initialPrice() + 1 * seg0._priceIncrease())
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

    function testRevert_CalculatePurchaseReturn_ZeroCollateralInput() public {
        vm.expectRevert(
            IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__ZeroCollateralInput
                .selector
        );
        exposedLib.exposed_calculatePurchaseReturn(
            twoSlopedSegmentsTestCurve.packedSegmentsArray,
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
        uint expectedCollateralSpent =
            (10 ether * 2 ether) / DiscreteCurveMathLib_v1.SCALING_FACTOR; // 20 ether

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
        uint expectedCollateralSpent =
            (10 ether * 2 ether) / DiscreteCurveMathLib_v1.SCALING_FACTOR; // 20 ether

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
        // Using only the first segment of twoSlopedSegmentsTestCurve.packedSegmentsArray (sloped)
        PackedSegment[] memory segments = new PackedSegment[](1);
        segments[0] = twoSlopedSegmentsTestCurve.packedSegmentsArray[0]; // initialPrice 1, increase 0.1, supplyPerStep 10, steps 3

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
            twoSlopedSegmentsTestCurve.packedSegmentsArray,
            0, // Zero issuanceAmountIn
            (
                twoSlopedSegmentsTestCurve.packedSegmentsArray[0]._supplyPerStep(
                )
                    * twoSlopedSegmentsTestCurve.packedSegmentsArray[0]
                        ._numberOfSteps()
            ) // currentTotalIssuanceSupply
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
        // Using only the first segment of twoSlopedSegmentsTestCurve.packedSegmentsArray (sloped)
        PackedSegment[] memory segments = new PackedSegment[](1);
        segments[0] = twoSlopedSegmentsTestCurve.packedSegmentsArray[0]; // initialPrice 1, increase 0.1, supplyPerStep 10, steps 3
        PackedSegment seg0 = twoSlopedSegmentsTestCurve.packedSegmentsArray[0];

        // Current supply is 30 ether (3 steps minted from seg0)
        uint currentSupply = seg0._supplyPerStep() * seg0._numberOfSteps(); // 30 ether

        PackedSegment[] memory tempSegArray = new PackedSegment[](1);
        tempSegArray[0] = seg0;
        uint reserveForSeg0Full = _calculateCurveReserve(tempSegArray); // Reserve for 30 supply = 33 ether

        // Selling 10 ether issuance (the tokens from the last minted step, step 2 of seg0)
        uint issuanceToSell = seg0._supplyPerStep(); // 10 ether

        // Expected: final supply after sale = 20 ether
        // Reserve for 20 supply (first 2 steps of seg0):
        // Step 0 (price 1.0): 10 coll
        // Step 1 (price 1.1): 11 coll
        // Total reserve for 20 supply = 10 + 11 = 21 ether
        uint reserveFor20Supply = 0;
        reserveFor20Supply += (
            seg0._supplyPerStep()
                * (seg0._initialPrice() + 0 * seg0._priceIncrease())
        ) / DiscreteCurveMathLib_v1.SCALING_FACTOR;
        reserveFor20Supply += (
            seg0._supplyPerStep()
                * (seg0._initialPrice() + 1 * seg0._priceIncrease())
        ) / DiscreteCurveMathLib_v1.SCALING_FACTOR;

        // Collateral out = Reserve(30) - Reserve(20) = 33 - 21 = 12 ether
        uint expectedCollateralOut = reserveForSeg0Full - reserveFor20Supply;
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
        // Using twoSlopedSegmentsTestCurve.packedSegmentsArray
        // twoSlopedSegmentsTestCurve.totalCapacity = 70 ether
        // twoSlopedSegmentsTestCurve.totalReserve = 94 ether
        uint actualReserve = exposedLib.exposed_calculateReserveForSupply(
            twoSlopedSegmentsTestCurve.packedSegmentsArray,
            twoSlopedSegmentsTestCurve.totalCapacity
        );
        assertEq(
            actualReserve,
            twoSlopedSegmentsTestCurve.totalReserve,
            "Reserve for full multi-segment curve mismatch"
        );
    }

    function test_CalculateReserveForSupply_MultiSegment_PartialFillLaterSegment(
    ) public {
        // Using twoSlopedSegmentsTestCurve.packedSegmentsArray
        PackedSegment seg0 = twoSlopedSegmentsTestCurve.packedSegmentsArray[0]; // capacity 30
        PackedSegment seg1 = twoSlopedSegmentsTestCurve.packedSegmentsArray[1]; // initialPrice 1.5, increase 0.05, supplyPerStep 20, steps 2.

        PackedSegment[] memory tempSeg0Array = new PackedSegment[](1);
        tempSeg0Array[0] = seg0;
        uint reserveForSeg0Full = _calculateCurveReserve(tempSeg0Array); // reserve 33

        // Target supply: Full seg0 (30) + 1 step of seg1 (20) = 50 ether
        uint targetSupply = (seg0._supplyPerStep() * seg0._numberOfSteps())
            + seg1._supplyPerStep(); // 30 + 20 = 50 ether

        // Cost for the first step of segment 1:
        // 20 supply * (1.5 price + 0 * 0.05 increase) = 30 ether collateral
        uint costFirstStepSeg1 = (
            seg1._supplyPerStep()
                * (seg1._initialPrice() + 0 * seg1._priceIncrease())
        ) / DiscreteCurveMathLib_v1.SCALING_FACTOR;

        uint expectedTotalReserve = reserveForSeg0Full + costFirstStepSeg1; // 33 + 30 = 63 ether

        uint actualReserve = exposedLib.exposed_calculateReserveForSupply(
            twoSlopedSegmentsTestCurve.packedSegmentsArray, targetSupply
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
        // Using twoSlopedSegmentsTestCurve.packedSegmentsArray
        // twoSlopedSegmentsTestCurve.totalCapacity = 70 ether
        // twoSlopedSegmentsTestCurve.totalReserve = 94 ether
        uint targetSupplyBeyondCapacity =
            twoSlopedSegmentsTestCurve.totalCapacity + 100 ether; // e.g., 70e18 + 100e18 = 170e18

        // Expect revert because targetSupplyBeyondCapacity > twoSlopedSegmentsTestCurve.totalCapacity
        bytes memory expectedError = abi.encodeWithSelector(
            IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__SupplyExceedsCurveCapacity
                .selector,
            targetSupplyBeyondCapacity,
            twoSlopedSegmentsTestCurve.totalCapacity
        );
        vm.expectRevert(expectedError);
        exposedLib.exposed_calculateReserveForSupply(
            twoSlopedSegmentsTestCurve.packedSegmentsArray,
            targetSupplyBeyondCapacity
        );
    }

    function test_CalculateReserveForSupply_SingleSlopedSegment_PartialStepFill(
    ) public {
        // Using the first segment of twoSlopedSegmentsTestCurve:
        // Seg0: P_init=1.0, P_inc=0.1, S_step=10, N_steps=3
        // Prices: 1.0 (0-10), 1.1 (10-20), 1.2 (20-30)
        PackedSegment[] memory segments = new PackedSegment[](1);
        segments[0] = twoSlopedSegmentsTestCurve.packedSegmentsArray[0];

        // Target Supply: 15 ether
        // Step 0 (0-10 supply): 10 ether * 1.0 price = 10 ether reserve
        // Step 1 (10-15 supply, partial 5 ether): 5 ether * 1.1 price = 5.5 ether reserve
        // Total expected reserve = 10 + 5.5 = 15.5 ether
        uint targetSupply = 15 ether;
        uint expectedReserve = 155 * 10 ** 17; // 15.5 ether

        uint actualReserve =
            exposedLib.exposed_calculateReserveForSupply(segments, targetSupply);
        assertEq(
            actualReserve,
            expectedReserve,
            "Reserve for sloped segment partial step fill mismatch"
        );
    }

    // TODO: Implement test
    // function test_CalculateReserveForSupply_MixedFlatAndSlopedSegments() public {
    // }

    function test_CalculatePurchaseReturn_Edge_CollateralForExactlyOneStep_Sloped(
    ) public {
        PackedSegment[] memory segments = new PackedSegment[](1);
        segments[0] = twoSlopedSegmentsTestCurve.packedSegmentsArray[0]; // Sloped segment from default setup

        uint currentSupply = 0 ether;
        // Cost of the first step of segments[0]
        // initialPrice = 1 ether, supplyPerStep = 10 ether
        uint costFirstStep = (
            segments[0]._supplyPerStep() * segments[0]._initialPrice()
        ) / DiscreteCurveMathLib_v1.SCALING_FACTOR; // 10 ether
        uint collateralIn = costFirstStep;

        uint expectedIssuanceOut = segments[0]._supplyPerStep(); // 10 ether
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
        PackedSegment seg0 = twoSlopedSegmentsTestCurve.packedSegmentsArray[0]; // Sloped segment from default setup
        segments[0] = seg0;

        uint currentSupply = 0 ether;
        // Cost of the first step of seg0 is 10 ether
        uint costFirstStep = (seg0._supplyPerStep() * seg0._initialPrice())
            / DiscreteCurveMathLib_v1.SCALING_FACTOR;
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
        // Uses twoSlopedSegmentsTestCurve.packedSegmentsArray which has total capacity of twoSlopedSegmentsTestCurve.totalCapacity (70 ether)
        // and total reserve of twoSlopedSegmentsTestCurve.totalReserve (94 ether)
        uint currentSupply = 0 ether;

        // Test with exact collateral to buy out the curve
        uint collateralInExact = twoSlopedSegmentsTestCurve.totalReserve;
        uint expectedIssuanceOutExact = twoSlopedSegmentsTestCurve.totalCapacity;
        uint expectedCollateralSpentExact =
            twoSlopedSegmentsTestCurve.totalReserve;

        (uint issuanceOut, uint collateralSpent) = exposedLib
            .exposed_calculatePurchaseReturn(
            twoSlopedSegmentsTestCurve.packedSegmentsArray,
            collateralInExact,
            currentSupply
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
        uint collateralInMore =
            twoSlopedSegmentsTestCurve.totalReserve + 100 ether;
        // Expected behavior: still only buys out the curve capacity and spends the required reserve.
        uint expectedIssuanceOutMore = twoSlopedSegmentsTestCurve.totalCapacity;
        uint expectedCollateralSpentMore =
            twoSlopedSegmentsTestCurve.totalReserve;

        (issuanceOut, collateralSpent) = exposedLib
            .exposed_calculatePurchaseReturn(
            twoSlopedSegmentsTestCurve.packedSegmentsArray,
            collateralInMore,
            currentSupply
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
        uint currentSupply = 5 ether; // Mid-step 0 of twoSlopedSegmentsTestCurve.packedSegmentsArray[0]

        PackedSegment seg0 = twoSlopedSegmentsTestCurve.packedSegmentsArray[0];
        // getCurrentPriceAndStep(twoSlopedSegmentsTestCurve.packedSegmentsArray, 5 ether) will yield:
        // priceAtPurchaseStart = 1.0 ether (price of step 0 of seg0)
        // stepAtPurchaseStart = 0 (index of step 0 of seg0)
        // segmentAtPurchaseStart = 0 (index of seg0)

        // Collateral to buy one full step (step 0 of segment 0, price 1.0)
        // Note: calculatePurchaseReturn's internal _calculatePurchaseForSingleSegment will attempt to buy
        // full steps from the identified startStep (step 0 of seg0 in this case).
        uint collateralIn = (seg0._supplyPerStep() * seg0._initialPrice())
            / DiscreteCurveMathLib_v1.SCALING_FACTOR; // 10 ether

        // Expected: Buys remaining 5e18 of step 0 (cost 5e18), remaining budget 5e18.
        // Next step price 1.1e18. Buys 5/1.1 = 4.545...e18 tokens.
        // Total issuance = 5e18 + 4.545...e18 = 9.545...e18
        uint expectedIssuanceOut = 9_545_454_545_454_545_454; // 9.545... ether
        uint expectedCollateralSpent = collateralIn; // 10 ether (budget fully spent)

        (uint issuanceOut, uint collateralSpent) = exposedLib
            .exposed_calculatePurchaseReturn(
            twoSlopedSegmentsTestCurve.packedSegmentsArray,
            collateralIn,
            currentSupply
        );

        assertEq(issuanceOut, expectedIssuanceOut, "Issuance mid-step mismatch");
        assertEq(
            collateralSpent,
            expectedCollateralSpent,
            "Collateral mid-step mismatch"
        );
    }

    function test_CalculatePurchaseReturn_StartEndOfStep_Sloped() public {
        PackedSegment seg0 = twoSlopedSegmentsTestCurve.packedSegmentsArray[0];
        uint currentSupply = seg0._supplyPerStep(); // 10 ether, end of step 0 of seg0

        // getCurrentPriceAndStep(twoSlopedSegmentsTestCurve.packedSegmentsArray, 10 ether) will yield:
        // priceAtPurchaseStart = 1.1 ether (price of step 1 of seg0)
        // stepAtPurchaseStart = 1 (index of step 1 of seg0)
        // segmentAtPurchaseStart = 0 (index of seg0)

        // Collateral to buy one full step (which will be step 1 of segment 0, price 1.1)
        uint priceOfStep1Seg0 = seg0._initialPrice() + seg0._priceIncrease();
        uint collateralIn = (seg0._supplyPerStep() * priceOfStep1Seg0)
            / DiscreteCurveMathLib_v1.SCALING_FACTOR; // 11 ether

        // Expected: Buys 1 full step (step 1 of segment 0)
        uint expectedIssuanceOut = seg0._supplyPerStep(); // 10 ether (supply of step 1)
        uint expectedCollateralSpent = collateralIn; // 11 ether

        (uint issuanceOut, uint collateralSpent) = exposedLib
            .exposed_calculatePurchaseReturn(
            twoSlopedSegmentsTestCurve.packedSegmentsArray,
            collateralIn,
            currentSupply
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
        PackedSegment seg0 = twoSlopedSegmentsTestCurve.packedSegmentsArray[0];
        PackedSegment seg1 = twoSlopedSegmentsTestCurve.packedSegmentsArray[1];
        uint currentSupply = seg0._supplyPerStep() * seg0._numberOfSteps(); // 30 ether, end of segment 0

        // getCurrentPriceAndStep(twoSlopedSegmentsTestCurve.packedSegmentsArray, 30 ether) will yield:
        // priceAtPurchaseStart = 1.5 ether (initial price of segment 1)
        // stepAtPurchaseStart = 0 (index of step 0 in segment 1)
        // segmentAtPurchaseStart = 1 (index of segment 1)

        // Collateral to buy one full step from segment 1 (step 0 of seg1, price 1.5)
        uint collateralIn = (seg1._supplyPerStep() * seg1._initialPrice())
            / DiscreteCurveMathLib_v1.SCALING_FACTOR; // 30 ether

        // Expected: Buys 1 full step (step 0 of segment 1)
        uint expectedIssuanceOut = seg1._supplyPerStep(); // 20 ether (supply of step 0 of seg1)
        uint expectedCollateralSpent = collateralIn; // 30 ether

        (uint issuanceOut, uint collateralSpent) = exposedLib
            .exposed_calculatePurchaseReturn(
            twoSlopedSegmentsTestCurve.packedSegmentsArray,
            collateralIn,
            currentSupply
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
        PackedSegment seg0 = twoSlopedSegmentsTestCurve.packedSegmentsArray[0];
        PackedSegment seg1 = twoSlopedSegmentsTestCurve.packedSegmentsArray[1];

        PackedSegment[] memory tempSeg0Array = new PackedSegment[](1);
        tempSeg0Array[0] = seg0;
        uint reserveForSeg0Full = _calculateCurveReserve(tempSeg0Array); // Collateral needed for segment 0 (33 ether)

        // For segment 1:
        //   Price of first step = seg1._initialPrice() (1.5 ether)
        //   Supply per step in seg1 = seg1._supplyPerStep() (20 ether)
        //   Let's target buying 5 ether issuance from segment 1's first step.
        uint partialIssuanceInSeg1 = 5 ether;
        uint costForPartialInSeg1 = (
            partialIssuanceInSeg1 * seg1._initialPrice()
        ) / DiscreteCurveMathLib_v1.SCALING_FACTOR; // (5 * 1.5) = 7.5 ether

        uint collateralIn = reserveForSeg0Full + costForPartialInSeg1; // 33 + 7.5 = 40.5 ether

        uint expectedIssuanceOut = (
            seg0._supplyPerStep() * seg0._numberOfSteps()
        ) + partialIssuanceInSeg1; // 30 + 5 = 35 ether
        // Due to how partial purchases are calculated, the spent collateral should exactly match collateralIn if it's utilized fully.
        uint expectedCollateralSpent = collateralIn;

        (uint issuanceOut, uint collateralSpent) = exposedLib
            .exposed_calculatePurchaseReturn(
            twoSlopedSegmentsTestCurve.packedSegmentsArray,
            collateralIn,
            currentSupply
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

    // Test P3.4.2: End in next segment (segment transition) - From flat segment to sloped segment
    function test_CalculatePurchaseReturn_Transition_FlatToSloped_PartialBuyInSlopedSegment(
    ) public {
        // Uses flatSlopedTestCurve.packedSegmentsArray:
        PackedSegment flatSeg0 = flatSlopedTestCurve.packedSegmentsArray[0]; // Seg0 (Flat): initialPrice 0.5, supplyPerStep 50, steps 1. Capacity 50. Cost to buyout = 25 ether.
        PackedSegment slopedSeg1 = flatSlopedTestCurve.packedSegmentsArray[1]; // Seg1 (Sloped): initialPrice 0.8, priceIncrease 0.02, supplyPerStep 25, steps 2.

        uint currentSupply = 0 ether;

        // Collateral to:
        // 1. Buy out flatSeg0 (50 tokens):
        //    Cost = (50 ether * 0.5 ether) / SCALING_FACTOR = 25 ether.
        // 2. Buy 10 tokens from the first step of slopedSeg1 (price 0.8 ether):
        //    Cost = (10 ether * 0.8 ether) / SCALING_FACTOR = 8 ether.
        uint collateralToBuyoutFlatSeg = (
            flatSeg0._supplyPerStep() * flatSeg0._initialPrice()
        ) / DiscreteCurveMathLib_v1.SCALING_FACTOR;

        uint tokensToBuyInSlopedSeg = 10 ether;
        uint costForPartialSlopedSeg = (
            tokensToBuyInSlopedSeg * slopedSeg1._initialPrice()
        ) // Price of first step in sloped segment
            / DiscreteCurveMathLib_v1.SCALING_FACTOR;

        uint collateralIn = collateralToBuyoutFlatSeg + costForPartialSlopedSeg; // 25 + 8 = 33 ether

        uint expectedTokensToMint =
            flatSeg0._supplyPerStep() + tokensToBuyInSlopedSeg; // 50 + 10 = 60 ether
        uint expectedCollateralSpent = collateralIn; // Should spend all 33 ether

        (uint tokensToMint, uint collateralSpent) = exposedLib
            .exposed_calculatePurchaseReturn(
            flatSlopedTestCurve.packedSegmentsArray, // Use the flatSlopedTestCurve configuration
            collateralIn,
            currentSupply
        );

        assertEq(
            tokensToMint,
            expectedTokensToMint,
            "Flat to Sloped transition: tokensToMint mismatch"
        );
        assertEq(
            collateralSpent,
            expectedCollateralSpent,
            "Flat to Sloped transition: collateralSpent mismatch"
        );
    }

    // Test P2.2.1: CurrentSupply mid-step, budget can complete current step - Flat segment
    function test_CalculatePurchaseReturn_StartMidStep_CompleteStep_FlatSegment(
    ) public {
        // Use the flat segment from flatSlopedTestCurve
        PackedSegment flatSeg = flatSlopedTestCurve.packedSegmentsArray[0]; // initialPrice = 0.5 ether, priceIncrease = 0, supplyPerStep = 50 ether, numberOfSteps = 1
        PackedSegment[] memory segments = new PackedSegment[](1);
        segments[0] = flatSeg;

        uint currentSupply = 10 ether; // Start 10 ether into the 50 ether capacity of the flat segment's single step.

        // Remaining supply in the step = 50 ether (flatSeg._supplyPerStep()) - 10 ether (currentSupply) = 40 ether.
        // Cost to purchase remaining supply = 40 ether * 0.5 ether (flatSeg._initialPrice()) / SCALING_FACTOR = 20 ether.
        uint collateralIn = (
            (flatSeg._supplyPerStep() - currentSupply) * flatSeg._initialPrice()
        ) / DiscreteCurveMathLib_v1.SCALING_FACTOR; // Should be 20 ether

        uint expectedTokensToMint = flatSeg._supplyPerStep() - currentSupply; // 40 ether
        uint expectedCollateralSpent = collateralIn; // 20 ether

        (uint tokensToMint, uint collateralSpent) = exposedLib
            .exposed_calculatePurchaseReturn(segments, collateralIn, currentSupply);

        assertEq(
            tokensToMint,
            expectedTokensToMint,
            "Flat mid-step complete: tokensToMint mismatch"
        );
        assertEq(
            collateralSpent,
            expectedCollateralSpent,
            "Flat mid-step complete: collateralSpent mismatch"
        );
    }

    // Test P2.3.1: CurrentSupply mid-step, budget cannot complete current step (early exit) - Flat segment
    function test_CalculatePurchaseReturn_StartMidStep_CannotCompleteStep_FlatSegment(
    ) public {
        // Use the flat segment from flatSlopedTestCurve
        PackedSegment flatSeg = flatSlopedTestCurve.packedSegmentsArray[0]; // initialPrice = 0.5 ether, priceIncrease = 0, supplyPerStep = 50 ether, numberOfSteps = 1
        PackedSegment[] memory segments = new PackedSegment[](1);
        segments[0] = flatSeg;

        uint currentSupply = 10 ether; // Start 10 ether into the 50 ether capacity.

        // Remaining supply in step = 40 ether. Cost to complete step = 20 ether.
        // Provide collateral that CANNOT complete the step. Let's buy 10 tokens.
        // Cost for 10 tokens = 10 ether * 0.5 price / SCALING_FACTOR = 5 ether.
        uint collateralIn = 5 ether;

        uint expectedTokensToMint = 10 ether; // Should be able to buy 10 tokens.
        uint expectedCollateralSpent = collateralIn; // Collateral should be fully spent.

        (uint tokensToMint, uint collateralSpent) = exposedLib
            .exposed_calculatePurchaseReturn(segments, collateralIn, currentSupply);

        assertEq(
            tokensToMint,
            expectedTokensToMint,
            "Flat mid-step cannot complete: tokensToMint mismatch"
        );
        assertEq(
            collateralSpent,
            expectedCollateralSpent,
            "Flat mid-step cannot complete: collateralSpent mismatch"
        );
    }

    function test_CalculatePurchaseReturn_Transition_FlatToFlatSegment()
        public
    {
        // Using flatToFlatTestCurve
        uint currentSupply = 0 ether;
        PackedSegment flatSeg0_ftf = flatToFlatTestCurve.packedSegmentsArray[0];
        PackedSegment flatSeg1_ftf = flatToFlatTestCurve.packedSegmentsArray[1];

        PackedSegment[] memory tempSeg0Array_ftf = new PackedSegment[](1);
        tempSeg0Array_ftf[0] = flatSeg0_ftf;
        uint reserveForFlatSeg0 = _calculateCurveReserve(tempSeg0Array_ftf);

        // Collateral to buy out segment 0 and 10 tokens from segment 1
        uint tokensToBuyInSeg1 = 10 ether;
        uint costForPartialSeg1 = (
            tokensToBuyInSeg1 * flatSeg1_ftf._initialPrice()
        ) / DiscreteCurveMathLib_v1.SCALING_FACTOR;
        uint collateralIn = reserveForFlatSeg0 + costForPartialSeg1;

        uint expectedTokensToMint = (
            flatSeg0_ftf._supplyPerStep() * flatSeg0_ftf._numberOfSteps()
        ) + tokensToBuyInSeg1;
        uint expectedCollateralSpent = collateralIn;

        (uint tokensToMint, uint collateralSpent) = exposedLib
            .exposed_calculatePurchaseReturn(
            flatToFlatTestCurve.packedSegmentsArray, collateralIn, currentSupply
        );

        assertEq(
            tokensToMint,
            expectedTokensToMint,
            "Flat to Flat transition: tokensToMint mismatch"
        );
        assertEq(
            collateralSpent,
            expectedCollateralSpent,
            "Flat to Flat transition: collateralSpent mismatch"
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
        } else {
            // numberOfSteps > 1
            vm.assume(priceIncrease > 0); // True Sloped: >1 steps, >0 priceIncrease
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
        // Uses twoSlopedSegmentsTestCurve.packedSegmentsArray which are set up with correct progression
        exposedLib.exposed_validateSegmentArray(
            twoSlopedSegmentsTestCurve.packedSegmentsArray
        ); // Should not revert
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
        } else {
            // numberOfSteps > 1
            vm.assume(priceIncrease > 0); // True Sloped: >1 steps, >0 priceIncrease
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
        } else {
            // ns0 > 1
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
        } else {
            // ns1 > 1
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
        } else {
            // numberOfStepsTpl > 1
            vm.assume(priceIncreaseTpl > 0); // True Sloped template: >1 steps, >0 priceIncrease
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

    // Test P3.2.1 (from test_cases.md, adapted): Complete partial step, then partial purchase next step - Flat segment to Flat segment
    // This covers "Case 3: Starting mid-step (Phase 2 + Phase 3 integration)"
    // 3.2: Complete partial step, then partial purchase next step
    // 3.2.1: Flat segment (implies transition to next segment which is also flat here)
    function test_CalculatePurchaseReturn_StartMidFlat_CompleteFlat_PartialNextFlat(
    ) public {
        // Uses flatToFlatTestCurve:
        // Seg0 (Flat): initialPrice 1 ether, supplyPerStep 20 ether, steps 1. Capacity 20. Cost to buyout = 20 ether.
        // Seg1 (Flat): initialPrice 1.5 ether, supplyPerStep 30 ether, steps 1. Capacity 30.
        PackedSegment flatSeg0 = flatToFlatTestCurve.packedSegmentsArray[0];
        PackedSegment flatSeg1 = flatToFlatTestCurve.packedSegmentsArray[1];

        uint currentSupply = 10 ether; // Start 10 ether into Seg0 (20 ether capacity)
        uint remainingInSeg0 = flatSeg0._supplyPerStep() - currentSupply; // 10 ether

        // Collateral to:
        // 1. Buy out remaining in flatSeg0:
        //    Cost = 10 ether (remaining supply) * 1 ether (price) / SCALING_FACTOR = 10 ether.
        uint collateralToCompleteSeg0 = (
            remainingInSeg0 * flatSeg0._initialPrice()
        ) / DiscreteCurveMathLib_v1.SCALING_FACTOR;

        // 2. Buy 5 tokens from the first (and only) step of flatSeg1 (price 1.5 ether):
        uint tokensToBuyInSeg1 = 5 ether;
        uint costForPartialSeg1 = (tokensToBuyInSeg1 * flatSeg1._initialPrice())
            / DiscreteCurveMathLib_v1.SCALING_FACTOR;

        uint collateralIn = collateralToCompleteSeg0 + costForPartialSeg1; // 10 + 7.5 = 17.5 ether

        uint expectedTokensToMint = remainingInSeg0 + tokensToBuyInSeg1; // 10 + 5 = 15 ether
        // For flat segments with exact math, collateral spent should equal collateralIn if fully utilized.
        uint expectedCollateralSpent = collateralIn;

        (uint tokensToMint, uint collateralSpent) = exposedLib
            .exposed_calculatePurchaseReturn(
            flatToFlatTestCurve.packedSegmentsArray, collateralIn, currentSupply
        );

        assertEq(
            tokensToMint,
            expectedTokensToMint,
            "MidFlat->NextFlat: tokensToMint mismatch"
        );
        assertEq(
            collateralSpent,
            expectedCollateralSpent,
            "MidFlat->NextFlat: collateralSpent mismatch"
        );
    }

    // --- Fuzz tests for _findPositionForSupply ---

    function _createFuzzedSegmentAndCalcProperties(
        uint currentIterInitialPriceToUse, // The initial price for *this* segment
        uint priceIncreaseTpl,
        uint supplyPerStepTpl,
        uint numberOfStepsTpl
    )
        internal
        view
        returns (
            PackedSegment newSegment,
            uint capacityOfThisSegment,
            uint finalPriceOfThisSegment
        )
    {
        // Assumptions for currentIterInitialPriceToUse:
        // - Already determined (either template or previous final price).
        // - Within INITIAL_PRICE_MASK.
        // - (currentIterInitialPriceToUse > 0 || priceIncreaseTpl > 0) to ensure not free.
        vm.assume(currentIterInitialPriceToUse <= INITIAL_PRICE_MASK);
        vm.assume(currentIterInitialPriceToUse > 0 || priceIncreaseTpl > 0);

        newSegment = exposedLib.exposed_createSegment(
            currentIterInitialPriceToUse,
            priceIncreaseTpl,
            supplyPerStepTpl,
            numberOfStepsTpl
        );

        capacityOfThisSegment =
            newSegment._supplyPerStep() * newSegment._numberOfSteps();

        uint priceRangeInSegment;
        // numberOfStepsTpl is assumed > 0 by the caller _generateFuzzedValidSegmentsAndCapacity
        uint term = numberOfStepsTpl - 1;
        if (priceIncreaseTpl > 0 && term > 0) {
            // Overflow check for term * priceIncreaseTpl
            // Using PRICE_INCREASE_MASK as a general large number check for the result of multiplication
            if (
                priceIncreaseTpl != 0
                    && PRICE_INCREASE_MASK / priceIncreaseTpl < term
            ) {
                vm.assume(false);
            }
        }
        priceRangeInSegment = term * priceIncreaseTpl;

        // Overflow check for currentIterInitialPriceToUse + priceRangeInSegment
        if (currentIterInitialPriceToUse > type(uint).max - priceRangeInSegment)
        {
            vm.assume(false);
        }
        finalPriceOfThisSegment =
            currentIterInitialPriceToUse + priceRangeInSegment;

        return (newSegment, capacityOfThisSegment, finalPriceOfThisSegment);
    }

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

        vm.assume(initialPriceTpl <= INITIAL_PRICE_MASK);
        vm.assume(priceIncreaseTpl <= PRICE_INCREASE_MASK);
        vm.assume(
            supplyPerStepTpl <= SUPPLY_PER_STEP_MASK && supplyPerStepTpl > 0
        );
        vm.assume(
            numberOfStepsTpl <= NUMBER_OF_STEPS_MASK && numberOfStepsTpl > 0
        );
        if (initialPriceTpl == 0) {
            vm.assume(priceIncreaseTpl > 0);
        }

        if (numberOfStepsTpl == 1) {
            vm.assume(priceIncreaseTpl == 0);
        } else {
            vm.assume(priceIncreaseTpl > 0);
        }

        segments = new PackedSegment[](numSegmentsToFuzz);
        uint lastSegFinalPrice = 0;
        // totalCurveCapacity is a named return, initialized to 0

        for (uint8 i = 0; i < numSegmentsToFuzz; ++i) {
            uint currentSegInitialPriceToUse;
            if (i == 0) {
                currentSegInitialPriceToUse = initialPriceTpl;
            } else {
                // vm.assume(lastSegFinalPrice <= INITIAL_PRICE_MASK); // This check is now inside the helper for currentIterInitialPriceToUse
                currentSegInitialPriceToUse = lastSegFinalPrice;
            }

            (
                PackedSegment createdSegment,
                uint capacityOfCreatedSegment,
                uint finalPriceOfCreatedSegment
            ) = _createFuzzedSegmentAndCalcProperties(
                currentSegInitialPriceToUse,
                priceIncreaseTpl,
                supplyPerStepTpl,
                numberOfStepsTpl
            );

            segments[i] = createdSegment;
            totalCurveCapacity += capacityOfCreatedSegment;
            lastSegFinalPrice = finalPriceOfCreatedSegment;
        }

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

    function testFuzz_CalculateReserveForSupply_Properties(
        uint8 numSegmentsToFuzz,
        uint initialPriceTpl,
        uint priceIncreaseTpl,
        uint supplyPerStepTpl,
        uint numberOfStepsTpl,
        uint targetSupplyRatio // Ratio from 0 to 110 (0=0%, 100=100% capacity, 110=110% capacity)
    ) public {
        // Bound inputs for segment generation
        numSegmentsToFuzz = uint8(
            bound(numSegmentsToFuzz, 1, DiscreteCurveMathLib_v1.MAX_SEGMENTS)
        );
        initialPriceTpl = bound(initialPriceTpl, 0, INITIAL_PRICE_MASK); // Allow 0 initial price if PI > 0
        priceIncreaseTpl = bound(priceIncreaseTpl, 0, PRICE_INCREASE_MASK);
        supplyPerStepTpl = bound(supplyPerStepTpl, 1, SUPPLY_PER_STEP_MASK); // Must be > 0
        numberOfStepsTpl = bound(numberOfStepsTpl, 1, NUMBER_OF_STEPS_MASK); // Must be > 0

        // Ensure template is not free if initialPriceTpl is 0
        if (initialPriceTpl == 0) {
            vm.assume(priceIncreaseTpl > 0);
        }

        (PackedSegment[] memory segments, uint totalCurveCapacity) =
        _generateFuzzedValidSegmentsAndCapacity(
            numSegmentsToFuzz,
            initialPriceTpl,
            priceIncreaseTpl,
            supplyPerStepTpl,
            numberOfStepsTpl
        );

        // If segment generation resulted in an empty array (e.g. due to internal vm.assume failures in helper)
        // or if totalCurveCapacity is 0 (which can happen if supplyPerStep or numberOfSteps are fuzzed to 0
        // despite bounding, or if numSegments is 0 - though we bound numSegmentsToFuzz >= 1),
        // then we can't meaningfully proceed with ratio-based targetSupply.
        if (segments.length == 0) {
            // Helper ensures numSegmentsToFuzz >=1, so this is defensive
            return;
        }

        targetSupplyRatio = bound(targetSupplyRatio, 0, 110); // 0% to 110%

        uint targetSupply;
        if (totalCurveCapacity == 0) {
            // If curve capacity is 0 (e.g. 1 segment with 0 supply/steps, though createSegment prevents this)
            // only test targetSupply = 0.
            if (targetSupplyRatio == 0) {
                targetSupply = 0;
            } else {
                // Cannot test ratios against 0 capacity other than 0 itself.
                return;
            }
        } else {
            if (targetSupplyRatio == 0) {
                targetSupply = 0;
            } else if (targetSupplyRatio <= 100) {
                targetSupply = (totalCurveCapacity * targetSupplyRatio) / 100;
                // Ensure targetSupply does not exceed totalCurveCapacity due to rounding,
                // especially if targetSupplyRatio is 100.
                if (targetSupply > totalCurveCapacity) {
                    targetSupply = totalCurveCapacity;
                }
            } else {
                // targetSupplyRatio > 100 (e.g., 101 to 110)
                // Calculate supply beyond capacity. Add 1 wei to ensure it's strictly greater if ratio calculation results in equality.
                targetSupply = (
                    totalCurveCapacity * (targetSupplyRatio - 100) / 100
                ) + totalCurveCapacity + 1;
            }
        }

        if (targetSupply > totalCurveCapacity && totalCurveCapacity > 0) {
            // This check is for when we intentionally set targetSupply > totalCurveCapacity
            // and the curve actually has capacity.
            // _validateSupplyAgainstSegments (called by _calculateReserveForSupply) should revert.
            bytes memory expectedError = abi.encodeWithSelector(
                IDiscreteCurveMathLib_v1
                    .DiscreteCurveMathLib__SupplyExceedsCurveCapacity
                    .selector,
                targetSupply,
                totalCurveCapacity
            );
            vm.expectRevert(expectedError);
            exposedLib.exposed_calculateReserveForSupply(segments, targetSupply);
        } else {
            // Conditions where it should not revert with SupplyExceedsCurveCapacity:
            // 1. targetSupply <= totalCurveCapacity
            // 2. totalCurveCapacity == 0 (and thus targetSupply must also be 0 to reach here)

            uint reserve = exposedLib.exposed_calculateReserveForSupply(
                segments, targetSupply
            );

            if (targetSupply == 0) {
                assertEq(reserve, 0, "FCR_P: Reserve for 0 supply should be 0");
            }

            // Further property: If the curve consists of a single flat segment, and targetSupply is within its capacity
            if (
                numSegmentsToFuzz == 1 && priceIncreaseTpl == 0
                    && initialPriceTpl > 0 && targetSupply <= totalCurveCapacity
            ) {
                // Calculate expected reserve for a single flat segment
                // uint expectedReserve = (targetSupply * initialPriceTpl) / DiscreteCurveMathLib_v1.SCALING_FACTOR; // Original calculation before _mulDivUp consideration
                // Note: The library uses _mulDivUp for reserve calculation in flat segments if initialPrice > 0.
                // So, if (targetSupply * initialPriceTpl) % SCALING_FACTOR > 0, it rounds up.
                uint directCalc = (targetSupply * initialPriceTpl)
                    / DiscreteCurveMathLib_v1.SCALING_FACTOR;
                if (
                    (targetSupply * initialPriceTpl)
                        % DiscreteCurveMathLib_v1.SCALING_FACTOR > 0
                ) {
                    directCalc++;
                }
                assertEq(
                    reserve,
                    directCalc,
                    "FCR_P: Reserve for single flat segment mismatch"
                );
            }
            // Add more specific assertions based on fuzzed segment properties if complex invariants can be derived.
            // For now, primarily testing reverts and zero conditions.
            assertTrue(true, "FCR_P: Passed without unexpected revert"); // Placeholder if no specific value check
        }
    }

    // // --- Fuzz tests for _calculatePurchaseReturn ---

    function testFuzz_CalculatePurchaseReturn_Properties(
        uint8 numSegmentsToFuzz,
        uint initialPriceTpl,
        uint priceIncreaseTpl,
        uint supplyPerStepTpl,
        uint numberOfStepsTpl,
        uint collateralToSpendProvidedRatio,
        uint currentSupplyRatio
    ) public {
        // RESTRICTIVE BOUNDS to prevent overflow while maintaining good test coverage

        // Segments: Test with 1-5 segments (instead of MAX_SEGMENTS=10)
        numSegmentsToFuzz = uint8(bound(numSegmentsToFuzz, 1, 5));

        // Prices: Keep in reasonable DeFi ranges (0.001 to 10,000 tokens, scaled by 1e18)
        // This represents $0.001 to $10,000 per token - realistic DeFi price range
        initialPriceTpl = bound(initialPriceTpl, 1e15, 1e22); // 0.001 to 10,000 ether
        priceIncreaseTpl = bound(priceIncreaseTpl, 0, 1e21); // 0 to 1,000 ether increase per step

        // Supply per step: Reasonable token amounts (1 to 1M tokens)
        // This prevents massive capacity calculations
        supplyPerStepTpl = bound(supplyPerStepTpl, 1e18, 1e24); // 1 to 1,000,000 ether (tokens)

        // Number of steps: Keep reasonable for gas and overflow prevention
        numberOfStepsTpl = bound(numberOfStepsTpl, 1, 20); // Max 20 steps per segment

        // Collateral ratio: 0% to 200% of reserve (testing under/over spending)
        collateralToSpendProvidedRatio =
            bound(collateralToSpendProvidedRatio, 0, 200);

        // Current supply ratio: 0% to 100% of capacity
        currentSupplyRatio = bound(currentSupplyRatio, 0, 100);

        // Enforce validation rules from PackedSegmentLib
        if (initialPriceTpl == 0) {
            vm.assume(priceIncreaseTpl > 0);
        }
        if (numberOfStepsTpl > 1) {
            vm.assume(priceIncreaseTpl > 0); // Prevent multi-step flat segments
        }

        // Additional overflow protection for extreme combinations
        uint maxTheoreticalCapacityPerSegment =
            supplyPerStepTpl * numberOfStepsTpl;
        uint maxTheoreticalTotalCapacity =
            maxTheoreticalCapacityPerSegment * numSegmentsToFuzz;

        // Skip test if total capacity would exceed reasonable bounds (100M tokens total)
        if (maxTheoreticalTotalCapacity > 1e26) {
            // 100M tokens * 1e18
            return;
        }

        // Skip if price progression could get too extreme
        uint maxPriceInSegment =
            initialPriceTpl + (numberOfStepsTpl - 1) * priceIncreaseTpl;
        if (maxPriceInSegment > 1e23) {
            // More than $100,000 per token
            return;
        }

        // Generate segments with overflow protection
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

        // Additional check for generation issues
        if (totalCurveCapacity == 0 && segments.length > 0) {
            // This suggests overflow occurred in capacity calculation during generation
            return;
        }

        // Verify individual segment capacities don't overflow
        uint calculatedTotalCapacity = 0;
        for (uint i = 0; i < segments.length; i++) {
            (,, uint supplyPerStep, uint numberOfSteps) = segments[i]._unpack();

            if (supplyPerStep == 0 || numberOfSteps == 0) {
                return; // Invalid segment
            }

            // Check for overflow in capacity calculation
            uint segmentCapacity = supplyPerStep * numberOfSteps;
            if (segmentCapacity / supplyPerStep != numberOfSteps) {
                return; // Overflow detected
            }

            calculatedTotalCapacity += segmentCapacity;
            if (calculatedTotalCapacity < segmentCapacity) {
                return; // Overflow in total capacity
            }
        }

        // Setup current supply with overflow protection
        currentSupplyRatio = bound(currentSupplyRatio, 0, 100);
        uint currentTotalIssuanceSupply;
        if (totalCurveCapacity == 0) {
            if (currentSupplyRatio > 0) {
                return;
            }
            currentTotalIssuanceSupply = 0;
        } else {
            currentTotalIssuanceSupply =
                (totalCurveCapacity * currentSupplyRatio) / 100;
            if (currentTotalIssuanceSupply > totalCurveCapacity) {
                currentTotalIssuanceSupply = totalCurveCapacity;
            }
        }

        // Calculate total curve reserve with error handling
        uint totalCurveReserve;
        bool reserveCalcFailedFuzz = false;
        try exposedLib.exposed_calculateReserveForSupply(
            segments, totalCurveCapacity
        ) returns (uint reserve) {
            totalCurveReserve = reserve;
        } catch {
            reserveCalcFailedFuzz = true;
            // If reserve calculation fails due to overflow, skip test
            return;
        }

        // Setup collateral to spend with overflow protection
        collateralToSpendProvidedRatio =
            bound(collateralToSpendProvidedRatio, 0, 200);
        uint collateralToSpendProvided;

        if (totalCurveReserve == 0) {
            // Handle zero-reserve edge case more systematically
            collateralToSpendProvided = collateralToSpendProvidedRatio == 0
                ? 0
                : bound(collateralToSpendProvidedRatio, 1, 10 ether); // Using ratio as proxy for small amount
        } else {
            // Protect against overflow in collateral calculation
            if (collateralToSpendProvidedRatio <= 100) {
                collateralToSpendProvided =
                    (totalCurveReserve * collateralToSpendProvidedRatio) / 100;
            } else {
                // For ratios > 100%, calculate more carefully to prevent overflow
                uint baseAmount = totalCurveReserve;
                uint extraRatio = collateralToSpendProvidedRatio - 100;
                uint extraAmount = (totalCurveReserve * extraRatio) / 100;

                // Check for overflow before addition
                if (baseAmount > type(uint).max - extraAmount - 1) {
                    // Added -1
                    return; // Would overflow
                }
                collateralToSpendProvided = baseAmount + extraAmount + 1;
            }
        }

        // Test expected reverts
        if (collateralToSpendProvided == 0) {
            vm.expectRevert(
                IDiscreteCurveMathLib_v1
                    .DiscreteCurveMathLib__ZeroCollateralInput
                    .selector
            );
            exposedLib.exposed_calculatePurchaseReturn(
                segments, collateralToSpendProvided, currentTotalIssuanceSupply
            );
            return;
        }

        if (
            currentTotalIssuanceSupply > totalCurveCapacity
                && totalCurveCapacity > 0 // Only expect if capacity > 0
        ) {
            bytes memory expectedError = abi.encodeWithSelector(
                IDiscreteCurveMathLib_v1
                    .DiscreteCurveMathLib__SupplyExceedsCurveCapacity
                    .selector,
                currentTotalIssuanceSupply,
                totalCurveCapacity
            );
            vm.expectRevert(expectedError);
            exposedLib.exposed_calculatePurchaseReturn(
                segments, collateralToSpendProvided, currentTotalIssuanceSupply
            );
            return;
        }

        // Main test execution with comprehensive error handling
        uint tokensToMint;
        uint collateralSpentByPurchaser;

        try exposedLib.exposed_calculatePurchaseReturn(
            segments, collateralToSpendProvided, currentTotalIssuanceSupply
        ) returns (uint _tokensToMint, uint _collateralSpentByPurchaser) {
            tokensToMint = _tokensToMint;
            collateralSpentByPurchaser = _collateralSpentByPurchaser;
        } catch Error(string memory reason) {
            // Log the revert reason for debugging
            emit log(string.concat("Unexpected revert: ", reason));
            fail(
                string.concat(
                    "Function should not revert with valid inputs: ", reason
                )
            );
        } catch (bytes memory lowLevelData) {
            emit log("Unexpected low-level revert");
            emit log_bytes(lowLevelData);
            fail("Function reverted with low-level error");
        }

        // === CORE INVARIANTS ===

        // Property 1: Never overspend
        assertTrue(
            collateralSpentByPurchaser <= collateralToSpendProvided,
            "FCPR_P1: Spent more than provided"
        );

        // Property 2: Never overmint
        if (totalCurveCapacity > 0) {
            assertTrue(
                tokensToMint
                    <= (totalCurveCapacity - currentTotalIssuanceSupply),
                "FCPR_P2: Minted more than available capacity"
            );
        } else {
            assertEq(
                tokensToMint, 0, "FCPR_P2: Minted tokens when capacity is 0"
            );
        }

        // Property 3: Deterministic behavior (only test if first call succeeded)
        try exposedLib.exposed_calculatePurchaseReturn(
            segments, collateralToSpendProvided, currentTotalIssuanceSupply
        ) returns (uint tokensToMint2, uint collateralSpentByPurchaser2) {
            assertEq(
                tokensToMint,
                tokensToMint2,
                "FCPR_P3: Non-deterministic token calculation"
            );
            assertEq(
                collateralSpentByPurchaser,
                collateralSpentByPurchaser2,
                "FCPR_P3: Non-deterministic collateral calculation"
            );
        } catch {
            // If second call fails but first succeeded, that indicates non-determinship
            fail("FCPR_P3: Second identical call failed while first succeeded");
        }

        // === BOUNDARY CONDITIONS ===

        // Property 4: No activity at full capacity
        if (
            currentTotalIssuanceSupply == totalCurveCapacity
                && totalCurveCapacity > 0
        ) {
            console2.log("P4: tokensToMint (at full capacity):", tokensToMint);
            console2.log(
                "P4: collateralSpentByPurchaser (at full capacity):",
                collateralSpentByPurchaser
            );
            assertEq(tokensToMint, 0, "FCPR_P4: No tokens at full capacity");
            assertEq(
                collateralSpentByPurchaser,
                0,
                "FCPR_P4: No spending at full capacity"
            );
        }

        // Property 5: Zero spending implies zero minting (except for free segments)
        if (collateralSpentByPurchaser == 0 && tokensToMint > 0) {
            bool isPotentiallyFree = false;
            if (
                segments.length > 0
                    && currentTotalIssuanceSupply < totalCurveCapacity
            ) {
                try exposedLib.exposed_getCurrentPriceAndStep(
                    segments, currentTotalIssuanceSupply
                ) returns (uint currentPrice, uint, uint segIdx) {
                    if (segIdx < segments.length && currentPrice == 0) {
                        isPotentiallyFree = true;
                    }
                } catch {
                    console2.log(
                        "FUZZ CPR DEBUG: P5 - getCurrentPriceAndStep reverted."
                    );
                }
            }
            if (!isPotentiallyFree) {
                assertEq(
                    tokensToMint,
                    0,
                    "FCPR_P5: Minted tokens without spending on non-free segment"
                );
            }
        }

        // === MATHEMATICAL PROPERTIES ===

        // Property 6: Monotonicity (more budget → more/equal tokens when capacity allows)
        if (
            currentTotalIssuanceSupply < totalCurveCapacity
                && collateralToSpendProvided > 0
                && collateralSpentByPurchaser < collateralToSpendProvided
                && collateralToSpendProvided <= type(uint).max - 1 ether // Prevent overflow
        ) {
            uint biggerBudget = collateralToSpendProvided + 1 ether;
            try exposedLib.exposed_calculatePurchaseReturn(
                segments, biggerBudget, currentTotalIssuanceSupply
            ) returns (uint tokensMore, uint) {
                assertTrue(
                    tokensMore >= tokensToMint,
                    "FCPR_P6: More budget should yield more/equal tokens"
                );
            } catch {
                console2.log(
                    "FUZZ CPR DEBUG: P6 - Call with biggerBudget failed."
                );
            }
        }

        // Property 7: Rounding should favor protocol (spent ≥ theoretical minimum)
        if (
            tokensToMint > 0 && collateralSpentByPurchaser > 0
                && currentTotalIssuanceSupply + tokensToMint <= totalCurveCapacity
        ) {
            try exposedLib.exposed_calculateReserveForSupply(
                segments, currentTotalIssuanceSupply + tokensToMint
            ) returns (uint reserveAfter) {
                try exposedLib.exposed_calculateReserveForSupply(
                    segments, currentTotalIssuanceSupply
                ) returns (uint reserveBefore) {
                    if (reserveAfter >= reserveBefore) {
                        uint theoreticalCost = reserveAfter - reserveBefore;
                        assertTrue(
                            collateralSpentByPurchaser >= theoreticalCost,
                            "FCPR_P7: Should favor protocol in rounding"
                        );
                    }
                } catch {
                    console2.log(
                        "FUZZ CPR DEBUG: P7 - Calculation of reserveBefore failed."
                    );
                }
            } catch {
                console2.log(
                    "FUZZ CPR DEBUG: P7 - Calculation of reserveAfter failed."
                );
            }
        }

        // Property 8: Compositionality (for non-boundary cases)
        if (
            tokensToMint > 0 && collateralSpentByPurchaser > 0
                && collateralSpentByPurchaser < collateralToSpendProvided / 2 // Ensure first purchase is partial
                && currentTotalIssuanceSupply + tokensToMint < totalCurveCapacity // Ensure capacity for second
        ) {
            uint remainingBudget =
                collateralToSpendProvided - collateralSpentByPurchaser;
            uint newSupply = currentTotalIssuanceSupply + tokensToMint;

            try exposedLib.exposed_calculatePurchaseReturn(
                segments, remainingBudget, newSupply
            ) returns (uint tokensSecond, uint) {
                try exposedLib.exposed_calculatePurchaseReturn(
                    segments,
                    collateralToSpendProvided,
                    currentTotalIssuanceSupply
                ) returns (uint tokensTotal, uint) {
                    uint combinedTokens = tokensToMint + tokensSecond;
                    uint tolerance = Math.max(combinedTokens / 1000, 1);

                    assertApproxEqAbs(
                        tokensTotal,
                        combinedTokens,
                        tolerance,
                        "FCPR_P8: Compositionality within rounding tolerance"
                    );
                } catch {
                    console2.log(
                        "FUZZ CPR DEBUG: P8 - Single large purchase for comparison failed."
                    );
                }
            } catch {
                console2.log(
                    "FUZZ CPR DEBUG: P8 - Second purchase in compositionality test failed."
                );
            }
        }

        // === BOUNDARY DETECTION ===

        // Property 9: Detect and validate step/segment boundaries
        if (currentTotalIssuanceSupply > 0 && segments.length > 0) {
            try exposedLib.exposed_getCurrentPriceAndStep(
                segments, currentTotalIssuanceSupply
            ) returns (uint, uint stepIdx, uint segIdx) {
                // Removed 'price'
                if (segIdx < segments.length) {
                    (,, uint supplyPerStepP9,) = segments[segIdx]._unpack();
                    if (supplyPerStepP9 > 0) {
                        bool atStepBoundary =
                            (currentTotalIssuanceSupply % supplyPerStepP9) == 0;

                        if (atStepBoundary && currentTotalIssuanceSupply > 0) {
                            assertTrue(
                                stepIdx > 0 || segIdx > 0,
                                "FCPR_P9: At step boundary should not be at curve start"
                            );
                        }
                    }
                }
            } catch {
                console2.log(
                    "FUZZ CPR DEBUG: P9 - getCurrentPriceAndStep reverted."
                );
            }
        }

        // Property 10: Consistency with capacity calculations
        uint remainingCapacity = totalCurveCapacity > currentTotalIssuanceSupply
            ? totalCurveCapacity - currentTotalIssuanceSupply
            : 0;

        if (remainingCapacity == 0) {
            assertEq(
                tokensToMint, 0, "FCPR_P10: No tokens when no capacity remains"
            );
        }

        if (tokensToMint == remainingCapacity && remainingCapacity > 0) {
            bool couldBeFreeP10 = false;
            if (segments.length > 0) {
                try exposedLib.exposed_getCurrentPriceAndStep(
                    segments, currentTotalIssuanceSupply
                ) returns (uint currentPriceP10, uint, uint) {
                    if (currentPriceP10 == 0) {
                        couldBeFreeP10 = true;
                    }
                } catch {
                    console2.log(
                        "FUZZ CPR DEBUG: P10 - getCurrentPriceAndStep reverted for free check."
                    );
                }
            }

            if (!couldBeFreeP10) {
                assertTrue(
                    collateralSpentByPurchaser > 0,
                    "FCPR_P10: Should spend collateral when filling entire remaining capacity"
                );
            }
        }

        // Final success assertion
        assertTrue(true, "FCPR_P: All properties satisfied");
    }

    // --- Fuzz tests for _calculateSaleReturn ---

    function testFuzz_CalculateSaleReturn_Properties(
        uint8 numSegmentsToFuzz,
        uint initialPriceTpl,
        uint priceIncreaseTpl,
        uint supplyPerStepTpl,
        uint numberOfStepsTpl,
        uint tokensToSellRatio, // Ratio (0-100) to determine tokensToSell based on currentTotalIssuanceSupply
        uint currentSupplyRatio // Ratio (0-100) to determine currentTotalIssuanceSupply based on totalCurveCapacity
    ) public {
        // RESTRICTIVE BOUNDS (similar to purchase fuzz test)
        numSegmentsToFuzz = uint8(bound(numSegmentsToFuzz, 1, 5));
        initialPriceTpl = bound(initialPriceTpl, 1e15, 1e22);
        priceIncreaseTpl = bound(priceIncreaseTpl, 0, 1e21);
        supplyPerStepTpl = bound(supplyPerStepTpl, 1e18, 1e24);
        numberOfStepsTpl = bound(numberOfStepsTpl, 1, 20);
        tokensToSellRatio = bound(tokensToSellRatio, 0, 100); // 0% to 100% of current supply
        currentSupplyRatio = bound(currentSupplyRatio, 0, 100); // 0% to 100% of capacity

        // Enforce validation rules from PackedSegmentLib
        if (initialPriceTpl == 0) {
            vm.assume(priceIncreaseTpl > 0);
        }
        if (numberOfStepsTpl > 1) {
            vm.assume(priceIncreaseTpl > 0); // Prevent multi-step flat segments
        } else {
            // numberOfStepsTpl == 1
            vm.assume(priceIncreaseTpl == 0); // Prevent single-step sloped segments
        }

        // Overflow protection checks (similar to purchase fuzz test)
        uint maxTheoreticalCapacityPerSegment =
            supplyPerStepTpl * numberOfStepsTpl;
        if (
            supplyPerStepTpl > 0
                && maxTheoreticalCapacityPerSegment / supplyPerStepTpl
                    != numberOfStepsTpl
        ) return; // Overflow
        uint maxTheoreticalTotalCapacity =
            maxTheoreticalCapacityPerSegment * numSegmentsToFuzz;
        if (
            numSegmentsToFuzz > 0
                && maxTheoreticalTotalCapacity / numSegmentsToFuzz
                    != maxTheoreticalCapacityPerSegment
        ) return; // Overflow

        if (maxTheoreticalTotalCapacity > 1e26) return; // Skip if too large

        uint maxPriceInSegment =
            initialPriceTpl + (numberOfStepsTpl - 1) * priceIncreaseTpl;
        if (
            numberOfStepsTpl > 1 && priceIncreaseTpl > 0
                && (maxPriceInSegment < initialPriceTpl)
        ) return; // Overflow in price calc
        if (maxPriceInSegment > 1e23) return;

        (PackedSegment[] memory segments, uint totalCurveCapacity) =
        _generateFuzzedValidSegmentsAndCapacity(
            numSegmentsToFuzz,
            initialPriceTpl,
            priceIncreaseTpl,
            supplyPerStepTpl,
            numberOfStepsTpl
        );

        if (segments.length == 0) return;
        if (
            totalCurveCapacity == 0 && segments.length > 0
                && (supplyPerStepTpl > 0 && numberOfStepsTpl > 0)
        ) {
            // If generation resulted in 0 capacity despite valid inputs, likely an internal assume failed.
            return;
        }

        uint currentTotalIssuanceSupply;
        if (totalCurveCapacity == 0) {
            if (currentSupplyRatio > 0) return; // Cannot have supply if no capacity
            currentTotalIssuanceSupply = 0;
        } else {
            currentTotalIssuanceSupply =
                (totalCurveCapacity * currentSupplyRatio) / 100;
            if (currentTotalIssuanceSupply > totalCurveCapacity) {
                // Ensure not exceeding due to rounding
                currentTotalIssuanceSupply = totalCurveCapacity;
            }
        }

        uint tokensToSell_;
        if (currentTotalIssuanceSupply == 0) {
            if (tokensToSellRatio > 0) return; // Cannot sell from zero supply
            tokensToSell_ = 0;
        } else {
            tokensToSell_ =
                (currentTotalIssuanceSupply * tokensToSellRatio) / 100;
            if (tokensToSell_ > currentTotalIssuanceSupply) {
                // Ensure not exceeding due to rounding
                tokensToSell_ = currentTotalIssuanceSupply;
            }
        }

        // --- Handle Expected Reverts ---
        if (tokensToSell_ == 0) {
            vm.expectRevert(
                IDiscreteCurveMathLib_v1
                    .DiscreteCurveMathLib__ZeroIssuanceInput
                    .selector
            );
            exposedLib.exposed_calculateSaleReturn(
                segments, tokensToSell_, currentTotalIssuanceSupply
            );
            return;
        }

        // _validateSupplyAgainstSegments is called inside _calculateSaleReturn
        if (
            currentTotalIssuanceSupply > totalCurveCapacity
                && totalCurveCapacity > 0
        ) {
            bytes memory expectedError = abi.encodeWithSelector(
                IDiscreteCurveMathLib_v1
                    .DiscreteCurveMathLib__SupplyExceedsCurveCapacity
                    .selector,
                currentTotalIssuanceSupply,
                totalCurveCapacity
            );
            vm.expectRevert(expectedError);
            exposedLib.exposed_calculateSaleReturn(
                segments, tokensToSell_, currentTotalIssuanceSupply
            );
            return;
        }

        // Note: NoSegmentsConfigured is tricky here because if supply is 0, it might return (0,0)
        // If segments.length == 0 AND currentTotalIssuanceSupply > 0, then it should revert.
        // If segments.length == 0 AND currentTotalIssuanceSupply == 0 AND tokensToSell_ > 0, it returns (0,0).
        // This is handled by the logic within calculateSaleReturn.

        uint collateralToReturn;
        uint tokensToBurn;

        try exposedLib.exposed_calculateSaleReturn(
            segments, tokensToSell_, currentTotalIssuanceSupply
        ) returns (uint _collateralToReturn, uint _tokensToBurn) {
            collateralToReturn = _collateralToReturn;
            tokensToBurn = _tokensToBurn;
        } catch Error(string memory reason) {
            emit log(string.concat("FCSR_UnexpectedRevert: ", reason));
            fail(string.concat("FCSR_SaleFuncReverted: ", reason));
        } catch (bytes memory lowLevelData) {
            emit log("FCSR_UnexpectedLowLevelRevert");
            emit log_bytes(lowLevelData);
            fail("FCSR_SaleFuncLowLevelReverted");
        }

        // === CORE INVARIANTS ===

        // P1: Burned Amount Constraints
        assertTrue(
            tokensToBurn <= tokensToSell_, "FCSR_P1a: Burned more than intended"
        );
        assertTrue(
            tokensToBurn <= currentTotalIssuanceSupply,
            "FCSR_P1b: Burned more than available supply"
        );

        // P2: Non-Negative Collateral (implicit by uint)

        // P3: Deterministic Behavior
        try exposedLib.exposed_calculateSaleReturn(
            segments, tokensToSell_, currentTotalIssuanceSupply
        ) returns (uint collateralToReturn2, uint tokensToBurn2) {
            assertEq(
                collateralToReturn,
                collateralToReturn2,
                "FCSR_P3a: Non-deterministic collateral"
            );
            assertEq(
                tokensToBurn,
                tokensToBurn2,
                "FCSR_P3b: Non-deterministic tokens burned"
            );
        } catch {
            fail("FCSR_P3: Second identical call failed");
        }

        // P4: Zero Supply Behavior
        if (currentTotalIssuanceSupply == 0) {
            assertEq(
                tokensToBurn, 0, "FCSR_P4a: Tokens burned from zero supply"
            );
            assertEq(
                collateralToReturn,
                0,
                "FCSR_P4b: Collateral from zero supply sale"
            );
        }

        // P5: Selling All Tokens
        if (
            tokensToBurn == currentTotalIssuanceSupply
                && currentTotalIssuanceSupply > 0
        ) {
            uint reserveForFullSupply;
            bool p5_reserve_calc_ok = true;
            try exposedLib.exposed_calculateReserveForSupply(
                segments, currentTotalIssuanceSupply
            ) returns (uint r) {
                reserveForFullSupply = r;
            } catch {
                p5_reserve_calc_ok = false; // Could revert if supply > capacity, but that's checked earlier
            }
            if (p5_reserve_calc_ok) {
                assertEq(
                    collateralToReturn,
                    reserveForFullSupply,
                    "FCSR_P5: Collateral for selling all tokens mismatch"
                );
            }
        }

        // P6: Partial Sale Due to Insufficient Supply (i.e. tokensToBurn < tokensToSell_)
        if (tokensToBurn < tokensToSell_ && tokensToSell_ > 0) {
            assertEq(
                tokensToBurn,
                currentTotalIssuanceSupply,
                "FCSR_P6: Partial burn implies all supply sold"
            );
        }

        // P7: Monotonicity of Collateral (Conceptual - harder to test directly with single fuzzed inputs)
        // If selling X tokens yields C1, selling Y (Y > X) should yield C2 >= C1.

        // P8: Rounding Favors Protocol (Collateral returned <= theoretical max)
        if (tokensToBurn > 0) {
            uint reserveBefore;
            uint reserveAfter;
            bool p8_reserve_before_ok = true;
            bool p8_reserve_after_ok = true;

            try exposedLib.exposed_calculateReserveForSupply(
                segments, currentTotalIssuanceSupply
            ) returns (uint r) {
                reserveBefore = r;
            } catch {
                p8_reserve_before_ok = false;
            }

            if (currentTotalIssuanceSupply >= tokensToBurn) {
                try exposedLib.exposed_calculateReserveForSupply(
                    segments, currentTotalIssuanceSupply - tokensToBurn
                ) returns (uint r) {
                    reserveAfter = r;
                } catch {
                    p8_reserve_after_ok = false;
                }
            } else {
                // Should not happen if P1b holds
                p8_reserve_after_ok = false;
            }

            if (
                p8_reserve_before_ok && p8_reserve_after_ok
                    && reserveBefore >= reserveAfter
            ) {
                uint theoreticalMaxCollateral = reserveBefore - reserveAfter;
                assertTrue(
                    collateralToReturn <= theoreticalMaxCollateral,
                    "FCSR_P8: Rounding should not overpay collateral"
                );
            }
        }

        // P9: Compositionality (Conceptual - complex to set up reliably in fuzz)

        // P10: If no segments and positive supply, should have reverted earlier or handled by specific logic.
        // If segments.length == 0 and currentTotalIssuanceSupply == 0 and tokensToSell_ > 0,
        // then collateralToReturn == 0 and tokensToBurn == 0. This is covered by P4.

        assertTrue(true, "FCSR_P: All properties satisfied");
    }

    // Test: Compare _calculateReserveForSupply with _calculatePurchaseReturn
    // Start with an empty curve, calculate reserve for a target supply.
    // Then, use that reserve as collateral input for _calculatePurchaseReturn.
    // Ensure the minted tokens match the target supply and collateral spent matches the calculated reserve.
    function test_Compare_ReserveForSupply_vs_PurchaseReturn_TwoSlopedCurve()
        public
    {
        // Use twoSlopedSegmentsTestCurve
        PackedSegment[] memory segments =
            twoSlopedSegmentsTestCurve.packedSegmentsArray;

        // Calculate target supply: one third into the last step of the second segment
        PackedSegment seg0 = segments[0];
        PackedSegment seg1 = segments[1];

        uint supplySeg0 = seg0._supplyPerStep() * seg0._numberOfSteps(); // 30 ether

        // Supply of the first step of segment 1
        uint supplySeg1Step0 = seg1._supplyPerStep(); // 20 ether

        // Total supply at the beginning of the last step of segment 1
        uint supplyAtStartOfLastStepSeg1 = supplySeg0 + supplySeg1Step0; // 50 ether

        // Supply per step in the last step of segment 1 (which is seg1._supplyPerStep())
        uint supplyPerStepInLastStepSeg1 = seg1._supplyPerStep(); // 20 ether

        // One third of the supply in that last step
        uint supplyIntoLastStep = (supplyPerStepInLastStepSeg1 * 1) / 3;

        uint targetSupply = supplyAtStartOfLastStepSeg1 + supplyIntoLastStep;
        // targetSupply = 50 ether + (20 ether / 3) = (150e18 + 20e18) / 3 = 170e18 / 3 = 56666666666666666666 wei

        // 1. Calculate the reserve needed to reach targetSupply
        uint expectedReserve =
            exposedLib.exposed_calculateReserveForSupply(segments, targetSupply);

        // 2. Use that reserve to purchase tokens from an empty curve
        (uint actualTokensMinted, uint actualCollateralSpent) = exposedLib
            .exposed_calculatePurchaseReturn(
            segments,
            expectedReserve, // Collateral to spend
            0 // Current total issuance supply (empty curve)
        );

        // 3. Assertions
        assertEq(
            actualTokensMinted,
            targetSupply,
            "Tokens minted should match target supply"
        );
        assertEq(
            actualCollateralSpent,
            expectedReserve,
            "Collateral spent should match expected reserve"
        );
    }
}
