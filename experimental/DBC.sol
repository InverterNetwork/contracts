// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "./IDBC.sol";

/**
 * @title DBC
 * @dev Implementation of the DBC contract using an addTranche pattern for setup.
 */
contract DBC is IDBC {
    address public owner;
    
    uint8 private _trancheCount; // Renamed to avoid conflict with getter
    mapping(uint8 => Tranche) private tranches;
    

    modifier onlyOwner() {
        require(msg.sender == owner, "DBC: Not owner");
        _;
    }

    constructor() {
        owner = msg.sender; // Set deployer as owner
        _trancheCount = 0;
    }

    /**
     * @notice Adds a new tranche to the bonding curve configuration.
     * @dev Can only be called by the owner during setup.
     * @param startingPrice_ Starting price for this tranche.
     * @param startSupply_ Starting supply level for this tranche.
     * @param endSupplyExcluding_ Ending supply level (exclusive) for this tranche.
     * @param stepHeight_ Height of each step within this tranche.
     * @param stepsAmount_ Number of steps within this tranche.
     */
    function addTranche(
        uint256 startingPrice_,
        uint256 startSupply_,
        uint256 endSupplyExcluding_,
        uint256 stepHeight_,
        uint256 stepsAmount_
    ) external onlyOwner { 
        require(_trancheCount < type(uint8).max, "DBC: Max tranches reached");
        // Optional: Add validation for tranche parameters (e.g., end > start)
        require(endSupplyExcluding_ > startSupply_, "DBC: endSupply must be > startSupply");
        
        // Validate against previous tranche if it exists
        if (_trancheCount > 0) {
            Tranche storage prevTranche = tranches[_trancheCount - 1];
                
            // Calculate previous tranche's end price
            uint256 prevTrancheEndPrice = prevTranche.startingPrice + 
                (prevTranche.stepHeight * prevTranche.stepsAmount);
                
            // Ensure current tranche's starting price is greater than previous tranche's end price
            require(startingPrice_ > prevTrancheEndPrice, 
                "DBC: startingPrice must be > previous tranche's end price");
            
            // Validate that startSupply is >= previous tranche's endSupplyExcluding
            require(startSupply_ >= prevTranche.endSupplyExcluding, 
                "DBC: startSupply must be >= previous tranche's endSupply");
        }

        tranches[_trancheCount] = Tranche(
            startingPrice_,
            startSupply_,
            endSupplyExcluding_,
            stepHeight_,
            stepsAmount_
        );
        _trancheCount++;
    }

    /**
     * @notice Returns the total number of configured tranches.
     */
    function getTranches() public view override returns (uint8) {
        return _trancheCount;
    }

    /**
     * @notice Returns the details of a specific tranche by its index.
     * @param index_ The index of the tranche.
     * @return The Tranche struct data.
     */
    function getTrancheDetails(uint8 index_) public view returns (Tranche memory) {
         require(index_ < _trancheCount, "DBC: Invalid tranche index");
         // Note: Returning structs from mappings requires copying to memory
         Tranche storage t = tranches[index_];
         return Tranche(
             t.startingPrice,
             t.startSupply,
             t.endSupplyExcluding,
             t.stepHeight,
             t.stepsAmount
         );
    }
}
