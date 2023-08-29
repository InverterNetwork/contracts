// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {VirtualCollateralSupplyBaseMock} from
    "test/modules/fundingManager/bondingCurveFundingManager/marketMaker/utils/mocks/VirtualCollateralSupplyBaseMock.sol";
import {IVirtualCollateralSupply} from
    "src/modules/fundingManager/bondingCurveFundingManager/marketMaker/IVirtualCollateralSupply.sol";

contract VirtualCollateralSupplyBaseTest is Test {
    VirtualCollateralSupplyBaseMock virtualCollateralSupplyBase;
    uint internal constant INITIAL_SUPPLY = 1000e18;
    uint internal constant MAX_UINT_TEST = 2 ** 256 - 1;

    function setUp() public {
        virtualCollateralSupplyBase = new VirtualCollateralSupplyBaseMock();
        virtualCollateralSupplyBase.setVirtualCollateralSupply(INITIAL_SUPPLY);
    }

    function testAddCollateralAmount(uint amount) external {
        vm.assume(amount < (MAX_UINT_TEST - INITIAL_SUPPLY));
        vm.startPrank(msg.sender);
        virtualCollateralSupplyBase.addCollateralAmount(amount);
        assertEq(
            virtualCollateralSupplyBase.getVirtualCollateralSupply(),
            (INITIAL_SUPPLY + amount)
        );
    }

    function testSubCollateralAmount(uint amount) external {
        vm.assume(amount <= INITIAL_SUPPLY);
        vm.startPrank(msg.sender);
        virtualCollateralSupplyBase.subCollateralAmount(amount);
        assertEq(
            virtualCollateralSupplyBase.getVirtualCollateralSupply(),
            (INITIAL_SUPPLY - amount)
        );
    }

    function testSubCollateralAmountFails(uint amount) external {
        vm.assume(amount > INITIAL_SUPPLY);
        vm.startPrank(msg.sender);
        vm.expectRevert(
            IVirtualCollateralSupply
                .VirtualCollateralSupply__SubtractResultsInUnderflow
                .selector
        );
        virtualCollateralSupplyBase.subCollateralAmount(amount);
    }
}
