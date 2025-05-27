// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.19;

import {IDiscreteCurveMathLib_v1} from "../interfaces/IDiscreteCurveMathLib_v1.sol";
import {PackedSegmentLib} from "../libraries/PackedSegmentLib.sol";
import {PackedSegment} from "../types/PackedSegment_v1.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title DiscreteCurveMathLib_v1
 * @notice Library for mathematical operations on discrete bonding curves.
 * @dev This library uses packed storage for curve segments to optimize gas costs.
 * It provides functions to calculate prices, reserves, and purchase/sale returns.
 */
library DiscreteCurveMathLib_v1 {
    // --- Constants ---
    uint256 public constant SCALING_FACTOR = 1e18;
    uint256 public constant MAX_SEGMENTS = 10;

    // --- Structs ---

    /**
     * @notice Helper struct to represent a specific position on the bonding curve.
     * @param segmentIndex The index of the segment where the position lies.
     * @param stepIndexWithinSegment The index of the step within that segment.
     * @param priceAtCurrentStep The price at this specific step.
     * @param supplyCoveredUpToThisPosition The total supply minted up to and including this position.
     */
    struct CurvePosition {
        uint256 segmentIndex;
        uint256 stepIndexWithinSegment;
        uint256 priceAtCurrentStep;
        uint256 supplyCoveredUpToThisPosition;
    }

    // Enable clean syntax for PackedSegment instances: e.g., segment.initialPrice()
    using PackedSegmentLib for PackedSegment;

    // --- Internal Helper Functions ---

    /**
     * @notice Validates that the provided currentTotalIssuanceSupply is consistent with the segment configuration.
     * @dev Reverts if segments are empty and supply > 0, or if supply exceeds total capacity of all segments.
     * @param segments Array of PackedSegment configurations for the curve.
     * @param currentTotalIssuanceSupply The current total issuance supply to validate.
     */
    function _validateSupplyAgainstSegments(
        PackedSegment[] memory segments,
        uint256 currentTotalIssuanceSupply
    ) internal pure {
        uint256 numSegments = segments.length; // Cache length
        if (numSegments == 0) {
            if (currentTotalIssuanceSupply > 0) {
                // It's invalid to have a supply if no segments are defined to back it.
                revert IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__NoSegmentsConfigured();
            }
            // If segments.length == 0 and currentTotalIssuanceSupply == 0, it's a valid initial state.
            return;
        }

        uint256 totalCurveCapacity = 0;
        for (uint256 segmentIndex = 0; segmentIndex < numSegments; ++segmentIndex) { // Use cached length
            // Note: supplyPerStep and numberOfSteps are validated > 0 by PackedSegmentLib.create
            uint256 supplyPerStep = segments[segmentIndex].supplyPerStep();
            uint256 numberOfStepsInSegment = segments[segmentIndex].numberOfSteps();
            totalCurveCapacity += numberOfStepsInSegment * supplyPerStep;
        }

        if (currentTotalIssuanceSupply > totalCurveCapacity) {
            revert IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__SupplyExceedsCurveCapacity(
                currentTotalIssuanceSupply,
                totalCurveCapacity
            );
        }
    }

    /**
     * @notice Finds the segment, step, price, and cumulative supply for a given target total issuance supply.
     * @dev Iterates linearly through segments.
     * @param segments Array of PackedSegment configurations for the curve.
     * @param targetTotalIssuanceSupply The total supply for which to find the position.
     * @return targetPosition A CurvePosition struct detailing the location on the curve.
     */
    function _findPositionForSupply(
        PackedSegment[] memory segments,
        uint256 targetTotalIssuanceSupply
    ) internal pure returns (CurvePosition memory targetPosition) {
        uint256 numSegments = segments.length; // Cache length
        if (numSegments == 0) {
            revert IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__NoSegmentsConfigured();
        }
        if (numSegments > MAX_SEGMENTS) {
            // This check is also in validateSegmentArray, but good for internal consistency
            revert IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__TooManySegments();
        }

        uint256 cumulativeSupply = 0;
        // targetPosition members are initialized to 0 by default

        for (uint256 segmentIndex = 0; segmentIndex < numSegments; ++segmentIndex) { // Use cached length
            // Note: supplyPerStep within the segment is guaranteed > 0 by PackedSegmentLib.create validation.
            (
                uint256 initialPrice,
                uint256 priceIncreasePerStep,
                uint256 supplyPerStep,
                uint256 totalStepsInSegment
            ) = segments[segmentIndex].unpack();

            uint256 supplyInCurrentSegment = totalStepsInSegment * supplyPerStep;
            uint256 endOfCurrentSegmentSupply = cumulativeSupply + supplyInCurrentSegment;

            if (targetTotalIssuanceSupply < endOfCurrentSegmentSupply) {
                // Case 1: Target supply is strictly WITHIN the current segment.
                targetPosition.segmentIndex = segmentIndex;
                uint256 supplyNeededFromThisSegment = targetTotalIssuanceSupply - cumulativeSupply;
                // supplyPerStep is guaranteed > 0 by PackedSegmentLib.create
                targetPosition.stepIndexWithinSegment = supplyNeededFromThisSegment / supplyPerStep; 
                targetPosition.priceAtCurrentStep = initialPrice + (targetPosition.stepIndexWithinSegment * priceIncreasePerStep);
                targetPosition.supplyCoveredUpToThisPosition = targetTotalIssuanceSupply;
                return targetPosition;
            } else if (targetTotalIssuanceSupply == endOfCurrentSegmentSupply) {
                // Case 2: Target supply is EXACTLY AT THE END of the current segment.
                targetPosition.supplyCoveredUpToThisPosition = targetTotalIssuanceSupply;
                if (segmentIndex + 1 < numSegments) { // Use cached length
                    // There is a next segment. Position is start of next segment.
                    targetPosition.segmentIndex = segmentIndex + 1;
                    targetPosition.stepIndexWithinSegment = 0;
                    // Unpack segments[segmentIndex+1] to get its initialPrice
                    (uint256 nextInitialPrice,,,) = segments[segmentIndex + 1].unpack();
                    targetPosition.priceAtCurrentStep = nextInitialPrice; // Price is initial of next segment
                } else {
                    // This is the last segment. Position is the last step of this current (last) segment.
                    targetPosition.segmentIndex = segmentIndex;
                    // totalStepsInSegment is guaranteed > 0 by PackedSegmentLib.create
                    targetPosition.stepIndexWithinSegment = totalStepsInSegment - 1; 
                    targetPosition.priceAtCurrentStep = initialPrice + (targetPosition.stepIndexWithinSegment * priceIncreasePerStep);
                }
                return targetPosition;
            } else {
                // Case 3: Target supply is BEYOND the current segment.
                // Continue to the next segment.
                cumulativeSupply = endOfCurrentSegmentSupply;
            }
        }

        // Target supply is beyond all configured segments
        targetPosition.segmentIndex = numSegments - 1; // Indicates the last segment, use cached length
        // targetPosition.stepIndexWithinSegment will be the last step of the last segment
        // Unpack the last segment once
        (
            uint256 lastSegmentInitialPrice, 
            uint256 lastSegmentPriceIncreasePerStep,, 
            uint256 lastSegmentTotalSteps
        ) = segments[numSegments - 1].unpack();
        targetPosition.stepIndexWithinSegment = lastSegmentTotalSteps > 0 ? lastSegmentTotalSteps - 1 : 0;
        targetPosition.priceAtCurrentStep = lastSegmentInitialPrice + (targetPosition.stepIndexWithinSegment * lastSegmentPriceIncreasePerStep);
        targetPosition.supplyCoveredUpToThisPosition = cumulativeSupply; // Total supply covered by all segments
        // The caller should check if targetPosition.supplyCoveredUpToThisPosition < targetTotalIssuanceSupply
        // to understand if the target was fully met.
        return targetPosition;
    }

    // Functions from sections IV-VIII will be added in subsequent steps.

    /**
     * @notice Gets the current price, step index, and segment index for a given total issuance supply.
     * @dev Adjusts to the price of the *next* step if currentTotalIssuanceSupply exactly lands on a step boundary.
     * @param segments Array of PackedSegment configurations for the curve.
     * @param currentTotalIssuanceSupply The current total supply.
     * @return price The price at the current (or next, if on boundary) step.
     * @return stepIndex The index of the current (or next) step within its segment.
     * @return segmentIndex The index of the current (or next) segment.
     */
    function getCurrentPriceAndStep(
        PackedSegment[] memory segments,
        uint256 currentTotalIssuanceSupply
    ) internal pure returns (uint256 price, uint256 stepIndex, uint256 segmentIndex) {
        CurvePosition memory targetPosition = _findPositionForSupply(segments, currentTotalIssuanceSupply);

        // Validate that currentTotalIssuanceSupply is within curve bounds.
        // _findPositionForSupply sets targetPosition.supplyCoveredUpToThisPosition to the maximum supply
        // of the curve if targetTotalIssuanceSupply is beyond the curve's capacity.
        // If currentTotalIssuanceSupply is 0, targetPosition.supplyCoveredUpToThisPosition will also be 0.
        // Thus, (0 > 0) is false, no revert.
        // If currentTotalIssuanceSupply > 0 and within capacity, targetPosition.supplyCoveredUpToThisPosition == currentTotalIssuanceSupply.
        // Thus, (X > X) is false, no revert.
        // If currentTotalIssuanceSupply > 0 and beyond capacity, targetPosition.supplyCoveredUpToThisPosition is max capacity.
        // Thus, (currentTotalIssuanceSupply > max_capacity) is true, causing a revert.
        if (currentTotalIssuanceSupply > targetPosition.supplyCoveredUpToThisPosition) {
            revert IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__TargetSupplyBeyondCurveCapacity();
        }
        
        // Since _findPositionForSupply (after its own fix for Issue 1) now correctly handles
        // segment boundaries by pointing to the start of the next segment (or the last step of the
        // last segment if at max capacity), and returns the price/step for that position,
        // we can directly use its output. The complex adjustment logic previously here is no longer needed.
        return (targetPosition.priceAtCurrentStep, targetPosition.stepIndexWithinSegment, targetPosition.segmentIndex);
    }

    // --- Core Calculation Functions ---

    /**
     * @notice Calculates the total collateral reserve required to back a given target supply.
     * @dev Iterates through segments, summing the collateral needed for the portion of targetSupply in each.
     * @param segments Array of PackedSegment configurations for the curve.
     * @param targetSupply The target total issuance supply for which to calculate the reserve.
     * @return totalReserve The total collateral reserve required.
     */
    function calculateReserveForSupply(
        PackedSegment[] memory segments,
        uint256 targetSupply
    ) internal pure returns (uint256 totalReserve) {
        if (targetSupply == 0) {
            return 0;
        }
        uint256 numSegments = segments.length; // Cache length
        if (numSegments == 0) {
            revert IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__NoSegmentsConfigured();
        }
        if (numSegments > MAX_SEGMENTS) {
            revert IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__TooManySegments();
        }
        _validateSupplyAgainstSegments(segments, targetSupply);

        uint256 cumulativeSupplyProcessed = 0;
        // totalReserve is initialized to 0 by default

        for (uint256 segmentIndex = 0; segmentIndex < numSegments; ++segmentIndex) { // Use cached length
            if (cumulativeSupplyProcessed >= targetSupply) {
                break; // All target supply has been accounted for.
            }

            // Unpack segment data - using batch unpack as per instruction suggestion for this case
            (
                uint256 initialPrice,
                uint256 priceIncreasePerStep,
                uint256 supplyPerStep,
                uint256 totalStepsInSegment
            ) = segments[segmentIndex].unpack();
            // Note: supplyPerStep is guaranteed > 0 by PackedSegmentLib.create validation.

            uint256 supplyRemainingInTarget = targetSupply - cumulativeSupplyProcessed;
            
            // Calculate how many steps from *this* segment are needed to cover supplyRemainingInTarget
            // Ceiling division: (numerator + denominator - 1) / denominator
            uint256 stepsToProcessInSegment = (supplyRemainingInTarget + supplyPerStep - 1) / supplyPerStep;

            // Cap at the segment's actual available steps
            if (stepsToProcessInSegment > totalStepsInSegment) {
                stepsToProcessInSegment = totalStepsInSegment;
            }

            uint256 collateralForPortion;
            if (priceIncreasePerStep == 0) {
                // Flat segment
                collateralForPortion = (stepsToProcessInSegment * supplyPerStep * initialPrice) / SCALING_FACTOR;
            } else {
                // Sloped segment: sum of an arithmetic series
                // S_n = n/2 * (2a + (n-1)d)
                // Here, n = stepsToProcessInSegment, a = initialPrice, d = priceIncreasePerStep
                // Each term (price) is multiplied by supplyPerStep and divided by SCALING_FACTOR.
                // Collateral = supplyPerStep/SCALING_FACTOR * Sum_{k=0}^{n-1} (initialPrice + k*priceIncreasePerStep)
                // Collateral = supplyPerStep/SCALING_FACTOR * (n*initialPrice + priceIncreasePerStep * n*(n-1)/2)
                // Collateral = (supplyPerStep * n * (2*initialPrice + (n-1)*priceIncreasePerStep)) / (2 * SCALING_FACTOR)
                // where n is stepsToProcessInSegment.
                
                if (stepsToProcessInSegment == 0) {
                    collateralForPortion = 0;
                } else {
                    uint256 firstStepPrice = initialPrice;
                    uint256 lastStepPrice = initialPrice + (stepsToProcessInSegment - 1) * priceIncreasePerStep;
                    uint256 sumOfPrices = firstStepPrice + lastStepPrice;
                    uint256 totalPriceForAllStepsInPortion;
                    if (sumOfPrices == 0) { // If prices are zero, total is zero
                        totalPriceForAllStepsInPortion = 0;
                    } else if (stepsToProcessInSegment % 2 == 0) {
                        totalPriceForAllStepsInPortion = (stepsToProcessInSegment / 2) * sumOfPrices;
                    } else {
                        totalPriceForAllStepsInPortion = stepsToProcessInSegment * (sumOfPrices / 2);
                    }
                    collateralForPortion = Math.mulDiv(supplyPerStep, totalPriceForAllStepsInPortion, SCALING_FACTOR);
                }
            }

            totalReserve += collateralForPortion;
            cumulativeSupplyProcessed += stepsToProcessInSegment * supplyPerStep;
        }
        
        // If targetSupply was greater than the total capacity of the curve,
        // cumulativeSupplyProcessed will be less than targetSupply.
        // The function returns the reserve for the supply that *could* be covered.
        // A check can be added by the caller if needed.
        // For example: if (cumulativeSupplyProcessed < targetSupply) { revert IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__TargetSupplyBeyondCurveCapacity(); }
        // However, the function is "calculateReserveForSupply", so it calculates for what's available up to targetSupply.

        return totalReserve;
    }

    /**
     * @notice Calculates the amount of issuance tokens received for a given collateral input.
     * @dev Iterates through segments starting from the current supply's position,
     *      calculating affordable steps in each segment. Uses binary search for sloped segments.
     * @param segments Array of PackedSegment configurations for the curve.
     * @param collateralToSpendProvided The amount of collateral being provided for purchase.
     * @param currentTotalIssuanceSupply The current total supply before this purchase.
     * @return tokensToMint The total amount of issuance tokens minted.
     * @return collateralSpentByPurchaser The actual amount of collateral spent.
     */
    function calculatePurchaseReturn(
        PackedSegment[] memory segments,
        uint256 collateralToSpendProvided, // Renamed from collateralAmountIn
        uint256 currentTotalIssuanceSupply
    ) internal pure returns (uint256 tokensToMint, uint256 collateralSpentByPurchaser) { // Renamed return values
        _validateSupplyAgainstSegments(segments, currentTotalIssuanceSupply);

        if (collateralToSpendProvided == 0) {
            revert IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__ZeroCollateralInput();
        }
        
        uint256 numSegments = segments.length; // Renamed from segLen
        if (numSegments == 0) { 
            revert IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__NoSegmentsConfigured();
        }
        
        // tokensToMint and collateralSpentByPurchaser are initialized to 0 by default as return variables
        uint256 budgetRemaining = collateralToSpendProvided; // Renamed from remainingCollateral

        (
            uint256 priceAtPurchaseStart,
            uint256 stepAtPurchaseStart,
            uint256 segmentIndexAtPurchaseStart // Renamed from segmentAtPurchaseStart
        ) = getCurrentPriceAndStep(segments, currentTotalIssuanceSupply);

        for (uint256 currentSegmentIndex = segmentIndexAtPurchaseStart; currentSegmentIndex < numSegments; ++currentSegmentIndex) { // Renamed i to currentSegmentIndex
            if (budgetRemaining == 0) {
                break; 
            }

            uint256 startStepInCurrentSegment; // Renamed from currentSegmentStartStepForHelper
            uint256 priceAtStartStepInCurrentSegment; // Renamed from priceAtCurrentSegmentStartStepForHelper
            PackedSegment currentSegment = segments[currentSegmentIndex];
            
            (uint256 currentSegmentInitialPrice,,, uint256 currentSegmentTotalSteps) = currentSegment.unpack(); // Renamed cs variables


            if (currentSegmentIndex == segmentIndexAtPurchaseStart) {
                startStepInCurrentSegment = stepAtPurchaseStart;
                priceAtStartStepInCurrentSegment = priceAtPurchaseStart;
            } else {
                startStepInCurrentSegment = 0;
                priceAtStartStepInCurrentSegment = currentSegmentInitialPrice; 
            }
            
            if (startStepInCurrentSegment >= currentSegmentTotalSteps) { 
                continue; 
            }

            (uint256 tokensMintedInSegment, uint256 collateralSpentInSegment) = // Renamed issuanceBoughtThisSegment, collateralSpentThisSegment
                _calculatePurchaseForSingleSegment(
                    currentSegment,
                    budgetRemaining,
                    startStepInCurrentSegment,
                    priceAtStartStepInCurrentSegment
                );

            tokensToMint += tokensMintedInSegment;
            collateralSpentByPurchaser += collateralSpentInSegment;
            budgetRemaining -= collateralSpentInSegment;
        }
        return (tokensToMint, collateralSpentByPurchaser);
    }

    /**
     * @notice Helper function to calculate the issuance and collateral for full steps in a non-free flat segment.
     * @param availableBudget The collateral budget available.
     * @param pricePerStepInFlatSegment The price for each step in this flat segment.
     * @param supplyPerStepInSegment The supply per step in this segment.
     * @param stepsAvailableToPurchase The number of steps available for purchase in this segment.
     * @return tokensMinted The total issuance from full steps.
     * @return collateralSpent The total collateral spent for these full steps.
     */
    function _calculateFullStepsForFlatSegment(
        uint256 availableBudget, // Renamed from _budget
        uint256 pricePerStepInFlatSegment, // Renamed from _priceAtSegmentInitialStep
        uint256 supplyPerStepInSegment, // Renamed from _sPerStepSeg
        uint256 stepsAvailableToPurchase // Renamed from _stepsAvailableToPurchaseInSeg
    ) private pure returns (uint256 tokensMinted, uint256 collateralSpent) { // Renamed issuanceOut
        // Calculate full steps for flat segment
        // pricePerStepInFlatSegment is guaranteed non-zero when this function is called.
        uint256 maxTokensMintableWithBudget = Math.mulDiv(availableBudget, SCALING_FACTOR, pricePerStepInFlatSegment);
        uint256 numFullStepsAffordable = maxTokensMintableWithBudget / supplyPerStepInSegment;

        if (numFullStepsAffordable > stepsAvailableToPurchase) {
            numFullStepsAffordable = stepsAvailableToPurchase;
        }
        tokensMinted = numFullStepsAffordable * supplyPerStepInSegment;
        collateralSpent = Math.mulDiv(tokensMinted, pricePerStepInFlatSegment, SCALING_FACTOR);
        return (tokensMinted, collateralSpent);
    }

    /**
     * @notice Helper function to calculate purchase return for a single sloped segment using linear search.
     * @dev Iterates step-by-step to find affordable steps. More gas-efficient for small number of steps.
     * @param segment The PackedSegment to process.
     * @param totalBudget The amount of collateral available for this segment.
     * @param purchaseStartStepInSegment The starting step index within this segment for the current purchase (0-indexed).
     * @param priceAtPurchaseStartStep The price at the `purchaseStartStepInSegment`.
     * @return tokensPurchased The issuance tokens bought from this segment.
     * @return totalCollateralSpent The collateral spent for this segment.
     */
    function _linearSearchSloped(
        PackedSegment segment,
        uint256 totalBudget, // Renamed from budget
        uint256 purchaseStartStepInSegment, // Renamed from startStep
        uint256 priceAtPurchaseStartStep // Renamed from startPrice
    ) internal pure returns (uint256 tokensPurchased, uint256 totalCollateralSpent) { // Renamed issuanceOut, collateralSpent
        (, uint256 priceIncreasePerStep, uint256 supplyPerStep, uint256 totalStepsInSegment) = segment.unpack(); // Renamed variables
        
        if (purchaseStartStepInSegment >= totalStepsInSegment) { 
            revert IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__InvalidSegmentInitialStep();
        }
        uint256 maxStepsPurchasableInSegment = totalStepsInSegment - purchaseStartStepInSegment; // Renamed

        uint256 priceForCurrentStep = priceAtPurchaseStartStep; // Renamed
        uint256 stepsSuccessfullyPurchased = 0; // Renamed
        // totalCollateralSpent is already a return variable, can use it directly.

        while (stepsSuccessfullyPurchased < maxStepsPurchasableInSegment) {
            uint256 costForCurrentStep = (supplyPerStep * priceForCurrentStep) / SCALING_FACTOR; // Renamed

            if (totalCollateralSpent + costForCurrentStep <= totalBudget) {
                totalCollateralSpent += costForCurrentStep;
                stepsSuccessfullyPurchased++;
                priceForCurrentStep += priceIncreasePerStep; 
            } else {
                break; 
            }
        }

        tokensPurchased = stepsSuccessfullyPurchased * supplyPerStep;
        return (tokensPurchased, totalCollateralSpent);
    }

    /**
     * @notice Helper function to calculate purchase return for a single segment.
     * @dev Contains logic for flat segments and uses linear search for sloped segments.
     * @param segment The PackedSegment to process.
     * @param budgetForSegment The amount of collateral available for this segment.
     * @param purchaseStartStepInSegment The starting step index within this segment for the current purchase.
     * @param priceAtPurchaseStartStep The price at the `purchaseStartStepInSegment`.
     * @return tokensToIssue The issuance tokens bought from this segment.
     * @return collateralToSpend The collateral spent for this segment.
     */
    function _calculatePurchaseForSingleSegment(
        PackedSegment segment,
        uint256 budgetForSegment, // Renamed from remainingCollateralIn
        uint256 purchaseStartStepInSegment, // Renamed from segmentInitialStep
        uint256 priceAtPurchaseStartStep // Renamed from priceAtSegmentInitialStep
    ) private pure returns (uint256 tokensToIssue, uint256 collateralToSpend) { // Renamed return values
        // Unpack segment details once at the beginning
        (, uint256 priceIncreasePerStep, uint256 supplyPerStep, uint256 totalStepsInSegment) = segment.unpack(); // Renamed

        if (purchaseStartStepInSegment >= totalStepsInSegment) { 
            revert IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__InvalidSegmentInitialStep();
        }

        uint256 remainingStepsInSegment = totalStepsInSegment - purchaseStartStepInSegment; // Renamed
        // tokensToIssue and collateralToSpend are implicitly initialized to 0 as return variables.

        if (priceIncreasePerStep == 0) { // Flat Segment Logic
            if (priceAtPurchaseStartStep == 0) { // Entirely free mint part of the segment
                tokensToIssue = remainingStepsInSegment * supplyPerStep;
                // collateralToSpend is implicitly 0
                return (tokensToIssue, 0); 
            } else { // Non-free flat part
                (tokensToIssue, collateralToSpend) = _calculateFullStepsForFlatSegment(
                    budgetForSegment,
                    priceAtPurchaseStartStep,
                    supplyPerStep,
                    remainingStepsInSegment
                );

                uint256 budgetRemainingForPartialPurchase = budgetForSegment - collateralToSpend; // Renamed
                uint256 maxPartialIssuanceFromSegment = (remainingStepsInSegment * supplyPerStep) - tokensToIssue; // Renamed
                uint256 numFullStepsPurchased = tokensToIssue / supplyPerStep; 

                if (numFullStepsPurchased < remainingStepsInSegment && budgetRemainingForPartialPurchase > 0 && maxPartialIssuanceFromSegment > 0) {
                    (uint256 partialTokensIssued, uint256 partialCollateralSpent) = _calculatePartialPurchaseAmount( // Renamed
                        budgetRemainingForPartialPurchase,
                        priceAtPurchaseStartStep, 
                        supplyPerStep, 
                        maxPartialIssuanceFromSegment
                    );
                    tokensToIssue += partialTokensIssued;
                    collateralToSpend += partialCollateralSpent;
                }
            }
        } else { // Sloped Segment Logic
            (uint256 fullStepTokensIssued, uint256 fullStepCollateralSpent) = _linearSearchSloped( // Renamed
                segment, 
                budgetForSegment, 
                purchaseStartStepInSegment,    
                priceAtPurchaseStartStep 
            );

            tokensToIssue = fullStepTokensIssued;
            collateralToSpend = fullStepCollateralSpent;
            
            uint256 numFullStepsPurchased = fullStepTokensIssued / supplyPerStep; 
            
            uint256 budgetRemainingForPartialPurchase = budgetForSegment - collateralToSpend; // Renamed
            uint256 priceForNextPartialStep = priceAtPurchaseStartStep + (numFullStepsPurchased * priceIncreasePerStep); // Renamed
            uint256 maxPartialIssuanceFromSegment = (remainingStepsInSegment * supplyPerStep) - tokensToIssue; // Renamed

            if (numFullStepsPurchased < remainingStepsInSegment && budgetRemainingForPartialPurchase > 0 && maxPartialIssuanceFromSegment > 0) {
                (uint256 partialTokensIssued, uint256 partialCollateralSpent) = _calculatePartialPurchaseAmount( // Renamed
                    budgetRemainingForPartialPurchase,
                    priceForNextPartialStep,
                    supplyPerStep, 
                    maxPartialIssuanceFromSegment
                );
                tokensToIssue += partialTokensIssued;
                collateralToSpend += partialCollateralSpent;
            }
        }
    }

    /**
     * @notice Calculates the amount of partial issuance and its cost given budget and various constraints.
     * @param availableBudget The remaining collateral available for this partial purchase.
     * @param pricePerTokenForPartialPurchase The price at which this partial issuance is to be bought.
     * @param maxTokensPerIndividualStep The maximum issuance normally available in one full step (supplyPerStep).
     * @param maxTokensRemainingInSegment The maximum total partial issuance allowed by remaining segment capacity.
     * @return tokensToIssue The amount of tokens to be issued for the partial purchase.
     * @return collateralToSpend The collateral cost for the tokensToIssue.
     */
    function _calculatePartialPurchaseAmount(
        uint256 availableBudget, // Renamed from _budget
        uint256 pricePerTokenForPartialPurchase, // Renamed from _priceForPartialStep
        uint256 maxTokensPerIndividualStep, // Renamed from _supplyPerFullStep
        uint256 maxTokensRemainingInSegment // Renamed from _maxIssuanceAllowedOverall
    ) private pure returns (uint256 tokensToIssue, uint256 collateralToSpend) { // Renamed return values
        if (pricePerTokenForPartialPurchase == 0) {
            // For free mints, issue the minimum of what's available in the step or segment.
            if (maxTokensPerIndividualStep < maxTokensRemainingInSegment) {
                tokensToIssue = maxTokensPerIndividualStep;
            } else {
                tokensToIssue = maxTokensRemainingInSegment;
            }
            collateralToSpend = 0;
            return (tokensToIssue, collateralToSpend);
        }

        // Calculate the maximum tokens that can be afforded with the available budget.
        uint256 maxAffordableTokens = Math.mulDiv(
            availableBudget,
            SCALING_FACTOR,
            pricePerTokenForPartialPurchase
        );
        
        // Determine the actual tokens to issue by taking the minimum of three constraints:
        // 1. What the budget can afford.
        // 2. The maximum tokens available in an individual step.
        // 3. The maximum tokens remaining in the current segment.
        tokensToIssue = _min3(
            maxAffordableTokens,
            maxTokensPerIndividualStep,
            maxTokensRemainingInSegment
        );
        
        // Calculate the collateral to spend for the determined tokensToIssue.
        collateralToSpend = Math.mulDiv(
            tokensToIssue,
            pricePerTokenForPartialPurchase,
            SCALING_FACTOR
        );

        // Assertions to ensure invariants (can be kept for testing/development).
        assert(collateralToSpend <= availableBudget); 
        assert(tokensToIssue <= maxTokensRemainingInSegment); 
        assert(tokensToIssue <= maxTokensPerIndividualStep); 

        return (tokensToIssue, collateralToSpend);
    }

    /**
     * @dev Helper function to find the minimum of three uint256 values.
     */
    function _min3(uint256 a, uint256 b, uint256 c) private pure returns (uint256) {
        if (a < b) {
            return a < c ? a : c;
        } else {
            return b < c ? b : c;
        }
    }

    /**
     * @notice Calculates the amount of collateral returned for selling a given amount of issuance tokens.
     * @dev Uses the difference in reserve at current supply and supply after sale.
     * @param segments Array of PackedSegment configurations for the curve.
     * @param tokensToSell The amount of issuance tokens being sold.
     * @param currentTotalIssuanceSupply The current total supply before this sale.
     * @return collateralToReturn The total amount of collateral returned to the seller.
     * @return tokensToBurn The actual amount of issuance tokens burned (capped at current supply).
     */
    function calculateSaleReturn(
        PackedSegment[] memory segments,
        uint256 tokensToSell, // Renamed from issuanceAmountIn
        uint256 currentTotalIssuanceSupply
    ) internal pure returns (uint256 collateralToReturn, uint256 tokensToBurn) { // Renamed return values
        _validateSupplyAgainstSegments(segments, currentTotalIssuanceSupply);

        if (tokensToSell == 0) {
            revert IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__ZeroIssuanceInput();
        }
        
        uint256 numSegments = segments.length; // Renamed from segLen
        if (numSegments == 0) { 
            // This implies currentTotalIssuanceSupply must be 0.
            // Selling from 0 supply on an unconfigured curve. tokensToBurn will be 0.
        }

        tokensToBurn = tokensToSell > currentTotalIssuanceSupply ? currentTotalIssuanceSupply : tokensToSell;

        if (tokensToBurn == 0) { 
            return (0, 0);
        }

        uint256 finalSupplyAfterSale = currentTotalIssuanceSupply - tokensToBurn;

        uint256 collateralAtCurrentSupply = calculateReserveForSupply(segments, currentTotalIssuanceSupply);
        uint256 collateralAtFinalSupply = calculateReserveForSupply(segments, finalSupplyAfterSale);

        if (collateralAtCurrentSupply < collateralAtFinalSupply) {
            // This should not happen with a correctly defined bonding curve (prices are non-negative).
            return (0, tokensToBurn); 
        }

        collateralToReturn = collateralAtCurrentSupply - collateralAtFinalSupply;

        return (collateralToReturn, tokensToBurn);
    }

    // --- Public API Convenience Functions (as per plan, though internal) ---

    /**
     * @notice Convenience function to create a PackedSegment using the internal PackedSegmentLib.
     * @dev This is effectively an alias to PackedSegmentLib.create for use within contexts
     *      that have imported DiscreteCurveMathLib_v1 directly.
     * @param initialPrice The initial price for this segment.
     * @param priceIncrease The price increase per step for this segment.
     * @param supplyPerStep The supply minted per step for this segment.
     * @param numberOfSteps The number of steps in this segment.
     * @return The newly created PackedSegment.
     */
    function createSegment(
        uint256 initialPrice,
        uint256 priceIncrease,
        uint256 supplyPerStep,
        uint256 numberOfSteps
    ) internal pure returns (PackedSegment) {
        // All validation is handled by PackedSegmentLib.create
        return PackedSegmentLib.create(initialPrice, priceIncrease, supplyPerStep, numberOfSteps);
    }

    /**
     * @notice Validates an array of PackedSegments.
     * @dev Checks for empty array, exceeding max segments, and basic validity of each segment.
     *      More detailed validation of individual segment parameters occurs at creation time.
     * @param segments Array of PackedSegment configurations to validate.
     */
    function validateSegmentArray(PackedSegment[] memory segments) internal pure {
        uint256 numSegments = segments.length; // Renamed from segLen
        if (numSegments == 0) {
            revert IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__NoSegmentsConfigured();
        }
        if (numSegments > MAX_SEGMENTS) {
            revert IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__TooManySegments();
        }

        // Note: Individual segment's supplyPerStep > 0 and numberOfSteps > 0 
        // are guaranteed by PackedSegmentLib.create validation.
        // This function primarily validates array-level properties.
        for (uint256 segmentIndex = 0; segmentIndex < numSegments; ++segmentIndex) { // Renamed i to segmentIndex
            // The check for segments[segmentIndex].supplyPerStep() == 0 was removed as it's redundant.
            // Similarly, numberOfSteps > 0 is also guaranteed by PackedSegmentLib.create.
            // If other per-segment validations were needed here (that aren't covered by create), they could be added.
        }
    }
}
