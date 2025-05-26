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

    // Default curve configuration
    PackedSegment[] internal defaultSegments;
    
    // Parameters for default curve segments (for clarity in setUp and tests)
    uint256 internal defaultSeg0_initialPrice;
    uint256 internal defaultSeg0_priceIncrease;
    uint256 internal defaultSeg0_supplyPerStep;
    uint256 internal defaultSeg0_numberOfSteps;
    uint256 internal defaultSeg0_capacity;
    uint256 internal defaultSeg0_reserve;


    uint256 internal defaultSeg1_initialPrice;
    uint256 internal defaultSeg1_priceIncrease;
    uint256 internal defaultSeg1_supplyPerStep;
    uint256 internal defaultSeg1_numberOfSteps;
    uint256 internal defaultSeg1_capacity;
    uint256 internal defaultSeg1_reserve;

    uint256 internal defaultCurve_totalCapacity;
    uint256 internal defaultCurve_totalReserve;


    function setUp() public virtual {
        exposedLib = new DiscreteCurveMathLibV1_Exposed();

        // Initialize default curve parameters
        // Segment 0 (Sloped)
        defaultSeg0_initialPrice = 1 ether;
        defaultSeg0_priceIncrease = 0.1 ether;
        defaultSeg0_supplyPerStep = 10 ether;
        defaultSeg0_numberOfSteps = 3; // Prices: 1.0, 1.1, 1.2
        defaultSeg0_capacity = defaultSeg0_supplyPerStep * defaultSeg0_numberOfSteps; // 30 ether
        defaultSeg0_reserve = 0;
        defaultSeg0_reserve += (defaultSeg0_supplyPerStep * (defaultSeg0_initialPrice + 0 * defaultSeg0_priceIncrease)) / DiscreteCurveMathLib_v1.SCALING_FACTOR; // 10
        defaultSeg0_reserve += (defaultSeg0_supplyPerStep * (defaultSeg0_initialPrice + 1 * defaultSeg0_priceIncrease)) / DiscreteCurveMathLib_v1.SCALING_FACTOR; // 11
        defaultSeg0_reserve += (defaultSeg0_supplyPerStep * (defaultSeg0_initialPrice + 2 * defaultSeg0_priceIncrease)) / DiscreteCurveMathLib_v1.SCALING_FACTOR; // 12
        // Total reserve for seg0 = 10 + 11 + 12 = 33 ether

        // Segment 1 (Sloped)
        defaultSeg1_initialPrice = 1.5 ether; 
        defaultSeg1_priceIncrease = 0.05 ether;
        defaultSeg1_supplyPerStep = 20 ether;
        defaultSeg1_numberOfSteps = 2; // Prices: 1.5, 1.55
        defaultSeg1_capacity = defaultSeg1_supplyPerStep * defaultSeg1_numberOfSteps; // 40 ether
        defaultSeg1_reserve = 0;
        defaultSeg1_reserve += (defaultSeg1_supplyPerStep * (defaultSeg1_initialPrice + 0 * defaultSeg1_priceIncrease)) / DiscreteCurveMathLib_v1.SCALING_FACTOR; // 30
        defaultSeg1_reserve += (defaultSeg1_supplyPerStep * (defaultSeg1_initialPrice + 1 * defaultSeg1_priceIncrease)) / DiscreteCurveMathLib_v1.SCALING_FACTOR; // 31
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
        // Uses the `defaultSegments` initialized in setUp()
        // Default Seg0: initialPrice 1, increase 0.1, supplyPerStep 10, steps 3. Capacity 30.
        // Default Seg1: initialPrice 1.5, increase 0.05, supplyPerStep 20, steps 2. Capacity 40.

        // Target supply: 40 ether
        // Segment 0 (default) provides 30 ether (10*3).
        // Remaining needed: 40 - 30 = 10 ether from Segment 1.
        // Segment 1 (default): supplyPerStep = 20 ether.
        //   Step 0 of seg1 covers supply 0-20 (total 30-50 for the curve). Price 1.5 ether.
        //   Target 10 ether from Segment 1 falls into its step 0.
        uint256 targetSupply = defaultSeg0_capacity + 10 ether; // 30 + 10 = 40 ether

        DiscreteCurveMathLib_v1.CurvePosition memory pos = exposedLib.findPositionForSupplyPublic(defaultSegments, targetSupply);

        assertEq(pos.segmentIndex, 1, "Segment index mismatch");
        // Supply from seg0 = 30. Supply needed from seg1 = 10.
        // Step 0 of seg1 covers supply 0-20 (relative to seg1 start).
        // 10 supply needed from seg1 falls into step 0 (0-indexed).
        // supplyNeededFromThisSegment (seg1) = 10. stepIndex = 10 / 20 (defaultSeg1_supplyPerStep) = 0.
        assertEq(pos.stepIndexWithinSegment, 0, "Step index mismatch for segment 1");
        
        uint256 expectedPrice = defaultSeg1_initialPrice + (0 * defaultSeg1_priceIncrease); // Price at step 0 of segment 1
        assertEq(pos.priceAtCurrentStep, expectedPrice, "Price mismatch for segment 1");
        assertEq(pos.supplyCoveredUpToThisPosition, targetSupply, "Supply covered mismatch");
    }

    function test_FindPositionForSupply_TargetBeyondCapacity() public {
        // Uses defaultSegments
        // defaultCurve_totalCapacity = 70 ether
        uint256 targetSupply = defaultCurve_totalCapacity + 10 ether; // Beyond capacity (70 + 10 = 80)

        DiscreteCurveMathLib_v1.CurvePosition memory pos = exposedLib.findPositionForSupplyPublic(defaultSegments, targetSupply);

        assertEq(pos.segmentIndex, 1, "Segment index should be last segment (1)");
        assertEq(pos.stepIndexWithinSegment, defaultSeg1_numberOfSteps - 1, "Step index should be last step of last segment");
        
        uint256 expectedPriceAtEndOfCurve = defaultSeg1_initialPrice + ((defaultSeg1_numberOfSteps - 1) * defaultSeg1_priceIncrease);
        assertEq(pos.priceAtCurrentStep, expectedPriceAtEndOfCurve, "Price should be at end of last segment");
        assertEq(pos.supplyCoveredUpToThisPosition, defaultCurve_totalCapacity, "Supply covered should be total curve capacity");
    }

    function test_FindPositionForSupply_TargetSupplyZero() public {
        // Using only the first segment of defaultSegments for simplicity
        PackedSegment[] memory segments = new PackedSegment[](1);
        segments[0] = defaultSegments[0];

        uint256 targetSupply = 0 ether;

        DiscreteCurveMathLib_v1.CurvePosition memory pos = exposedLib.findPositionForSupplyPublic(segments, targetSupply);

        assertEq(pos.segmentIndex, 0, "Segment index should be 0 for target supply 0");
        assertEq(pos.stepIndexWithinSegment, 0, "Step index should be 0 for target supply 0");
        assertEq(pos.priceAtCurrentStep, defaultSeg0_initialPrice, "Price should be initial price of first segment for target supply 0");
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
        // Using defaultSegments
        uint256 currentSupply = 0 ether;
        (uint256 price, uint256 stepIdx, uint256 segmentIdx) = exposedLib.getCurrentPriceAndStepPublic(defaultSegments, currentSupply);

        assertEq(segmentIdx, 0, "Segment index should be 0 for current supply 0");
        assertEq(stepIdx, 0, "Step index should be 0 for current supply 0");
        assertEq(price, defaultSeg0_initialPrice, "Price should be initial price of first segment for current supply 0");
    }

    function test_GetCurrentPriceAndStep_WithinStep_NotBoundary() public {
        // Using defaultSegments
        // Default Seg0: initialPrice 1, increase 0.1, supplyPerStep 10, steps 3.
        // Step 0: 0-10 supply, price 1.0
        // Step 1: 10-20 supply, price 1.1.
        uint256 currentSupply = 15 ether; // Falls in step 1 of segment 0
        (uint256 price, uint256 stepIdx, uint256 segmentIdx) = exposedLib.getCurrentPriceAndStepPublic(defaultSegments, currentSupply);

        assertEq(segmentIdx, 0, "Segment index mismatch");
        assertEq(stepIdx, 1, "Step index mismatch - should be step 1"); 
        uint256 expectedPrice = defaultSeg0_initialPrice + (1 * defaultSeg0_priceIncrease); // Price of step 1
        assertEq(price, expectedPrice, "Price mismatch - should be price of step 1");
    }

    function test_GetCurrentPriceAndStep_EndOfStep_NotEndOfSegment() public {
        // Using defaultSegments
        // Default Seg0: initialPrice 1, increase 0.1, supplyPerStep 10, steps 3.
        // Current supply is 10 ether, exactly at the end of step 0 of segment 0.
        // Price should be for step 1 of segment 0.
        uint256 currentSupply = defaultSeg0_supplyPerStep; // 10 ether
        (uint256 price, uint256 stepIdx, uint256 segmentIdx) = exposedLib.getCurrentPriceAndStepPublic(defaultSegments, currentSupply);

        assertEq(segmentIdx, 0, "Segment index mismatch");
        assertEq(stepIdx, 1, "Step index should advance to 1"); 
        uint256 expectedPrice = defaultSeg0_initialPrice + (1 * defaultSeg0_priceIncrease); // Price of step 1 (1.1)
        assertEq(price, expectedPrice, "Price should be for step 1");
    }

    function test_GetCurrentPriceAndStep_EndOfSegment_NotLastSegment() public {
        // Using defaultSegments
        // Current supply is 30 ether, exactly at the end of segment 0 (defaultSeg0_capacity).
        // Price/step should be for the start of segment 1.
        uint256 currentSupply = defaultSeg0_capacity; 
        (uint256 price, uint256 stepIdx, uint256 segmentIdx) = exposedLib.getCurrentPriceAndStepPublic(defaultSegments, currentSupply);

        assertEq(segmentIdx, 1, "Segment index should advance to 1");
        assertEq(stepIdx, 0, "Step index should be 0 of segment 1"); 
        assertEq(price, defaultSeg1_initialPrice, "Price should be initial price of segment 1");
    }

    function test_GetCurrentPriceAndStep_EndOfLastSegment() public {
        // Using defaultSegments
        // Current supply is total capacity of the curve (70 ether).
        uint256 currentSupply = defaultCurve_totalCapacity;

        (uint256 price, uint256 stepIdx, uint256 segmentIdx) = exposedLib.getCurrentPriceAndStepPublic(defaultSegments, currentSupply);

        assertEq(segmentIdx, 1, "Segment index should be last segment (1)");
        assertEq(stepIdx, defaultSeg1_numberOfSteps - 1, "Step index should be last step of last segment");
        uint256 expectedPrice = defaultSeg1_initialPrice + ((defaultSeg1_numberOfSteps - 1) * defaultSeg1_priceIncrease);
        assertEq(price, expectedPrice, "Price should be price of last step of last segment");
    }

    function test_GetCurrentPriceAndStep_SupplyBeyondCapacity_Reverts() public {
        // Using a single segment for simplicity, but based on defaultSeg0
        PackedSegment[] memory segments = new PackedSegment[](1);
        segments[0] = defaultSegments[0]; // Capacity 30 ether
        
        uint256 currentSupply = defaultSeg0_capacity + 5 ether; // Beyond capacity of this single segment array

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
        // Using defaultSegments
        uint256 reserve = exposedLib.calculateReserveForSupplyPublic(defaultSegments, 0);
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
        // Using only the first segment of defaultSegments (which is sloped)
        PackedSegment[] memory segments = new PackedSegment[](1);
        segments[0] = defaultSegments[0]; // initialPrice 1, increase 0.1, supplyPerStep 10, steps 3

        // Target 2 steps (20 ether supply) from defaultSeg0
        // Step 0: price 1.0, supply 10. Cost = 10 * 1.0 = 10
        // Step 1: price 1.1, supply 10. Cost = 10 * 1.1 = 11
        // Total reserve = (10 + 11) = 21 ether (scaled)
        uint256 targetSupply = 2 * defaultSeg0_supplyPerStep; // 20 ether 
        
        uint256 expectedReserve = 0;
        expectedReserve += (defaultSeg0_supplyPerStep * (defaultSeg0_initialPrice + 0 * defaultSeg0_priceIncrease)) / DiscreteCurveMathLib_v1.SCALING_FACTOR;
        expectedReserve += (defaultSeg0_supplyPerStep * (defaultSeg0_initialPrice + 1 * defaultSeg0_priceIncrease)) / DiscreteCurveMathLib_v1.SCALING_FACTOR;
        // expectedReserve = 10 + 11 = 21 ether

        uint256 reserve = exposedLib.calculateReserveForSupplyPublic(segments, targetSupply);
        assertEq(reserve, expectedReserve, "Reserve for sloped segment partial fill mismatch");
    }

    // --- Tests for calculatePurchaseReturn ---

    function test_CalculatePurchaseReturn_SingleFlatSegment_PartialBuy_AffordSome() public {
        PackedSegment[] memory segments = new PackedSegment[](1);
        uint256 initialPrice = 2 ether;
        uint256 priceIncrease = 0; // Flat segment
        uint256 supplyPerStep = 10 ether;
        uint256 numberOfSteps = 5; // Total capacity 50 ether
        segments[0] = DiscreteCurveMathLib_v1.createSegment(initialPrice, priceIncrease, supplyPerStep, numberOfSteps);

        uint256 currentSupply = 0 ether;
        uint256 collateralIn = 45 ether; // Enough for 2 steps (40 ether cost), but not 3 (60 ether cost)

        // New logic: 2 full steps (20 issuance, 40 cost) + partial step (2.5 issuance, 5 cost)
        uint256 expectedIssuanceOut = 22500000000000000000; // 22.5 ether
        uint256 expectedCollateralSpent = 45000000000000000000; // 45 ether

        (uint256 issuanceOut, uint256 collateralSpent) = exposedLib.calculatePurchaseReturnPublic(
            segments,
            collateralIn,
            currentSupply
        );

        assertEq(issuanceOut, expectedIssuanceOut, "Flat partial buy: issuanceOut mismatch");
        assertEq(collateralSpent, expectedCollateralSpent, "Flat partial buy: collateralSpent mismatch");
    }

    function test_CalculatePurchaseReturn_SingleFlatSegment_PartialBuy_AffordAllInStep() public {
        PackedSegment[] memory segments = new PackedSegment[](1);
        uint256 initialPrice = 2 ether;
        uint256 priceIncrease = 0; // Flat segment
        uint256 supplyPerStep = 10 ether;
        uint256 numberOfSteps = 5; // Total capacity 50 ether
        segments[0] = DiscreteCurveMathLib_v1.createSegment(initialPrice, priceIncrease, supplyPerStep, numberOfSteps);

        uint256 currentSupply = 0 ether;
        // Collateral to buy exactly 2.5 steps (25 ether issuance) would be 50 ether.
        uint256 collateralIn = 50 ether; 

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
        uint256 expectedIssuanceOut = 25000000000000000000; // 25 ether
        uint256 expectedCollateralSpent = 50000000000000000000; // 50 ether

        (uint256 issuanceOut, uint256 collateralSpent) = exposedLib.calculatePurchaseReturnPublic(
            segments,
            collateralIn,
            currentSupply
        );

        assertEq(issuanceOut, expectedIssuanceOut, "Flat partial buy (exact for steps): issuanceOut mismatch");
        assertEq(collateralSpent, expectedCollateralSpent, "Flat partial buy (exact for steps): collateralSpent mismatch");
    }


    function test_CalculatePurchaseReturn_SingleSlopedSegment_AffordMultipleFullSteps() public {
        // Using only the first segment of defaultSegments (sloped)
        PackedSegment[] memory segments = new PackedSegment[](1);
        segments[0] = defaultSegments[0]; // initialPrice 1, increase 0.1, supplyPerStep 10, steps 3

        uint256 currentSupply = 0 ether;
        // Cost step 0 (price 1.0): 10 supply * 1.0 price = 10 collateral
        // Cost step 1 (price 1.1): 10 supply * 1.1 price = 11 collateral
        // Total cost for 2 steps (20 supply) = 10 + 11 = 21 collateral
        uint256 collateralIn = 25 ether; // Enough for 2 steps (cost 21), with 4 ether remaining

        // New logic: 2 full steps (20 issuance, 21 cost)
        // Remaining budget = 25 - 21 = 4 ether.
        // Next step price (step 2 of seg0) = 1 + (2 * 0.1) = 1.2 ether.
        // Partial issuance = (4 * 1e18) / 1.2e18 = 3.333... ether.
        // Partial cost = (3.333... * 1.2) / 1 = 4 ether.
        // Total issuance = 20 + 3.333... = 23.333... ether.
        // Total cost = 21 + 3.999... = 24.999... ether.
        uint256 expectedIssuanceOut = 23333333333333333333; // 23.333... ether
        uint256 expectedCollateralSpent = 24999999999999999999; // 24.999... ether

        (uint256 issuanceOut, uint256 collateralSpent) = exposedLib.calculatePurchaseReturnPublic(
            segments,
            collateralIn,
            currentSupply
        );

        assertEq(issuanceOut, expectedIssuanceOut, "Sloped multi-step buy: issuanceOut mismatch");
        assertEq(collateralSpent, expectedCollateralSpent, "Sloped multi-step buy: collateralSpent mismatch");
    }

    // --- Tests for calculateSaleReturn ---

    function test_CalculateSaleReturn_SingleSlopedSegment_PartialSell() public {
        // Using only the first segment of defaultSegments (sloped)
        PackedSegment[] memory segments = new PackedSegment[](1);
        segments[0] = defaultSegments[0]; // initialPrice 1, increase 0.1, supplyPerStep 10, steps 3

        // Current supply is 30 ether (3 steps minted from defaultSeg0)
        uint256 currentSupply = defaultSeg0_capacity; // 30 ether
        // Reserve for 30 supply (defaultSeg0_reserve) = 33 ether
        
        // Selling 10 ether issuance (the tokens from the last minted step, step 2 of defaultSeg0)
        uint256 issuanceToSell = defaultSeg0_supplyPerStep; // 10 ether

        // Expected: final supply after sale = 20 ether
        // Reserve for 20 supply (first 2 steps of defaultSeg0):
        // Step 0 (price 1.0): 10 coll
        // Step 1 (price 1.1): 11 coll
        // Total reserve for 20 supply = 10 + 11 = 21 ether
        uint256 reserveFor20Supply = 0;
        reserveFor20Supply += (defaultSeg0_supplyPerStep * (defaultSeg0_initialPrice + 0 * defaultSeg0_priceIncrease)) / DiscreteCurveMathLib_v1.SCALING_FACTOR;
        reserveFor20Supply += (defaultSeg0_supplyPerStep * (defaultSeg0_initialPrice + 1 * defaultSeg0_priceIncrease)) / DiscreteCurveMathLib_v1.SCALING_FACTOR;
        
        // Collateral out = Reserve(30) - Reserve(20) = 33 - 21 = 12 ether
        uint256 expectedCollateralOut = defaultSeg0_reserve - reserveFor20Supply;
        uint256 expectedIssuanceBurned = issuanceToSell;

        (uint256 collateralOut, uint256 issuanceBurned) = exposedLib.calculateSaleReturnPublic(
            segments,
            issuanceToSell,
            currentSupply
        );

        assertEq(collateralOut, expectedCollateralOut, "Sloped partial sell: collateralOut mismatch");
        assertEq(issuanceBurned, expectedIssuanceBurned, "Sloped partial sell: issuanceBurned mismatch");
    }

    // --- Additional calculateReserveForSupply tests ---

    function test_CalculateReserveForSupply_MultiSegment_FullCurve() public {
        // Using defaultSegments
        // defaultCurve_totalCapacity = 70 ether
        // defaultCurve_totalReserve = 94 ether
        uint256 actualReserve = exposedLib.calculateReserveForSupplyPublic(defaultSegments, defaultCurve_totalCapacity);
        assertEq(actualReserve, defaultCurve_totalReserve, "Reserve for full multi-segment curve mismatch");
    }

    function test_CalculateReserveForSupply_MultiSegment_PartialFillLaterSegment() public {
        // Using defaultSegments
        // Default Seg0: capacity 30, reserve 33
        // Default Seg1: initialPrice 1.5, increase 0.05, supplyPerStep 20, steps 2.
        // Target supply: Full seg0 (30) + 1 step of seg1 (20) = 50 ether
        uint256 targetSupply = defaultSeg0_capacity + defaultSeg1_supplyPerStep; // 30 + 20 = 50 ether

        // Cost for the first step of segment 1:
        // 20 supply * (1.5 price + 0 * 0.05 increase) = 30 ether collateral
        uint256 costFirstStepSeg1 = (defaultSeg1_supplyPerStep * (defaultSeg1_initialPrice + 0 * defaultSeg1_priceIncrease)) / DiscreteCurveMathLib_v1.SCALING_FACTOR;
        
        uint256 expectedTotalReserve = defaultSeg0_reserve + costFirstStepSeg1; // 33 + 30 = 63 ether

        uint256 actualReserve = exposedLib.calculateReserveForSupplyPublic(defaultSegments, targetSupply);
        assertEq(actualReserve, expectedTotalReserve, "Reserve for multi-segment partial fill mismatch");
    }

    function test_CalculateReserveForSupply_TargetSupplyBeyondCurveCapacity() public {
        // Using defaultSegments
        // defaultCurve_totalCapacity = 70 ether
        // defaultCurve_totalReserve = 94 ether
        uint256 targetSupplyBeyondCapacity = defaultCurve_totalCapacity + 100 ether;

        uint256 actualReserve = exposedLib.calculateReserveForSupplyPublic(defaultSegments, targetSupplyBeyondCapacity);
        
        // The function should return the reserve for the maximum supply the curve can offer.
        assertEq(actualReserve, defaultCurve_totalReserve, "Reserve beyond capacity should be reserve for full curve");
    }

    // TODO: Implement test
    // function test_CalculateReserveForSupply_MixedFlatAndSlopedSegments() public {
    // }

    function test_CalculateReserveForSupply_FreeToStartThenSlopedSegment() public {
        PackedSegment[] memory segments = new PackedSegment[](2);

        // Segment 0: Free mint
        uint256 supplyPerStep0 = 50 ether;
        uint256 numberOfSteps0 = 1; // Capacity 50 ether. Cost: 0
        segments[0] = DiscreteCurveMathLib_v1.createSegment(0, 0, supplyPerStep0, numberOfSteps0);

        // Segment 1: Sloped
        uint256 initialPrice1 = 0.2 ether;
        uint256 priceIncrease1 = 0.05 ether;
        uint256 supplyPerStep1 = 10 ether;
        uint256 numberOfSteps1 = 3; // Capacity 30 ether.
                                    // Cost: (10*0.2) + (10*0.25) + (10*0.3) = 2 + 2.5 + 3 = 7.5 ether
        segments[1] = DiscreteCurveMathLib_v1.createSegment(initialPrice1, priceIncrease1, supplyPerStep1, numberOfSteps1);
        
        // Target supply: Full free segment (50) + 2 steps of sloped segment (20) = 70 ether
        uint256 targetSupply = (supplyPerStep0 * numberOfSteps0) + (2 * supplyPerStep1); // 50 + 20 = 70 ether
        
        uint256 costPartialSeg1 = 0;
        costPartialSeg1 += (supplyPerStep1 * (initialPrice1 + 0 * priceIncrease1)) / DiscreteCurveMathLib_v1.SCALING_FACTOR; // 10 * 0.2 = 2
        costPartialSeg1 += (supplyPerStep1 * (initialPrice1 + 1 * priceIncrease1)) / DiscreteCurveMathLib_v1.SCALING_FACTOR; // 10 * 0.25 = 2.5
        // Total for partial seg1 = 2 + 2.5 = 4.5 ether

        uint256 expectedTotalReserve = 0 + costPartialSeg1; // 0 + 4.5 = 4.5 ether

        uint256 actualReserve = exposedLib.calculateReserveForSupplyPublic(segments, targetSupply);
        assertEq(actualReserve, expectedTotalReserve, "Reserve for free then sloped segments mismatch");
    }


    function test_CalculatePurchaseReturn_Edge_CollateralForExactlyOneStep_Sloped() public {
        PackedSegment[] memory segments = new PackedSegment[](1);
        segments[0] = defaultSegments[0]; // Sloped segment from default setup

        uint256 currentSupply = 0 ether;
        // Cost of the first step of defaultSegments[0]
        // initialPrice = 1 ether, supplyPerStep = 10 ether
        uint256 costFirstStep = (defaultSeg0_supplyPerStep * defaultSeg0_initialPrice) / DiscreteCurveMathLib_v1.SCALING_FACTOR; // 10 ether
        uint256 collateralIn = costFirstStep;

        uint256 expectedIssuanceOut = defaultSeg0_supplyPerStep; // 10 ether
        uint256 expectedCollateralSpent = costFirstStep; // 10 ether

        (uint256 issuanceOut, uint256 collateralSpent) = exposedLib.calculatePurchaseReturnPublic(
            segments,
            collateralIn,
            currentSupply
        );

        assertEq(issuanceOut, expectedIssuanceOut, "Issuance for exactly one sloped step mismatch");
        assertEq(collateralSpent, expectedCollateralSpent, "Collateral for exactly one sloped step mismatch");
    }

    function test_CalculatePurchaseReturn_Edge_CollateralLessThanOneStep_Flat() public {
        PackedSegment[] memory segments = new PackedSegment[](1);
        uint256 flatPrice = 2 ether;
        uint256 flatSupplyPerStep = 10 ether;
        uint256 flatNumSteps = 1;
        segments[0] = DiscreteCurveMathLib_v1.createSegment(flatPrice, 0, flatSupplyPerStep, flatNumSteps);

        uint256 currentSupply = 0 ether;
        uint256 costOneStep = (flatSupplyPerStep * flatPrice) / DiscreteCurveMathLib_v1.SCALING_FACTOR; // 20 ether
        uint256 collateralIn = costOneStep - 1 wei; // 19.99... ether, less than enough for one step

        // With partial purchases, it should buy what it can.
        // collateralIn = 19999999999999999999. flatPrice = 2e18.
        // issuanceOut = (collateralIn * SCALING_FACTOR) / flatPrice = 9999999999999999999.
        // collateralSpent = (issuanceOut * flatPrice) / SCALING_FACTOR = 19999999999999999998.
        uint256 expectedIssuanceOut = 9999999999999999999; 
        uint256 expectedCollateralSpent = 19999999999999999998;

        (uint256 issuanceOut, uint256 collateralSpent) = exposedLib.calculatePurchaseReturnPublic(
            segments,
            collateralIn,
            currentSupply
        );

        assertEq(issuanceOut, expectedIssuanceOut, "Issuance for less than one flat step mismatch");
        assertEq(collateralSpent, expectedCollateralSpent, "Collateral for less than one flat step mismatch");
    }

    function test_CalculatePurchaseReturn_Edge_CollateralLessThanOneStep_Sloped() public {
        PackedSegment[] memory segments = new PackedSegment[](1);
        segments[0] = defaultSegments[0]; // Sloped segment from default setup

        uint256 currentSupply = 0 ether;
        // Cost of the first step of defaultSegments[0] is 10 ether
        uint256 costFirstStep = (defaultSeg0_supplyPerStep * defaultSeg0_initialPrice) / DiscreteCurveMathLib_v1.SCALING_FACTOR;
        uint256 collateralIn = costFirstStep - 1 wei; // Just less than enough for the first step

        // With partial purchases.
        // collateralIn = 9999999999999999999. initialPrice (nextStepPrice) = 1e18.
        // issuanceOut = (collateralIn * SCALING_FACTOR) / initialPrice = 9999999999999999999.
        // collateralSpent = (issuanceOut * initialPrice) / SCALING_FACTOR = 9999999999999999999.
        uint256 expectedIssuanceOut = 9999999999999999999;
        uint256 expectedCollateralSpent = 9999999999999999999;

        (uint256 issuanceOut, uint256 collateralSpent) = exposedLib.calculatePurchaseReturnPublic(
            segments,
            collateralIn,
            currentSupply
        );

        assertEq(issuanceOut, expectedIssuanceOut, "Issuance for less than one sloped step mismatch");
        assertEq(collateralSpent, expectedCollateralSpent, "Collateral for less than one sloped step mismatch");
    }

    function test_CalculatePurchaseReturn_Edge_CollateralToBuyoutCurve() public {
        // Uses defaultSegments which has total capacity of defaultCurve_totalCapacity (70 ether)
        // and total reserve of defaultCurve_totalReserve (94 ether)
        uint256 currentSupply = 0 ether;
        
        // Test with exact collateral to buy out the curve
        uint256 collateralInExact = defaultCurve_totalReserve; 
        uint256 expectedIssuanceOutExact = defaultCurve_totalCapacity;
        uint256 expectedCollateralSpentExact = defaultCurve_totalReserve;

        (uint256 issuanceOut, uint256 collateralSpent) = exposedLib.calculatePurchaseReturnPublic(
            defaultSegments,
            collateralInExact,
            currentSupply
        );

        assertEq(issuanceOut, expectedIssuanceOutExact, "Issuance for curve buyout (exact collateral) mismatch");
        assertEq(collateralSpent, expectedCollateralSpentExact, "Collateral for curve buyout (exact collateral) mismatch");

        // Test with slightly more collateral than needed to buy out the curve
        uint256 collateralInMore = defaultCurve_totalReserve + 100 ether;
        // Expected behavior: still only buys out the curve capacity and spends the required reserve.
        uint256 expectedIssuanceOutMore = defaultCurve_totalCapacity;
        uint256 expectedCollateralSpentMore = defaultCurve_totalReserve;
        
        (issuanceOut, collateralSpent) = exposedLib.calculatePurchaseReturnPublic(
            defaultSegments,
            collateralInMore,
            currentSupply
        );

        assertEq(issuanceOut, expectedIssuanceOutMore, "Issuance for curve buyout (more collateral) mismatch");
        assertEq(collateralSpent, expectedCollateralSpentMore, "Collateral for curve buyout (more collateral) mismatch");
    }

    // --- calculatePurchaseReturn current supply variation tests ---

    function test_CalculatePurchaseReturn_StartMidStep_Sloped() public {
        uint256 currentSupply = 5 ether; // Mid-step 0 of defaultSegments[0]
        
        // getCurrentPriceAndStep(defaultSegments, 5 ether) will yield:
        // priceAtPurchaseStart = 1.0 ether (price of step 0 of defaultSeg0)
        // stepAtPurchaseStart = 0 (index of step 0 of defaultSeg0)
        // segmentAtPurchaseStart = 0 (index of defaultSeg0)

        // Collateral to buy one full step (step 0 of segment 0, price 1.0)
        // Note: calculatePurchaseReturn's internal _calculatePurchaseForSingleSegment will attempt to buy
        // full steps from the identified startStep (step 0 of seg0 in this case).
        uint256 collateralIn = (defaultSeg0_supplyPerStep * defaultSeg0_initialPrice) / DiscreteCurveMathLib_v1.SCALING_FACTOR; // 10 ether

        // Expected: Buys 1 full step (step 0 of segment 0)
        uint256 expectedIssuanceOut = defaultSeg0_supplyPerStep; // 10 ether
        uint256 expectedCollateralSpent = collateralIn; // 10 ether

        (uint256 issuanceOut, uint256 collateralSpent) = exposedLib.calculatePurchaseReturnPublic(
            defaultSegments,
            collateralIn,
            currentSupply
        );

        assertEq(issuanceOut, expectedIssuanceOut, "Issuance mid-step mismatch");
        assertEq(collateralSpent, expectedCollateralSpent, "Collateral mid-step mismatch");
    }

    function test_CalculatePurchaseReturn_StartEndOfStep_Sloped() public {
        uint256 currentSupply = defaultSeg0_supplyPerStep; // 10 ether, end of step 0 of defaultSegments[0]
        
        // getCurrentPriceAndStep(defaultSegments, 10 ether) will yield:
        // priceAtPurchaseStart = 1.1 ether (price of step 1 of defaultSeg0)
        // stepAtPurchaseStart = 1 (index of step 1 of defaultSeg0)
        // segmentAtPurchaseStart = 0 (index of defaultSeg0)

        // Collateral to buy one full step (which will be step 1 of segment 0, price 1.1)
        uint256 priceOfStep1Seg0 = defaultSeg0_initialPrice + defaultSeg0_priceIncrease;
        uint256 collateralIn = (defaultSeg0_supplyPerStep * priceOfStep1Seg0) / DiscreteCurveMathLib_v1.SCALING_FACTOR; // 11 ether

        // Expected: Buys 1 full step (step 1 of segment 0)
        uint256 expectedIssuanceOut = defaultSeg0_supplyPerStep; // 10 ether (supply of step 1)
        uint256 expectedCollateralSpent = collateralIn; // 11 ether

        (uint256 issuanceOut, uint256 collateralSpent) = exposedLib.calculatePurchaseReturnPublic(
            defaultSegments,
            collateralIn,
            currentSupply
        );

        assertEq(issuanceOut, expectedIssuanceOut, "Issuance end-of-step mismatch");
        assertEq(collateralSpent, expectedCollateralSpent, "Collateral end-of-step mismatch");
    }

    function test_CalculatePurchaseReturn_StartEndOfSegment_MultiSegment() public {
        uint256 currentSupply = defaultSeg0_capacity; // 30 ether, end of segment 0
        
        // getCurrentPriceAndStep(defaultSegments, 30 ether) will yield:
        // priceAtPurchaseStart = 1.5 ether (initial price of segment 1)
        // stepAtPurchaseStart = 0 (index of step 0 in segment 1)
        // segmentAtPurchaseStart = 1 (index of segment 1)

        // Collateral to buy one full step from segment 1 (step 0 of seg1, price 1.5)
        uint256 collateralIn = (defaultSeg1_supplyPerStep * defaultSeg1_initialPrice) / DiscreteCurveMathLib_v1.SCALING_FACTOR; // 30 ether

        // Expected: Buys 1 full step (step 0 of segment 1)
        uint256 expectedIssuanceOut = defaultSeg1_supplyPerStep; // 20 ether (supply of step 0 of seg1)
        uint256 expectedCollateralSpent = collateralIn; // 30 ether

        (uint256 issuanceOut, uint256 collateralSpent) = exposedLib.calculatePurchaseReturnPublic(
            defaultSegments,
            collateralIn,
            currentSupply
        );

        assertEq(issuanceOut, expectedIssuanceOut, "Issuance end-of-segment mismatch");
        assertEq(collateralSpent, expectedCollateralSpent, "Collateral end-of-segment mismatch");
    }

    function test_CalculatePurchaseReturn_SpanningSegments_EndsWithPartialInSecondSegment() public {
        // Objective: Buy out segment 0 completely, then buy a partial amount of the first step in segment 1.
        uint256 currentSupply = 0 ether;

        // Collateral needed for segment 0 is defaultSeg0_reserve (33 ether)
        // For segment 1:
        //   Price of first step = defaultSeg1_initialPrice (1.5 ether)
        //   Supply per step in seg1 = defaultSeg1_supplyPerStep (20 ether)
        //   Let's target buying 5 ether issuance from segment 1's first step.
        uint256 partialIssuanceInSeg1 = 5 ether;
        uint256 costForPartialInSeg1 = (partialIssuanceInSeg1 * defaultSeg1_initialPrice) / DiscreteCurveMathLib_v1.SCALING_FACTOR; // (5 * 1.5) = 7.5 ether

        uint256 collateralIn = defaultSeg0_reserve + costForPartialInSeg1; // 33 + 7.5 = 40.5 ether

        uint256 expectedIssuanceOut = defaultSeg0_capacity + partialIssuanceInSeg1; // 30 + 5 = 35 ether
        // Due to how partial purchases are calculated, the spent collateral should exactly match collateralIn if it's utilized fully.
        uint256 expectedCollateralSpent = collateralIn; 

        (uint256 issuanceOut, uint256 collateralSpent) = exposedLib.calculatePurchaseReturnPublic(
            defaultSegments,
            collateralIn,
            currentSupply
        );

        assertEq(issuanceOut, expectedIssuanceOut, "Spanning segments, partial end: issuanceOut mismatch");
        assertEq(collateralSpent, expectedCollateralSpent, "Spanning segments, partial end: collateralSpent mismatch");
    }
}
