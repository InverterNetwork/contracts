// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "../../experimental/DBC.sol";
import "../../experimental/IDBC.sol";

contract DBCTest is Test {
    DBC public dbc;
    uint8 public expectedTrancheCount = 3;

    function setUp() public {
        // Deploy the contract with the minimal constructor
        dbc = new DBC();

        // Add first tranche using the addTranche function
        dbc.addTranche(
            1 ether, // startingPrice
            0, // startSupply
            400 ether, // endSupplyExcluding
            0, // stepHeight
            0 // stepsAmount
        );

        // Add second tranche using the addTranche function
        dbc.addTranche(
            1.5 ether, // startingPrice
            400 ether, // startSupply
            900 ether, // endSupplyExcluding
            0.5 ether, // stepHeight
            5 // stepsAmount
        );

        // Add third tranche using the addTranche function
        // dbc.addTranche(
        //     3.1 ether, // startingPrice (increased to be > previous tranche's end price of 3 ether)
        //     2_000_000 ether, // startSupply
        //     3_000_000 ether, // endSupplyExcluding
        //     0.2 ether, // stepHeight
        //     5 // stepsAmount
        // );
    }

    function test_calculatePurchaseReturn() public {
        
    }
}
