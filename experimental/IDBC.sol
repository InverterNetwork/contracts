// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/**
 * @title IDBC
 * @dev Interface for the DBC contract
 */
interface IDBC {
    struct Tranche {
        uint256 startingPrice;
        uint256 startSupply;
        uint256 endSupplyExcluding;
        uint256 stepHeight;
        uint256 stepsAmount;
    }
    
    function getTranches() external view returns (uint8);
} 