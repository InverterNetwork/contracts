// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {VirtualCollateralSupplyBaseMock} from
    "./utils/mocks/VirtualCollateralSupplyBaseMock.sol";
import {IVirtualCollateralSupply} from
    "src/modules/fundingManager/bondingCurveFundingManager/marketMaker/IVirtualCollateralSupply.sol";

contract VirtualCollateralSupplyBaseTest is Test {
    VirtualCollateralSupplyBaseMock virtualCollateralSupplyBase;
    uint internal constant INITIAL_SUPPLY = 1000e18;
    uint internal constant MAX_UINT = type(uint).max;

    event VirtualCollateralSupplySet(
        uint indexed newSupply, uint indexed oldSupply
    );

    event VirtualCollateralAmountAdded(
        uint indexed amountAdded, uint indexed newSupply
    );

    event VirtualCollateralAmountSubtracted(
        uint indexed amountSubtracted, uint indexed newSupply
    );

    function setUp() public {
        virtualCollateralSupplyBase = new VirtualCollateralSupplyBaseMock();
        virtualCollateralSupplyBase.setVirtualCollateralSupply(INITIAL_SUPPLY);
    }

    function testAddCollateralAmount(uint amount) external {
        amount = bound(amount, 0, (MAX_UINT - INITIAL_SUPPLY));
        // Test event
        vm.expectEmit(
            true, true, false, false, address(virtualCollateralSupplyBase)
        );
        emit VirtualCollateralAmountAdded(amount, (INITIAL_SUPPLY + amount));
        virtualCollateralSupplyBase.addVirtualCollateralAmount(amount);
        assertEq(
            virtualCollateralSupplyBase.getVirtualCollateralSupply(),
            (INITIAL_SUPPLY + amount)
        );
    }

    function testAddCollateralAmountFails(uint amount) external {
        amount = bound(amount, (MAX_UINT - INITIAL_SUPPLY) + 1, MAX_UINT);

        vm.expectRevert(
            IVirtualCollateralSupply
                .VirtualCollateralSupply_AddResultsInOverflow
                .selector
        );
        virtualCollateralSupplyBase.addVirtualCollateralAmount(amount);

        assertEq(
            virtualCollateralSupplyBase.getVirtualCollateralSupply(),
            (INITIAL_SUPPLY)
        );
    }

    function testSubCollateralAmount(uint amount) external {
        vm.assume(amount <= INITIAL_SUPPLY);

        // Test event
        vm.expectEmit(
            true, true, false, false, address(virtualCollateralSupplyBase)
        );
        emit VirtualCollateralAmountSubtracted(
            amount, (INITIAL_SUPPLY - amount)
        );
        virtualCollateralSupplyBase.subVirtualCollateralAmount(amount);
        assertEq(
            virtualCollateralSupplyBase.getVirtualCollateralSupply(),
            (INITIAL_SUPPLY - amount)
        );
    }

    function testSubCollateralAmountFails(uint amount) external {
        vm.assume(amount > INITIAL_SUPPLY);

        vm.expectRevert(
            IVirtualCollateralSupply
                .VirtualCollateralSupply__SubtractResultsInUnderflow
                .selector
        );
        virtualCollateralSupplyBase.subVirtualCollateralAmount(amount);
    }

    function testGetterAndSetter(uint amount) external {
        vm.assume(amount <= MAX_UINT);

        assertEq(
            virtualCollateralSupplyBase.getVirtualCollateralSupply(),
            (INITIAL_SUPPLY)
        );
        // Test event
        vm.expectEmit(
            true, true, false, false, address(virtualCollateralSupplyBase)
        );
        emit VirtualCollateralSupplySet(amount, INITIAL_SUPPLY);
        virtualCollateralSupplyBase.setVirtualCollateralSupply(amount);

        assertEq(
            virtualCollateralSupplyBase.getVirtualCollateralSupply(), (amount)
        );
    }
}
