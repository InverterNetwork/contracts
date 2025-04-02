// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "../../experimental/DBC.sol";
import "../../experimental/IDBC.sol";

contract DBCTest is Test {
    DBC public dbc;
    uint8 public expectedTrancheCount = 2;

    function setUp() public {
        // Deploy the contract with the minimal constructor
        dbc = new DBC();

        // Add first tranche using the addTranche function
        dbc.addTranche(
            1 ether, // startingPrice
            0, // startSupply
            1_000_000 ether, // endSupplyExcluding
            0, // stepHeight
            0 // stepsAmount
        );

        // Add second tranche using the addTranche function
        dbc.addTranche(
            2 ether, // startingPrice
            1_000_000 ether, // startSupply
            2_000_000 ether, // endSupplyExcluding
            0.1 ether, // stepHeight
            10 // stepsAmount
        );
    }

    function testInitialState() public {
        assertEq(
            dbc.getTranches(),
            expectedTrancheCount,
            "Initial tranche count mismatch"
        );
        assertEq(
            dbc.owner(),
            address(this),
            "Owner should be deployer (test contract)"
        );
    }

    function testGetTrancheDetails() public {
        // Test retrieving tranche 0
        IDBC.Tranche memory tranche0 = dbc.getTrancheDetails(0);
        assertEq(tranche0.startingPrice, 1 ether, "Tranche 0 startingPrice mismatch");
        assertEq(tranche0.startSupply, 0, "Tranche 0 startSupply mismatch");
        assertEq(
            tranche0.endSupplyExcluding,
            1_000_000 ether,
            "Tranche 0 endSupplyExcluding mismatch"
        );
        assertEq(tranche0.stepHeight, 0, "Tranche 0 stepHeight mismatch");
        assertEq(tranche0.stepsAmount, 0, "Tranche 0 stepsAmount mismatch");

        // Test retrieving tranche 1
        IDBC.Tranche memory tranche1 = dbc.getTrancheDetails(1);
        assertEq(tranche1.startingPrice, 2 ether, "Tranche 1 startingPrice mismatch");
        assertEq(tranche1.startSupply, 1_000_000 ether, "Tranche 1 startSupply mismatch");
        assertEq(
            tranche1.endSupplyExcluding,
            2_000_000 ether,
            "Tranche 1 endSupplyExcluding mismatch"
        );
        assertEq(tranche1.stepHeight, 0.1 ether, "Tranche 1 stepHeight mismatch");
        assertEq(tranche1.stepsAmount, 10, "Tranche 1 stepsAmount mismatch");
    }

    function testAddTranche_RevertsIfNotOwner() public {
        // Change the caller to a different address
        vm.prank(address(0xDEADBEEF));
        vm.expectRevert("DBC: Not owner");
        dbc.addTranche(3 ether, 2_000_000 ether, 3_000_000 ether, 0.2 ether, 5);
    }

    function testGetTrancheDetails_RevertsIfInvalidIndex() public {
        vm.expectRevert("DBC: Invalid tranche index");
        dbc.getTrancheDetails(expectedTrancheCount); // Try to get index 2 (which doesn't exist)
    }

    // Add more test functions here
}
