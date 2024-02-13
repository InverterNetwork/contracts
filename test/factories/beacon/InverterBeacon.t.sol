// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// External Libraries
import "@oz/utils/Address.sol";

import {IERC165} from "@oz/utils/introspection/IERC165.sol";

// SuT
import {
    InverterBeacon,
    IInverterBeacon
} from "src/factories/beacon/InverterBeacon.sol";

// Mocks
import {ModuleImplementationV1Mock} from
    "test/utils/mocks/factories/beacon/ModuleImplementationV1Mock.sol";
import {ModuleImplementationV2Mock} from
    "test/utils/mocks/factories/beacon/ModuleImplementationV2Mock.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

import {Ownable} from "@oz/access/Ownable.sol";

contract InverterBeaconTest is Test {
    // SuT
    InverterBeacon beacon;

    // Events copied from SuT
    event Upgraded(address indexed implementation, uint newMinorVersion);

    function setUp() public {
        beacon = new InverterBeacon(0);
    }

    function testDeploymentInvariants() public {
        assertEq(beacon.implementation(), address(0));

        // Check that orchestrator's dependencies correctly initialized.
        // Ownable2Step:
        assertEq(beacon.owner(), address(this));
        assertEq(beacon.pendingOwner(), address(0));

        //Check for version
        (uint majorVersion, uint minorVersion) = beacon.version();
        assertEq(majorVersion, 0);
        assertEq(minorVersion, 0);
    }

    //--------------------------------------------------------------------------------
    // Test: upgradeTo()

    function testUpgradeTo() public {
        ModuleImplementationV1Mock toUpgrade1 = new ModuleImplementationV1Mock();
        ModuleImplementationV2Mock toUpgrade2 = new ModuleImplementationV2Mock();

        uint majorVersion;
        uint minorVersion;

        vm.expectEmit(true, true, true, true);
        emit Upgraded(address(toUpgrade1), 1);

        beacon.upgradeTo(address(toUpgrade1), 1);

        assertEq(beacon.implementation(), address(toUpgrade1));
        (majorVersion, minorVersion) = beacon.version();
        assertEq(majorVersion, 0);
        assertEq(minorVersion, 1);

        vm.expectEmit(true, true, true, true);
        emit Upgraded(address(toUpgrade2), 2);

        beacon.upgradeTo(address(toUpgrade2), 2);
        (majorVersion, minorVersion) = beacon.version();
        assertEq(majorVersion, 0);
        assertEq(minorVersion, 2);

        assertEq(beacon.implementation(), address(toUpgrade2));
    }

    function testUpgradeToOnlyCallableByOwner(address caller) public {
        vm.assume(caller != address(this));
        vm.prank(caller);

        vm.expectRevert(
            abi.encodeWithSelector(
                OZErrors.Ownable__UnauthorizedAccount, caller
            )
        );
        beacon.upgradeTo(address(0), 1);
    }

    function testUpgradeToFailsForFalseMinorVersion(
        uint initialMinorVersion,
        uint newMinorVersion
    ) public {
        //generate implementation address
        address implementation = address(new ModuleImplementationV1Mock());

        //Upgrade to an initial Version
        if (initialMinorVersion != 0) {
            beacon.upgradeTo(implementation, initialMinorVersion);
        }

        if (newMinorVersion <= initialMinorVersion) {
            vm.expectRevert(
                IInverterBeacon
                    .Beacon__InvalidImplementationMinorVersion
                    .selector
            );
        }
        beacon.upgradeTo(implementation, newMinorVersion);
    }

    function testUpgradeToFailsIfImplementationNotContract() public {
        // Note that address(0xCAFE) is EOA.
        vm.expectRevert(IInverterBeacon.Beacon__InvalidImplementation.selector);
        beacon.upgradeTo(address(0xCAFE), 2);
    }

    //--------------------------------------------------------------------------------
    // Test: ERC-165's supportInterface()

    function testSupportsInterface() public {
        assertTrue(beacon.supportsInterface(type(IInverterBeacon).interfaceId));
    }
}
