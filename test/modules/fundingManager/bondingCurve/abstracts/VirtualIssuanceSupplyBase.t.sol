// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {IERC165} from "@oz/utils/introspection/IERC165.sol";
import {VirtualIssuanceSupplyBaseMock} from
    "test/modules/fundingManager/bondingCurve/utils/mocks/VirtualIssuanceSupplyBaseMock.sol";
import {IVirtualIssuanceSupplyBase} from
    "src/modules/fundingManager/bondingCurve/interfaces/IVirtualIssuanceSupplyBase.sol";

contract VirtualIssuanceSupplyBaseTest is Test {
    VirtualIssuanceSupplyBaseMock virtualIssuanceSupplyBase;
    uint internal constant INITIAL_SUPPLY = 1000e18;
    uint internal constant MAX_UINT = type(uint).max;

    event VirtualIssuanceSupplySet(
        uint indexed newSupply, uint indexed oldSupply
    );
    event VirtualIssuanceAmountAdded(
        uint indexed amountAdded, uint indexed newSupply
    );
    event VirtualIssuanceAmountSubtracted(
        uint indexed amountSubtracted, uint indexed newSupply
    );

    function setUp() public {
        virtualIssuanceSupplyBase = new VirtualIssuanceSupplyBaseMock();
        virtualIssuanceSupplyBase.setVirtualIssuanceSupply(INITIAL_SUPPLY);
    }

    function testSupportsInterface() public {
        assertTrue(
            virtualIssuanceSupplyBase.supportsInterface(
                type(IVirtualIssuanceSupplyBase).interfaceId
            )
        );
    }

    function testAddTokenAmount(uint amount) external {
        amount = bound(amount, 0, (MAX_UINT - INITIAL_SUPPLY));

        // Test event
        vm.expectEmit(
            true, true, false, false, address(virtualIssuanceSupplyBase)
        );
        emit VirtualIssuanceAmountAdded(amount, (INITIAL_SUPPLY + amount));
        virtualIssuanceSupplyBase.addVirtualTokenAmount(amount);
        assertEq(
            virtualIssuanceSupplyBase.getVirtualIssuanceSupply(),
            (INITIAL_SUPPLY + amount)
        );
    }

    function testAddTokenAmountFails(uint amount) external {
        amount = bound(amount, (MAX_UINT - INITIAL_SUPPLY) + 1, MAX_UINT);

        vm.expectRevert(
            IVirtualIssuanceSupplyBase
                .VirtualIssuanceSupplyBase_AddResultsInOverflow
                .selector
        );
        virtualIssuanceSupplyBase.addVirtualTokenAmount(amount);

        assertEq(
            virtualIssuanceSupplyBase.getVirtualIssuanceSupply(),
            (INITIAL_SUPPLY)
        );
    }

    function testSubTokenAmount(uint amount) external {
        vm.assume(amount < INITIAL_SUPPLY);

        // Test event
        vm.expectEmit(
            true, true, false, false, address(virtualIssuanceSupplyBase)
        );
        emit VirtualIssuanceAmountSubtracted(amount, (INITIAL_SUPPLY - amount));
        virtualIssuanceSupplyBase.subVirtualTokenAmount(amount);
        assertEq(
            virtualIssuanceSupplyBase.getVirtualIssuanceSupply(),
            (INITIAL_SUPPLY - amount)
        );
    }

    function testSubTokenAmountFails(uint amount) external {
        vm.assume(amount > INITIAL_SUPPLY);

        vm.expectRevert(
            IVirtualIssuanceSupplyBase
                .VirtualIssuanceSupplyBase__SubtractResultsInUnderflow
                .selector
        );
        virtualIssuanceSupplyBase.subVirtualTokenAmount(amount);
    }

    function testSubTokenAmountFailsIfZero() external {
        uint amount = INITIAL_SUPPLY;

        vm.expectRevert(
            IVirtualIssuanceSupplyBase
                .VirtualIssuanceSupplyBase__VirtualSupplyCannotBeZero
                .selector
        );
        virtualIssuanceSupplyBase.subVirtualTokenAmount(amount);
    }

    function testGetterAndSetter(uint amount) external {
        amount = bound(amount, 1, MAX_UINT);

        assertEq(
            virtualIssuanceSupplyBase.getVirtualIssuanceSupply(),
            (INITIAL_SUPPLY)
        );
        // Test event
        vm.expectEmit(
            true, true, false, false, address(virtualIssuanceSupplyBase)
        );
        emit VirtualIssuanceSupplySet(amount, INITIAL_SUPPLY);
        virtualIssuanceSupplyBase.setVirtualIssuanceSupply(amount);

        assertEq(virtualIssuanceSupplyBase.getVirtualIssuanceSupply(), (amount));
    }

    function testGetterAndSetterFailsIfSetToZero() external {
        uint amount = 0;

        vm.expectRevert(
            IVirtualIssuanceSupplyBase
                .VirtualIssuanceSupplyBase__VirtualSupplyCannotBeZero
                .selector
        );
        virtualIssuanceSupplyBase.setVirtualIssuanceSupply(amount);

        assertEq(
            virtualIssuanceSupplyBase.getVirtualIssuanceSupply(),
            (INITIAL_SUPPLY)
        );
    }
}
