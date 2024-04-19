// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// External Libraries
import "@oz/utils/Address.sol";

import {IERC165} from "@oz/utils/introspection/IERC165.sol";

// SuT
import {IInverterBeacon_v1} from "src/proxies/interfaces/IInverterBeacon_v1.sol";

import {InverterBeaconV1AccessMock} from
    "test/utils/mocks/proxies/InverterBeaconV1AccessMock.sol";

// Mocks
import {ModuleImplementationV1Mock} from
    "test/utils/mocks/proxies/ModuleImplementationV1Mock.sol";
import {ModuleImplementationV2Mock} from
    "test/utils/mocks/proxies/ModuleImplementationV2Mock.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

import {Ownable} from "@oz/access/Ownable.sol";

contract InverterBeaconV1Test is Test {
    // SuT
    InverterBeaconV1AccessMock beacon;

    ModuleImplementationV1Mock possibleImplementation =
        new ModuleImplementationV1Mock();

    // Events copied from SuT
    event Upgraded(address indexed implementation, uint newMinorVersion);

    event ShutdownInitiated();

    event ShutdownReversed();

    function setUp() public {
        beacon = new InverterBeaconV1AccessMock(
            address(this), 0, address(possibleImplementation), 0
        );
    }

    function testDeploymentInvariants() public {
        assertEq(beacon.owner(), address(this));
        assertEq(beacon.implementation(), address(possibleImplementation));

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
    // Test: modifier

    function testZeroAsNewMinorVersion() public {
        //Check for version
        (, uint minorVersionPre) = beacon.version();
        assertEq(minorVersionPre, 0);

        //generate implementation address
        address implementation = address(new ModuleImplementationV1Mock());

        vm.expectRevert(
            IInverterBeacon_v1
                .InverterBeacon__InvalidImplementationMinorVersion
                .selector
        );

        //Upgrade to an initial Version
        beacon.upgradeTo(implementation, 0, false);
    }

    function testNewMinorVersion(uint initialMinorVersion, uint newMinorVersion)
        public
    {
        // we can't upgrade to 0 version
        // as the 0 version can only be set during
        // initialization (first version ever set)
        vm.assume(initialMinorVersion > 0);

        //generate implementation address
        address implementation = address(new ModuleImplementationV1Mock());

        //Upgrade to an initial Version
        beacon.upgradeTo(implementation, initialMinorVersion, false);

        //Check for version
        (, uint minorVersionPre) = beacon.version();
        assertEq(minorVersionPre, initialMinorVersion);

        if (newMinorVersion <= initialMinorVersion) {
            vm.expectRevert(
                IInverterBeacon_v1
                    .InverterBeacon__InvalidImplementationMinorVersion
                    .selector
            );
        }
        beacon.upgradeTo(implementation, newMinorVersion, false);

        if (newMinorVersion > initialMinorVersion) {
            //Check for version
            (, uint minorVersionPost) = beacon.version();
            assertEq(minorVersionPost, newMinorVersion);
        }
    }

    function testValidImplementation(address newImplementation) public {
        if (!(newImplementation.code.length > 0)) {
            vm.expectRevert(
                IInverterBeacon_v1
                    .InverterBeacon__InvalidImplementation
                    .selector
            );
        }

        beacon.original_setImplementation(newImplementation, false);
    }

    //--------------------------------------------------------------------------------
    // Test: upgradeTo()

    function testUpgradeTo(
        address newImplementation,
        uint oldMinorVersion,
        uint newMinorVersion,
        bool overrideShutdown
    ) public {
        // needs to be a valid upgrade
        vm.assume(oldMinorVersion < newMinorVersion);

        //Turn off setImplementation
        beacon.flipUseOriginal_setImplementation();

        if (oldMinorVersion != 0) {
            beacon.upgradeTo(address(0), oldMinorVersion, false);
        }

        vm.expectEmit(true, true, true, true);
        emit Upgraded(address(newImplementation), newMinorVersion);

        beacon.upgradeTo(
            address(newImplementation), newMinorVersion, overrideShutdown
        );

        (, uint minorVersion) = beacon.version();
        assertEq(newMinorVersion, minorVersion);
    }

    function testUpgradeToPOC() public {
        ModuleImplementationV1Mock toUpgrade1 = new ModuleImplementationV1Mock();
        ModuleImplementationV2Mock toUpgrade2 = new ModuleImplementationV2Mock();

        uint majorVersion;
        uint minorVersion;

        vm.expectEmit(true, true, true, true);
        emit Upgraded(address(toUpgrade1), 1);

        beacon.upgradeTo(address(toUpgrade1), 1, false);

        assertEq(beacon.implementation(), address(toUpgrade1));
        (majorVersion, minorVersion) = beacon.version();
        assertEq(majorVersion, 0);
        assertEq(minorVersion, 1);

        vm.expectEmit(true, true, true, true);
        emit Upgraded(address(toUpgrade2), 2);

        beacon.upgradeTo(address(toUpgrade2), 2, false);
        (majorVersion, minorVersion) = beacon.version();
        assertEq(majorVersion, 0);
        assertEq(minorVersion, 2);

        assertEq(beacon.implementation(), address(toUpgrade2));
    }

    function testUpgradeToModifierInPosition() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert(
            abi.encodeWithSelector(
                OZErrors.Ownable__UnauthorizedAccount, address(0xBEEF)
            )
        );
        beacon.upgradeTo(address(this), 1, false);

        vm.expectRevert(
            IInverterBeacon_v1.InverterBeacon__InvalidImplementation.selector
        );
        beacon.upgradeTo(address(0), 1, false);
    }

    //--------------------------------------------------------------------------------
    // Test: shutDownImplementation

    function testShutDownImplementation() public {
        ModuleImplementationV1Mock toUpgrade1 = new ModuleImplementationV1Mock();

        beacon.upgradeTo(address(toUpgrade1), 1, false);

        vm.expectEmit(true, true, true, true);
        emit ShutdownInitiated();

        beacon.shutDownImplementation();

        //Check that internal implementation stays the same
        assertEq(beacon.get_implementation(), address(toUpgrade1));
        assertEq(beacon.implementation(), address(0));
        assertTrue(beacon.emergencyModeActive());
    }

    function testShutDownImplementationModifierInPosition() public {
        vm.prank(address(0xBEEF));

        vm.expectRevert(
            abi.encodeWithSelector(
                OZErrors.Ownable__UnauthorizedAccount, address(0xBEEF)
            )
        );
        beacon.shutDownImplementation();
    }

    //--------------------------------------------------------------------------------
    // Test: restartImplementation

    function testRestartImplementation() public {
        ModuleImplementationV1Mock toUpgrade1 = new ModuleImplementationV1Mock();

        beacon.upgradeTo(address(toUpgrade1), 1, false);

        beacon.shutDownImplementation();

        vm.expectEmit(true, true, true, true);
        emit ShutdownReversed();

        beacon.restartImplementation();

        //Check that internal implementation stays the same
        assertEq(beacon.get_implementation(), address(toUpgrade1));
        assertEq(beacon.implementation(), address(toUpgrade1));
        assertFalse(beacon.emergencyModeActive());
    }

    function testRestartImplementationModifierInPosition() public {
        vm.prank(address(0xBEEF));

        vm.expectRevert(
            abi.encodeWithSelector(
                OZErrors.Ownable__UnauthorizedAccount, address(0xBEEF)
            )
        );
        beacon.restartImplementation();
    }

    //--------------------------------------------------------------------------------
    // Test: _setImplementation

    function test_setImplementation(
        bool emergencyModeActive,
        bool overrideShutdown
    ) public {
        //Set oldImplementation
        ModuleImplementationV1Mock toUpgrade1 = new ModuleImplementationV1Mock();

        beacon.original_setImplementation(address(toUpgrade1), false);

        if (emergencyModeActive) {
            beacon.shutDownImplementation();
        }

        ModuleImplementationV2Mock toUpgrade2 = new ModuleImplementationV2Mock();

        if (emergencyModeActive && overrideShutdown) {
            vm.expectEmit(true, true, true, true);
            emit ShutdownReversed();
        }

        beacon.original_setImplementation(address(toUpgrade2), overrideShutdown);

        assertEq(beacon.get_implementation(), address(toUpgrade2));

        if (!emergencyModeActive) {
            assertEq(beacon.implementation(), address(toUpgrade2));
        } else {
            //if override shutdown is not active it should stay inactive
            if (!overrideShutdown) {
                assertEq(beacon.implementation(), address(0));
            } else {
                assertFalse(beacon.emergencyModeActive());
                assertEq(beacon.implementation(), address(toUpgrade2));
            }
        }

        //
    }

    function test_setImplementationModifierInPosition() public {
        vm.expectRevert(
            IInverterBeacon_v1.InverterBeacon__InvalidImplementation.selector
        );
        beacon.original_setImplementation(address(0), false);
    }

    //--------------------------------------------------------------------------------
    // Test: ERC-165's supportInterface()

    function testSupportsInterface() public {
        assertTrue(
            beacon.supportsInterface(type(IInverterBeacon_v1).interfaceId)
        );
    }
}
