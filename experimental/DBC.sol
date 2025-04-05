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
        uint256 supply_,
        uint256 currentReserve_
    ) public view returns (uint256) {
        Tranche memory t = getCurrentTranche(supply_);

        uint256 additionalReserve = 0;
        uint256 unfilledStepCapacity;
        {
            uint256 stepLength = getStepLength(t);
            uint256 currentStepIdx = getStepIdx(t, supply_, stepLength); 
            uint256 currentStepHeight = t.stepHeight * (currentStepIdx + 1);
            console.log("currentStepHeight", currentStepHeight);
            console.log("stepLength", stepLength);

            // get remaining (unfilled area) area of partially filled step
            uint256 endSupplyForCompletedSteps = t.startSupply + (currentStepIdx * stepLength);
            uint256 length = supply_ - endSupplyForCompletedSteps;
            uint256 roofHeight = (t.stepHeight * (currentStepIdx + 1));
            console.log("roofHeight", roofHeight);
            uint256 baseHeight = t.startingPrice;
            console.log("baseHeight", baseHeight);
            console.log("(baseHeight + roofHeight)", (baseHeight + roofHeight));
            uint256 stepArea = (baseHeight + roofHeight) * stepLength / 1 ether;
            console.log("stepArea", stepArea);
            // console.log("stepLength", stepLength);
            // console.log("t.stepHeight", t.stepHeight);
            unfilledStepCapacity = stepLength * currentStepHeight / 1 ether;
        }

        console.log("unfilledStepCapacity", unfilledStepCapacity);

        // calculate the area of the partially filled step
        // uint256 length = supply_ - endSupplyForCompletedSteps;
        // uint256 roofHeight = (t.stepHeight * (currentStepIdx + 1));
        // uint256 baseHeight = t.startingPrice;
        // uint256 baseArea = calcRectangleArea(length, baseHeight);
        // uint256 roofArea = calcRectangleArea(length, roofHeight);

        // // how many steps are left to fill
        // uint256 stepsLeft = t.stepsAmount - currentStepIdx;

        // // fill them iteratively until all amountIn is "spent"
        // // and keep track of the reserve
        // for (uint256 i = 0; i < stepsLeft; i++) {
        //     uint256 stepPrice = t.startingPrice + (stepIdx * t.stepHeight);
        //     uint256 stepArea = calcRectangleArea(stepLength, stepPrice);
        //     additionalReserve += stepArea;
        // }

        // console.log("additionalReserve", additionalReserve);


        return additionalReserve;
    }

    function calculatePurchaseReturn2(uint256 amountIn_, uint256 currentPointOnSupply_) public returns (uint256 returnAmount) {

        uint256 filledSupplyForTranche = currentPointOnSupply_;
        console.log("initialAmountIn_", amountIn_);

        for (uint8 i = 0; i < _trancheCount; i++) {
            console.log("i", i);
            Tranche memory t = tranches[i];
            uint256 trancheSupplyCapacity = t.endSupplyExcluding - t.startSupply;
            console.log("trancheSupplyCapacity", trancheSupplyCapacity);

            uint256 unfilledStepReserve;
            uint256 unfilledStepSupply;
            if(currentPointOnSupply_ > t.endSupplyExcluding) {
                console.log("currentPointOnSupply_ > t.endSupplyExcluding");
                filledSupplyForTranche -= trancheSupplyCapacity;
            } else {
                console.log("currentPointOnSupply_ <= t.endSupplyExcluding");
                console.log("currentPointOnSupply_", currentPointOnSupply_);
                console.log("t.endSupplyExcluding", t.endSupplyExcluding);
                uint256 stepLength = getStepLength(t);
                console.log("stepLength", stepLength);
                // initially this is the stepIdx of the step that is partially filled
                uint256 stepIdx = getStepIdx(t, currentPointOnSupply_, stepLength);
                console.log("stepIdx", stepIdx);

                for (uint256 j = stepIdx; j < t.stepsAmount; j++) {
                    console.log();
                    console.log("j", j);
                    console.log("amountIn_", amountIn_);
                    console.log("returnAmount", returnAmount);

                    if(j - stepIdx == 0) {
                        console.log("first step (angebrochen)");
                        uint256 stepReserveCapacity = getStepReserveCapacity(stepLength, t.stepHeight, j, t.startingPrice);
                        unfilledStepSupply = (trancheSupplyCapacity - filledSupplyForTranche) % stepLength;
                        uint256 unfilledStepPercentage = (unfilledStepSupply * 1 ether) / stepLength;
                        unfilledStepReserve = unfilledStepPercentage * stepReserveCapacity  / 1 ether;
                        console.log("unfilledStepReserve", unfilledStepReserve);
                        console.log("unfilledStepSupply", unfilledStepSupply);
                        if(amountIn_ < unfilledStepReserve) {
                            console.log("amountIn_ < unfilledStepReserve");
                            unfilledStepReserve = amountIn_;
                            unfilledStepSupply = unfilledStepReserve * stepLength / stepReserveCapacity;
                        }
                    } else {
                        unfilledStepReserve = getStepReserveCapacity(stepLength, t.stepHeight, j, t.startingPrice);
                        if (amountIn_ > unfilledStepReserve) {
                            console.log("empty step, to be filled completely");
                            console.log("unfilledStepReserve", unfilledStepReserve);
                            unfilledStepSupply = stepLength;
                            console.log("unfilledStepSupply", unfilledStepSupply);
                        } else {
                            console.log("empty step, to be filled partially");
                            uint256 unfilledStepPercentage = amountIn_ * 1 ether / unfilledStepReserve;
                            console.log("unfilledStepPercentage", unfilledStepPercentage);
                            unfilledStepSupply = unfilledStepPercentage * stepLength / 1 ether;
                            console.log("unfilledStepReserve", unfilledStepReserve);
                            console.log("unfilledStepSupply", unfilledStepSupply);
                            unfilledStepReserve = amountIn_;
                        }
                    }

                    amountIn_ -= unfilledStepReserve;
                    returnAmount += unfilledStepSupply;

                    console.log("--------------------------------");
                    console.log("amountIn_", amountIn_);
                    console.log("returnAmount", returnAmount);

                    if (amountIn_ == 0) {
                        return returnAmount;
                    }
                }
            }

            currentPointOnSupply_ += unfilledStepSupply;
        }


        return returnAmount;
    }

    function getReserveAtSupply(uint256 supply_) public view returns (uint256 reserve) {
        for (uint8 i = 0; i < _trancheCount; i++) {
            uint256 trancheSupply = tranches[i].endSupplyExcluding;

            if(supply_ >= tranches[i].endSupplyExcluding) {
                reserve += tranches[i].reserveCapacity;
            } else {
                reserve += getTrancheReserveAtSupply(i, supply_);
            }
        }
        return reserve;
    }

    function getStepLength(Tranche memory t) public pure returns (uint256 stepLength) {
        stepLength = (t.endSupplyExcluding - t.startSupply) / t.stepsAmount;
    }

    function getStepIdx(Tranche memory t, uint256 supply_, uint256 stepLength) public view returns (uint256 stepIdx) {
        console.log("--------------------------------");
        console.log("supply_", supply_);
        console.log("t.startSupply", t.startSupply);
        console.log("stepLength", stepLength);
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
        console.log("supply_", supply_);
        uint256 filledTrancheSupply = supply_;

        for (uint8 i = 0; i < _trancheCount; i++) {
            console.log("i", i);
            if(supply_ > tranches[i].endSupplyExcluding) {
                filledTrancheSupply -= (tranches[i].endSupplyExcluding - tranches[i].startSupply);

                console.log("filledTrancheSupply", filledTrancheSupply);
            } else {
                t = tranches[i];
                console.log("t set");    
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