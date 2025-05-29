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

    // --- Constants ---
    uint public constant SCALING_FACTOR = 1e18;
    uint public constant MAX_SEGMENTS = 10;
    uint private constant MAX_LINEAR_SEARCH_STEPS = 200; // Max iterations for _linearSearchSloped


    // --- Internal Helper Functions ---

    /**
     * @notice Validates that the provided currentTotalIssuanceSupply is consistent with the segment configuration.
     * @dev Reverts if segments are empty and supply > 0, or if supply exceeds total capacity of all segments.
     * @param segments Array of PackedSegment configurations for the curve.
     * @param currentTotalIssuanceSupply The current total issuance supply to validate.
     */
    function _validateSupplyAgainstSegments(
        PackedSegment[] memory segments,
        uint currentTotalIssuanceSupply
    ) internal pure returns (uint totalCurveCapacity) {
        // Added return type
        uint numSegments = segments.length; // Cache length
        if (numSegments == 0) {
            if (currentTotalIssuanceSupply > 0) {
                // It's invalid to have a supply if no segments are defined to back it.
                revert
                    IDiscreteCurveMathLib_v1
                    .DiscreteCurveMathLib__NoSegmentsConfigured();
            }
            // If segments.length == 0 and currentTotalIssuanceSupply == 0, it's a valid initial state.
            return 0; // Return 0 capacity
        }

        // totalCurveCapacity is initialized to 0 by default as a return variable
        for (uint segmentIndex = 0; segmentIndex < numSegments; ++segmentIndex)
        {
            // Use cached length
            // Note: supplyPerStep and numberOfSteps are validated > 0 by PackedSegmentLib.create
            uint supplyPerStep = segments[segmentIndex].supplyPerStep();
            uint numberOfStepsInSegment = segments[segmentIndex].numberOfSteps();
            totalCurveCapacity += numberOfStepsInSegment * supplyPerStep;
        }

        if (currentTotalIssuanceSupply > totalCurveCapacity) {
            revert
                IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__SupplyExceedsCurveCapacity(
                currentTotalIssuanceSupply, totalCurveCapacity
            );
        }
        // Implicitly returns totalCurveCapacity
    }

    /**
     * @notice Finds the segment, step, price, and cumulative supply for a given target total issuance supply.
     * @dev Iterates linearly through segments.
     * @param segments Array of PackedSegment configurations for the curve.
     * @param targetSupply The total supply for which to find the position.
     * @return position A CurvePosition struct detailing the location on the curve.
     */
    function _findPositionForSupply(
        PackedSegment[] memory segments,
        uint targetSupply // Renamed from targetTotalIssuanceSupply
    ) internal pure returns (IDiscreteCurveMathLib_v1.CurvePosition memory position) {
        uint numSegments = segments.length;
        if (numSegments == 0) {
            revert
                IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__NoSegmentsConfigured();
        }
        // Although callers like getCurrentPriceAndStep might do their own MAX_SEGMENTS check via validateSegmentArray,
        // _findPositionForSupply can be called by other internal logic, so keeping this is safer.
        if (numSegments > MAX_SEGMENTS) {
            revert
                IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__TooManySegments();
        }

        uint cumulativeSupply = 0;

        for (uint i = 0; i < numSegments; ++i) {
            (
                uint initialPrice,
                uint priceIncreasePerStep,
                uint supplyPerStep,
                uint totalStepsInSegment
            ) = segments[i].unpack();

            uint segmentCapacity = totalStepsInSegment * supplyPerStep;
            uint segmentEndSupply = cumulativeSupply + segmentCapacity;

            if (targetSupply <= segmentEndSupply) {
                // Found the segment where targetSupply resides or ends.
                position.segmentIndex = i;
                // supplyCoveredUpToThisPosition is critical for getCurrentPriceAndStep validation.
                // If targetSupply is within this segment (or at its end), it's covered up to targetSupply.
                position.supplyCoveredUpToThisPosition = targetSupply;

                if (targetSupply == segmentEndSupply && i + 1 < numSegments) {
                    // Exactly at a boundary AND there's a next segment:
                    // Position points to the start of the next segment.
                    position.segmentIndex = i + 1;
                    position.stepIndexWithinSegment = 0;
                    // Price is the initial price of the next segment.
                    position.priceAtCurrentStep = segments[i + 1].initialPrice(); // Use direct accessor
                } else {
                    // Either within the current segment, or at the end of the *last* segment.
                    uint supplyIntoThisSegment = targetSupply - cumulativeSupply;
                    // stepIndex is the 0-indexed step that contains/is completed by supplyIntoThisSegment.
                    // For "next price" semantic, this is the step whose price will be quoted.
                    position.stepIndexWithinSegment =
                        supplyIntoThisSegment / supplyPerStep;

                    // If at the end of the *last* segment, stepIndex needs to be the last step.
                    if (
                        targetSupply == segmentEndSupply && i == numSegments - 1
                    ) {
                        position.stepIndexWithinSegment = totalStepsInSegment
                            > 0 ? totalStepsInSegment - 1 : 0;
                    }
                    position.priceAtCurrentStep = initialPrice
                        + (position.stepIndexWithinSegment * priceIncreasePerStep);
                }
                return position;
            }
            cumulativeSupply = segmentEndSupply;
        }

        // Fallback: targetSupply is greater than total capacity of all segments.
        // This should be caught by _validateSupplyAgainstSegments in public-facing functions.
        // If reached, position to the end of the last segment.
        position.segmentIndex = numSegments - 1;
        (
            uint lastSegInitialPrice,
            uint lastSegPriceIncreasePerStep,
            ,
            uint lastSegTotalSteps
        ) = segments[numSegments - 1].unpack();

        position.stepIndexWithinSegment =
            lastSegTotalSteps > 0 ? lastSegTotalSteps - 1 : 0;
        position.priceAtCurrentStep = lastSegInitialPrice
            + (position.stepIndexWithinSegment * lastSegPriceIncreasePerStep);
        // supplyCoveredUpToThisPosition is the total capacity of the curve.
        position.supplyCoveredUpToThisPosition = cumulativeSupply;
        return position;
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
        uint currentTotalIssuanceSupply
    ) internal pure returns (uint price, uint stepIndex, uint segmentIndex) {
        // Perform validation first. This will revert if currentTotalIssuanceSupply > totalCurveCapacity.
        _validateSupplyAgainstSegments(segments, currentTotalIssuanceSupply);
        // Note: The returned totalCurveCapacity is not explicitly used here as _findPositionForSupply
        // will correctly determine the position based on the now-validated currentTotalIssuanceSupply.

        // _findPositionForSupply can now assume currentTotalIssuanceSupply is valid (within or at capacity).
        IDiscreteCurveMathLib_v1.CurvePosition memory posDetails =
            _findPositionForSupply(segments, currentTotalIssuanceSupply);

        // The previous explicit check:
        // if (currentTotalIssuanceSupply > posDetails.supplyCoveredUpToThisPosition) {
        //     revert IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__TargetSupplyBeyondCurveCapacity();
        // }
        // is now covered by the _validateSupplyAgainstSegments call above.
        // _findPositionForSupply ensures posDetails.supplyCoveredUpToThisPosition is either currentTotalIssuanceSupply
        // or the total curve capacity if currentTotalIssuanceSupply was at the very end.

        // Since _findPositionForSupply now correctly handles
        // segment boundaries by pointing to the start of the next segment (or the last step of the
        // last segment if at max capacity), and returns the price/step for that position,
        // we can directly use its output. The complex adjustment logic previously here is no longer needed.
        return (
            posDetails.priceAtCurrentStep,
            posDetails.stepIndexWithinSegment,
            posDetails.segmentIndex
        );
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
        uint targetSupply
    ) internal pure returns (uint totalReserve) {
        if (targetSupply == 0) {
            return 0;
        }
        uint numSegments = segments.length; // Cache length
        if (numSegments == 0) {
            revert
                IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__NoSegmentsConfigured();
        }
        if (numSegments > MAX_SEGMENTS) {
            revert
                IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__TooManySegments();
        }
        _validateSupplyAgainstSegments(segments, targetSupply); // Validation occurs, returned capacity not stored if unused
        // The loop condition `cumulativeSupplyProcessed >= targetSupply` and `targetSupply <= totalCurveCapacity` (from validation)
        // should be sufficient.

        uint cumulativeSupplyProcessed = 0;
        // totalReserve is initialized to 0 by default

        for (uint segmentIndex = 0; segmentIndex < numSegments; ++segmentIndex)
        {
            // Use cached length
            if (cumulativeSupplyProcessed >= targetSupply) {
                break; // All target supply has been accounted for.
            }

            // Unpack segment data - using batch unpack as per instruction suggestion for this case
            (
                uint initialPrice,
                uint priceIncreasePerStep,
                uint supplyPerStep,
                uint totalStepsInSegment
            ) = segments[segmentIndex].unpack();
            // Note: supplyPerStep is guaranteed > 0 by PackedSegmentLib.create validation.

            uint supplyRemainingInTarget =
                targetSupply - cumulativeSupplyProcessed;

            // Calculate how many steps from *this* segment are needed to cover supplyRemainingInTarget
            // Ceiling division: (numerator + denominator - 1) / denominator
            uint stepsToProcessInSegment =
                (supplyRemainingInTarget + supplyPerStep - 1) / supplyPerStep;

            // Cap at the segment's actual available steps
            if (stepsToProcessInSegment > totalStepsInSegment) {
                stepsToProcessInSegment = totalStepsInSegment;
            }

            uint collateralForPortion;
            if (priceIncreasePerStep == 0) {
                // Flat segment
                // Use mulDivUp for conservative reserve calculation (favors protocol)
                if (initialPrice == 0) {
                    // Free portion
                    collateralForPortion = 0;
                } else {
                    collateralForPortion = _mulDivUp(
                        stepsToProcessInSegment * supplyPerStep,
                        initialPrice,
                        SCALING_FACTOR
                    );
                }
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
                    uint firstStepPrice = initialPrice;
                    uint lastStepPrice = initialPrice
                        + (stepsToProcessInSegment - 1) * priceIncreasePerStep;
                    uint sumOfPrices = firstStepPrice + lastStepPrice;
                    uint totalPriceForAllStepsInPortion;
                    if (sumOfPrices == 0 || stepsToProcessInSegment == 0) {
                        totalPriceForAllStepsInPortion = 0;
                    } else {
                        // n * sumOfPrices is always even, so Math.mulDiv is exact.
                        totalPriceForAllStepsInPortion =
                            Math.mulDiv(stepsToProcessInSegment, sumOfPrices, 2);
                    }
                    // Use mulDivUp for conservative reserve calculation (favors protocol)
                    collateralForPortion = _mulDivUp(
                        supplyPerStep,
                        totalPriceForAllStepsInPortion,
                        SCALING_FACTOR
                    );
                }
            }

            totalReserve += collateralForPortion;
            cumulativeSupplyProcessed += stepsToProcessInSegment * supplyPerStep;
        }

        // Note: The case where targetSupply > totalCurveCapacity is handled by the
        // _validateSupplyAgainstSegments check at the beginning of this function,
        // which will cause a revert. Therefore, this function will only proceed
        // if targetSupply is within the curve's defined capacity.
        // If, for some other reason, cumulativeSupplyProcessed < targetSupply at this point
        // (e.g. an issue with loop logic or segment data), it implies an internal inconsistency
        // as the initial validation should have caught out-of-bounds targetSupply.
        // The function calculates reserve for the portion of targetSupply covered by the loop.

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
        uint collateralToSpendProvided, // Renamed from collateralAmountIn
        uint currentTotalIssuanceSupply
    )
        internal
        pure
        returns (uint tokensToMint, uint collateralSpentByPurchaser)
    {
        // Renamed return values
        _validateSupplyAgainstSegments(segments, currentTotalIssuanceSupply); // Validation occurs
        // If totalCurveCapacity is needed later, _validateSupplyAgainstSegments can be called again,
        // or a separate _getTotalCapacity function could be used if this becomes a frequent pattern.

        if (collateralToSpendProvided == 0) {
            revert
                IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__ZeroCollateralInput();
        }

        uint numSegments = segments.length; // Renamed from segLen
        if (numSegments == 0) {
            revert
                IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__NoSegmentsConfigured();
        }

        // tokensToMint and collateralSpentByPurchaser are initialized to 0 by default as return variables
        uint budgetRemaining = collateralToSpendProvided; // Renamed from remainingCollateral

        (
            uint priceAtPurchaseStart,
            uint stepAtPurchaseStart,
            uint segmentIndexAtPurchaseStart // Renamed from segmentAtPurchaseStart
        ) = getCurrentPriceAndStep(segments, currentTotalIssuanceSupply);

        for (
            uint currentSegmentIndex = segmentIndexAtPurchaseStart;
            currentSegmentIndex < numSegments;
            ++currentSegmentIndex
        ) {
            // Renamed i to currentSegmentIndex
            if (budgetRemaining == 0) {
                break;
            }

            uint startStepInCurrentSegment; // Renamed from currentSegmentStartStepForHelper
            uint priceAtStartStepInCurrentSegment; // Renamed from priceAtCurrentSegmentStartStepForHelper
            PackedSegment currentSegment = segments[currentSegmentIndex];

            (uint currentSegmentInitialPrice,,, uint currentSegmentTotalSteps) =
                currentSegment.unpack(); // Renamed cs variables

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

            (uint tokensMintedInSegment, uint collateralSpentInSegment) = // Renamed issuanceBoughtThisSegment, collateralSpentThisSegment
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
        uint availableBudget, // Renamed from _budget
        uint pricePerStepInFlatSegment, // Renamed from _priceAtSegmentInitialStep
        uint supplyPerStepInSegment, // Renamed from _sPerStepSeg
        uint stepsAvailableToPurchase // Renamed from _stepsAvailableToPurchaseInSeg
    ) private pure returns (uint tokensMinted, uint collateralSpent) {
        // Renamed issuanceOut
        // Calculate full steps for flat segment
        // The caller (_calculatePurchaseForSingleSegment) ensures priceAtPurchaseStartStep (which becomes pricePerStepInFlatSegment) is non-zero.
        // Adding an explicit check here for defense-in-depth.
        require(
            pricePerStepInFlatSegment > 0,
            "Price cannot be zero for non-free flat segment step calculation"
        );
        uint maxTokensMintableWithBudget = Math.mulDiv(
            availableBudget, SCALING_FACTOR, pricePerStepInFlatSegment
        );
        uint numFullStepsAffordable =
            maxTokensMintableWithBudget / supplyPerStepInSegment;

        if (numFullStepsAffordable > stepsAvailableToPurchase) {
            numFullStepsAffordable = stepsAvailableToPurchase;
        }
        tokensMinted = numFullStepsAffordable * supplyPerStepInSegment;
        // collateralSpent should be rounded up to favor the protocol
        collateralSpent =
            _mulDivUp(tokensMinted, pricePerStepInFlatSegment, SCALING_FACTOR);
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
        uint totalBudget, // Renamed from budget
        uint purchaseStartStepInSegment, // Renamed from startStep
        uint priceAtPurchaseStartStep // Renamed from startPrice
    ) internal pure returns (uint tokensPurchased, uint totalCollateralSpent) {
        // Renamed issuanceOut, collateralSpent
        (
            ,
            uint priceIncreasePerStep,
            uint supplyPerStep,
            uint totalStepsInSegment
        ) = segment.unpack(); // Renamed variables

        if (purchaseStartStepInSegment >= totalStepsInSegment) {
            revert
                IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__InvalidSegmentInitialStep();
        }
        uint maxStepsPurchasableInSegment =
            totalStepsInSegment - purchaseStartStepInSegment; // Renamed

        uint priceForCurrentStep = priceAtPurchaseStartStep; // Renamed
        uint stepsSuccessfullyPurchased = 0; // Renamed
        // totalCollateralSpent is already a return variable, can use it directly.

        // Loop capped by MAX_LINEAR_SEARCH_STEPS to prevent excessive gas usage (HIGH-1)
        while (
            stepsSuccessfullyPurchased < maxStepsPurchasableInSegment
                && stepsSuccessfullyPurchased < MAX_LINEAR_SEARCH_STEPS
        ) {
            // costForCurrentStep should be rounded up to favor the protocol
            uint costForCurrentStep =
                _mulDivUp(supplyPerStep, priceForCurrentStep, SCALING_FACTOR); // Renamed

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
        uint budgetForSegment, // Renamed from remainingCollateralIn
        uint purchaseStartStepInSegment, // Renamed from segmentInitialStep
        uint priceAtPurchaseStartStep // Renamed from priceAtSegmentInitialStep
    ) private pure returns (uint tokensToIssue, uint collateralToSpend) {
        // Renamed return values
        // Unpack segment details once at the beginning
        (
            ,
            uint priceIncreasePerStep,
            uint supplyPerStep,
            uint totalStepsInSegment
        ) = segment.unpack(); // Renamed

        if (purchaseStartStepInSegment >= totalStepsInSegment) {
            revert
                IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__InvalidSegmentInitialStep();
        }

        uint remainingStepsInSegment =
            totalStepsInSegment - purchaseStartStepInSegment; // Renamed
        // tokensToIssue and collateralToSpend are implicitly initialized to 0 as return variables.

        if (priceIncreasePerStep == 0) {
            // Flat Segment Logic
            if (priceAtPurchaseStartStep == 0) {
                // Entirely free mint part of the segment
                tokensToIssue = remainingStepsInSegment * supplyPerStep;
                // collateralToSpend is implicitly 0
                return (tokensToIssue, 0);
            } else {
                // Non-free flat part
                (tokensToIssue, collateralToSpend) =
                _calculateFullStepsForFlatSegment(
                    budgetForSegment,
                    priceAtPurchaseStartStep,
                    supplyPerStep,
                    remainingStepsInSegment
                );

                uint budgetRemainingForPartialPurchase =
                    budgetForSegment - collateralToSpend; // Renamed
                uint maxPartialIssuanceFromSegment =
                    (remainingStepsInSegment * supplyPerStep) - tokensToIssue; // Renamed
                uint numFullStepsPurchased = tokensToIssue / supplyPerStep;

                if (
                    numFullStepsPurchased < remainingStepsInSegment
                        && budgetRemainingForPartialPurchase > 0
                        && maxPartialIssuanceFromSegment > 0
                ) {
                    (uint partialTokensIssued, uint partialCollateralSpent) =
                    _calculatePartialPurchaseAmount( // Renamed
                        budgetRemainingForPartialPurchase,
                        priceAtPurchaseStartStep,
                        supplyPerStep,
                        maxPartialIssuanceFromSegment
                    );
                    tokensToIssue += partialTokensIssued;
                    collateralToSpend += partialCollateralSpent;
                }
            }
        } else {
            // Sloped Segment Logic
            (uint fullStepTokensIssued, uint fullStepCollateralSpent) =
            _linearSearchSloped( // Renamed
                segment,
                budgetForSegment,
                purchaseStartStepInSegment,
                priceAtPurchaseStartStep
            );

            tokensToIssue = fullStepTokensIssued;
            collateralToSpend = fullStepCollateralSpent;

            uint numFullStepsPurchased = fullStepTokensIssued / supplyPerStep;

            uint budgetRemainingForPartialPurchase =
                budgetForSegment - collateralToSpend; // Renamed
            uint priceForNextPartialStep = priceAtPurchaseStartStep
                + (numFullStepsPurchased * priceIncreasePerStep); // Renamed
            uint maxPartialIssuanceFromSegment =
                (remainingStepsInSegment * supplyPerStep) - tokensToIssue; // Renamed

            if (
                numFullStepsPurchased < remainingStepsInSegment
                    && budgetRemainingForPartialPurchase > 0
                    && maxPartialIssuanceFromSegment > 0
            ) {
                (uint partialTokensIssued, uint partialCollateralSpent) =
                _calculatePartialPurchaseAmount( // Renamed
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
        uint availableBudget, // Renamed from _budget
        uint pricePerTokenForPartialPurchase, // Renamed from _priceForPartialStep
        uint maxTokensPerIndividualStep, // Renamed from _supplyPerFullStep
        uint maxTokensRemainingInSegment // Renamed from _maxIssuanceAllowedOverall
    ) private pure returns (uint tokensToIssue, uint collateralToSpend) {
        // Renamed return values
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
        uint maxAffordableTokens = Math.mulDiv(
            availableBudget, SCALING_FACTOR, pricePerTokenForPartialPurchase
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
        // collateralToSpend should be rounded up to favor the protocol
        collateralToSpend = _mulDivUp(
            tokensToIssue, pricePerTokenForPartialPurchase, SCALING_FACTOR
        );

        return (tokensToIssue, collateralToSpend);
    }

    /**
     * @dev Helper function to find the minimum of three uint256 values.
     */
    function _min3(uint a, uint b, uint c) private pure returns (uint) {
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
        uint tokensToSell, // Renamed from issuanceAmountIn
        uint currentTotalIssuanceSupply
    ) internal pure returns (uint collateralToReturn, uint tokensToBurn) {
        // Renamed return values
        _validateSupplyAgainstSegments(segments, currentTotalIssuanceSupply); // Validation occurs
        // If totalCurveCapacity is needed later, _validateSupplyAgainstSegments can be called again.

        if (tokensToSell == 0) {
            revert
                IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__ZeroIssuanceInput();
        }

        uint numSegments = segments.length; // Renamed from segLen
        if (numSegments == 0) {
            // This implies currentTotalIssuanceSupply must be 0.
            // Selling from 0 supply on an unconfigured curve. tokensToBurn will be 0.
        }

        tokensToBurn = tokensToSell > currentTotalIssuanceSupply
            ? currentTotalIssuanceSupply
            : tokensToSell;

        if (tokensToBurn == 0) {
            return (0, 0);
        }

        uint finalSupplyAfterSale = currentTotalIssuanceSupply - tokensToBurn;

        uint collateralAtCurrentSupply =
            calculateReserveForSupply(segments, currentTotalIssuanceSupply);
        uint collateralAtFinalSupply =
            calculateReserveForSupply(segments, finalSupplyAfterSale);

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
        uint initialPrice,
        uint priceIncrease,
        uint supplyPerStep,
        uint numberOfSteps
    ) internal pure returns (PackedSegment) {
        // All validation is handled by PackedSegmentLib.create
        return PackedSegmentLib.create(
            initialPrice, priceIncrease, supplyPerStep, numberOfSteps
        );
    }

    /**
     * @notice Validates an array of PackedSegments.
     * @dev Checks for empty array, exceeding max segments, and basic validity of each segment.
     *      More detailed validation of individual segment parameters occurs at creation time.
     * @param segments Array of PackedSegment configurations to validate.
     */
    function validateSegmentArray(PackedSegment[] memory segments)
        internal
        pure
    {
        uint numSegments = segments.length; // Renamed from segLen
        if (numSegments == 0) {
            revert
                IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__NoSegmentsConfigured();
        }
        if (numSegments > MAX_SEGMENTS) {
            revert
                IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__TooManySegments();
        }

        // Note: Individual segment's supplyPerStep > 0 and numberOfSteps > 0
        // are guaranteed by PackedSegmentLib.create validation.
        // Also, segments with initialPrice == 0 AND priceIncreasePerStep == 0 are disallowed by PackedSegmentLib.create.
        // This function primarily validates array-level properties and inter-segment price progression.

        // Check for non-decreasing price progression between segments.
        // The initial price of segment i+1 must be >= final price of segment i.
        for (uint i = 0; i < numSegments - 1; ++i) {
            PackedSegment currentSegment = segments[i];
            PackedSegment nextSegment = segments[i + 1];

            uint currentInitialPrice = currentSegment.initialPrice();
            uint currentPriceIncrease = currentSegment.priceIncrease();
            uint currentNumberOfSteps = currentSegment.numberOfSteps();

            // Final price of the current segment.
            // If numberOfSteps is 1, final price is initialPrice.
            // Otherwise, it's initialPrice + (numberOfSteps - 1) * priceIncrease.
            uint finalPriceCurrentSegment;
            if (currentNumberOfSteps == 0) {
                // This case should be prevented by PackedSegmentLib.create's check for numberOfSteps > 0.
                // If somehow reached, treat as an invalid state or handle as per specific requirements.
                // For safety, assume it implies an issue, though create() should prevent it.
                // As a defensive measure, one might revert or assign a value that ensures progression check logic.
                // However, relying on create() validation is typical.
                // If steps is 0, let's consider its "final price" to be its initial price to avoid underflow with (steps-1).
                finalPriceCurrentSegment = currentInitialPrice;
            } else if (currentNumberOfSteps == 1) {
                finalPriceCurrentSegment = currentInitialPrice;
            } else {
                finalPriceCurrentSegment = currentInitialPrice
                    + (currentNumberOfSteps - 1) * currentPriceIncrease;
                // Check for overflow in final price calculation, though bit limits on components make this unlikely
                // to overflow uint256 unless priceIncrease is extremely large.
                // Max initialPrice ~2^72, max (steps-1)*priceIncrease ~ (2^16)*(2^72) ~ 2^88. Sum ~2^88. Fits uint256.
            }

            uint initialPriceNextSegment = nextSegment.initialPrice();

            if (initialPriceNextSegment < finalPriceCurrentSegment) {
                // Note: DiscreteCurveMathLib__InvalidPriceProgression error needs to be defined in IDiscreteCurveMathLib_v1.sol
                revert
                    IDiscreteCurveMathLib_v1
                    .DiscreteCurveMathLib__InvalidPriceProgression(
                    i, finalPriceCurrentSegment, initialPriceNextSegment
                );
            }
        }
    }

    // --- Custom Math Helpers for Rounding ---

    /**
     * @dev Calculates (a * b) % modulus.
     * @notice Solidity 0.8.x's default behavior for `(a * b) % modulus` computes the product `a * b`
     * using full 256x256 bit precision before applying the modulus, preventing overflow of `a * b`
     * from affecting the result of the modulo operation itself (as long as modulus is not zero).
     * @param a The first operand.
     * @param b The second operand.
     * @param modulus The modulus.
     * @return (a * b) % modulus.
     */
    function _mulmod(uint a, uint b, uint modulus)
        private
        pure
        returns (uint)
    {
        require(
            modulus > 0,
            "DiscreteCurveMathLib_v1: modulus cannot be zero in _mulmod"
        );
        return (a * b) % modulus;
    }

    /**
     * @dev Calculates (a * b) / denominator, rounding up.
     * @param a The first operand for multiplication.
     * @param b The second operand for multiplication.
     * @param denominator The denominator for division.
     * @return result ceil((a * b) / denominator).
     */
    function _mulDivUp(uint a, uint b, uint denominator)
        private
        pure
        returns (uint result)
    {
        require(
            denominator > 0,
            "DiscreteCurveMathLib_v1: division by zero in _mulDivUp"
        );
        result = Math.mulDiv(a, b, denominator); // Standard OpenZeppelin Math.mulDiv rounds down (floor division)

        // If there's any remainder from (a * b) / denominator, we need to add 1 to round up.
        // A remainder exists if (a * b) % denominator is not 0.
        // We use the local _mulmod function which safely computes (a * b) % denominator.
        if (_mulmod(a, b, denominator) > 0) {
            // Before incrementing, check if 'result' is already at max_uint256 to prevent overflow.
            // This scenario (overflowing after adding 1 due to rounding) is extremely unlikely if a, b, denominator
            // are such that mulDiv itself doesn't revert, but it's a good safety check.
            require(
                result < type(uint).max,
                "DiscreteCurveMathLib_v1: _mulDivUp overflow on increment"
            );
            result++;
        }
        return result;
    }
}
