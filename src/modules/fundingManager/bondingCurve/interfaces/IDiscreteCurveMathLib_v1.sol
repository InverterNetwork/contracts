// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.19;

import {PackedSegment} from "../types/PackedSegment_v1.sol";

/**
 * @title IDiscreteCurveMathLib_v1
 * @notice Interface for DiscreteCurveMathLib_v1, providing mathematical operations
 * for discrete bonding curves using packed segment data.
 */
interface IDiscreteCurveMathLib_v1 {
    // --- Errors ---

    /**
     * @notice Reverted when an attempt is made to configure a segment with an initial price
     * that exceeds the maximum allowed value for packed storage.
     */
    error DiscreteCurveMathLib__InitialPriceTooLarge();

    /**
     * @notice Reverted when an attempt is made to configure a segment with a price increase per step
     * that exceeds the maximum allowed value for packed storage.
     */
    error DiscreteCurveMathLib__PriceIncreaseTooLarge();

    /**
     * @notice Reverted when an attempt is made to configure a segment with a supply per step
     * that exceeds the maximum allowed value for packed storage.
     */
    error DiscreteCurveMathLib__SupplyPerStepTooLarge();

    /**
     * @notice Reverted when an attempt is made to configure a segment with an invalid number of steps
     * (e.g., zero or exceeding the maximum allowed value for packed storage).
     */
    error DiscreteCurveMathLib__InvalidNumberOfSteps();

    /**
     * @notice Reverted when an operation requires segments to be configured, but none are.
     */
    error DiscreteCurveMathLib__NoSegmentsConfigured();

    /**
     * @notice Reverted when the number of segments provided exceeds the maximum allowed.
     */
    error DiscreteCurveMathLib__TooManySegments();

    /**
     * @notice Reverted when a segment is configured with zero supply per step.
     */
    error DiscreteCurveMathLib__ZeroSupplyPerStep();

    /**
     * @notice Reverted when an attempt is made to configure a segment that is entirely free
     * (i.e., initialPrice is 0 and priceIncreasePerStep is 0).
     */
    error DiscreteCurveMathLib__SegmentIsFree();

    /**
     * @notice Reverted when the price progression between segments is invalid.
     * Specifically, if the initial price of a segment is less than the final price of the preceding segment.
     * @param segmentIndex The index of the first segment in the pair being compared (the one that ends).
     * @param previousSegmentFinalPrice The calculated final price of segment `segmentIndex`.
     * @param nextSegmentInitialPrice The initial price of segment `segmentIndex + 1`.
     */
    error DiscreteCurveMathLib__InvalidPriceProgression(
        uint segmentIndex,
        uint previousSegmentFinalPrice,
        uint nextSegmentInitialPrice
    );

    /**
     * @notice Reverted when an operation (e.g., purchase) cannot be fulfilled due to
     * insufficient liquidity or supply available on the curve.
     */
    error DiscreteCurveMathLib__InsufficientLiquidity();

    /**
     * @notice Reverted when an input supply amount for an operation (e.g., sale)
     * exceeds the total current issuance supply.
     */
    error DiscreteCurveMathLib__SupplyAmountExceedsTotal();

    /**
     * @notice Reverted when a target supply is requested that is beyond the capacity of the configured curve.
     */
    error DiscreteCurveMathLib__TargetSupplyBeyondCurveCapacity();

    /**
     * @notice Reverted when a purchase or sale operation is attempted with zero collateral or issuance tokens respectively.
     */
    error DiscreteCurveMathLib__ZeroCollateralInput();
    error DiscreteCurveMathLib__ZeroIssuanceInput();

    /**
     * @notice Reverted when _calculatePurchaseForSingleSegment is called with a segmentInitialStep
     * that is out of bounds for the segment's number of steps.
     */
    error DiscreteCurveMathLib__InvalidSegmentInitialStep();

    /**
     * @notice Reverted when a provided currentTotalIssuanceSupply exceeds the total capacity of all configured segments.
     * @param providedSupply The currentTotalIssuanceSupply that was provided.
     * @param maxCapacity The calculated maximum capacity of the curve based on its segments.
     */
    error DiscreteCurveMathLib__SupplyExceedsCurveCapacity(
        uint providedSupply, uint maxCapacity
    );

    /**
     * @notice Reverted when a flat segment (priceIncrease == 0) is defined with more than one step.
     * Flat segments must have exactly one step.
     */
    error DiscreteCurveMathLib__InvalidFlatSegment();

    /**
     * @notice Reverted when a point segment (numberOfSteps == 1) is defined with a price increase.
     * Point segments must have zero price increase (i.e., be flat).
     */
    error DiscreteCurveMathLib__InvalidPointSegment();

    /**
     * @notice Reverted when attempting to sell more tokens than are currently in supply.
     * @param requested The amount of tokens requested to be sold.
     * @param available The actual amount of tokens available for sale (current total issuance supply).
     */
    error DiscreteCurveMathLib__InsufficientIssuanceToSell(
        uint requested, uint available
    );

    /**
     * @notice Reverted when a single-step segment is configured with a non-zero price increase.
     * @param segmentIndex The index of the segment that is configured with a non-zero price increase.
     */
    error DiscreteCurveMathLib__SingleStepMustBeFlat(uint segmentIndex);

    // --- Events ---

    /**
     * @notice Emitted when a new segment is conceptually created and its packed representation is generated.
     * @dev This event is typically emitted by a contract that uses this library to manage curve segments.
     * @param segment The packed data of the created segment.
     * @param segmentIndex The index of the created segment in the curve's segment array.
     */
    event DiscreteCurveMathLib__SegmentCreated(
        PackedSegment indexed segment, uint indexed segmentIndex
    );

    // --- Functions ---

    function getCurrentPriceAndStep(
        PackedSegment[] memory segments,
        uint currentTotalIssuanceSupply
    ) external pure returns (uint price, uint stepIndex, uint segmentIndex);

    function calculateReserveForSupply(
        PackedSegment[] memory segments,
        uint targetSupply
    ) external pure returns (uint totalReserve);

    function calculatePurchaseReturn(
        PackedSegment[] memory segments,
        uint collateralAmountIn,
        uint currentTotalIssuanceSupply
    )
        external
        pure
        returns (uint issuanceAmountOut, uint collateralAmountSpent);

    function calculateSaleReturn(
        PackedSegment[] memory segments,
        uint issuanceAmountIn,
        uint currentTotalIssuanceSupply
    )
        external
        pure
        returns (uint collateralAmountOut, uint issuanceAmountBurned);

    function createSegment(
        uint initialPrice,
        uint priceIncrease,
        uint supplyPerStep,
        uint numberOfSteps
    ) external pure returns (PackedSegment);

    function validateSegmentArray(PackedSegment[] memory segments)
        external
        pure;
}
