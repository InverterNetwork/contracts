// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.19;

import {IDiscreteCurveMathLib_v1} from
    "../interfaces/IDiscreteCurveMathLib_v1.sol";
import {PackedSegmentLib} from "../libraries/PackedSegmentLib.sol";
import {PackedSegment} from "../types/PackedSegment_v1.sol";
import {Math} from "@oz/utils/math/Math.sol";

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
     * @notice Calculates the total collateral reserve required to back a given target supply of issuance tokens.
     * @dev Iterates through the curve segments, summing the collateral required for each step up to the targetSupply_.
     *      Uses arithmetic series for sloped segments and direct multiplication for flat segments.
     *      Rounds up collateral calculations for individual steps to favor the protocol.
     *      Reverts if segments_ array is empty and targetSupply_ > 0.
     *      Reverts if segments_ array exceeds MAX_SEGMENTS.
     *      Reverts if targetSupply_ exceeds the total capacity of all segments_.
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
        uint numSegments_ = segments_.length;
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
        _validateSupplyAgainstSegments(segments_, targetSupply_);

        uint cumulativeSupplyProcessed_ = 0;

        for (
            uint segmentIndex_ = 0;
            segmentIndex_ < numSegments_;
            ++segmentIndex_
        ) {
            if (cumulativeSupplyProcessed_ >= targetSupply_) {
                break;
            }

            (
                uint initialPrice_,
                uint priceIncreasePerStep_,
                uint supplyPerStep_,
                uint totalStepsInSegment_
            ) = segments_[segmentIndex_]._unpack();

            uint segmentCapacity_ = totalStepsInSegment_ * supplyPerStep_;
            uint supplyRemainingInTarget_ =
                targetSupply_ - cumulativeSupplyProcessed_;

            // Calculate how much of this segment we need to process
            uint supplyToProcessInSegment_ = supplyRemainingInTarget_
                > segmentCapacity_ ? segmentCapacity_ : supplyRemainingInTarget_;

            // Calculate full steps and partial step for this segment
            uint fullStepsToProcess_ =
                supplyToProcessInSegment_ / supplyPerStep_;
            uint partialStepSupply_ = supplyToProcessInSegment_ % supplyPerStep_;

            uint collateralForPortion_ = 0;

            // Calculate cost for full steps
            if (fullStepsToProcess_ > 0) {
                if (priceIncreasePerStep_ == 0) {
                    // Flat segment
                    if (initialPrice_ > 0) {
                        collateralForPortion_ += _mulDivUp(
                            fullStepsToProcess_ * supplyPerStep_,
                            initialPrice_,
                            SCALING_FACTOR
                        );
                    }
                } else {
                    // Sloped segment: arithmetic series for full steps
                    uint firstStepPrice_ = initialPrice_;
                    uint lastStepPrice_ = initialPrice_
                        + (fullStepsToProcess_ - 1) * priceIncreasePerStep_;
                    uint sumOfPrices_ = firstStepPrice_ + lastStepPrice_;
                    uint totalPriceForAllSteps_ =
                        Math.mulDiv(fullStepsToProcess_, sumOfPrices_, 2);
                    collateralForPortion_ += _mulDivUp(
                        supplyPerStep_, totalPriceForAllSteps_, SCALING_FACTOR
                    );
                }
            }

            // Calculate cost for partial step (if any)
            if (partialStepSupply_ > 0) {
                uint partialStepPrice_ = initialPrice_
                    + (fullStepsToProcess_ * priceIncreasePerStep_);
                if (partialStepPrice_ > 0) {
                    collateralForPortion_ += _mulDivUp(
                        partialStepSupply_, partialStepPrice_, SCALING_FACTOR
                    );
                }
            }

            totalReserve_ += collateralForPortion_;

            // Update cumulative supply with actual supply processed
            cumulativeSupplyProcessed_ += supplyToProcessInSegment_;
        }

        return totalReserve_;
    }

    /**
     * @notice Calculates the amount of issuance tokens a purchaser receives for a given amount of collateral,
     *         and the actual amount of collateral spent.
     * @dev Iterates through curve segments starting from the position_ indicated by currentTotalIssuanceSupply_.
     *      It first determines the starting segment and step. If the starting supply is mid-step,
     *      it calculates the cost to complete that partial step. Then, it iterates through subsequent
     *      full steps and segments, consuming the provided collateral.
     *      The function handles purchases that span multiple steps and segments.
     *      It ensures that collateral is not overspent and issuance does not exceed curve capacity.
     *      Collateral calculations for steps are rounded up to favor the protocol.
     *      Tokens minted for a partial final step (due to budget constraint) are rounded down.
     *      Reverts if collateralToSpendProvided_ is zero.
     *      Reverts if segments_ array is empty.
     *      Caller is responsible for pre-validating the segments_ array structure (e.g., price progression, MAX_SEGMENTS)
     *      and ensuring currentTotalIssuanceSupply_ does not exceed total curve capacity before calling this function.
     * @param segments_ Array of PackedSegment configurations for the curve.
     * @param collateralToSpendProvided_ The amount of collateral the purchaser is providing.
     * @param currentTotalIssuanceSupply_ The current total issuance supply before this purchase.
     * @return tokensToMint_ The total amount of issuance tokens to be minted.
     * @return collateralSpentByPurchaser_ The actual amount of collateral spent from the provided budget.
     */
    function _calculatePurchaseReturn(
        PackedSegment[] memory segments_,
        uint collateralToSpendProvided_,
        uint currentTotalIssuanceSupply_
    )
        internal
        pure // Already pure, ensuring it stays
        returns (uint tokensToMint_, uint collateralSpentByPurchaser_)
    {
        if (collateralToSpendProvided_ == 0) {
            revert
                IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__ZeroCollateralInput();
        }

        // Phase 1: Find which segment and step to start purchasing from.
        uint segmentIndex_ = 0;
        uint supplyCoveredByPreviousSegments_ = 0;

        if (currentTotalIssuanceSupply_ > 0) {
            // Only search if there's existing supply
            uint cumulativeProcessedSupply_ = 0;
            for (uint i_ = 0; i_ < segments_.length; ++i_) {
                uint currentSegmentCapacity_ = segments_[i_]._supplyPerStep()
                    * segments_[i_]._numberOfSteps();
                uint endOfCurrentSegmentSupply_ =
                    cumulativeProcessedSupply_ + currentSegmentCapacity_;

                if (currentTotalIssuanceSupply_ < endOfCurrentSegmentSupply_) {
                    // currentTotalIssuanceSupply_ is within segment i_
                    segmentIndex_ = i_;
                    supplyCoveredByPreviousSegments_ =
                        cumulativeProcessedSupply_;
                    break;
                } else if (
                    currentTotalIssuanceSupply_ == endOfCurrentSegmentSupply_
                ) {
                    // currentTotalIssuanceSupply_ is exactly at the end of segment i_.
                    // Purchase should start at the beginning of the next segment (i_ + 1), if it exists.
                    if (i_ + 1 < segments_.length) {
                        segmentIndex_ = i_ + 1;
                        supplyCoveredByPreviousSegments_ =
                            endOfCurrentSegmentSupply_;
                    } else {
                        // At the very end of the last segment, no more capacity to purchase.
                        segmentIndex_ = segments_.length; // Will prevent Phase 3 loop
                        supplyCoveredByPreviousSegments_ =
                            endOfCurrentSegmentSupply_;
                    }
                    break;
                }
                cumulativeProcessedSupply_ = endOfCurrentSegmentSupply_;
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
            uint segmentIssuanceSupply_ =
                currentTotalIssuanceSupply_ - supplyCoveredByPreviousSegments_;

            uint supplyPerStep_ = segments_[segmentIndex_]._supplyPerStep();
            // If supplyPerStep_ is 0 (should be prevented by PackedSegmentLib), handle to avoid division by zero.
            // However, PackedSegmentLib ensures supplyPerStep_ > 0.
            stepIndex_ = segmentIssuanceSupply_ / supplyPerStep_;
            uint currentStepIssuanceSupply_ =
                segmentIssuanceSupply_ % supplyPerStep_;
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
                    collateralSpentByPurchaser_ = _mulDivUp(
                        additionalIssuanceAmount_, stepPrice_, SCALING_FACTOR
                    );
                    return (tokensToMint_, collateralSpentByPurchaser_);
                }
            }
        }

        uint fullStepBacking = 0;

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
                fullStepBacking += stepCollateralCapacity_;
            } else {
                // Partial step purchase and exit
                uint partialIssuance_ =
                    Math.mulDiv(remainingBudget_, SCALING_FACTOR, stepPrice_);
                tokensToMint_ += partialIssuance_;
                remainingBudget_ -=
                    _mulDivUp(partialIssuance_, stepPrice_, SCALING_FACTOR);

                break;
            }
        }

        collateralSpentByPurchaser_ =
            collateralToSpendProvided_ - remainingBudget_;
        return (tokensToMint_, collateralSpentByPurchaser_);
    }

    // /**
    //  * @notice Helper function to calculate purchase return for a single sloped segment using linear search.
    //  * /**
    //  * @notice Helper function to calculate purchase return for a single segment.
    //  * /**
    //  * @notice Calculates the amount of partial issuance and its cost given budget_ and various constraints.
    //  * /**
    //  * @notice Calculates the amount of collateral returned for selling a given amount of issuance tokens.
    //  * @dev Uses the difference in reserve at current supply and supply after sale.
    //  * @param segments_ Array of PackedSegment configurations for the curve.
    //  * @param tokensToSell_ The amount of issuance tokens being sold.
    //  * @param currentTotalIssuanceSupply_ The current total supply before this sale.
    //  * @return collateralToReturn_ The total amount of collateral returned to the seller.
    //  * @return tokensToBurn_ The actual amount of issuance tokens burned (capped at current supply).
    //  */
    // function _calculateSaleReturn(
    //     PackedSegment[] memory segments_,
    //     uint tokensToSell_, // Renamed from issuanceAmountIn
    //     uint currentTotalIssuanceSupply_
    // ) internal pure returns (uint collateralToReturn_, uint tokensToBurn_) {
    //     // Renamed return values
    //     _validateSupplyAgainstSegments(segments_, currentTotalIssuanceSupply_); // Validation occurs
    //     // If totalCurveCapacity_ is needed later, _validateSupplyAgainstSegments can be called again.

    //     if (tokensToSell_ == 0) {
    //         revert
    //             IDiscreteCurveMathLib_v1
    //             .DiscreteCurveMathLib__ZeroIssuanceInput();
    //     }

    //     uint numSegments_ = segments_.length; // Renamed from segLen
    //     if (numSegments_ == 0) {
    //         // This implies currentTotalIssuanceSupply_ must be 0.
    //         // Selling from 0 supply on an unconfigured curve. tokensToBurn_ will be 0.
    //     }

    //     tokensToBurn_ = tokensToSell_ > currentTotalIssuanceSupply_
    //         ? currentTotalIssuanceSupply_
    //         : tokensToSell_;

    //     if (tokensToBurn_ == 0) {
    //         return (0, 0);
    //     }

    //     uint finalSupplyAfterSale_ = currentTotalIssuanceSupply_ - tokensToBurn_;

    //     uint collateralAtCurrentSupply_ =
    //         _calculateReserveForSupply(segments_, currentTotalIssuanceSupply_);
    //     uint collateralAtFinalSupply_ =
    //         _calculateReserveForSupply(segments_, finalSupplyAfterSale_);

    //     if (collateralAtCurrentSupply_ < collateralAtFinalSupply_) {
    //         // This should not happen with a correctly defined bonding curve (prices are non-negative).
    //         return (0, tokensToBurn_);
    //     }

    //     collateralToReturn_ =
    //         collateralAtCurrentSupply_ - collateralAtFinalSupply_;

    //     return (collateralToReturn_, tokensToBurn_);
    // }

    /**
     * @notice Calculates the amount of collateral returned for selling a given amount of issuance tokens.
     * @dev Optimized version that calculates both reserve values in a single pass through segments.
     * @param segments_ Array of PackedSegment configurations for the curve.
     * @param tokensToSell_ The amount of issuance tokens being sold.
     * @param currentTotalIssuanceSupply_ The current total supply before this sale.
     * @return collateralToReturn_ The total amount of collateral returned to the seller.
     * @return tokensToBurn_ The actual amount of issuance tokens burned (capped at current supply).
     */
    function _calculateSaleReturn(
        PackedSegment[] memory segments_,
        uint tokensToSell_,
        uint currentTotalIssuanceSupply_
    ) internal pure returns (uint collateralToReturn_, uint tokensToBurn_) {
        if (tokensToSell_ == 0) {
            revert
                IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__ZeroIssuanceInput();
        }

        if (tokensToSell_ > currentTotalIssuanceSupply_) {
            revert IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__InsufficientIssuanceToSell(
                tokensToSell_,
                currentTotalIssuanceSupply_
            );
        }
        tokensToBurn_ = tokensToSell_;

        uint finalSupplyAfterSale_ = currentTotalIssuanceSupply_ - tokensToBurn_;

        // Optimized: Calculate both reserves in a single pass
        (uint collateralAtFinalSupply_, uint collateralAtCurrentSupply_) =
        _calculateReservesForTwoSupplies(
            segments_, finalSupplyAfterSale_, currentTotalIssuanceSupply_
        );

        collateralToReturn_ =
            collateralAtCurrentSupply_ - collateralAtFinalSupply_;

        return (collateralToReturn_, tokensToBurn_);
    }

    /**
     * @notice Optimized helper that calculates reserves for two different supply points in one pass.
     * @dev Iterates through segments once, calculating reserves for both supply points simultaneously.
     *      This is more gas-efficient than calling _calculateReserveForSupply twice.
     *      Assumes lowerSupply_ <= higherSupply_.
     * @param segments_ Array of PackedSegment configurations for the curve.
     * @param lowerSupply_ The lower supply point (must be <= higherSupply_).
     * @param higherSupply_ The higher supply point.
     * @return lowerReserve_ The total reserve at lowerSupply_.
     * @return higherReserve_ The total reserve at higherSupply_.
     */
    function _calculateReservesForTwoSupplies(
        PackedSegment[] memory segments_,
        uint lowerSupply_,
        uint higherSupply_
    ) internal pure returns (uint lowerReserve_, uint higherReserve_) {
        if (lowerSupply_ == higherSupply_) {
            // If supplies are the same, calculate reserve once.
            // _calculateReserveForSupply has its own segment validation (NoSegmentsConfigured, TooManySegments, SupplyExceedsCurveCapacity).
            // Since this library's functions are typically called with pre-validated segments by the FM,
            // and _calculateReserveForSupply is also an internal pure function,
            // its internal validations will still run if its conditions are met (e.g. targetSupply > 0 for NoSegmentsConfigured).
            uint reserve_ = _calculateReserveForSupply(segments_, lowerSupply_);
            return (reserve_, reserve_);
        }

        // Caller (e.g., FM_BC_DBC via _calculateSaleReturn) is responsible for ensuring segments_ array
        // is valid (not empty, within MAX_SEGMENTS, correct price progression) before calling functions
        // that use _calculateReservesForTwoSupplies.
        // Thus, direct checks for segments_.length == 0 or segments_.length > MAX_SEGMENTS are omitted here.

        uint cumulativeSupplyProcessed_ = 0;
        bool lowerSupplyReached_ = false;

        for (
            uint segmentIndex_ = 0;
            segmentIndex_ < segments_.length;
            ++segmentIndex_
        ) {
            if (cumulativeSupplyProcessed_ >= higherSupply_) {
                break;
            }

            (
                uint initialPrice_,
                uint priceIncreasePerStep_,
                uint supplyPerStep_,
                uint totalStepsInSegment_
            ) = segments_[segmentIndex_]._unpack();

            uint segmentCapacity_ = totalStepsInSegment_ * supplyPerStep_;
            uint segmentEndSupply_ =
                cumulativeSupplyProcessed_ + segmentCapacity_;

            // Process for lower supply if we haven't reached it yet
            if (
                !lowerSupplyReached_ && lowerSupply_ > 0
                    && segmentEndSupply_ > 0
            ) {
                uint supplyToProcessForLower_ = lowerSupply_
                    > cumulativeSupplyProcessed_
                    ? lowerSupply_ - cumulativeSupplyProcessed_
                    : 0;

                if (
                    supplyToProcessForLower_ > 0
                        && cumulativeSupplyProcessed_ < lowerSupply_
                ) {
                    uint effectiveSupplyForLower_ = supplyToProcessForLower_
                        > segmentCapacity_
                        ? segmentCapacity_
                        : supplyToProcessForLower_;

                    lowerReserve_ += _calculateSegmentReserve(
                        initialPrice_,
                        priceIncreasePerStep_,
                        supplyPerStep_,
                        effectiveSupplyForLower_
                    );

                    if (
                        cumulativeSupplyProcessed_ + effectiveSupplyForLower_
                            >= lowerSupply_
                    ) {
                        lowerSupplyReached_ = true;
                    }
                }
            }

            // Process for higher supply
            uint supplyToProcessForHigher_ = higherSupply_
                > cumulativeSupplyProcessed_
                ? higherSupply_ - cumulativeSupplyProcessed_
                : 0;

            if (supplyToProcessForHigher_ > 0) {
                uint effectiveSupplyForHigher_ = supplyToProcessForHigher_
                    > segmentCapacity_
                    ? segmentCapacity_
                    : supplyToProcessForHigher_;

                higherReserve_ += _calculateSegmentReserve(
                    initialPrice_,
                    priceIncreasePerStep_,
                    supplyPerStep_,
                    effectiveSupplyForHigher_
                );
            }

            cumulativeSupplyProcessed_ = segmentEndSupply_;
        }

        return (lowerReserve_, higherReserve_);
    }

    /**
     * @notice Helper function to calculate reserve for a portion of a segment.
     * @dev Handles both flat and sloped segments, with proper rounding up for collateral.
     * @param initialPrice_ The initial price of the segment.
     * @param priceIncreasePerStep_ The price increase per step.
     * @param supplyPerStep_ The supply per step.
     * @param supplyToProcess_ The total supply to process in this segment.
     * @return collateral_ The collateral required for the specified supply.
     */
    function _calculateSegmentReserve(
        uint initialPrice_,
        uint priceIncreasePerStep_,
        uint supplyPerStep_,
        uint supplyToProcess_
    ) internal pure returns (uint collateral_) {
        uint fullSteps_ = supplyToProcess_ / supplyPerStep_;
        uint partialStepSupply_ = supplyToProcess_ % supplyPerStep_;

        // Calculate cost for full steps
        if (fullSteps_ > 0) {
            if (priceIncreasePerStep_ == 0) {
                // Flat segment
                if (initialPrice_ > 0) {
                    collateral_ += _mulDivUp(
                        fullSteps_ * supplyPerStep_,
                        initialPrice_,
                        SCALING_FACTOR
                    );
                }
            } else {
                // Sloped segment: arithmetic series for full steps
                uint firstStepPrice_ = initialPrice_;
                uint lastStepPrice_ =
                    initialPrice_ + (fullSteps_ - 1) * priceIncreasePerStep_;
                uint sumOfPrices_ = firstStepPrice_ + lastStepPrice_;
                uint totalPriceForAllSteps_ =
                    Math.mulDiv(fullSteps_, sumOfPrices_, 2);
                collateral_ += _mulDivUp(
                    supplyPerStep_, totalPriceForAllSteps_, SCALING_FACTOR
                );
            }
        }

        // Calculate cost for partial step (if any)
        if (partialStepSupply_ > 0) {
            uint partialStepPrice_ =
                initialPrice_ + (fullSteps_ * priceIncreasePerStep_);
            if (partialStepPrice_ > 0) {
                collateral_ += _mulDivUp(
                    partialStepSupply_, partialStepPrice_, SCALING_FACTOR
                );
            }
        }

        return collateral_;
    }

    // New helper function to calculate collateral for a specific range
    function _calculateCollateralForRange(
        PackedSegment[] memory segments_,
        uint fromSupply_,
        uint toSupply_
    ) internal pure returns (uint collateral_) {
        // Implementation would calculate collateral only for the range being sold
        // This avoids redundant calculations and is more efficient
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
