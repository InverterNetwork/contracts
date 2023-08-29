// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {VirtualTokenSupplyBaseMock} from
    "test/modules/fundingManager/bondingCurveFundingManager/marketMaker/utils/mocks/VirtualTokenSupplyBaseMock.sol";
import {IVirtualTokenSupply} from
    "src/modules/fundingManager/bondingCurveFundingManager/marketMaker/IVirtualTokenSupply.sol";

contract VirtualTokenSupplyBaseTest is Test {
    VirtualTokenSupplyBaseMock virtualTokenSupplyBase;
    uint internal constant INITIAL_SUPPLY = 1000e18;
    uint internal constant MAX_UINT_TEST = 2 ** 256 - 1;

    function setUp() public {
        virtualTokenSupplyBase = new VirtualTokenSupplyBaseMock();
        virtualTokenSupplyBase.setVirtualTokenSupply(INITIAL_SUPPLY);
    }

    function testAddTokenAmount(uint amount) external {
        vm.assume(amount < (MAX_UINT_TEST - INITIAL_SUPPLY));
        vm.startPrank(msg.sender);
        virtualTokenSupplyBase.addTokenAmount(amount);
        assertEq(
            virtualTokenSupplyBase.getVirtualTokenSupply(),
            (INITIAL_SUPPLY + amount)
        );
    }

    function testSubTokenAmount(uint amount) external {
        vm.assume(amount <= INITIAL_SUPPLY);
        vm.startPrank(msg.sender);
        virtualTokenSupplyBase.subTokenAmount(amount);
        assertEq(
            virtualTokenSupplyBase.getVirtualTokenSupply(),
            (INITIAL_SUPPLY - amount)
        );
    }

    function testSubTokenAmountFails(uint amount) external {
        vm.assume(amount > INITIAL_SUPPLY);
        vm.startPrank(msg.sender);
        vm.expectRevert(
            IVirtualTokenSupply
                .VirtualTokenSupply__SubtractResultsInUnderflow
                .selector
        );
        virtualTokenSupplyBase.subTokenAmount(amount);
    }
}
