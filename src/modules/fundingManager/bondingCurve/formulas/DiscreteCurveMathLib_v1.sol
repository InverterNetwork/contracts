// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.19;

// Internal
import {IDiscreteCurveMathLib_v1} from
    "../interfaces/IDiscreteCurveMathLib_v1.sol";
import {PackedSegmentLib} from "../libraries/PackedSegmentLib.sol";
import {PackedSegment} from "../types/PackedSegment_v1.sol";

// External
import {Math} from "@oz/utils/math/Math.sol";
import {FixedPointMathLib} from "@modLib/FixedPointMathLib.sol";

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

    function _findPositionForSupply(
        PackedSegment[] memory segments_,
        uint targetSupply_
    )
        internal
        pure
        returns (
            uint segmentIndex,
            uint stepIndexWithinSegment,
            uint priceAtCurrentStep
        )
    {
        uint numSegments_ = segments_.length;
        uint cumulativeSupply_ = 0;
        // segmentIndex, stepIndexWithinSegment, priceAtCurrentStep are implicitly declared due to named returns.

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
                // Found the segment containing targetSupply_
                segmentIndex = i_;

                // Calculate position within segment
                uint supplyIntoSegment_ = targetSupply_ - cumulativeSupply_;

                // Determine current step (0-based)
                if (supplyIntoSegment_ == 0) {
                    stepIndexWithinSegment = 0;
                } else {
                    stepIndexWithinSegment =
                        (supplyIntoSegment_ - 1) / supplyPerStep_;
                }

                // Calculate price at current step
                priceAtCurrentStep = initialPrice_
                    + (stepIndexWithinSegment * priceIncreasePerStep_);

                return
                    (segmentIndex, stepIndexWithinSegment, priceAtCurrentStep);
            }
            cumulativeSupply_ = segmentEndSupply_;
        }

        // Target supply exceeds total curve capacity
        revert
            IDiscreteCurveMathLib_v1
            .DiscreteCurveMathLib__SupplyExceedsCurveCapacity(
            targetSupply_, cumulativeSupply_
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

            // Calculate collateral required for this portion of the segment
            uint collateralForPortion_ = _calculateSegmentReserve(
                initialPrice_,
                priceIncreasePerStep_,
                supplyPerStep_,
                supplyToProcessInSegment_
            );

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
        pure
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
            return (0, 0); // No tokens minted, no budget spent
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
                uint remainingStepCollateralCapacity_ = FixedPointMathLib
                    ._mulDivUp(
                    remainingStepIssuanceSupply_, stepPrice_, SCALING_FACTOR
                );

                if (remainingBudget_ >= remainingStepCollateralCapacity_) {
                    // Complete the step and move to next
                    remainingBudget_ -= remainingStepCollateralCapacity_;
                    tokensToMint_ += remainingStepIssuanceSupply_;
                    stepIndex_++;
                } else {
                    // Partial fill and exit - calculate tokens from remaining budget
                    uint partialIssuance_ = Math.mulDiv(
                        remainingBudget_, SCALING_FACTOR, stepPrice_
                    );
                    tokensToMint_ += partialIssuance_;
                    collateralSpentByPurchaser_ = collateralToSpendProvided_;
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
            uint stepCollateralCapacity_ = FixedPointMathLib._mulDivUp(
                supplyPerStep_, stepPrice_, SCALING_FACTOR
            );

            if (remainingBudget_ >= stepCollateralCapacity_) {
                // Purchase full step
                remainingBudget_ -= stepCollateralCapacity_;
                tokensToMint_ += supplyPerStep_;
                stepIndex_++;
            } else {
                // Partial step purchase and exit - calculate tokens from remaining budget
                uint partialIssuance_ =
                    Math.mulDiv(remainingBudget_, SCALING_FACTOR, stepPrice_);
                tokensToMint_ += partialIssuance_;
                break;
            }
        }

        // Calculate total collateral spent
        collateralSpentByPurchaser_ =
            collateralToSpendProvided_ - remainingBudget_;
        return (tokensToMint_, collateralSpentByPurchaser_);
    }

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
            revert
                IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__InsufficientIssuanceToSell(
                tokensToSell_, currentTotalIssuanceSupply_
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

        // Caller (e.g., FM_BC_Discrete via _calculateSaleReturn) is responsible for ensuring segments_ array
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
                    collateral_ += FixedPointMathLib._mulDivUp(
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
                collateral_ += FixedPointMathLib._mulDivUp(
                    supplyPerStep_, totalPriceForAllSteps_, SCALING_FACTOR
                );
            }
        }

        // Calculate cost for partial step (if any)
        if (partialStepSupply_ > 0) {
            uint partialStepPrice_ =
                initialPrice_ + (fullSteps_ * priceIncreasePerStep_);
            if (partialStepPrice_ > 0) {
                collateral_ += FixedPointMathLib._mulDivUp(
                    partialStepSupply_, partialStepPrice_, SCALING_FACTOR
                );
            }
        }

        return collateral_;
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

            // Validate single-step segments are flat
            if (currentNumberOfSteps_ == 1 && currentPriceIncrease_ > 0) {
                revert
                    IDiscreteCurveMathLib_v1
                    .DiscreteCurveMathLib__SingleStepMustBeFlat(i_);
            }

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
}
