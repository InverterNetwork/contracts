// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {VirtualTokenSupplyBaseMock} from
    "./utils/mocks/VirtualTokenSupplyBaseMock.sol";
import {IVirtualTokenSupply} from
    "src/modules/fundingManager/bondingCurveFundingManager/marketMaker/IVirtualTokenSupply.sol";

contract VirtualTokenSupplyBaseTest is Test {
    VirtualTokenSupplyBaseMock virtualTokenSupplyBase;
    uint internal constant INITIAL_SUPPLY = 1000e18;
    uint internal constant MAX_UINT = type(uint).max;

    event VirtualTokenSupplySet(uint indexed newSupply, uint indexed oldSupply);
    event VirtualTokenAmountAdded(
        uint indexed amountAdded, uint indexed newSupply
    );
    event VirtualTokenAmountSubtracted(
        uint indexed amountSubtracted, uint indexed newSupply
    );

    function setUp() public {
        virtualTokenSupplyBase = new VirtualTokenSupplyBaseMock();
        virtualTokenSupplyBase.setVirtualTokenSupply(INITIAL_SUPPLY);
    }

    function testAddTokenAmount(uint amount) external {
        amount = bound(amount, 0, (MAX_UINT - INITIAL_SUPPLY));

        // Test event
        vm.expectEmit(true, true, false, false, address(virtualTokenSupplyBase));
        emit VirtualTokenAmountAdded(amount, (INITIAL_SUPPLY + amount));
        virtualTokenSupplyBase.addVirtualTokenAmount(amount);
        assertEq(
            virtualTokenSupplyBase.getVirtualTokenSupply(),
            (INITIAL_SUPPLY + amount)
        );
    }

    function testAddTokenAmountFails(uint amount) external {
        amount = bound(amount, (MAX_UINT - INITIAL_SUPPLY) + 1, MAX_UINT);

        vm.expectRevert(
            IVirtualTokenSupply.VirtualTokenSupply_AddResultsInOverflow.selector
        );
        virtualTokenSupplyBase.addVirtualTokenAmount(amount);

        assertEq(
            virtualTokenSupplyBase.getVirtualTokenSupply(), (INITIAL_SUPPLY)
        );
    }

    function testSubTokenAmount(uint amount) external {
        vm.assume(amount < INITIAL_SUPPLY);

        // Test event
        vm.expectEmit(true, true, false, false, address(virtualTokenSupplyBase));
        emit VirtualTokenAmountSubtracted(amount, (INITIAL_SUPPLY - amount));
        virtualTokenSupplyBase.subVirtualTokenAmount(amount);
        assertEq(
            virtualTokenSupplyBase.getVirtualTokenSupply(),
            (INITIAL_SUPPLY - amount)
        );
    }

    function testSubTokenAmountFails(uint amount) external {
        vm.assume(amount > INITIAL_SUPPLY);

        vm.expectRevert(
            IVirtualTokenSupply
                .VirtualTokenSupply__SubtractResultsInUnderflow
                .selector
        );
        virtualTokenSupplyBase.subVirtualTokenAmount(amount);
    }

    function testSubTokenAmountFailsIfZero() external {
        uint amount = INITIAL_SUPPLY;

        vm.expectRevert(
            IVirtualTokenSupply
                .VirtualTokenSupply__VirtualSupplyCannotBeZero
                .selector
        );
        virtualTokenSupplyBase.subVirtualTokenAmount(amount);
    }

    function testGetterAndSetter(uint amount) external {
        amount = bound(amount, 1, MAX_UINT);

        assertEq(
            virtualTokenSupplyBase.getVirtualTokenSupply(), (INITIAL_SUPPLY)
        );
        // Test event
        vm.expectEmit(true, true, false, false, address(virtualTokenSupplyBase));
        emit VirtualTokenSupplySet(amount, INITIAL_SUPPLY);
        virtualTokenSupplyBase.setVirtualTokenSupply(amount);

        assertEq(virtualTokenSupplyBase.getVirtualTokenSupply(), (amount));
    }

    function testGetterAndSetterFailsIfSetToZero() external {
        uint amount = 0;

        vm.expectRevert(
            IVirtualTokenSupply
                .VirtualTokenSupply__VirtualSupplyCannotBeZero
                .selector
        );
        virtualTokenSupplyBase.setVirtualTokenSupply(amount);

        assertEq(
            virtualTokenSupplyBase.getVirtualTokenSupply(), (INITIAL_SUPPLY)
        );
    }
}
