// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.19;

import {PackedSegment} from "../types/PackedSegment_v1.sol";

/**
 * @title IDiscreteCurveMathLib_v1
 * @notice Interface for DiscreteCurveMathLib_v1, providing mathematical operations
 * for discrete bonding curves using packed segment data.
 */
interface IDiscreteCurveMathLib_v1 {
    /**
     * @notice Represents the configuration for a single segment of the curve when providing
     * human-readable input, before it's packed.
     * @param initialPriceOfSegment The price at the very beginning of this segment.
     * @param priceIncreasePerStep The amount the price increases with each step within this segment.
     * @param supplyPerStep The amount of new supply minted/sold at each step within this segment.
     * @param numberOfStepsInSegment The total number of discrete steps in this segment.
     */
    struct SegmentConfig {
        uint256 initialPriceOfSegment;
        uint256 priceIncreasePerStep;
        uint256 supplyPerStep;
        uint256 numberOfStepsInSegment;
    }

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
     * @notice Reverted when a segment is configured with zero initial price and zero price increase.
     */
    error DiscreteCurveMathLib__SegmentHasNoPrice();

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
    error DiscreteCurveMathLib__SupplyExceedsCurveCapacity(uint256 providedSupply, uint256 maxCapacity);

    // --- Events ---

    /**
     * @notice Emitted when a new segment is conceptually created and its packed representation is generated.
     * @dev This event is typically emitted by a contract that uses this library to manage curve segments.
     * @param segment The packed data of the created segment.
     * @param segmentIndex The index of the created segment in the curve's segment array.
     */
    event DiscreteCurveMathLib__SegmentCreated(PackedSegment indexed segment, uint256 indexed segmentIndex);

    // --- Functions ---

    function getCurrentPriceAndStep(
        PackedSegment[] memory segments,
        uint256 currentTotalIssuanceSupply
    ) external pure returns (uint256 price, uint256 stepIndex, uint256 segmentIndex);

    function calculateReserveForSupply(
        PackedSegment[] memory segments,
        uint256 targetSupply
    ) external pure returns (uint256 totalReserve);

    function calculatePurchaseReturn(
        PackedSegment[] memory segments,
        uint256 collateralAmountIn,
        uint256 currentTotalIssuanceSupply
    ) external pure returns (uint256 issuanceAmountOut, uint256 collateralAmountSpent);

    function calculateSaleReturn(
        PackedSegment[] memory segments,
        uint256 issuanceAmountIn,
        uint256 currentTotalIssuanceSupply
    ) external pure returns (uint256 collateralAmountOut, uint256 issuanceAmountBurned);

    function createSegment(
        uint256 initialPrice,
        uint256 priceIncrease,
        uint256 supplyPerStep,
        uint256 numberOfSteps
    ) external pure returns (PackedSegment);

    function validateSegmentArray(PackedSegment[] memory segments) external pure;
}
