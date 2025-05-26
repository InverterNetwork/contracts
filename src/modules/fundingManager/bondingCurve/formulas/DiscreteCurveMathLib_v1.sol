// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.19;

import {IDiscreteCurveMathLib_v1} from "../interfaces/IDiscreteCurveMathLib_v1.sol";
import {PackedSegmentLib} from "../libraries/PackedSegmentLib.sol";
import {PackedSegment} from "../types/PackedSegment_v1.sol";

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
        uint256 segLen = segments.length; // Cache length
        if (segLen == 0) {
            if (currentTotalIssuanceSupply > 0) {
                // It's invalid to have a supply if no segments are defined to back it.
                revert IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__NoSegmentsConfigured();
            }
            // If segments.length == 0 and currentTotalIssuanceSupply == 0, it's a valid initial state.
            return;
        }

        uint256 totalCurveCapacity = 0;
        for (uint256 i = 0; i < segLen; ++i) { // Use cached length
            // Note: supplyPerStep and numberOfSteps are validated > 0 by PackedSegmentLib.create
            (,, uint256 sPerStep, uint256 nSteps) = segments[i].unpack(); // Batch unpack
            totalCurveCapacity += nSteps * sPerStep;
        }

        if (currentTotalIssuanceSupply > totalCurveCapacity) {
            revert IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__SupplyExceedsCurveCapacity(
                currentTotalIssuanceSupply,
                totalCurveCapacity
            );
        }
    }

    /**
     * @notice Calculates the cumulative supply of all segments before a given segment index.
     * @dev Helper function for gas optimization.
     * @param segments Array of PackedSegment configurations for the curve.
     * @param segmentIndex The index of the segment *after* which cumulative supply is counted.
     * @return cumulative The total supply from segments 0 to segmentIndex-1.
     */
    function _getCumulativeSupplyBeforeSegment(
        PackedSegment[] memory segments,
        uint256 segmentIndex
    ) private pure returns (uint256 cumulative) {
        // cumulative is initialized to 0 by default
        for (uint256 i = 0; i < segmentIndex; ++i) {
            // Ensure i is within bounds, though loop condition should handle this.
            // This check is more for robustness if segmentIndex could be out of range from an external call,
            // but as a private helper called internally with validated segmentIndex, it's less critical.
            // if (i >= segments.length) break; // Should not happen with correct usage
            (,, uint256 sPerStep, uint256 nSteps) = segments[i].unpack(); // Batch unpack
            cumulative += nSteps * sPerStep;
        }
        return cumulative;
    }

    /**
     * @notice Finds the segment, step, price, and cumulative supply for a given target total issuance supply.
     * @dev Iterates linearly through segments.
     * @param segments Array of PackedSegment configurations for the curve.
     * @param targetTotalIssuanceSupply The total supply for which to find the position.
     * @return pos A CurvePosition struct detailing the location on the curve.
     */
    function _findPositionForSupply(
        PackedSegment[] memory segments,
        uint256 targetTotalIssuanceSupply
    ) internal pure returns (CurvePosition memory pos) {
        uint256 segLen = segments.length; // Cache length
        if (segLen == 0) {
            revert IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__NoSegmentsConfigured();
        }
        if (segLen > MAX_SEGMENTS) {
            // This check is also in validateSegmentArray, but good for internal consistency
            revert IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__TooManySegments();
        }

        uint256 cumulativeSupply = 0;
        // pos members are initialized to 0 by default

        for (uint256 i = 0; i < segLen; ++i) { // Use cached length
            // Note: supplyPerStep within the segment is guaranteed > 0 by PackedSegmentLib.create validation.
            (uint256 initialPrice, uint256 priceIncrease, uint256 supplyPerStep, uint256 stepsInSegment) = segments[i].unpack();

            uint256 supplyInCurrentSegment = stepsInSegment * supplyPerStep;
            uint256 endOfCurrentSegmentSupply = cumulativeSupply + supplyInCurrentSegment;

            if (targetTotalIssuanceSupply < endOfCurrentSegmentSupply) {
                // Case 1: Target supply is strictly WITHIN the current segment.
                pos.segmentIndex = i;
                uint256 supplyNeededFromThisSegment = targetTotalIssuanceSupply - cumulativeSupply;
                // supplyPerStep is guaranteed > 0 by PackedSegmentLib.create
                pos.stepIndexWithinSegment = supplyNeededFromThisSegment / supplyPerStep; 
                pos.priceAtCurrentStep = initialPrice + (pos.stepIndexWithinSegment * priceIncrease);
                pos.supplyCoveredUpToThisPosition = targetTotalIssuanceSupply;
                return pos;
            } else if (targetTotalIssuanceSupply == endOfCurrentSegmentSupply) {
                // Case 2: Target supply is EXACTLY AT THE END of the current segment.
                pos.supplyCoveredUpToThisPosition = targetTotalIssuanceSupply;
                if (i + 1 < segLen) { // Use cached length
                    // There is a next segment. Position is start of next segment.
                    pos.segmentIndex = i + 1;
                    pos.stepIndexWithinSegment = 0;
                    // Unpack segments[i+1] to get its initialPrice
                    (uint256 nextInitialPrice,,,) = segments[i + 1].unpack();
                    pos.priceAtCurrentStep = nextInitialPrice; // Price is initial of next segment
                } else {
                    // This is the last segment. Position is the last step of this current (last) segment.
                    pos.segmentIndex = i;
                    // stepsInSegment is guaranteed > 0 by PackedSegmentLib.create
                    pos.stepIndexWithinSegment = stepsInSegment - 1; 
                    pos.priceAtCurrentStep = initialPrice + (pos.stepIndexWithinSegment * priceIncrease);
                }
                return pos;
            } else {
                // Case 3: Target supply is BEYOND the current segment.
                // Continue to the next segment.
                cumulativeSupply = endOfCurrentSegmentSupply;
            }
        }

        // Target supply is beyond all configured segments
        pos.segmentIndex = segLen - 1; // Indicates the last segment, use cached length
        // pos.stepIndexWithinSegment will be the last step of the last segment
        // Unpack the last segment once
        (uint256 lastInitialPrice, uint256 lastPriceIncrease,, uint256 lastNumberOfSteps) = segments[segLen - 1].unpack();
        pos.stepIndexWithinSegment = lastNumberOfSteps > 0 ? lastNumberOfSteps - 1 : 0;
        pos.priceAtCurrentStep = lastInitialPrice + (pos.stepIndexWithinSegment * lastPriceIncrease);
        pos.supplyCoveredUpToThisPosition = cumulativeSupply; // Total supply covered by all segments
        // The caller should check if pos.supplyCoveredUpToThisPosition < targetTotalIssuanceSupply
        // to understand if the target was fully met.
        return pos;
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
        CurvePosition memory pos = _findPositionForSupply(segments, currentTotalIssuanceSupply);

        // Validate that currentTotalIssuanceSupply is within curve bounds.
        // _findPositionForSupply sets pos.supplyCoveredUpToThisPosition to the maximum supply
        // of the curve if targetTotalIssuanceSupply is beyond the curve's capacity.
        // If currentTotalIssuanceSupply is 0, pos.supplyCoveredUpToThisPosition will also be 0.
        // Thus, (0 > 0) is false, no revert.
        // If currentTotalIssuanceSupply > 0 and within capacity, pos.supplyCoveredUpToThisPosition == currentTotalIssuanceSupply.
        // Thus, (X > X) is false, no revert.
        // If currentTotalIssuanceSupply > 0 and beyond capacity, pos.supplyCoveredUpToThisPosition is max capacity.
        // Thus, (currentTotalIssuanceSupply > max_capacity) is true, causing a revert.
        if (currentTotalIssuanceSupply > pos.supplyCoveredUpToThisPosition) {
            revert IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__TargetSupplyBeyondCurveCapacity();
        }
        
        // Since _findPositionForSupply (after its own fix for Issue 1) now correctly handles
        // segment boundaries by pointing to the start of the next segment (or the last step of the
        // last segment if at max capacity), and returns the price/step for that position,
        // we can directly use its output. The complex adjustment logic previously here is no longer needed.
        return (pos.priceAtCurrentStep, pos.stepIndexWithinSegment, pos.segmentIndex);
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
        uint256 segLen = segments.length; // Cache length
        if (segLen == 0) {
            revert IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__NoSegmentsConfigured();
        }
        // No MAX_SEGMENTS check here as _findPositionForSupply would have caught it if it was an issue for positioning,
        // and this function just iterates. If segments array is too long, it's a deployment/config issue.

        uint256 cumulativeSupplyProcessed = 0;
        // totalReserve is initialized to 0 by default

        for (uint256 i = 0; i < segLen; ++i) { // Use cached length
            if (cumulativeSupplyProcessed >= targetSupply) {
                break; // All target supply has been accounted for.
            }

            // Unpack segment data - using batch unpack as per instruction suggestion for this case
            (
                uint256 pInitial,
                uint256 pIncrease,
                uint256 sPerStep,
                uint256 nSteps
            ) = segments[i].unpack();
            // Note: sPerStep is guaranteed > 0 by PackedSegmentLib.create validation.

            uint256 supplyRemainingInTarget = targetSupply - cumulativeSupplyProcessed;
            
            // Calculate how many steps from *this* segment are needed to cover supplyRemainingInTarget
            // Ceiling division: (numerator + denominator - 1) / denominator
            uint256 nStepsToProcessThisSeg = (supplyRemainingInTarget + sPerStep - 1) / sPerStep;

            // Cap at the segment's actual available steps
            if (nStepsToProcessThisSeg > nSteps) {
                nStepsToProcessThisSeg = nSteps;
            }

            uint256 collateralForPortion;
            if (pIncrease == 0) {
                // Flat segment
                collateralForPortion = (nStepsToProcessThisSeg * sPerStep * pInitial) / SCALING_FACTOR;
            } else {
                // Sloped segment: sum of an arithmetic series
                // S_n = n/2 * (2a + (n-1)d)
                // Here, n = nStepsToProcessThisSeg, a = pInitial, d = pIncrease
                // Each term (price) is multiplied by sPerStep and divided by SCALING_FACTOR.
                // Collateral = sPerStep/SCALING_FACTOR * Sum_{k=0}^{n-1} (pInitial + k*pIncrease)
                // Collateral = sPerStep/SCALING_FACTOR * (n*pInitial + pIncrease * n*(n-1)/2)
                // Collateral = (sPerStep * n * (2*pInitial + (n-1)*pIncrease)) / (2 * SCALING_FACTOR)
                // where n is nStepsToProcessThisSeg.
                // termVal = (2 * pInitial) + (nStepsToProcessThisSeg > 0 ? (nStepsToProcessThisSeg - 1) * pIncrease : 0)
                // collateralForPortion = (sPerStep * nStepsToProcessThisSeg * termVal) / (2 * SCALING_FACTOR)

                if (nStepsToProcessThisSeg == 0) {
                    collateralForPortion = 0;
                } else {
                    uint256 firstTermPrice = pInitial;
                    uint256 lastTermPrice = pInitial + (nStepsToProcessThisSeg - 1) * pIncrease;
                    // Sum of arithmetic series = num_terms * (first_term + last_term) / 2
                    uint256 sumOfPrices = nStepsToProcessThisSeg * (firstTermPrice + lastTermPrice) / 2;
                    collateralForPortion = (sPerStep * sumOfPrices) / SCALING_FACTOR;
                }
            }

            totalReserve += collateralForPortion;
            cumulativeSupplyProcessed += nStepsToProcessThisSeg * sPerStep;
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
     * @param collateralAmountIn The amount of collateral being provided for purchase.
     * @param currentTotalIssuanceSupply The current total supply before this purchase.
     * @return issuanceAmountOut The total amount of issuance tokens minted.
     * @return collateralAmountSpent The actual amount of collateral spent.
     */
    function calculatePurchaseReturn(
        PackedSegment[] memory segments,
        uint256 collateralAmountIn,
        uint256 currentTotalIssuanceSupply
    ) internal pure returns (uint256 issuanceAmountOut, uint256 collateralAmountSpent) {
        _validateSupplyAgainstSegments(segments, currentTotalIssuanceSupply);

        if (collateralAmountIn == 0) {
            revert IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__ZeroCollateralInput();
        }
        // Note: segments.length == 0 case is handled by _validateSupplyAgainstSegments if currentTotalIssuanceSupply > 0.
        // If currentTotalIssuanceSupply is 0, and segments.length is 0, _validateSupplyAgainstSegments returns.
        // However, getCurrentPriceAndStep would then revert due to NoSegmentsConfigured if called.
        // For safety and explicitness, keeping the direct check here if collateralAmountIn > 0.
        uint256 segLen = segments.length; // Cache length
        if (segLen == 0) { // This implies currentTotalIssuanceSupply must be 0 from validation above.
             // If collateralAmountIn > 0, but no segments, cannot purchase.
            revert IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__NoSegmentsConfigured();
        }
        
        uint256 totalIssuanceAmountOut = 0;
        uint256 totalCollateralSpent = 0;
        uint256 remainingCollateral = collateralAmountIn;

        (
            uint256 priceAtPurchaseStart,
            uint256 stepAtPurchaseStart,
            uint256 segmentAtPurchaseStart
        ) = getCurrentPriceAndStep(segments, currentTotalIssuanceSupply);

        for (uint256 i = segmentAtPurchaseStart; i < segLen; ++i) { // Use cached length
            if (remainingCollateral == 0) {
                break; 
            }

            uint256 currentSegmentStartStepForHelper;
            uint256 priceAtCurrentSegmentStartStepForHelper;
            PackedSegment currentSegment = segments[i];
            // Unpack currentSegment once here
            (uint256 csInitialPrice,,, uint256 csNumberOfSteps) = currentSegment.unpack();


            if (i == segmentAtPurchaseStart) {
                currentSegmentStartStepForHelper = stepAtPurchaseStart;
                priceAtCurrentSegmentStartStepForHelper = priceAtPurchaseStart;
            } else {
                currentSegmentStartStepForHelper = 0;
                priceAtCurrentSegmentStartStepForHelper = csInitialPrice; // Use unpacked value
            }
            
            if (currentSegmentStartStepForHelper >= csNumberOfSteps) { // Use unpacked value
                continue; 
            }

            (uint256 issuanceBoughtThisSegment, uint256 collateralSpentThisSegment) =
                _calculatePurchaseForSingleSegment(
                    currentSegment,
                    remainingCollateral,
                    currentSegmentStartStepForHelper,
                    priceAtCurrentSegmentStartStepForHelper
                );

            totalIssuanceAmountOut += issuanceBoughtThisSegment;
            totalCollateralSpent += collateralSpentThisSegment;
            remainingCollateral -= collateralSpentThisSegment;
        }
        return (totalIssuanceAmountOut, totalCollateralSpent);
    }

    /**
     * @notice Helper function to calculate the issuance and collateral for full steps in a non-free flat segment.
     * @param _budget The collateral budget available.
     * @param _priceAtSegmentInitialStep The price for each step in this flat segment.
     * @param _sPerStepSeg The supply per step in this segment.
     * @param _stepsAvailableToPurchaseInSeg The number of steps available for purchase in this segment.
     * @return issuanceOut The total issuance from full steps.
     * @return collateralSpent The total collateral spent for these full steps.
     */
    function _calculateFullStepsForFlatSegment(
        uint256 _budget,
        uint256 _priceAtSegmentInitialStep,
        uint256 _sPerStepSeg,
        uint256 _stepsAvailableToPurchaseInSeg
    ) private pure returns (uint256 issuanceOut, uint256 collateralSpent) {
        // Calculate full steps for flat segment
        // _priceAtSegmentInitialStep is guaranteed non-zero when this function is called.
        uint256 maxFullStepsIssuanceByBudget = (_budget * SCALING_FACTOR) / _priceAtSegmentInitialStep;
        uint256 numFullStepsAffordable = maxFullStepsIssuanceByBudget / _sPerStepSeg;

        if (numFullStepsAffordable > _stepsAvailableToPurchaseInSeg) {
            numFullStepsAffordable = _stepsAvailableToPurchaseInSeg;
        }
        issuanceOut = numFullStepsAffordable * _sPerStepSeg;
        collateralSpent = (issuanceOut * _priceAtSegmentInitialStep) / SCALING_FACTOR;
        return (issuanceOut, collateralSpent);
    }

    /**
     * @notice Helper function to calculate purchase return for a single sloped segment using linear search.
     * @dev Iterates step-by-step to find affordable steps. More gas-efficient for small number of steps.
     * @param segment The PackedSegment to process.
     * @param budget The amount of collateral available for this segment.
     * @param startStep The starting step index within this segment for the current purchase (0-indexed within the segment's own steps).
     * @param startPrice The price at the `startStep`.
     * @return issuanceOut The issuance tokens bought from this segment.
     * @return collateralSpent The collateral spent for this segment.
     */
    function _linearSearchSloped(
        PackedSegment segment,
        uint256 budget,
        uint256 startStep, // This is the step index *within the current segment* where the purchase attempt begins
        uint256 startPrice // This is the price at `startStep`
    ) private pure returns (uint256 issuanceOut, uint256 collateralSpent) {
        (, uint256 priceIncrease, uint256 sPerStep, uint256 numberOfStepsInSegment) = segment.unpack();
        
        // Calculate the maximum number of steps that can possibly be purchased in this segment 
        // from the given startStep.
        if (startStep >= numberOfStepsInSegment) { // Should not happen if called correctly
            return (0, 0);
        }
        uint256 maxStepsAvailableToPurchase = numberOfStepsInSegment - startStep;

        uint256 currentPrice = startPrice;
        uint256 stepsCovered = 0;
        // collateralSpent is already a return variable, can use it directly.

        // Iterate while there are steps available and budget allows
        while (stepsCovered < maxStepsAvailableToPurchase) {
            uint256 stepCost = (sPerStep * currentPrice) / SCALING_FACTOR;

            if (collateralSpent + stepCost <= budget) {
                collateralSpent += stepCost;
                stepsCovered++;
                currentPrice += priceIncrease; // Price for the *next* step
            } else {
                break; // Cannot afford the current step at currentPrice
            }
        }

        issuanceOut = stepsCovered * sPerStep;
        return (issuanceOut, collateralSpent);
    }

    /**
     * @notice Helper function to calculate purchase return for a single segment.
     * @dev Contains logic for flat segments and uses linear search for sloped segments.
     *      This function is designed to reduce stack depth in `calculatePurchaseReturn`.
     * @param segment The PackedSegment to process.
     * @param remainingCollateralIn The amount of collateral available for this segment.
     * @param segmentInitialStep The starting step index within this segment for the current purchase.
     * @param priceAtSegmentInitialStep The price at the `segmentInitialStep`.
     * @return issuanceOut The issuance tokens bought from this segment.
     * @return collateralSpent The collateral spent for this segment.
     */
    function _calculatePurchaseForSingleSegment(
        PackedSegment segment,
        uint256 remainingCollateralIn,
        uint256 segmentInitialStep,
        uint256 priceAtSegmentInitialStep
    ) private pure returns (uint256 issuanceOut, uint256 collateralSpent) {
        // Unpack segment details once at the beginning
        (, uint256 pIncreaseSeg, uint256 sPerStepSeg, uint256 nStepsSeg) = segment.unpack();

        // Note: sPerStepSeg is guaranteed > 0 by PackedSegmentLib.create validation.

        // Guard: segmentInitialStep is out of bounds for the segment
        if (segmentInitialStep >= nStepsSeg) { 
            revert IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__InvalidSegmentInitialStep();
        }

        uint256 stepsAvailableToPurchaseInSeg = nStepsSeg - segmentInitialStep;
        // issuanceOut and collateralSpent are implicitly initialized to 0 as return variables.

        if (pIncreaseSeg == 0) { // Flat Segment Logic
            if (priceAtSegmentInitialStep == 0) { // Entirely free mint part of the segment
                issuanceOut = stepsAvailableToPurchaseInSeg * sPerStepSeg;
                // collateralSpent is implicitly 0 as a return variable
                return (issuanceOut, 0); // Early return for free mint
            } else { // Non-free flat part
                // Calculate full steps for flat segment
                (issuanceOut, collateralSpent) = _calculateFullStepsForFlatSegment(
                    remainingCollateralIn,
                    priceAtSegmentInitialStep,
                    sPerStepSeg,
                    stepsAvailableToPurchaseInSeg
                );

                // Determine parameters for partial purchase (declare just-in-time)
                uint256 remainingBudgetForPartial = remainingCollateralIn - collateralSpent;
                // For flat segments, priceForPartialStep is the same as priceAtSegmentInitialStep
                // uint256 priceForPartialStep = priceAtSegmentInitialStep; // Not strictly needed as var, can pass directly
                uint256 maxIssuancePossibleInSegmentAfterFullSteps = (stepsAvailableToPurchaseInSeg * sPerStepSeg) - issuanceOut;
                uint256 numFullStepsBought = issuanceOut / sPerStepSeg; 

                // Check if a partial purchase is viable and should be attempted
                if (numFullStepsBought < stepsAvailableToPurchaseInSeg && remainingBudgetForPartial > 0 && maxIssuancePossibleInSegmentAfterFullSteps > 0) {
                    (uint256 pIssuance, uint256 pCost) = _calculatePartialPurchaseAmount(
                        remainingBudgetForPartial,
                        priceAtSegmentInitialStep, // Pass directly
                        sPerStepSeg, 
                        maxIssuancePossibleInSegmentAfterFullSteps
                    );
                    issuanceOut += pIssuance;
                    collateralSpent += pCost;
                }
            }
        } else { // Sloped Segment Logic
            // Calculate full steps using linear search
            (uint256 fullStepIssuance, uint256 fullStepCollateralSpent) = _linearSearchSloped(
                segment, // segment is already unpacked in _linearSearchSloped
                remainingCollateralIn, 
                segmentInitialStep,    
                priceAtSegmentInitialStep 
            );

            issuanceOut = fullStepIssuance;
            collateralSpent = fullStepCollateralSpent;
            
            uint256 numFullStepsBought = fullStepIssuance / sPerStepSeg; 
            
            // Determine parameters for partial purchase (declare just-in-time)
            uint256 remainingBudgetForPartial = remainingCollateralIn - collateralSpent;
            uint256 priceForPartialStep = priceAtSegmentInitialStep + (numFullStepsBought * pIncreaseSeg);
            uint256 maxIssuancePossibleInSegmentAfterFullSteps = (stepsAvailableToPurchaseInSeg * sPerStepSeg) - issuanceOut;

            // Check if a partial purchase is viable and should be attempted
            // numFullStepsBought is relative to segmentInitialStep. stepsAvailableToPurchaseInSeg is total steps from segmentInitialStep.
            if (numFullStepsBought < stepsAvailableToPurchaseInSeg && remainingBudgetForPartial > 0 && maxIssuancePossibleInSegmentAfterFullSteps > 0) {
                // Note: _calculatePartialPurchaseAmount handles if priceForPartialStep is 0 (free mint)
                (uint256 pIssuance, uint256 pCost) = _calculatePartialPurchaseAmount(
                    remainingBudgetForPartial,
                    priceForPartialStep,
                    sPerStepSeg, // Max for one partial step slot
                    maxIssuancePossibleInSegmentAfterFullSteps
                );
                issuanceOut += pIssuance;
                collateralSpent += pCost;
            }
        }
        // Implicitly returns issuanceOut, collateralSpent
    }

    /**
     * @notice Calculates the amount of partial issuance and its cost given budget and various constraints.
     * @param _budget The remaining collateral available for this partial purchase.
     * @param _priceForPartialStep The price at which this partial issuance is to be bought.
     * @param _supplyPerFullStep The maximum issuance normally available in one full step (sPerStep).
     * @param _maxIssuanceAllowedOverall The maximum total partial issuance allowed by remaining segment capacity.
     * @return partialIssuance_ The amount of tokens to be issued for the partial purchase.
     * @return partialCost_ The collateral cost for the partialIssuance_.
     */
    function _calculatePartialPurchaseAmount(
        uint256 _budget,
        uint256 _priceForPartialStep,
        uint256 _supplyPerFullStep, // Typically sPerStep from the segment
        uint256 _maxIssuanceAllowedOverall // e.g., (total steps left * sPerStep) - full steps already bought
    ) private pure returns (uint256 partialIssuance_, uint256 partialCost_) {
        // Handle zero price (free mint) or zero budget scenarios first
        // Note: The _budget == 0 case is guarded by the caller (_calculatePurchaseForSingleSegment),
        // which only calls this function if remainingBudgetForPartial > 0.
        if (_priceForPartialStep == 0) {
            // For free mints, take up to _supplyPerFullStep, further capped by _maxIssuanceAllowedOverall
            partialIssuance_ = _supplyPerFullStep < _maxIssuanceAllowedOverall ? _supplyPerFullStep : _maxIssuanceAllowedOverall;
            // No cost for free mints
            partialCost_ = 0;
            return (partialIssuance_, partialCost_);
        }

        // 1. Calculate issuance strictly based on budget
        uint256 issuanceFromBudget = (_budget * SCALING_FACTOR) / _priceForPartialStep;

        // 2. Determine effective issuance: apply caps sequentially
        // Start with budget-limited issuance
        partialIssuance_ = issuanceFromBudget;

        // Cap by what a single (partial) step slot offers (_supplyPerFullStep)
        if (partialIssuance_ > _supplyPerFullStep) {
            partialIssuance_ = _supplyPerFullStep;
        }

        // Cap by the overall maximum issuance allowed for this partial purchase in the segment
        if (partialIssuance_ > _maxIssuanceAllowedOverall) {
            partialIssuance_ = _maxIssuanceAllowedOverall;
        }
        // Now partialIssuance_ is min(issuanceFromBudget, _supplyPerFullStep, _maxIssuanceAllowedOverall)

        // 3. Calculate cost for this determined partialIssuance_
        partialCost_ = (partialIssuance_ * _priceForPartialStep) / SCALING_FACTOR;

        // 4. Final budget adherence: If the calculated cost (after capping issuance)
        //    is still greater than the budget. This ensures we never spend more than _budget.
        if (partialCost_ > _budget) {
            partialCost_ = _budget;
            // Recalculate issuance based on spending the exact budget
            // (_priceForPartialStep is non-zero here due to earlier check)
            partialIssuance_ = (partialCost_ * SCALING_FACTOR) / _priceForPartialStep;
        }

        // Assertions to ensure invariants hold
        assert(partialCost_ <= _budget); // Cost should not exceed budget
        assert(partialIssuance_ <= _maxIssuanceAllowedOverall); // Issuance should not exceed overall segment allowance
        // If _priceForPartialStep > 0, then partialIssuance_ is also capped by _supplyPerFullStep due to the logic above.
        // If _priceForPartialStep == 0 (free mint), partialIssuance_ is min(_supplyPerFullStep, _maxIssuanceAllowedOverall).
        // So, this assertion should hold in both cases.
        assert(partialIssuance_ <= _supplyPerFullStep); 

        return (partialIssuance_, partialCost_);
    }


    /**
     * @notice Calculates the amount of collateral returned for selling a given amount of issuance tokens.
     * @dev Uses the difference in reserve at current supply and supply after sale.
     * @param segments Array of PackedSegment configurations for the curve.
     * @param issuanceAmountIn The amount of issuance tokens being sold.
     * @param currentTotalIssuanceSupply The current total supply before this sale.
     * @return collateralAmountOut The total amount of collateral returned to the seller.
     * @return issuanceAmountBurned The actual amount of issuance tokens burned (capped at current supply).
     */
    function calculateSaleReturn(
        PackedSegment[] memory segments,
        uint256 issuanceAmountIn,
        uint256 currentTotalIssuanceSupply
    ) internal pure returns (uint256 collateralAmountOut, uint256 issuanceAmountBurned) {
        _validateSupplyAgainstSegments(segments, currentTotalIssuanceSupply);

        if (issuanceAmountIn == 0) {
            revert IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__ZeroIssuanceInput();
        }
        
        // Note: segments.length == 0 case is handled by _validateSupplyAgainstSegments if currentTotalIssuanceSupply > 0.
        // If currentTotalIssuanceSupply is 0 (and segments.length is 0), _validateSupplyAgainstSegments returns.
        // Then issuanceAmountBurned will be 0 (as currentTotalIssuanceSupply is 0), and (0,0) will be returned.
        // If segments.length == 0 but currentTotalIssuanceSupply > 0, _validateSupplyAgainstSegments would have reverted.
        // If segments.length > 0, proceed.
        uint256 segLen = segments.length; // Cache length
        if (segLen == 0) { // This implies currentTotalIssuanceSupply must be 0.
            // Selling from 0 supply on an unconfigured curve. issuanceAmountBurned will be 0.
            // The check below `if (issuanceAmountBurned == 0)` handles returning (0,0).
            // No explicit revert here as _validateSupplyAgainstSegments covers invalid states.
        }


        issuanceAmountBurned = issuanceAmountIn > currentTotalIssuanceSupply ? currentTotalIssuanceSupply : issuanceAmountIn;

        if (issuanceAmountBurned == 0) { // Possible if issuanceAmountIn > 0 but currentTotalIssuanceSupply is 0
            return (0, 0);
        }

        uint256 finalSupplyAfterSale = currentTotalIssuanceSupply - issuanceAmountBurned;

        uint256 collateralAtCurrentSupply = calculateReserveForSupply(segments, currentTotalIssuanceSupply);
        uint256 collateralAtFinalSupply = calculateReserveForSupply(segments, finalSupplyAfterSale);

        if (collateralAtCurrentSupply < collateralAtFinalSupply) {
            // This should not happen with a correctly defined bonding curve (prices are non-negative).
            // It would imply that reducing supply *increases* the reserve.
            // Consider reverting or handling as an internal error. For now, assume valid curve.
            // This could be an assertion `assert(collateralAtCurrentSupply >= collateralAtFinalSupply)`.
            // For robustness, can return 0 or revert. Reverting might be too strict if it's due to dust.
            // Returning 0 collateral if this unexpected state occurs.
            return (0, issuanceAmountBurned); // Or revert with a specific error.
        }

        collateralAmountOut = collateralAtCurrentSupply - collateralAtFinalSupply;

        return (collateralAmountOut, issuanceAmountBurned);
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
        uint256 segLen = segments.length; // Cache length
        if (segLen == 0) {
            revert IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__NoSegmentsConfigured();
        }
        if (segLen > MAX_SEGMENTS) {
            revert IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__TooManySegments();
        }

        // Note: Individual segment's supplyPerStep > 0 and numberOfSteps > 0 
        // are guaranteed by PackedSegmentLib.create validation.
        // This function primarily validates array-level properties.
        for (uint256 i = 0; i < segLen; ++i) { // Use cached length
            // The check for segments[i].supplyPerStep() == 0 was removed as it's redundant.
            // Similarly, numberOfSteps > 0 is also guaranteed by PackedSegmentLib.create.
            // If other per-segment validations were needed here (that aren't covered by create), they could be added.
        }
    }
}
