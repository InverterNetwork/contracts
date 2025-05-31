// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.19;

import {IDiscreteCurveMathLib_v1} from
    "../interfaces/IDiscreteCurveMathLib_v1.sol";
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
    // Enable clean syntax for PackedSegment instances: e.g., segment.initialPrice()
    using PackedSegmentLib for PackedSegment;

    // =========================================================================
    // Constants
    uint public constant SCALING_FACTOR = 1e18;
    uint public constant MAX_SEGMENTS = 10;

    // =========================================================================
    // Internal Helper Functions

    /**
     * @notice Validates that the provided currentTotalIssuanceSupply_ is consistent with the segment configuration.
     * @dev Reverts if segments_ are empty and supply > 0, or if supply exceeds total capacity of all segments_.
     * @param segments_ Array of PackedSegment configurations for the curve.
     * @param currentTotalIssuanceSupply_ The current total issuance supply to validate.
     */
    function _validateSupplyAgainstSegments(
        PackedSegment[] memory segments_,
        uint currentTotalIssuanceSupply_
    ) internal pure returns (uint totalCurveCapacity_) {
        // Added return type
        uint numSegments_ = segments_.length; // Cache length
        if (numSegments_ == 0) {
            if (currentTotalIssuanceSupply_ > 0) {
                // It's invalid to have a supply if no segments_ are defined to back it.
                revert
                    IDiscreteCurveMathLib_v1
                    .DiscreteCurveMathLib__NoSegmentsConfigured();
            }
            // If segments_.length == 0 and currentTotalIssuanceSupply_ == 0, it's a valid initial state.
            return 0; // Return 0 capacity
        }

        // totalCurveCapacity_ is initialized to 0 by default as a return variable
        for (
            uint segmentIndex_ = 0;
            segmentIndex_ < numSegments_;
            ++segmentIndex_
        ) {
            // Use cached length
            // Note: supplyPerStep and numberOfSteps are validated > 0 by PackedSegmentLib.create
            uint supplyPerStep_ = segments_[segmentIndex_]._supplyPerStep();
            uint numberOfStepsInSegment_ =
                segments_[segmentIndex_]._numberOfSteps();
            totalCurveCapacity_ += numberOfStepsInSegment_ * supplyPerStep_;
        }

        if (currentTotalIssuanceSupply_ > totalCurveCapacity_) {
            revert
                IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__SupplyExceedsCurveCapacity(
                currentTotalIssuanceSupply_, totalCurveCapacity_
            );
        }
        // Implicitly returns totalCurveCapacity_
    }

    /**
     * @notice Finds the segment, step, price, and cumulative supply for a given target total issuance supply.
     * @dev Iterates linearly through segments.
     * @param segments_ Array of PackedSegment configurations for the curve.
     * @param targetSupply_ The total supply for which to find the position.
     * @return position_ A CurvePosition struct detailing the location on the curve.
     */
    function _findPositionForSupply(
        PackedSegment[] memory segments_,
        uint targetSupply_ // Renamed from targetTotalIssuanceSupply
    )
        internal
        pure
        returns (IDiscreteCurveMathLib_v1.CurvePosition memory position_)
    {
        uint numSegments_ = segments_.length;
        if (numSegments_ == 0) {
            revert
                IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__NoSegmentsConfigured();
        }
        // Although callers like _getCurrentPriceAndStep might do their own MAX_SEGMENTS check via _validateSegmentArray,
        // _findPositionForSupply can be called by other internal logic, so keeping this is safer.
        if (numSegments_ > MAX_SEGMENTS) {
            revert
                IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__TooManySegments();
        }

        uint cumulativeSupply_ = 0;

        for (uint i_ = 0; i_ < numSegments_; ++i_) {
            (
                uint initialPrice_,
                uint priceIncreasePerStep_,
                uint supplyPerStep_,
                uint totalStepsInSegment_
            ) = segments_[i_]._unpack();

            uint segmentCapacity_ = totalStepsInSegment_ * supplyPerStep_;
            uint segmentEndSupply_ = cumulativeSupply_ + segmentCapacity_;

            if (targetSupply_ <= segmentEndSupply_) {
                // Found the segment where targetSupply_ resides or ends.
                position_.segmentIndex = i_;
                // supplyCoveredUpToThisPosition is critical for _getCurrentPriceAndStep validation.
                // If targetSupply_ is within this segment (or at its end), it's covered up to targetSupply_.
                position_.supplyCoveredUpToThisPosition = targetSupply_;

                if (targetSupply_ == segmentEndSupply_ && i_ + 1 < numSegments_)
                {
                    // Exactly at a boundary AND there's a next segment:
                    // Position points to the start of the next segment.
                    position_.segmentIndex = i_ + 1;
                    position_.stepIndexWithinSegment = 0;
                    // Price is the initial price of the next segment.
                    position_.priceAtCurrentStep =
                        segments_[i_ + 1]._initialPrice(); // Use direct accessor
                } else {
                    // Either within the current segment, or at the end of the *last* segment.
                    uint supplyIntoThisSegment_ =
                        targetSupply_ - cumulativeSupply_;
                    // stepIndex is the 0-indexed step that contains/is completed by supplyIntoThisSegment_.
                    // For "next price" semantic, this is the step whose price will be quoted.
                    position_.stepIndexWithinSegment =
                        supplyIntoThisSegment_ / supplyPerStep_;

                    // If at the end of the *last* segment, stepIndex needs to be the last step.
                    if (
                        targetSupply_ == segmentEndSupply_
                            && i_ == numSegments_ - 1
                    ) {
                        position_.stepIndexWithinSegment = totalStepsInSegment_
                            > 0 ? totalStepsInSegment_ - 1 : 0;
                    }
                    position_.priceAtCurrentStep = initialPrice_
                        + (position_.stepIndexWithinSegment * priceIncreasePerStep_);
                }
                return position_;
            }
            cumulativeSupply_ = segmentEndSupply_;
        }

        // Fallback: targetSupply_ is greater than total capacity of all segments_.
        // This should be caught by _validateSupplyAgainstSegments in public-facing functions.
        // If reached, position_ to the end of the last segment.
        position_.segmentIndex = numSegments_ - 1;
        (
            uint lastSegInitialPrice_,
            uint lastSegPriceIncreasePerStep_,
            ,
            uint lastSegTotalSteps_
        ) = segments_[numSegments_ - 1]._unpack();

        position_.stepIndexWithinSegment =
            lastSegTotalSteps_ > 0 ? lastSegTotalSteps_ - 1 : 0;
        position_.priceAtCurrentStep = lastSegInitialPrice_
            + (position_.stepIndexWithinSegment * lastSegPriceIncreasePerStep_);
        // supplyCoveredUpToThisPosition is the total capacity of the curve.
        position_.supplyCoveredUpToThisPosition = cumulativeSupply_;
        return position_;
    }

    // Functions from sections IV-VIII will be added in subsequent steps.

    /**
     * @notice Gets the current price, step index, and segment index for a given total issuance supply.
     * @dev Adjusts to the price of the *next* step if currentTotalIssuanceSupply_ exactly lands on a step boundary.
     * @param segments_ Array of PackedSegment configurations for the curve.
     * @param currentTotalIssuanceSupply_ The current total supply.
     * @return price_ The price at the current (or next, if on boundary) step.
     * @return stepIndex_ The index of the current (or next) step within its segment.
     * @return segmentIndex_ The index of the current (or next) segment.
     */
    function _getCurrentPriceAndStep(
        PackedSegment[] memory segments_,
        uint currentTotalIssuanceSupply_
    )
        internal
        pure
        returns (uint price_, uint stepIndex_, uint segmentIndex_)
    {
        // Perform validation first. This will revert if currentTotalIssuanceSupply_ > totalCurveCapacity.
        _validateSupplyAgainstSegments(segments_, currentTotalIssuanceSupply_);
        // Note: The returned totalCurveCapacity_ is not explicitly used here as _findPositionForSupply
        // will correctly determine the position_ based on the now-validated currentTotalIssuanceSupply_.

        // _findPositionForSupply can now assume currentTotalIssuanceSupply_ is valid (within or at capacity).
        IDiscreteCurveMathLib_v1.CurvePosition memory posDetails_ =
            _findPositionForSupply(segments_, currentTotalIssuanceSupply_);

        // The previous explicit check:
        // if (currentTotalIssuanceSupply_ > posDetails_.supplyCoveredUpToThisPosition) {
        //     revert IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__TargetSupplyBeyondCurveCapacity();
        // }
        // is now covered by the _validateSupplyAgainstSegments call above.
        // _findPositionForSupply ensures posDetails_.supplyCoveredUpToThisPosition is either currentTotalIssuanceSupply_
        // or the total curve capacity if currentTotalIssuanceSupply_ was at the very end.

        // Since _findPositionForSupply now correctly handles
        // segment boundaries by pointing to the start of the next segment (or the last step of the
        // last segment if at max capacity), and returns the price/step for that position_,
        // we can directly use its output. The complex adjustment logic previously here is no longer needed.
        return (
            posDetails_.priceAtCurrentStep,
            posDetails_.stepIndexWithinSegment,
            posDetails_.segmentIndex
        );
    }

    // =========================================================================
    // Core Calculation Functions

    /**
     * @notice Calculates the total collateral reserve required to back a given target supply.
     * @dev Iterates through segments_, summing the collateral needed for the portion of targetSupply_ in each.
     * @param segments_ Array of PackedSegment configurations for the curve.
     * @param targetSupply_ The target total issuance supply for which to calculate the reserve.
     * @return totalReserve_ The total collateral reserve required.
     */
    function _calculateReserveForSupply(
        PackedSegment[] memory segments_,
        uint targetSupply_
    ) internal pure returns (uint totalReserve_) {
        if (targetSupply_ == 0) {
            return 0;
        }
        uint numSegments_ = segments_.length; // Cache length
        if (numSegments_ == 0) {
            revert
                IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__NoSegmentsConfigured();
        }
        if (numSegments_ > MAX_SEGMENTS) {
            revert
                IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__TooManySegments();
        }
        _validateSupplyAgainstSegments(segments_, targetSupply_); // Validation occurs, returned capacity not stored if unused
        // The loop condition `cumulativeSupplyProcessed_ >= targetSupply_` and `targetSupply_ <= totalCurveCapacity_` (from validation)
        // should be sufficient.

        uint cumulativeSupplyProcessed_ = 0;
        // totalReserve_ is initialized to 0 by default

        for (
            uint segmentIndex_ = 0;
            segmentIndex_ < numSegments_;
            ++segmentIndex_
        ) {
            // Use cached length
            if (cumulativeSupplyProcessed_ >= targetSupply_) {
                break; // All target supply has been accounted for.
            }

            // Unpack segment data - using batch unpack as per instruction suggestion for this case
            (
                uint initialPrice_,
                uint priceIncreasePerStep_,
                uint supplyPerStep_,
                uint totalStepsInSegment_
            ) = segments_[segmentIndex_]._unpack();
            // Note: supplyPerStep_ is guaranteed > 0 by PackedSegmentLib.create validation.

            uint supplyRemainingInTarget_ =
                targetSupply_ - cumulativeSupplyProcessed_;

            // Calculate how many steps from *this* segment are needed to cover supplyRemainingInTarget_
            // Ceiling division: (numerator + denominator - 1) / denominator
            uint stepsToProcessInSegment_ =
                (supplyRemainingInTarget_ + supplyPerStep_ - 1) / supplyPerStep_;

            // Cap at the segment's actual available steps
            if (stepsToProcessInSegment_ > totalStepsInSegment_) {
                stepsToProcessInSegment_ = totalStepsInSegment_;
            }

            uint collateralForPortion_;
            if (priceIncreasePerStep_ == 0) {
                // Flat segment
                // Use _mulDivUp for conservative reserve calculation (favors protocol)
                if (initialPrice_ == 0) {
                    // Free portion
                    collateralForPortion_ = 0;
                } else {
                    collateralForPortion_ = _mulDivUp(
                        stepsToProcessInSegment_ * supplyPerStep_,
                        initialPrice_,
                        SCALING_FACTOR
                    );
                }
            } else {
                // Sloped segment: sum of an arithmetic series
                // S_n = n/2 * (2a + (n-1)d)
                // Here, n = stepsToProcessInSegment_, a = initialPrice_, d = priceIncreasePerStep_
                // Each term (price) is multiplied by supplyPerStep_ and divided by SCALING_FACTOR.
                // Collateral = supplyPerStep_/SCALING_FACTOR * Sum_{k=0}^{n-1} (initialPrice_ + k*priceIncreasePerStep_)
                // Collateral = supplyPerStep_/SCALING_FACTOR * (n*initialPrice_ + priceIncreasePerStep_ * n*(n-1)/2)
                // Collateral = (supplyPerStep_ * n * (2*initialPrice_ + (n-1)*priceIncreasePerStep_)) / (2 * SCALING_FACTOR)
                // where n is stepsToProcessInSegment_.

                if (stepsToProcessInSegment_ == 0) {
                    collateralForPortion_ = 0;
                } else {
                    uint firstStepPrice_ = initialPrice_;
                    uint lastStepPrice_ = initialPrice_
                        + (stepsToProcessInSegment_ - 1) * priceIncreasePerStep_;
                    uint sumOfPrices_ = firstStepPrice_ + lastStepPrice_;
                    uint totalPriceForAllStepsInPortion_;
                    if (sumOfPrices_ == 0 || stepsToProcessInSegment_ == 0) {
                        totalPriceForAllStepsInPortion_ = 0;
                    } else {
                        // n * sumOfPrices_ is always even, so Math.mulDiv is exact.
                        totalPriceForAllStepsInPortion_ = Math.mulDiv(
                            stepsToProcessInSegment_, sumOfPrices_, 2
                        );
                    }
                    // Use _mulDivUp for conservative reserve calculation (favors protocol)
                    collateralForPortion_ = _mulDivUp(
                        supplyPerStep_,
                        totalPriceForAllStepsInPortion_,
                        SCALING_FACTOR
                    );
                }
            }

            totalReserve_ += collateralForPortion_;
            cumulativeSupplyProcessed_ +=
                stepsToProcessInSegment_ * supplyPerStep_;
        }

        // Note: The case where targetSupply_ > totalCurveCapacity_ is handled by the
        // _validateSupplyAgainstSegments check at the beginning of this function,
        // which will cause a revert. Therefore, this function will only proceed
        // if targetSupply_ is within the curve's defined capacity.
        // If, for some other reason, cumulativeSupplyProcessed_ < targetSupply_ at this point
        // (e.g. an issue with loop logic or segment data), it implies an internal inconsistency
        // as the initial validation should have caught out-of-bounds targetSupply_.
        // The function calculates reserve for the portion of targetSupply_ covered by the loop.

        return totalReserve_;
    }

    /**
     * @notice Calculates the amount of issuance tokens received for a given collateral input.
     * @dev Iterates through segments starting from the current supply's position.
     *      Assumes segments are pre-validated by caller.
     * @param segments_ Array of PackedSegment configurations for the curve.
     * @param collateralToSpendProvided_ The amount of collateral being provided for purchase.
     * @param currentTotalIssuanceSupply_ The current total supply before this purchase.
     * @return tokensToMint_ The total amount of issuance tokens minted.
     * @return collateralSpentByPurchaser_ The actual amount of collateral spent.
     */
    function _calculatePurchaseReturn(
        PackedSegment[] memory segments_,
        uint collateralToSpendProvided_,
        uint currentTotalIssuanceSupply_
    )
        internal
        pure
        returns (uint tokensToMint_, uint collateralSpentByPurchaser_)
    {
        if (collateralToSpendProvided_ == 0) {
            revert
                IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__ZeroCollateralInput();
        }
        if (segments_.length == 0) {
            revert
                IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__NoSegmentsConfigured();
        }

        // Phase 1: Find which segment and step to start purchasing from.
        uint segmentIndex_ = 0; 
        uint supplyCoveredByPreviousSegments_ = 0; 

        if (currentTotalIssuanceSupply_ > 0) { // Only search if there's existing supply
            uint cumulativeProcessedSupply_ = 0;
            for (uint i_ = 0; i_ < segments_.length; ++i_) {
                uint currentSegmentCapacity_ = segments_[i_]._supplyPerStep() * segments_[i_]._numberOfSteps();
                uint endOfCurrentSegmentSupply_ = cumulativeProcessedSupply_ + currentSegmentCapacity_;

                if (currentTotalIssuanceSupply_ < endOfCurrentSegmentSupply_) {
                    // currentTotalIssuanceSupply_ is within segment i_
                    segmentIndex_ = i_;
                    supplyCoveredByPreviousSegments_ = cumulativeProcessedSupply_;
                    break;
                } else if (currentTotalIssuanceSupply_ == endOfCurrentSegmentSupply_) {
                    // currentTotalIssuanceSupply_ is exactly at the end of segment i_.
                    // Purchase should start at the beginning of the next segment (i_ + 1), if it exists.
                    if (i_ + 1 < segments_.length) {
                        segmentIndex_ = i_ + 1;
                        supplyCoveredByPreviousSegments_ = endOfCurrentSegmentSupply_;
                    } else {
                        // At the very end of the last segment, no more capacity to purchase.
                        segmentIndex_ = segments_.length; // Will prevent Phase 3 loop
                        supplyCoveredByPreviousSegments_ = endOfCurrentSegmentSupply_;
                    }
                    break;
                }
                cumulativeProcessedSupply_ = endOfCurrentSegmentSupply_;
                // If loop finishes and we are here, currentTotalIssuanceSupply_ > total capacity of all segments
                // This case should ideally be prevented by caller validation.
                // If it occurs, segmentIndex_ will be set to segments_.length below.
                if (i_ == segments_.length - 1) { 
                    segmentIndex_ = segments_.length; 
                    supplyCoveredByPreviousSegments_ = cumulativeProcessedSupply_;
                }
            }
        }
        // If currentTotalIssuanceSupply_ is 0, segmentIndex_ remains 0, supplyCoveredByPreviousSegments_ remains 0.

        // Phase 2: Find step position and handle partial start step
        uint stepIndex_;
        uint remainingBudget_ = collateralToSpendProvided_;
        
        // Check if there's any segment to purchase from
        if (segmentIndex_ >= segments_.length) {
            // currentTotalIssuanceSupply_ is at or beyond total capacity. No purchase possible.
            collateralSpentByPurchaser_ = 0; // No budget spent
            // tokensToMint_ is already 0
            return (tokensToMint_, collateralSpentByPurchaser_);
        }
        
        {
            // Calculate position within current segment (segmentIndex_)
            uint segmentIssuanceSupply_ = currentTotalIssuanceSupply_ - supplyCoveredByPreviousSegments_;
            
            uint supplyPerStep_ = segments_[segmentIndex_]._supplyPerStep();
            // If supplyPerStep_ is 0 (should be prevented by PackedSegmentLib), handle to avoid division by zero.
            // However, PackedSegmentLib ensures supplyPerStep_ > 0.
            stepIndex_ = segmentIssuanceSupply_ / supplyPerStep_;
            uint currentStepIssuanceSupply_ = segmentIssuanceSupply_ % supplyPerStep_;

            // Calculate current step price and remaining capacity
            // Ensure stepIndex_ is within bounds for the current segment before calculating stepPrice_
            if (stepIndex_ >= segments_[segmentIndex_]._numberOfSteps() && currentStepIssuanceSupply_ == 0) {
                // This means currentTotalIssuanceSupply_ was exactly at the end of segmentIndex_,
                // and Phase 1 should have advanced segmentIndex_. This indicates a logic flaw if reached.
                // For safety, or if Phase 1 didn't advance segmentIndex_ to segments_.length for end-of-curve,
                // treat as no capacity in this segment.
                // This path should ideally not be hit if Phase 1 is correct.
                 // Let Phase 3 handle moving to the next segment or exiting.
            }

            uint stepPrice_ = segments_[segmentIndex_]._initialPrice()
                + (segments_[segmentIndex_]._priceIncrease() * stepIndex_);
            uint remainingStepIssuanceSupply_ =
                supplyPerStep_ - currentStepIssuanceSupply_;

            // Try to complete current step if partially filled
            if (remainingStepIssuanceSupply_ > 0) {
                uint remainingStepCollateralCapacity_ = _mulDivUp(
                    remainingStepIssuanceSupply_, stepPrice_, SCALING_FACTOR
                );

                if (remainingBudget_ >= remainingStepCollateralCapacity_) {
                    // Complete the step and move to next
                    remainingBudget_ -= remainingStepCollateralCapacity_;
                    tokensToMint_ += remainingStepIssuanceSupply_;
                    stepIndex_++;
                } else {
                    // Partial fill and exit
                    uint additionalIssuanceAmount_ = Math.mulDiv(
                        remainingBudget_, SCALING_FACTOR, stepPrice_
                    );
                    tokensToMint_ += additionalIssuanceAmount_; // tokensToMint_ was 0 before this line in this specific path
                    // Calculate actual collateral spent for this partial amount
                    collateralSpentByPurchaser_ = _mulDivUp(additionalIssuanceAmount_, stepPrice_, SCALING_FACTOR);
                    return (tokensToMint_, collateralSpentByPurchaser_);
                }
            }
        }

        // Phase 3: Purchase through remaining steps until budget exhausted
        while (remainingBudget_ > 0 && segmentIndex_ < segments_.length) {
            uint numberOfSteps_ = segments_[segmentIndex_]._numberOfSteps();

            // Move to next segment if current one is exhausted
            if (stepIndex_ >= numberOfSteps_) {
                segmentIndex_++;
                stepIndex_ = 0;
                continue;
            }

            // Cache segment parameters
            uint initialPrice_ = segments_[segmentIndex_]._initialPrice();
            uint priceIncrease_ = segments_[segmentIndex_]._priceIncrease();
            uint supplyPerStep_ = segments_[segmentIndex_]._supplyPerStep();

            // Calculate step price (works for both flat and sloped segments)
            uint stepPrice_ = initialPrice_ + (priceIncrease_ * stepIndex_);
            uint stepCollateralCapacity_ =
                _mulDivUp(supplyPerStep_, stepPrice_, SCALING_FACTOR);

            if (remainingBudget_ >= stepCollateralCapacity_) {
                // Purchase full step
                remainingBudget_ -= stepCollateralCapacity_;
                tokensToMint_ += supplyPerStep_;
                stepIndex_++;
            } else {
                // Partial step purchase and exit
                uint partialIssuance_ =
                    Math.mulDiv(remainingBudget_, SCALING_FACTOR, stepPrice_);
                tokensToMint_ += partialIssuance_;
                remainingBudget_ = 0;
            }
        }

        collateralSpentByPurchaser_ =
            collateralToSpendProvided_ - remainingBudget_;
        return (tokensToMint_, collateralSpentByPurchaser_);
    }

    /**
     * @notice Helper function to calculate purchase return for a single sloped segment using linear search.
    /**
     * @notice Helper function to calculate purchase return for a single segment.
    /**
     * @notice Calculates the amount of partial issuance and its cost given budget_ and various constraints.
    /**
     * @notice Calculates the amount of collateral returned for selling a given amount of issuance tokens.
     * @dev Uses the difference in reserve at current supply and supply after sale.
     * @param segments_ Array of PackedSegment configurations for the curve.
     * @param tokensToSell_ The amount of issuance tokens being sold.
     * @param currentTotalIssuanceSupply_ The current total supply before this sale.
     * @return collateralToReturn_ The total amount of collateral returned to the seller.
     * @return tokensToBurn_ The actual amount of issuance tokens burned (capped at current supply).
     */
    function _calculateSaleReturn(
        PackedSegment[] memory segments_,
        uint tokensToSell_, // Renamed from issuanceAmountIn
        uint currentTotalIssuanceSupply_
    ) internal pure returns (uint collateralToReturn_, uint tokensToBurn_) {
        // Renamed return values
        _validateSupplyAgainstSegments(segments_, currentTotalIssuanceSupply_); // Validation occurs
        // If totalCurveCapacity_ is needed later, _validateSupplyAgainstSegments can be called again.

        if (tokensToSell_ == 0) {
            revert
                IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__ZeroIssuanceInput();
        }

        uint numSegments_ = segments_.length; // Renamed from segLen
        if (numSegments_ == 0) {
            // This implies currentTotalIssuanceSupply_ must be 0.
            // Selling from 0 supply on an unconfigured curve. tokensToBurn_ will be 0.
        }

        tokensToBurn_ = tokensToSell_ > currentTotalIssuanceSupply_
            ? currentTotalIssuanceSupply_
            : tokensToSell_;

        if (tokensToBurn_ == 0) {
            return (0, 0);
        }

        uint finalSupplyAfterSale_ = currentTotalIssuanceSupply_ - tokensToBurn_;

        uint collateralAtCurrentSupply_ =
            _calculateReserveForSupply(segments_, currentTotalIssuanceSupply_);
        uint collateralAtFinalSupply_ =
            _calculateReserveForSupply(segments_, finalSupplyAfterSale_);

        if (collateralAtCurrentSupply_ < collateralAtFinalSupply_) {
            // This should not happen with a correctly defined bonding curve (prices are non-negative).
            return (0, tokensToBurn_);
        }

        collateralToReturn_ =
            collateralAtCurrentSupply_ - collateralAtFinalSupply_;

        return (collateralToReturn_, tokensToBurn_);
    }

    // =========================================================================
    // Internal Convenience Functions

    /**
     * @notice Convenience function to create a PackedSegment using the internal PackedSegmentLib.
     * @dev This is effectively an alias to PackedSegmentLib.create for use within contexts
     *      that have imported DiscreteCurveMathLib_v1 directly.
     * @param initialPrice_ The initial price for this segment.
     * @param priceIncrease_ The price increase per step for this segment.
     * @param supplyPerStep_ The supply minted per step for this segment.
     * @param numberOfSteps_ The number of steps in this segment.
     * @return The newly created PackedSegment.
     */
    function _createSegment(
        uint initialPrice_,
        uint priceIncrease_,
        uint supplyPerStep_,
        uint numberOfSteps_
    ) internal pure returns (PackedSegment) {
        // All validation is handled by PackedSegmentLib._create
        return PackedSegmentLib._create(
            initialPrice_, priceIncrease_, supplyPerStep_, numberOfSteps_
        );
    }

    /**
     * @notice Validates an array of PackedSegments.
     * @dev Checks for empty array, exceeding max segments, and basic validity of each segment.
     *      More detailed validation of individual segment parameters occurs at creation time.
     * @param segments_ Array of PackedSegment configurations to validate.
     */
    function _validateSegmentArray(PackedSegment[] memory segments_)
        internal
        pure
    {
        uint numSegments_ = segments_.length; // Renamed from segLen
        if (numSegments_ == 0) {
            revert
                IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__NoSegmentsConfigured();
        }
        if (numSegments_ > MAX_SEGMENTS) {
            revert
                IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__TooManySegments();
        }

        // Note: Individual segment's supplyPerStep_ > 0 and numberOfSteps_ > 0
        // are guaranteed by PackedSegmentLib._create validation.
        // Also, segments_ with initialPrice_ == 0 AND priceIncreasePerStep_ == 0 are disallowed by PackedSegmentLib._create.
        // This function primarily validates array-level properties and inter-segment price progression.

        // Check for non-decreasing price progression between segments_.
        // The initial price of segment i+1 must be >= final price of segment i.
        for (uint i_ = 0; i_ < numSegments_ - 1; ++i_) {
            PackedSegment currentSegment_ = segments_[i_];
            PackedSegment nextSegment_ = segments_[i_ + 1];

            uint currentInitialPrice_ = currentSegment_._initialPrice();
            uint currentPriceIncrease_ = currentSegment_._priceIncrease();
            uint currentNumberOfSteps_ = currentSegment_._numberOfSteps();

            // Final price of the current segment.
            // If numberOfSteps_ is 1, final price is initialPrice_.
            // Otherwise, it's initialPrice_ + (numberOfSteps_ - 1) * priceIncrease_.
            uint finalPriceCurrentSegment_;
            if (currentNumberOfSteps_ == 0) {
                // This case should be prevented by PackedSegmentLib._create's check for numberOfSteps_ > 0.
                // If somehow reached, treat as an invalid state or handle as per specific requirements.
                // For safety, assume it implies an issue, though _create() should prevent it.
                // As a defensive measure, one might revert or assign a value that ensures progression check logic.
                // However, relying on _create() validation is typical.
                // If steps is 0, let's consider its "final price" to be its initial price to avoid underflow with (steps-1).
                finalPriceCurrentSegment_ = currentInitialPrice_;
            } else if (currentNumberOfSteps_ == 1) {
                finalPriceCurrentSegment_ = currentInitialPrice_;
            } else {
                finalPriceCurrentSegment_ = currentInitialPrice_
                    + (currentNumberOfSteps_ - 1) * currentPriceIncrease_;
                // Check for overflow in final price calculation, though bit limits on components make this unlikely
                // to overflow uint256 unless priceIncrease_ is extremely large.
                // Max initialPrice_ ~2^72, max (steps-1)*priceIncrease_ ~ (2^16)*(2^72) ~ 2^88. Sum ~2^88. Fits uint256.
            }

            uint initialPriceNextSegment_ = nextSegment_._initialPrice();

            if (initialPriceNextSegment_ < finalPriceCurrentSegment_) {
                // Note: DiscreteCurveMathLib__InvalidPriceProgression error needs to be defined in IDiscreteCurveMathLib_v1.sol
                revert
                    IDiscreteCurveMathLib_v1
                    .DiscreteCurveMathLib__InvalidPriceProgression(
                    i_, finalPriceCurrentSegment_, initialPriceNextSegment_
                );
            }
        }
    }

    // =========================================================================
    // Custom Math Helpers

    /**
     * @dev Calculates (a_ * b_) % modulus_.
     * @notice Solidity 0.8.x's default behavior for `(a_ * b_) % modulus_` computes the product `a_ * b_`
     * using full 256x256 bit precision before applying the modulus_, preventing overflow of `a_ * b_`
     * from affecting the result of the modulo operation itself (as long as modulus_ is not zero).
     * @param a_ The first operand.
     * @param b_ The second operand.
     * @param modulus_ The modulus.
     * @return (a_ * b_) % modulus_.
     */
    function _mulmod(uint a_, uint b_, uint modulus_)
        private
        pure
        returns (uint)
    {
        require(
            modulus_ > 0,
            "DiscreteCurveMathLib_v1: modulus_ cannot be zero in _mulmod"
        );
        return (a_ * b_) % modulus_;
    }

    /**
     * @dev Calculates (a_ * b_) / denominator_, rounding up.
     * @param a_ The first operand for multiplication.
     * @param b_ The second operand for multiplication.
     * @param denominator_ The denominator for division.
     * @return result_ ceil((a_ * b_) / denominator_).
     */
    function _mulDivUp(uint a_, uint b_, uint denominator_)
        private
        pure
        returns (uint result_)
    {
        require(
            denominator_ > 0,
            "DiscreteCurveMathLib_v1: division by zero in _mulDivUp"
        );
        result_ = Math.mulDiv(a_, b_, denominator_); // Standard OpenZeppelin Math.mulDiv rounds down (floor division)

        // If there's any remainder from (a_ * b_) / denominator_, we need to add 1 to round up.
        // A remainder exists if (a_ * b_) % denominator_ is not 0.
        // We use the local _mulmod function which safely computes (a_ * b_) % denominator_.
        if (_mulmod(a_, b_, denominator_) > 0) {
            // Before incrementing, check if 'result_' is already at max_uint256 to prevent overflow.
            // This scenario (overflowing after adding 1 due to rounding) is extremely unlikely if a_, b_, denominator_
            // are such that mulDiv itself doesn't revert, but it's a good safety check.
            require(
                result_ < type(uint).max,
                "DiscreteCurveMathLib_v1: _mulDivUp overflow on increment"
            );
            result_++;
        }
        return result_;
    }
}
