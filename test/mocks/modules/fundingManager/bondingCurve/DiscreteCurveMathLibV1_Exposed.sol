// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.19;

import {IDiscreteCurveMathLib_v1} from
    "@fm/bondingCurve/interfaces/IDiscreteCurveMathLib_v1.sol";
import {DiscreteCurveMathLib_v1} from
    "@fm/bondingCurve/formulas/DiscreteCurveMathLib_v1.sol";
import {PackedSegment} from "@fm/bondingCurve/types/PackedSegment_v1.sol";

contract DiscreteCurveMathLibV1_Exposed {
    function createSegmentPublic(
        uint _initialPrice,
        uint _priceIncrease,
        uint _supplyPerStep,
        uint _numberOfSteps
    ) public pure returns (PackedSegment) {
        return DiscreteCurveMathLib_v1.createSegment(
            _initialPrice, _priceIncrease, _supplyPerStep, _numberOfSteps
        );
    }

    // If we need to test other internal functions from DiscreteCurveMathLib_v1 later,
    // they can be exposed here as well.

    function findPositionForSupplyPublic(
        PackedSegment[] memory segments,
        uint targetTotalIssuanceSupply
    ) public pure returns (IDiscreteCurveMathLib_v1.CurvePosition memory pos) {
        return DiscreteCurveMathLib_v1._findPositionForSupply(
            segments, targetTotalIssuanceSupply
        );
    }

    function getCurrentPriceAndStepPublic(
        PackedSegment[] memory segments,
        uint currentTotalIssuanceSupply
    ) public pure returns (uint price, uint stepIndex, uint segmentIndex) {
        return DiscreteCurveMathLib_v1.getCurrentPriceAndStep(
            segments, currentTotalIssuanceSupply
        );
    }

    function calculateReserveForSupplyPublic(
        PackedSegment[] memory segments,
        uint targetSupply
    ) public pure returns (uint totalReserve) {
        return DiscreteCurveMathLib_v1.calculateReserveForSupply(
            segments, targetSupply
        );
    }

    function calculatePurchaseReturnPublic(
        PackedSegment[] memory segments,
        uint collateralAmountIn,
        uint currentTotalIssuanceSupply
    )
        public
        pure
        returns (uint issuanceAmountOut, uint collateralAmountSpent)
    {
        return DiscreteCurveMathLib_v1.calculatePurchaseReturn(
            segments, collateralAmountIn, currentTotalIssuanceSupply
        );
    }

    function calculateSaleReturnPublic(
        PackedSegment[] memory segments,
        uint issuanceAmountIn,
        uint currentTotalIssuanceSupply
    )
        public
        pure
        returns (uint collateralAmountOut, uint issuanceAmountBurned)
    {
        return DiscreteCurveMathLib_v1.calculateSaleReturn(
            segments, issuanceAmountIn, currentTotalIssuanceSupply
        );
    }

    function linearSearchSlopedPublic(
        PackedSegment segment,
        uint totalBudget,
        uint purchaseStartStepInSegment,
        uint priceAtPurchaseStartStep
    ) public pure returns (uint tokensPurchased, uint totalCollateralSpent) {
        return DiscreteCurveMathLib_v1._linearSearchSloped(
            segment,
            totalBudget,
            purchaseStartStepInSegment,
            priceAtPurchaseStartStep
        );
    }
}
