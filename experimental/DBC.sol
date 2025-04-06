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
        Tranche memory t,
        uint256 supply_
        ) public view returns (uint256 reserve) {
        uint256 stepLength = getStepLength(t);
        uint256 currentStepIdx = getStepIdx(t, supply_, stepLength); 
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

        reserve = baseArea + roofArea + areaForCompletedSteps;
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
        
        uint256 roofArea = area / 1 ether;
        uint256 baseArea = y0 * (x1 - x0) / 1 ether;

        area = roofArea + baseArea;
        return area;
    }

    function calcRectangleArea(uint256 x, uint256 y) public pure returns (uint256 area) {
        area = x * y / 1 ether;
    }

    function calculatePurchaseReturn(
        uint256 amountIn_,
        uint256 currentPointOnSupply_
    ) public returns (uint256 returnAmount) {
        uint256 targetTrancheSupply = currentPointOnSupply_;

        for (uint8 i = 0; i < _trancheCount; i++) {
            Tranche memory t = tranches[i];
            uint256 trancheSupplyCapacity = t.endSupplyExcluding - t.startSupply;

            // if the target tranche supply is greater than the tranche supply capacity we need to move to the next tranche
            if(targetTrancheSupply > t.endSupplyExcluding - t.startSupply) {
                targetTrancheSupply -= (t.endSupplyExcluding - t.startSupply);
                continue;
            } 

            // if the current tranche reserve plus the amountIn is greater than the tranche reserve capacity
            // we know that amountIn *will* push the tranche reserve over the capacity into the next tranche
            // because reserve capacity is stored, we can easily calculate how much supply is consumed by this tranche
            uint256 trancheReserve = getTrancheReserveAtSupply(t, currentPointOnSupply_); // FIX: if i change currentPointOnSupply_ to targetTrancheSupply 
            if(trancheReserve + amountIn_ > t.reserveCapacity) {
                amountIn_ -= (t.reserveCapacity - trancheReserve);
                returnAmount += (t.endSupplyExcluding - targetTrancheSupply);
                currentPointOnSupply_ = t.endSupplyExcluding;
                continue;
            }

            // here we know supply start and end points lie both in current tranche

            uint256 stepLength = getStepLength(t);
            // get the stepIdx of the step that is partially filled
            uint256 stepIdx = getStepIdx(t, currentPointOnSupply_, stepLength); // FIX: if i change currentPointOnSupply_ to targetTrancheSupply 
            for (uint256 j = stepIdx; j < t.stepsAmount; j++) {
                uint256 stepReserveCapacity = getStepReserveCapacity(stepLength, t.stepHeight, j, t.startingPrice);
                uint256 unfilledStepSupply = (trancheSupplyCapacity - targetTrancheSupply) % stepLength == 0 ? stepLength : (trancheSupplyCapacity - targetTrancheSupply) % stepLength;
                uint256 unfilledStepPercentage = (unfilledStepSupply * 1 ether) / stepLength;
                uint256 unfilledStepReserve = unfilledStepPercentage * stepReserveCapacity  / 1 ether;

                // if we are at the first step (the one that is partially filled)
                if(j == stepIdx) {
                    // here start and end point lie within first step
                    if(amountIn_ < unfilledStepReserve) {
                        unfilledStepPercentage = amountIn_ * 1 ether / stepReserveCapacity;
                        returnAmount += unfilledStepPercentage * stepLength / 1 ether;
                        return returnAmount;
                    }

                    // here start and end point lie within different steps
                    amountIn_ -= unfilledStepReserve;
                    returnAmount += unfilledStepSupply;
                    continue;
                }

                // here we have moved on to another step
                // and this case is when the end point is not in the current step
                // so we need to fill the step completely 
                if(amountIn_ > stepReserveCapacity) {
                    amountIn_ -= stepReserveCapacity;
                    returnAmount += stepLength;
                    continue;
                }

                // here we have finally reached the step that will consume the remaining amountIn
                unfilledStepPercentage = amountIn_ * 1 ether / stepReserveCapacity;
                returnAmount += unfilledStepPercentage * stepLength / 1 ether;

                return returnAmount;

            }            
        }
    }

    function getReserveAtSupply(uint256 supply_) public view returns (uint256 reserve) {
        for (uint8 i = 0; i < _trancheCount; i++) {
            uint256 trancheSupply = tranches[i].endSupplyExcluding;

            if(supply_ >= tranches[i].endSupplyExcluding) {
                reserve += tranches[i].reserveCapacity;
            } else {
                reserve += getTrancheReserveAtSupply(tranches[i], supply_);
            }
        }
        return reserve;
    }

    function getStepLength(Tranche memory t) public pure returns (uint256 stepLength) {
        stepLength = (t.endSupplyExcluding - t.startSupply) / t.stepsAmount;
    }

    function getStepIdx(Tranche memory t, uint256 supply_, uint256 stepLength) public view returns (uint256 stepIdx) {
        stepIdx = (supply_ - t.startSupply) / stepLength;
    }

    function getCurrentTranche(uint256 supply_) public view returns (Tranche memory t) {
        for (uint8 i = 0; i < _trancheCount; i++) {
            if(supply_ < tranches[i].endSupplyExcluding) {
                return tranches[i];
            }
        }
    }

    function createPurchaseConfig(uint256 supply_) public view returns (uint256, Tranche memory t) {
        uint256 filledTrancheSupply = supply_;

        for (uint8 i = 0; i < _trancheCount; i++) {
            if(supply_ > tranches[i].endSupplyExcluding) {
                filledTrancheSupply -= (tranches[i].endSupplyExcluding - tranches[i].startSupply);
            } else {
                t = tranches[i];
            }
        }

        return (filledTrancheSupply, t);
    }

    function getStepReserveCapacity(uint256 stepLength, uint256 stepHeight, uint256 stepIdx, uint256 startingPrice) public pure returns (uint256 stepReserveCapacity) {
        uint256 roofHeight = (stepHeight * (stepIdx + 1));
        uint256 baseHeight = startingPrice;
        stepReserveCapacity = (roofHeight + startingPrice) * stepLength / 1 ether;
    }
}