// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "./IDBC.sol";
import "forge-std/console.sol";


contract DBC is IDBC {
    uint8 private _trancheCount;
    mapping(uint8 => Tranche) private tranches;
    
    constructor() {
        _trancheCount = 0;
    }

    function addTranche(
        uint256 startingPrice_,
        uint256 startSupply_,
        uint256 endSupplyExcluding_,
        uint256 stepHeight_,
        uint256 stepsAmount_
    ) external { 
        uint256 reserveCapacity = calcAreaUnderCurve(
            startSupply_,
            endSupplyExcluding_,
            startingPrice_,
            stepHeight_,
            stepsAmount_
        );

        tranches[_trancheCount] = Tranche(
            startingPrice_,
            startSupply_,
            endSupplyExcluding_,
            stepHeight_,
            stepsAmount_,
            reserveCapacity
        );

        _trancheCount++;
    }


    function getTranches() public view override returns (uint8) {
        return _trancheCount;
    }

    function getTrancheDetails(uint8 index_) public view returns (Tranche memory) {
         Tranche storage t = tranches[index_];
         return Tranche(
             t.startingPrice,
             t.startSupply,
             t.endSupplyExcluding,
             t.stepHeight,
             t.stepsAmount,
             t.reserveCapacity
         );
    }
    function getTrancheReserveAtSupply(
        uint8 index_,
        uint256 supply_
    ) public view returns (uint256 reserve) {
        Tranche memory t = tranches[index_];

        // find out in which step within the tranch are we
        uint256 stepLength = (t.endSupplyExcluding - t.startSupply) / t.stepsAmount;
        uint256 currentStepIdx = (supply_ - t.startSupply) / stepLength; 
        
        // calculate the area of the completed steps
        uint256 endSupplyForCompletedSteps = t.startSupply + (currentStepIdx * stepLength);
        uint256 areaForCompletedSteps = calcAreaUnderCurve(
            t.startSupply,
            endSupplyForCompletedSteps,
            t.startingPrice,
            t.stepHeight,
            currentStepIdx
        );

        // calculate the area of the remaining step
        uint256 length = supply_ - endSupplyForCompletedSteps;
        uint256 roofHeight = (t.stepHeight * (currentStepIdx + 1));
        uint256 baseHeight = t.startingPrice;

        uint256 baseArea = calcRectangleArea(length, baseHeight);
        uint256 roofArea = calcRectangleArea(length, roofHeight);

        reserve = baseArea + roofArea;

        return reserve;
    }

    function calcAreaUnderCurve(
        uint256 x0,
        uint256 x1,
        uint256 y0,
        uint256 stepHeight,
        uint256 stepsAmount
    ) public pure returns (uint256 area) {
        uint256 length = x1 - x0;
        uint256 height = stepHeight * stepsAmount + stepHeight;
        uint256 area = length * height / 2;
        
        uint256 stepArea = area / 1 ether;
        uint256 squareArea = y0 * (x1 - x0) / 1 ether;

        area = stepArea + squareArea;
        return area;
    }

    function calcRectangleArea(uint256 x, uint256 y) public pure returns (uint256 area) {
        area = x * y / 1 ether;
    }
}