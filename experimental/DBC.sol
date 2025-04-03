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
        uint256 reserveCapacity = getTrancheReserveCapacity(
            startingPrice_,
            startSupply_,
            endSupplyExcluding_,
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

    function getTrancheReserveCapacity(
        uint256 startingPrice_,
        uint256 startSupply_,
        uint256 endSupplyExcluding_,
        uint256 stepHeight_,
        uint256 stepsAmount_
    ) public view returns (uint256 capacity) {
        // if tranche consists of multiple linear steps
        uint256 length = endSupplyExcluding_ - startSupply_;
        uint256 height = stepHeight_ * stepsAmount_ + stepHeight_;
        uint256 area = length * height / 2;
        capacity += (area / 1 ether) + (startingPrice_ * (endSupplyExcluding_ - startSupply_) / 1 ether);
        return capacity;
    }
}
