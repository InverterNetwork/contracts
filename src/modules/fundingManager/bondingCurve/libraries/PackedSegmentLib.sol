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
    // =========================================================================
    // Constants

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

    function _create(
        uint initialPrice_,
        uint priceIncrease_,
        uint supplyPerStep_,
        uint numberOfSteps_
    ) internal pure returns (PackedSegment newSegment_) {
        // Existing validations...
        if (initialPrice_ > INITIAL_PRICE_MASK) {
            revert
                IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__InitialPriceTooLarge();
        }
        if (priceIncrease_ > PRICE_INCREASE_MASK) {
            revert
                IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__PriceIncreaseTooLarge();
        }
        if (supplyPerStep_ == 0) {
            revert
                IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__ZeroSupplyPerStep();
        }
        if (supplyPerStep_ > SUPPLY_MASK) {
            revert
                IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__SupplyPerStepTooLarge();
        }
        if (numberOfSteps_ == 0 || numberOfSteps_ > STEPS_MASK) {
            revert
                IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__InvalidNumberOfSteps();
        }

        // Prevent entirely free segments (zero collateral required)
        if (initialPrice_ == 0 && priceIncrease_ == 0) {
            revert IDiscreteCurveMathLib_v1.DiscreteCurveMathLib__SegmentIsFree(
            );
        }

        // VALIDATIONS based on design assumptions:

        // 1. Prevent multi-step flat segments (mathematical model violation)
        if (numberOfSteps_ > 1 && priceIncrease_ == 0) {
            revert
                IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__InvalidFlatSegment();
        }

        // 2. Prevent point segments (single step with price increase makes no sense)
        if (numberOfSteps_ == 1 && priceIncrease_ > 0) {
            revert
                IDiscreteCurveMathLib_v1
                .DiscreteCurveMathLib__InvalidPointSegment();
        }

        // Rest of function unchanged...
        bytes32 packed_ = bytes32(
            initialPrice_ | (priceIncrease_ << PRICE_INCREASE_OFFSET)
                | (supplyPerStep_ << SUPPLY_OFFSET)
                | (numberOfSteps_ << STEPS_OFFSET)
        );
        return PackedSegment.wrap(packed_);
    }

    /**
     * @notice Retrieves the initial price from a PackedSegment.
     * @param self_ The PackedSegment.
     * @return price_ The initial price.
     */
    function _initialPrice(PackedSegment self_)
        internal
        pure
        returns (uint price_)
    {
        return uint(PackedSegment.unwrap(self_)) & INITIAL_PRICE_MASK;
    }

    /**
     * @notice Retrieves the price increase per step from a PackedSegment.
     * @param self_ The PackedSegment.
     * @return increase_ The price increase per step.
     */
    function _priceIncrease(PackedSegment self_)
        internal
        pure
        returns (uint increase_)
    {
        return (uint(PackedSegment.unwrap(self_)) >> PRICE_INCREASE_OFFSET)
            & PRICE_INCREASE_MASK;
    }

    /**
     * @notice Retrieves the supply per step from a PackedSegment.
     * @param self_ The PackedSegment.
     * @return supply_ The supply per step.
     */
    function _supplyPerStep(PackedSegment self_)
        internal
        pure
        returns (uint supply_)
    {
        return
            (uint(PackedSegment.unwrap(self_)) >> SUPPLY_OFFSET) & SUPPLY_MASK;
    }

    /**
     * @notice Retrieves the number of steps from a PackedSegment.
     * @param self_ The PackedSegment.
     * @return steps_ The number of steps.
     */
    function _numberOfSteps(PackedSegment self_)
        internal
        pure
        returns (uint steps_)
    {
        return (uint(PackedSegment.unwrap(self_)) >> STEPS_OFFSET) & STEPS_MASK;
    }

    /**
     * @notice Unpacks all data fields from a PackedSegment.
     * @param self_ The PackedSegment.
     * @return initialPrice_ The initial price.
     * @return priceIncrease_ The price increase per step.
     * @return supplyPerStep_ The supply per step.
     * @return numberOfSteps_ The number of steps.
     */
    function _unpack(PackedSegment self_)
        internal
        pure
        returns (
            uint initialPrice_,
            uint priceIncrease_,
            uint supplyPerStep_,
            uint numberOfSteps_
        )
    {
        uint data_ = uint(PackedSegment.unwrap(self_));
        initialPrice_ = data_ & INITIAL_PRICE_MASK; // No shift needed as it's at offset 0
        priceIncrease_ = (data_ >> PRICE_INCREASE_OFFSET) & PRICE_INCREASE_MASK;
        supplyPerStep_ = (data_ >> SUPPLY_OFFSET) & SUPPLY_MASK;
        numberOfSteps_ = (data_ >> STEPS_OFFSET) & STEPS_MASK;
    }
}
