// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {IERC165} from "@oz/utils/introspection/IERC165.sol";
import {VirtualCollateralSupplyBaseV1Mock} from
    "test/modules/fundingManager/bondingCurve/utils/mocks/VirtualCollateralSupplyBaseV1Mock.sol";
import {IVirtualCollateralSupplyBase_v1} from
    "@fm/bondingCurve/interfaces/IVirtualCollateralSupplyBase_v1.sol";

contract VirtualCollateralSupplyBaseV1Test is Test {
    VirtualCollateralSupplyBaseV1Mock virtualCollateralSupplyBase;
    uint internal constant INITIAL_SUPPLY = 1000e18;
    uint internal constant MAX_UINT = type(uint).max;

    event VirtualCollateralSupplySet(uint newSupply, uint oldSupply);

    event VirtualCollateralAmountAdded(uint amountAdded, uint newSupply);

    event VirtualCollateralAmountSubtracted(
        uint amountSubtracted, uint newSupply
    );

    function setUp() public {
        virtualCollateralSupplyBase = new VirtualCollateralSupplyBaseV1Mock();
        virtualCollateralSupplyBase.setVirtualCollateralSupply(INITIAL_SUPPLY);
    }

    function testSupportsInterface() public {
        assertTrue(
            virtualCollateralSupplyBase.supportsInterface(
                type(IVirtualCollateralSupplyBase_v1).interfaceId
            )
        );
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
            IVirtualCollateralSupplyBase_v1
                .Module__VirtualCollateralSupplyBase__AddResultsInOverflow
                .selector
        );
        virtualCollateralSupplyBase.addVirtualCollateralAmount(amount);

        assertEq(
            virtualCollateralSupplyBase.getVirtualCollateralSupply(),
            (INITIAL_SUPPLY)
        );
    }

    function testSubCollateralAmount(uint amount) external {
        vm.assume(amount < INITIAL_SUPPLY);

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

    function testSubCollateralAmountFailsIfUnderflow(uint amount) external {
        vm.assume(amount > INITIAL_SUPPLY);

        vm.expectRevert(
            IVirtualCollateralSupplyBase_v1
                .Module__VirtualCollateralSupplyBase__SubtractResultsInUnderflow
                .selector
        );
        virtualCollateralSupplyBase.subVirtualCollateralAmount(amount);
    }

    function testSubCollateralAmountFailsIfZero() external {
        uint amount = INITIAL_SUPPLY;

        vm.expectRevert(
            IVirtualCollateralSupplyBase_v1
                .Module__VirtualCollateralSupplyBase__VirtualSupplyCannotBeZero
                .selector
        );
        virtualCollateralSupplyBase.subVirtualCollateralAmount(amount);
    }

    function testGetterAndSetter(uint amount) external {
        amount = bound(amount, 1, MAX_UINT);

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

    function testGetterAndSetterFailsIfSetToZero() external {
        uint amount = 0;

        vm.expectRevert(
            IVirtualCollateralSupplyBase_v1
                .Module__VirtualCollateralSupplyBase__VirtualSupplyCannotBeZero
                .selector
        );
        virtualCollateralSupplyBase.setVirtualCollateralSupply(amount);

        assertEq(
            virtualCollateralSupplyBase.getVirtualCollateralSupply(),
            (INITIAL_SUPPLY)
        );
    }
}
