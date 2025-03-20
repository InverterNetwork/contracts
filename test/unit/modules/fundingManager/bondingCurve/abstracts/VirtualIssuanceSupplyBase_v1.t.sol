// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {IERC165} from "@oz/utils/introspection/IERC165.sol";
import {VirtualIssuanceSupplyBaseV1Mock} from
    "test/modules/fundingManager/bondingCurve/utils/mocks/VirtualIssuanceSupplyBaseV1Mock.sol";
import {IVirtualIssuanceSupplyBase_v1} from
    "@fm/bondingCurve/interfaces/IVirtualIssuanceSupplyBase_v1.sol";

contract VirtualIssuanceSupplyBaseV1Test is Test {
    VirtualIssuanceSupplyBaseV1Mock virtualIssuanceSupplyBase;
    uint internal constant INITIAL_SUPPLY = 1000e18;
    uint internal constant MAX_UINT = type(uint).max;

    event VirtualIssuanceSupplySet(uint newSupply, uint oldSupply);
    event VirtualIssuanceAmountAdded(uint amountAdded, uint newSupply);
    event VirtualIssuanceAmountSubtracted(
        uint amountSubtracted, uint newSupply
    );

    function setUp() public {
        virtualIssuanceSupplyBase = new VirtualIssuanceSupplyBaseV1Mock();
        virtualIssuanceSupplyBase.setVirtualIssuanceSupply(INITIAL_SUPPLY);
    }

    function testSupportsInterface() public {
        assertTrue(
            virtualIssuanceSupplyBase.supportsInterface(
                type(IVirtualIssuanceSupplyBase_v1).interfaceId
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
        virtualIssuanceSupplyBase.addVirtualIssuanceAmount(amount);
        assertEq(
            virtualIssuanceSupplyBase.getVirtualIssuanceSupply(),
            (INITIAL_SUPPLY + amount)
        );
    }

    function testAddTokenAmountFails(uint amount) external {
        amount = bound(amount, (MAX_UINT - INITIAL_SUPPLY) + 1, MAX_UINT);

        vm.expectRevert(
            IVirtualIssuanceSupplyBase_v1
                .Module__VirtualIssuanceSupplyBase__AddResultsInOverflow
                .selector
        );
        virtualIssuanceSupplyBase.addVirtualIssuanceAmount(amount);

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
        virtualIssuanceSupplyBase.subVirtualIssuanceAmount(amount);
        assertEq(
            virtualIssuanceSupplyBase.getVirtualIssuanceSupply(),
            (INITIAL_SUPPLY - amount)
        );
    }

    function testSubTokenAmountFails(uint amount) external {
        vm.assume(amount > INITIAL_SUPPLY);

        vm.expectRevert(
            IVirtualIssuanceSupplyBase_v1
                .Module__VirtualIssuanceSupplyBase__SubtractResultsInUnderflow
                .selector
        );
        virtualIssuanceSupplyBase.subVirtualIssuanceAmount(amount);
    }

    function testSubTokenAmountFailsIfZero() external {
        uint amount = INITIAL_SUPPLY;

        vm.expectRevert(
            IVirtualIssuanceSupplyBase_v1
                .Module__VirtualIssuanceSupplyBase__VirtualSupplyCannotBeZero
                .selector
        );
        virtualIssuanceSupplyBase.subVirtualIssuanceAmount(amount);
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
            IVirtualIssuanceSupplyBase_v1
                .Module__VirtualIssuanceSupplyBase__VirtualSupplyCannotBeZero
                .selector
        );
        virtualIssuanceSupplyBase.setVirtualIssuanceSupply(amount);

        assertEq(
            virtualIssuanceSupplyBase.getVirtualIssuanceSupply(),
            (INITIAL_SUPPLY)
        );
    }
}
