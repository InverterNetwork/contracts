pragma solidity 0.8.23;

import {PackedSegment} from "../types/PackedSegment_v1.sol";
import {IDiscreteCurveMathLib_v1} from
    "../interfaces/IDiscreteCurveMathLib_v1.sol";

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
    uint private constant INITIAL_PRICE_BITS = 72; // Max: ~4.722e21 (scaled by 1e18 -> ~$4,722)
    uint private constant PRICE_INCREASE_BITS = 72; // Max: ~4.722e21 (scaled by 1e18 -> ~$4,722)
    uint private constant SUPPLY_BITS = 96; // Max: ~7.9e28 (scaled by 1e18 -> ~79 billion tokens)
    uint private constant STEPS_BITS = 16; // Max: 65,535 steps

    // Masks for extracting data
    uint private constant INITIAL_PRICE_MASK = (1 << INITIAL_PRICE_BITS) - 1;
    uint private constant PRICE_INCREASE_MASK = (1 << PRICE_INCREASE_BITS) - 1;
    uint private constant SUPPLY_MASK = (1 << SUPPLY_BITS) - 1;
    uint private constant STEPS_MASK = (1 << STEPS_BITS) - 1;

    // Bit offsets for packing data
    uint private constant INITIAL_PRICE_OFFSET = 0; // Not strictly needed for initial price, but good for consistency
    uint private constant PRICE_INCREASE_OFFSET = INITIAL_PRICE_BITS; // 72
    uint private constant SUPPLY_OFFSET =
        INITIAL_PRICE_BITS + PRICE_INCREASE_BITS; // 72 + 72 = 144
    uint private constant STEPS_OFFSET =
        INITIAL_PRICE_BITS + PRICE_INCREASE_BITS + SUPPLY_BITS; // 144 + 96 = 240

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
        uint _initialPrice,
        uint _priceIncrease,
        uint _supplyPerStep,
        uint _numberOfSteps
    ) internal pure returns (PackedSegment newSegment) {
        if (_initialPrice > INITIAL_PRICE_MASK) {
            revert
                IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__InitialPriceTooLarge();
        }
        if (_priceIncrease > PRICE_INCREASE_MASK) {
            revert
                IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__PriceIncreaseTooLarge();
        }
        if (_supplyPerStep == 0) {
            revert
                IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__ZeroSupplyPerStep();
        }
        if (_supplyPerStep > SUPPLY_MASK) {
            revert
                IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__SupplyPerStepTooLarge();
        }
        if (_numberOfSteps == 0 || _numberOfSteps > STEPS_MASK) {
            revert
                IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__InvalidNumberOfSteps();
        }
        // Disallow segments that are entirely free (both initial price and price increase are zero).
        if (_initialPrice == 0 && _priceIncrease == 0) {
            // Note: DiscreteCurveMathLib__SegmentIsFree error needs to be defined in IDiscreteCurveMathLib_v1.sol
            revert IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__SegmentIsFree(
            );
        }

        bytes32 packed = bytes32(
            _initialPrice | (_priceIncrease << PRICE_INCREASE_OFFSET)
                | (_supplyPerStep << SUPPLY_OFFSET)
                | (_numberOfSteps << STEPS_OFFSET)
        );
        return PackedSegment.wrap(packed);
    }

    /**
     * @notice Retrieves the initial price from a PackedSegment.
     * @param self The PackedSegment.
     * @return price The initial price.
     */
    function initialPrice(PackedSegment self)
        internal
        pure
        returns (uint price)
    {
        return uint(PackedSegment.unwrap(self)) & INITIAL_PRICE_MASK;
    }

    /**
     * @notice Retrieves the price increase per step from a PackedSegment.
     * @param self The PackedSegment.
     * @return increase The price increase per step.
     */
    function priceIncrease(PackedSegment self)
        internal
        pure
        returns (uint increase)
    {
        return (uint(PackedSegment.unwrap(self)) >> PRICE_INCREASE_OFFSET)
            & PRICE_INCREASE_MASK;
    }

    /**
     * @notice Retrieves the supply per step from a PackedSegment.
     * @param self The PackedSegment.
     * @return supply The supply per step.
     */
    function supplyPerStep(PackedSegment self)
        internal
        pure
        returns (uint supply)
    {
        return (uint(PackedSegment.unwrap(self)) >> SUPPLY_OFFSET) & SUPPLY_MASK;
    }

    /**
     * @notice Retrieves the number of steps from a PackedSegment.
     * @param self The PackedSegment.
     * @return steps The number of steps.
     */
    function numberOfSteps(PackedSegment self)
        internal
        pure
        returns (uint steps)
    {
        return (uint(PackedSegment.unwrap(self)) >> STEPS_OFFSET) & STEPS_MASK;
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
            uint initialPrice_,
            uint priceIncrease_,
            uint supplyPerStep_,
            uint numberOfSteps_
        )
    {
        uint data = uint(PackedSegment.unwrap(self));
        initialPrice_ = data & INITIAL_PRICE_MASK; // No shift needed as it's at offset 0
        priceIncrease_ = (data >> PRICE_INCREASE_OFFSET) & PRICE_INCREASE_MASK;
        supplyPerStep_ = (data >> SUPPLY_OFFSET) & SUPPLY_MASK;
        numberOfSteps_ = (data >> STEPS_OFFSET) & STEPS_MASK;
    }
}
