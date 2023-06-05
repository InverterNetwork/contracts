// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Test.sol";

// External Libraries
import "@oz/utils/Address.sol";

// SuT
import {Beacon, IBeacon} from "src/factories/beacon/Beacon.sol";

// Mocks
import {ModuleImplementationV1Mock} from
    "test/utils/mocks/factories/beacon/ModuleImplementationV1Mock.sol";
import {ModuleImplementationV2Mock} from
    "test/utils/mocks/factories/beacon/ModuleImplementationV2Mock.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

contract BeaconTest is Test {
    // SuT
    Beacon beacon;

    // Events copied from SuT
    event Upgraded(address indexed implementation);

    function setUp() public {
        beacon = new Beacon();
    }

    function testDeploymentInvariants() public {
        assertEq(beacon.implementation(), address(0));

        // Check that proposal's dependencies correctly initialized.
        // Ownable2Step:
        assertEq(beacon.owner(), address(this));
        assertEq(beacon.pendingOwner(), address(0));
    }

    //--------------------------------------------------------------------------------
    // Test: upgradeTo()

    function testUpgradeTo() public {
        ModuleImplementationV1Mock toUpgrade1 = new ModuleImplementationV1Mock();
        ModuleImplementationV2Mock toUpgrade2 = new ModuleImplementationV2Mock();

        vm.expectEmit(true, true, true, true);
        emit Upgraded(address(toUpgrade1));

        beacon.upgradeTo(address(toUpgrade1));

        assertEq(beacon.implementation(), address(toUpgrade1));

        vm.expectEmit(true, true, true, true);
        emit Upgraded(address(toUpgrade2));

        beacon.upgradeTo(address(toUpgrade2));

        assertEq(beacon.implementation(), address(toUpgrade2));
    }

    function testUpgradeToOnlyCallableByOwner(address caller) public {
        vm.assume(caller != address(this));
        vm.prank(caller);

        vm.expectRevert(OZErrors.Ownable2Step__CallerNotOwner);
        beacon.upgradeTo(address(0));
    }

    function testUpgradeToFailsIfImplementationNotContract() public {
        // Note that address(0xCAFE) is EOA.
        vm.expectRevert(Beacon.Beacon__InvalidImplementation.selector);
        beacon.upgradeTo(address(0xCAFE));
    }

    //--------------------------------------------------------------------------------
    // Test: ERC-165's supportInterface()

    function testSupportsInterface() public {
        assertTrue(beacon.supportsInterface(type(IBeacon).interfaceId));
    }
}
