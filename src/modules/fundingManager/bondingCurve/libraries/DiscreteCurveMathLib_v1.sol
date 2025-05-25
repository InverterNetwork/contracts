// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.19;

import {IDiscreteCurveMathLib_v1} from "../interfaces/IDiscreteCurveMathLib_v1.sol";
import {PackedSegment} from "../types/PackedSegment_v1.sol";

/**
 * @title DiscreteCurveMathLib_v1
 * @notice Library for mathematical operations on discrete bonding curves.
 * @dev This library uses packed storage for curve segments to optimize gas costs.
 * It provides functions to calculate prices, reserves, and purchase/sale returns.
 */
// --- PackedSegmentLib: Library for PackedSegment Manipulation ---

/**
 * @title PackedSegmentLib
 * @notice Library for creating and accessing data within a PackedSegment.
 * @dev This library handles the bitwise operations for packing and unpacking segment data.
 *
 * Layout (256 bits total):
 * - initialPriceOfSegment (72 bits): Offset 0
 * - priceIncreasePerStep (72 bits): Offset 72
 * - supplyPerStep (96 bits): Offset 144
 * - numberOfSteps (16 bits): Offset 240
 */
library PackedSegmentLib {
    // Bit field specifications (matching PackedSegment_v1.sol documentation)
    uint256 private constant INITIAL_PRICE_BITS = 72; // Max: ~4.722e21 (scaled by 1e18 -> ~$4,722)
    uint256 private constant PRICE_INCREASE_BITS = 72; // Max: ~4.722e21 (scaled by 1e18 -> ~$4,722)
    uint256 private constant SUPPLY_BITS = 96; // Max: ~7.9e28 (scaled by 1e18 -> ~79 billion tokens)
    uint256 private constant STEPS_BITS = 16; // Max: 65,535 steps

    // Masks for extracting data
    uint256 private constant INITIAL_PRICE_MASK = (1 << INITIAL_PRICE_BITS) - 1;
    uint256 private constant PRICE_INCREASE_MASK = (1 << PRICE_INCREASE_BITS) - 1;
    uint256 private constant SUPPLY_MASK = (1 << SUPPLY_BITS) - 1;
    uint256 private constant STEPS_MASK = (1 << STEPS_BITS) - 1;

    // Bit offsets for packing data
    uint256 private constant INITIAL_PRICE_OFFSET = 0; // Not strictly needed for initial price, but good for consistency
    uint256 private constant PRICE_INCREASE_OFFSET = INITIAL_PRICE_BITS; // 72
    uint256 private constant SUPPLY_OFFSET = INITIAL_PRICE_BITS + PRICE_INCREASE_BITS; // 72 + 72 = 144
    uint256 private constant STEPS_OFFSET = INITIAL_PRICE_BITS + PRICE_INCREASE_BITS + SUPPLY_BITS; // 144 + 96 = 240

    /**
     * @notice Creates a new PackedSegment from individual configuration parameters.
     * @dev Validates inputs against bitfield limits.
     * @param _initialPrice The initial price for this segment.
     * @param _priceIncrease The price increase per step for this segment.
     * @param _supplyPerStep The supply minted per step for this segment.
     * @param _numberOfSteps The number of steps in this segment.
     * @return newSegment The newly created PackedSegment.
     */
    function create(
        uint256 _initialPrice,
        uint256 _priceIncrease,
        uint256 _supplyPerStep,
        uint256 _numberOfSteps
    ) internal pure returns (PackedSegment newSegment) {
        if (_initialPrice > INITIAL_PRICE_MASK) {
            revert IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__InitialPriceTooLarge();
        }
        if (_priceIncrease > PRICE_INCREASE_MASK) {
            revert IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__PriceIncreaseTooLarge();
        }
        if (_supplyPerStep == 0) {
            revert IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__ZeroSupplyPerStep();
        }
        if (_supplyPerStep > SUPPLY_MASK) {
            revert IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__SupplyPerStepTooLarge();
        }
        if (_numberOfSteps == 0 || _numberOfSteps > STEPS_MASK) {
            revert IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__InvalidNumberOfSteps();
        }
        // Additional check from my analysis: ensure segment has some value if it's not free
        if (_initialPrice == 0 && _priceIncrease == 0 && _supplyPerStep > 0 && _numberOfSteps > 0) {
            // This is a free mint segment, which can be valid.
            // If we want to disallow segments that are entirely free AND have no price increase,
            // an additional check could be added here. For now, assuming free mints are allowed.
        }


        bytes32 packed = bytes32(
            _initialPrice |
                (_priceIncrease << PRICE_INCREASE_OFFSET) |
                (_supplyPerStep << SUPPLY_OFFSET) |
                (_numberOfSteps << STEPS_OFFSET)
        );
        return PackedSegment.wrap(packed);
    }

    /**
     * @notice Retrieves the initial price from a PackedSegment.
     * @param self The PackedSegment.
     * @return price The initial price.
     */
    function initialPrice(PackedSegment self) internal pure returns (uint256 price) {
        return uint256(PackedSegment.unwrap(self)) & INITIAL_PRICE_MASK;
    }

    /**
     * @notice Retrieves the price increase per step from a PackedSegment.
     * @param self The PackedSegment.
     * @return increase The price increase per step.
     */
    function priceIncrease(PackedSegment self) internal pure returns (uint256 increase) {
        return (uint256(PackedSegment.unwrap(self)) >> PRICE_INCREASE_OFFSET) & PRICE_INCREASE_MASK;
    }

    /**
     * @notice Retrieves the supply per step from a PackedSegment.
     * @param self The PackedSegment.
     * @return supply The supply per step.
     */
    function supplyPerStep(PackedSegment self) internal pure returns (uint256 supply) {
        return (uint256(PackedSegment.unwrap(self)) >> SUPPLY_OFFSET) & SUPPLY_MASK;
    }

    /**
     * @notice Retrieves the number of steps from a PackedSegment.
     * @param self The PackedSegment.
     * @return steps The number of steps.
     */
    function numberOfSteps(PackedSegment self) internal pure returns (uint256 steps) {
        return (uint256(PackedSegment.unwrap(self)) >> STEPS_OFFSET) & STEPS_MASK;
    }

    /**
     * @notice Unpacks all data fields from a PackedSegment.
     * @param self The PackedSegment.
     * @return initialPrice_ The initial price.
     * @return priceIncrease_ The price increase per step.
     * @return supplyPerStep_ The supply per step.
     * @return numberOfSteps_ The number of steps.
     */
    function unpack(PackedSegment self)
        internal
        pure
        returns (
            uint256 initialPrice_,
            uint256 priceIncrease_,
            uint256 supplyPerStep_,
            uint256 numberOfSteps_
        )
    {
        uint256 data = uint256(PackedSegment.unwrap(self));
        initialPrice_ = data & INITIAL_PRICE_MASK; // No shift needed as it's at offset 0
        priceIncrease_ = (data >> PRICE_INCREASE_OFFSET) & PRICE_INCREASE_MASK;
        supplyPerStep_ = (data >> SUPPLY_OFFSET) & SUPPLY_MASK;
        numberOfSteps_ = (data >> STEPS_OFFSET) & STEPS_MASK;
    }
}

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
        if (segments.length == 0) {
            revert IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__NoSegmentsConfigured();
        }
        if (segments.length > MAX_SEGMENTS) {
            // This check is also in validateSegmentArray, but good for internal consistency
            revert IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__TooManySegments();
        }

        uint256 cumulativeSupply = 0;
        // pos members are initialized to 0 by default

        for (uint256 i = 0; i < segments.length; ++i) {
            // Using individual accessors as per instruction example, can be batch unpacked too.
            uint256 initialPrice = segments[i].initialPrice();
            uint256 priceIncrease = segments[i].priceIncrease();
            uint256 supplyPerStep = segments[i].supplyPerStep();
            uint256 stepsInSegment = segments[i].numberOfSteps();

            // This check should ideally be done during segment validation/creation
            // but can be an assertion here if segments are externally provided without prior validation.
            // For now, assuming supplyPerStep > 0 due to PackedSegmentLib.create validation.
            // if (supplyPerStep == 0) { revert IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__ZeroSupplyPerStep(); }


            uint256 supplyInCurrentSegment = stepsInSegment * supplyPerStep;

            if (targetTotalIssuanceSupply <= cumulativeSupply + supplyInCurrentSegment) {
                // Target supply is within this segment or at its start
                pos.segmentIndex = i;
                uint256 supplyNeededFromThisSegment = targetTotalIssuanceSupply - cumulativeSupply;

                if (supplyPerStep == 0) { // Should be caught by create, but defensive
                     // If supplyPerStep is 0, and supplyNeeded is >0, it's an impossible state unless stepsInSegment is also 0.
                     // If supplyNeeded is 0, then stepIndex is 0.
                    pos.stepIndexWithinSegment = 0;
                } else {
                    pos.stepIndexWithinSegment = supplyNeededFromThisSegment / supplyPerStep; // Floor division
                }
                
                // Ensure stepIndexWithinSegment does not exceed the actual steps in the segment
                // This can happen if targetTotalIssuanceSupply is exactly at the boundary and supplyNeededFromThisSegment / supplyPerStep
                // results in stepsInSegment (e.g. 100 / 10 = 10, if stepsInSegment is 10, stepIndex is 9)
                if (pos.stepIndexWithinSegment >= stepsInSegment && stepsInSegment > 0) {
                    pos.stepIndexWithinSegment = stepsInSegment - 1; // Max step index is N-1
                }


                pos.priceAtCurrentStep = initialPrice + (pos.stepIndexWithinSegment * priceIncrease);
                pos.supplyCoveredUpToThisPosition = targetTotalIssuanceSupply;
                return pos;
            } else {
                cumulativeSupply += supplyInCurrentSegment;
            }
        }

        // Target supply is beyond all configured segments
        pos.segmentIndex = segments.length - 1; // Indicates the last segment
        // pos.stepIndexWithinSegment will be the last step of the last segment
        PackedSegment lastSegment = segments[segments.length - 1];
        pos.stepIndexWithinSegment = lastSegment.numberOfSteps() > 0 ? lastSegment.numberOfSteps() - 1 : 0;
        pos.priceAtCurrentStep = lastSegment.initialPrice() + (pos.stepIndexWithinSegment * lastSegment.priceIncrease());
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
        CurvePosition memory currentPos = _findPositionForSupply(segments, currentTotalIssuanceSupply);

        // Validate that currentTotalIssuanceSupply is within curve bounds.
        // _findPositionForSupply sets supplyCoveredUpToThisPosition to the max supply of the curve
        // if targetTotalIssuanceSupply is beyond the curve.
        // If currentTotalIssuanceSupply is 0, currentPos.supplyCoveredUpToThisPosition will be 0.
        if (currentTotalIssuanceSupply > 0 && currentTotalIssuanceSupply > currentPos.supplyCoveredUpToThisPosition) {
            revert IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__TargetSupplyBeyondCurveCapacity();
        }
        
        // If currentTotalIssuanceSupply is exactly 0, _findPositionForSupply correctly returns
        // segment 0, step 0, and its initial price. This is the "current" state.
        // The "next purchase" logic applies if we are about to mint the first token.

        price = currentPos.priceAtCurrentStep;
        stepIndex = currentPos.stepIndexWithinSegment;
        segmentIndex = currentPos.segmentIndex;

        // Handle boundary case: If currentTotalIssuanceSupply exactly filled a step,
        // the "current price" for the *next* action (like a purchase) should be the price of the next step.
        if (currentTotalIssuanceSupply > 0) { // Only adjust if some supply already exists
            PackedSegment currentSegment = segments[segmentIndex]; // Changed 'storage' to value type
            uint256 sPerStep = currentSegment.supplyPerStep();
            uint256 nSteps = currentSegment.numberOfSteps();
            
            // Calculate supply at the beginning of the current segment
            uint256 supplyAtStartOfCurrentSegment = currentPos.supplyCoveredUpToThisPosition - (sPerStep * (stepIndex + 1));
            // If currentTotalIssuanceSupply is a multiple of sPerStep relative to the start of its segment,
            // it means it exactly completes a step.
            if (sPerStep > 0 && (currentTotalIssuanceSupply - supplyAtStartOfCurrentSegment) % sPerStep == 0) {
                // It's the end of 'stepIndex'. We need the price/details for the next step.
                if (stepIndex < nSteps - 1) {
                    // More steps in the current segment
                    price = currentPos.priceAtCurrentStep + currentSegment.priceIncrease();
                    stepIndex = stepIndex + 1;
                } else {
                    // Last step of the current segment
                    if (segmentIndex < segments.length - 1) {
                        // More segments available
                        segmentIndex = segmentIndex + 1;
                        stepIndex = 0;
                        price = segments[segmentIndex].initialPrice();
                    } else {
                        // Last step of the last segment. No "next" step to advance to.
                        // The price and step remain as the final step's details.
                        // This indicates the curve is at max capacity for new pricing tiers.
                    }
                }
            }
        } else if (segments.length > 0) { 
            // currentTotalIssuanceSupply is 0. The "current" price is the initial price of the first segment.
            // If a purchase is made, it will be at this price.
            // The _findPositionForSupply already sets this up correctly.
            // No adjustment needed here for currentTotalIssuanceSupply == 0 based on the "next purchase" rule,
            // as the price returned by _findPositionForSupply IS the price for the first purchase.
        }


        return (price, stepIndex, segmentIndex);
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
        if (segments.length == 0) {
            revert IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__NoSegmentsConfigured();
        }
        // No MAX_SEGMENTS check here as _findPositionForSupply would have caught it if it was an issue for positioning,
        // and this function just iterates. If segments array is too long, it's a deployment/config issue.

        uint256 cumulativeSupplyProcessed = 0;
        // totalReserve is initialized to 0 by default

        for (uint256 i = 0; i < segments.length; ++i) {
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

            if (sPerStep == 0) { // Should be caught by create, but defensive
                continue; // Skip segments with no supply per step
            }

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
        if (collateralAmountIn == 0) {
            return (0, 0);
        }
        if (segments.length == 0) {
            revert IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__NoSegmentsConfigured();
        }

        uint256 totalIssuanceAmountOut = 0;
        uint256 totalCollateralSpent = 0;
        uint256 remainingCollateral = collateralAmountIn;

        // Determine the correct starting price and step for the purchase using getCurrentPriceAndStep
        (
            uint256 priceAtPurchaseStart, 
            uint256 stepAtPurchaseStart, 
            uint256 segmentAtPurchaseStart
        ) = getCurrentPriceAndStep(segments, currentTotalIssuanceSupply);

        for (uint256 i = segmentAtPurchaseStart; i < segments.length; ++i) {
            if (remainingCollateral == 0) {
                break; // No more collateral to spend.
            }

            (uint256 pInitialSeg, uint256 pIncreaseSeg, uint256 sPerStepSeg, uint256 nStepsSeg) = segments[i].unpack();

            if (sPerStepSeg == 0) continue; // Should not happen with validation

            uint256 currentSegmentStartStep;
            uint256 priceAtCurrentSegmentStartStep;

            if (i == segmentAtPurchaseStart) {
                currentSegmentStartStep = stepAtPurchaseStart;
                priceAtCurrentSegmentStartStep = priceAtPurchaseStart;
            } else {
                currentSegmentStartStep = 0; // Starting from the beginning of this new segment
                priceAtCurrentSegmentStartStep = pInitialSeg;
            }

            if (currentSegmentStartStep >= nStepsSeg) {
                continue; // This segment is already fully utilized or starting beyond its steps.
            }

            uint256 stepsAvailableInSeg = nStepsSeg - currentSegmentStartStep;
            uint256 issuanceBoughtThisSegment = 0;
            uint256 collateralSpentThisSegment = 0;

            if (pIncreaseSeg == 0) { // Flat Segment Logic
                if (priceAtCurrentSegmentStartStep == 0) { // Free mint segment
                    uint256 issuanceFromFlatFreeSegment = stepsAvailableInSeg * sPerStepSeg;
                    // No collateral spent for free mints
                    issuanceBoughtThisSegment = issuanceFromFlatFreeSegment;
                    // collateralSpentThisSegment remains 0
                } else {
                    uint256 maxIssuanceFromRemFlatSegment = stepsAvailableInSeg * sPerStepSeg;
                    uint256 costToBuyRemFlatSegment = (maxIssuanceFromRemFlatSegment * priceAtCurrentSegmentStartStep) / SCALING_FACTOR;

                    if (remainingCollateral >= costToBuyRemFlatSegment) {
                        issuanceBoughtThisSegment = maxIssuanceFromRemFlatSegment;
                        collateralSpentThisSegment = costToBuyRemFlatSegment;
                    } else {
                        // Partial purchase: how many sPerStepSeg units can be bought
                        issuanceBoughtThisSegment = (remainingCollateral * SCALING_FACTOR) / priceAtCurrentSegmentStartStep;
                        // Align to sPerStep boundaries (floor division)
                        issuanceBoughtThisSegment = (issuanceBoughtThisSegment / sPerStepSeg) * sPerStepSeg; 
                        collateralSpentThisSegment = (issuanceBoughtThisSegment * priceAtCurrentSegmentStartStep) / SCALING_FACTOR;
                    }
                }
            } else { // Sloped Segment Logic - Binary Search
                uint256 low = 0; // Min steps to buy
                uint256 high = stepsAvailableInSeg; // Max steps available
                uint256 best_n_steps_affordable = 0;
                uint256 cost_for_best_n_steps = 0;

                // Binary search for the maximum number of WHOLE steps affordable
                while (low <= high) {
                    uint256 mid_n = low + (high - low) / 2;
                    if (mid_n == 0) { // Cost is 0 for 0 steps, move low to 1 if high is not 0
                        if (high == 0) break; // if high is also 0, then 0 steps is the only option
                        low = 1; // ensure we test at least 1 step if possible
                        continue;
                    }

                    // Cost formula: (sPerStep * mid_n * (2*P_start + (mid_n-1)*P_increase)) / (2 * SCALING_FACTOR)
                    uint256 termVal = (2 * priceAtCurrentSegmentStartStep) + (mid_n - 1) * pIncreaseSeg;
                    uint256 cost_for_mid_n = (sPerStepSeg * mid_n * termVal) / (2 * SCALING_FACTOR);
                    
                    if (cost_for_mid_n <= remainingCollateral) {
                        best_n_steps_affordable = mid_n;
                        cost_for_best_n_steps = cost_for_mid_n;
                        low = mid_n + 1; // Try to afford more steps
                    } else {
                        high = mid_n - 1; // Too expensive
                    }
                }
                issuanceBoughtThisSegment = best_n_steps_affordable * sPerStepSeg;
                collateralSpentThisSegment = cost_for_best_n_steps;
            }

            totalIssuanceAmountOut += issuanceBoughtThisSegment;
            totalCollateralSpent += collateralSpentThisSegment;
            remainingCollateral -= collateralSpentThisSegment;

            // The loop will naturally break if remainingCollateral is 0 or if all segments are processed.
        }
        // The problem statement does not specify handling for "partial final step" beyond binary search for whole steps.
        // Any remainingCollateral not spent is implicitly returned to the user by them not spending it.
        return (totalIssuanceAmountOut, totalCollateralSpent);
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
        if (issuanceAmountIn == 0) {
            return (0, 0);
        }
        if (segments.length == 0) {
            // Cannot sell if there's no curve defined, implies no supply to sell or no reserve.
            // Or, if currentTotalIssuanceSupply is also 0, then 0 collateral makes sense.
            // If currentTotalIssuanceSupply > 0 but no segments, it's an inconsistent state.
            // Reverting seems safer if currentTotalIssuanceSupply > 0.
            // However, if currentTotalIssuanceSupply is 0, then issuanceAmountIn (capped) will be 0.
            if (currentTotalIssuanceSupply > 0) {
                 revert IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__NoSegmentsConfigured();
            } else {
                return (0,0); // Selling 0 from 0 supply.
            }
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
        if (segments.length == 0) {
            revert IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__NoSegmentsConfigured();
        }
        if (segments.length > MAX_SEGMENTS) {
            revert IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__TooManySegments();
        }

        for (uint256 i = 0; i < segments.length; ++i) {
            // Basic check: supplyPerStep must be > 0.
            // This is already enforced by PackedSegmentLib.create, so this is a redundant check
            // if segments are always created via PackedSegmentLib.create.
            // However, it's a good safeguard if segments could be sourced elsewhere (though unlikely with PackedSegment type).
            if (segments[i].supplyPerStep() == 0) {
                revert IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__ZeroSupplyPerStep();
            }
            // Could add other checks like ensuring numberOfSteps > 0, also covered by create.
        }
    }
}
