// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.19;

import {IDiscreteCurveMathLib_v1} from
    "@fm/bondingCurve/interfaces/IDiscreteCurveMathLib_v1.sol";
import {DiscreteCurveMathLib_v1} from
    "@fm/bondingCurve/formulas/DiscreteCurveMathLib_v1.sol";
import {PackedSegment} from "@fm/bondingCurve/types/PackedSegment_v1.sol";

contract DiscreteCurveMathLibV1_Exposed {
    function createSegmentPublic(
        uint initialPrice_,
        uint priceIncrease_,
        uint supplyPerStep_,
        uint numberOfSteps_
    ) public pure returns (PackedSegment) {
        return DiscreteCurveMathLib_v1._createSegment(
            initialPrice_, priceIncrease_, supplyPerStep_, numberOfSteps_
        );
    }

    // If we need to test other internal functions from DiscreteCurveMathLib_v1 later,
    // they can be exposed here as well.

    function findPositionForSupplyPublic(
        PackedSegment[] memory segments_,
        uint targetTotalIssuanceSupply_
    ) public pure returns (IDiscreteCurveMathLib_v1.CurvePosition memory pos_) {
        return DiscreteCurveMathLib_v1._findPositionForSupply(
            segments_, targetTotalIssuanceSupply_
        );
    }

    function getCurrentPriceAndStepPublic(
        PackedSegment[] memory segments_,
        uint currentTotalIssuanceSupply_
    ) public pure returns (uint price_, uint stepIndex_, uint segmentIndex_) {
        return DiscreteCurveMathLib_v1._getCurrentPriceAndStep(
            segments_, currentTotalIssuanceSupply_
        );
    }

    function calculateReserveForSupplyPublic(
        PackedSegment[] memory segments_,
        uint targetSupply_
    ) public pure returns (uint totalReserve_) {
        return DiscreteCurveMathLib_v1._calculateReserveForSupply(
            segments_, targetSupply_
        );
    }

    function calculatePurchaseReturnPublic(
        PackedSegment[] memory segments_,
        uint collateralAmountIn_,
        uint currentTotalIssuanceSupply_
    )
        public
        pure
        returns (uint issuanceAmountOut_, uint collateralAmountSpent_)
    {
        return DiscreteCurveMathLib_v1._calculatePurchaseReturn(
            segments_, collateralAmountIn_, currentTotalIssuanceSupply_
        );
    }

    function calculateSaleReturnPublic(
        PackedSegment[] memory segments_,
        uint issuanceAmountIn_,
        uint currentTotalIssuanceSupply_
    )
        public
        pure
        returns (uint collateralAmountOut_, uint issuanceAmountBurned_)
    {
        return DiscreteCurveMathLib_v1._calculateSaleReturn(
            segments_, issuanceAmountIn_, currentTotalIssuanceSupply_
        );
    }

    function linearSearchSlopedPublic(
        PackedSegment segment_,
        uint totalBudget_,
        uint purchaseStartStepInSegment_,
        uint priceAtPurchaseStartStep_
    ) public pure returns (uint tokensPurchased_, uint totalCollateralSpent_) {
        return DiscreteCurveMathLib_v1._linearSearchSloped(
            segment_,
            totalBudget_,
            purchaseStartStepInSegment_,
            priceAtPurchaseStartStep_
        );
    }
}
