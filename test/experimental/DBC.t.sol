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

        // FLOOR
        // Add first tranche using the addTranche function
        dbc.addTranche(
            0, // startingPrice
            0, // startSupply
            400 ether, // endSupplyExcluding
            1 ether, // stepHeight
            1 // stepsAmount
        );

        // ANCHOR
        // Add second tranche using the addTranche function
        dbc.addTranche(
            1 ether, // startingPrice
            400 ether, // startSupply
            900 ether, // endSupplyExcluding
            0.5 ether, // stepHeight
            5 // stepsAmount
        );
    }

    function test_getTrancheDetails_givenFloorTranche() public {
        assertEq(dbc.getTrancheDetails(0).reserveCapacity, 400 ether);
    }

    function test_getTrancheDetails_givenAnchorTranche() public {
        assertEq(dbc.getTrancheDetails(1).reserveCapacity, 1250 ether);
    }

    function test_getTrancheReserveAtSupply_givenAnchorTranche() public {
        uint256 supply = 650 ether;

        uint256 reserve = dbc.getTrancheReserveAtSupply(1, supply);
        
        assertEq(reserve, 125 ether);
    }
}
