// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.19;

import {
    DiscreteCurveMathLib_v1
} from "@fm/bondingCurve/formulas/DiscreteCurveMathLib_v1.sol";
import {PackedSegment} from "@fm/bondingCurve/types/PackedSegment_v1.sol";

contract DiscreteCurveMathLibV1_Exposed {
    function createSegmentPublic(
        uint256 _initialPrice,
        uint256 _priceIncrease,
        uint256 _supplyPerStep,
        uint256 _numberOfSteps
    ) public pure returns (PackedSegment) {
        return DiscreteCurveMathLib_v1.createSegment(
            _initialPrice,
            _priceIncrease,
            _supplyPerStep,
            _numberOfSteps
        );
    }

    // If we need to test other internal functions from DiscreteCurveMathLib_v1 later,
    // they can be exposed here as well.

    function findPositionForSupplyPublic(
        PackedSegment[] memory segments,
        uint256 targetTotalIssuanceSupply
    ) public pure returns (DiscreteCurveMathLib_v1.CurvePosition memory pos) {
        return DiscreteCurveMathLib_v1._findPositionForSupply(segments, targetTotalIssuanceSupply);
    }

    function getCurrentPriceAndStepPublic(
        PackedSegment[] memory segments,
        uint256 currentTotalIssuanceSupply
    ) public pure returns (uint256 price, uint256 stepIndex, uint256 segmentIndex) {
        return DiscreteCurveMathLib_v1.getCurrentPriceAndStep(segments, currentTotalIssuanceSupply);
    }

    function calculateReserveForSupplyPublic(
        PackedSegment[] memory segments,
        uint256 targetSupply
    ) public pure returns (uint256 totalReserve) {
        return DiscreteCurveMathLib_v1.calculateReserveForSupply(segments, targetSupply);
    }

    function calculatePurchaseReturnPublic(
        PackedSegment[] memory segments,
        uint256 collateralAmountIn,
        uint256 currentTotalIssuanceSupply
    ) public pure returns (uint256 issuanceAmountOut, uint256 collateralAmountSpent) {
        return DiscreteCurveMathLib_v1.calculatePurchaseReturn(
            segments,
            collateralAmountIn,
            currentTotalIssuanceSupply
        );
    }

    function calculateSaleReturnPublic(
        PackedSegment[] memory segments,
        uint256 issuanceAmountIn,
        uint256 currentTotalIssuanceSupply
    ) public pure returns (uint256 collateralAmountOut, uint256 issuanceAmountBurned) {
        return DiscreteCurveMathLib_v1.calculateSaleReturn(
            segments,
            issuanceAmountIn,
            currentTotalIssuanceSupply
        );
    }
}
