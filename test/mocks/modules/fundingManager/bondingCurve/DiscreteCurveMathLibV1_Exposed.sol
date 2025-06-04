// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.19;

import {IDiscreteCurveMathLib_v1} from
    "@fm/bondingCurve/interfaces/IDiscreteCurveMathLib_v1.sol";
import {DiscreteCurveMathLib_v1} from
    "@fm/bondingCurve/formulas/DiscreteCurveMathLib_v1.sol";
import {PackedSegment} from "@fm/bondingCurve/types/PackedSegment_v1.sol";

contract DiscreteCurveMathLibV1_Exposed {
    function exposed_createSegment(
        uint initialPrice_,
        uint priceIncrease_,
        uint supplyPerStep_,
        uint numberOfSteps_
    ) public view returns (PackedSegment) {
        return DiscreteCurveMathLib_v1._createSegment(
            initialPrice_, priceIncrease_, supplyPerStep_, numberOfSteps_
        );
    }

    // If we need to test other internal functions from DiscreteCurveMathLib_v1 later,
    // they can be exposed here as well.

    function exposed_findPositionForSupply(
        PackedSegment[] memory segments_,
        uint targetTotalIssuanceSupply_
    )
        public
        view
        returns (IDiscreteCurveMathLib_v1.CurvePosition memory pos_)
    {
        return DiscreteCurveMathLib_v1._findPositionForSupply(
            segments_, targetTotalIssuanceSupply_
        );
    }

    function exposed_getCurrentPriceAndStep(
        PackedSegment[] memory segments_,
        uint currentTotalIssuanceSupply_
    ) public view returns (uint price_, uint stepIndex_, uint segmentIndex_) {
        return DiscreteCurveMathLib_v1._getCurrentPriceAndStep(
            segments_, currentTotalIssuanceSupply_
        );
    }

    function exposed_calculateReserveForSupply(
        PackedSegment[] memory segments_,
        uint targetSupply_
    ) public view returns (uint totalReserve_) {
        return DiscreteCurveMathLib_v1._calculateReserveForSupply(
            segments_, targetSupply_
        );
    }

    function exposed_calculatePurchaseReturn(
        PackedSegment[] memory segments_,
        uint collateralAmountIn_,
        uint currentTotalIssuanceSupply_
    )
        public
        view
        returns (uint issuanceAmountOut_, uint collateralAmountSpent_)
    {
        return DiscreteCurveMathLib_v1._calculatePurchaseReturn(
            segments_, collateralAmountIn_, currentTotalIssuanceSupply_
        );
    }

    function exposed_calculateSaleReturn(
        PackedSegment[] memory segments_,
        uint issuanceAmountIn_,
        uint currentTotalIssuanceSupply_
    )
        public
        view
        returns (uint collateralAmountOut_, uint issuanceAmountBurned_)
    {
        return DiscreteCurveMathLib_v1._calculateSaleReturn(
            segments_, issuanceAmountIn_, currentTotalIssuanceSupply_
        );
    }

    function exposed_validateSegmentArray(PackedSegment[] memory segments_)
        public
        view
    {
        DiscreteCurveMathLib_v1._validateSegmentArray(segments_);
    }

    function exposed_validateSupplyAgainstSegments(
        PackedSegment[] memory segments_,
        uint currentTotalIssuanceSupply_
    ) public view returns (uint totalCurveCapacity_) {
        return DiscreteCurveMathLib_v1._validateSupplyAgainstSegments(
            segments_, currentTotalIssuanceSupply_
        );
    }

    function exposed_calculateReservesForTwoSupplies(
        PackedSegment[] memory segments_,
        uint lowerSupply_,
        uint higherSupply_
    ) public view returns (uint lowerReserve_, uint higherReserve_) {
        return DiscreteCurveMathLib_v1._calculateReservesForTwoSupplies(
            segments_, lowerSupply_, higherSupply_
        );
    }
}
