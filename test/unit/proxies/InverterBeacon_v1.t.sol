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

import {InverterReverter_v1} from
    "src/external/reverter/InverterReverter_v1.sol";

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

    InverterReverter_v1 reverter = new InverterReverter_v1();

    ModuleImplementationV1Mock possibleImplementation =
        new ModuleImplementationV1Mock();

    // Events copied from SuT
    event Upgraded(
        address indexed implementation,
        uint newMinorVersion,
        uint newPatchVersion
    );

    event ShutdownInitiated();

    event ShutdownReversed();

    function setUp() public {
        beacon = new InverterBeaconV1AccessMock(
            address(reverter),
            address(this),
            0,
            address(possibleImplementation),
            0,
            0
        );
    }

    function testDeploymentInvariants() public {
        assertEq(beacon.owner(), address(this));
        assertEq(beacon.implementation(), address(possibleImplementation));
        assertEq(beacon.getReverterAddress(), address(reverter));

        // Check that orchestrator's dependencies correctly initialized.
        // Ownable2Step:
        assertEq(beacon.owner(), address(this));
        assertEq(beacon.pendingOwner(), address(0));

        // Check for version
        (uint majorVersion, uint minorVersion, uint patchVersion) =
            beacon.version();
        assertEq(majorVersion, 0);
        assertEq(minorVersion, 0);
        assertEq(patchVersion, 0);
    }

    //--------------------------------------------------------------------------
    // Test: modifier

    function testZeroAsNewMinorAndPatchVersion() public {
        // Check for version
        (, uint minorVersionPre, uint patchVersionPre) = beacon.version();
        assertEq(minorVersionPre, 0);
        assertEq(patchVersionPre, 0);

        // generate implementation address
        address implementation = address(new ModuleImplementationV1Mock());

        vm.expectRevert(
            IInverterBeacon_v1
                .InverterBeacon__InvalidImplementationMinorOrPatchVersion
                .selector
        );

        // Upgrade to an initial Version
        beacon.upgradeTo(implementation, 0, 0, false);
    }

    function testNewMinorOrPatchVersion(
        uint initialVersion,
        uint newMinorVersion,
        uint newPatchVersion
    ) public {
        // we can't upgrade to 0 version
        // as the 0 version can only be set during
        // initialization (first version ever set)
        vm.assume(initialVersion > 0);

        // generate implementation address
        address implementation = address(new ModuleImplementationV1Mock());

        // Upgrade to an initial Version
        beacon.upgradeTo(implementation, initialVersion, initialVersion, false);

        // Check for version
        (, uint minorVersionPre, uint patchVersionPre) = beacon.version();
        assertEq(minorVersionPre, initialVersion);
        assertEq(patchVersionPre, initialVersion);

        if (
            newMinorVersion < initialVersion
                || newMinorVersion == initialVersion
                    && newPatchVersion <= initialVersion
        ) {
            vm.expectRevert(
                IInverterBeacon_v1
                    .InverterBeacon__InvalidImplementationMinorOrPatchVersion
                    .selector
            );
        }
        beacon.upgradeTo(
            implementation, newMinorVersion, newPatchVersion, false
        );

        if (newMinorVersion > initialVersion) {
            // Check for version
            (, uint minorVersionPost,) = beacon.version();
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

    //--------------------------------------------------------------------------
    // Test: upgradeTo()

    function testUpgradeTo(
        address newImplementation,
        uint oldMinorVersion,
        uint newMinorVersion,
        uint oldPatchVersion,
        uint newPatchVersion,
        bool overrideShutdown
    ) public {
        // needs to be a valid upgrade
        vm.assume(
            newMinorVersion > oldMinorVersion
                || newMinorVersion == oldMinorVersion
                    && newPatchVersion > oldPatchVersion
        );

        // Turn off setImplementation
        beacon.flipUseOriginal_setImplementation();

        if (oldMinorVersion != 0 || oldPatchVersion != 0) {
            beacon.upgradeTo(
                address(0), oldMinorVersion, oldPatchVersion, false
            );
        }

        vm.expectEmit(true, true, true, true);
        emit Upgraded(
            address(newImplementation), newMinorVersion, newPatchVersion
        );

        beacon.upgradeTo(
            address(newImplementation),
            newMinorVersion,
            newPatchVersion,
            overrideShutdown
        );

        (, uint minorVersion, uint patchVersion) = beacon.version();
        assertEq(newMinorVersion, minorVersion);
        assertEq(newPatchVersion, patchVersion);
    }

    function testUpgradeToPOC() public {
        ModuleImplementationV1Mock toUpgrade1 = new ModuleImplementationV1Mock();
        ModuleImplementationV2Mock toUpgrade2 = new ModuleImplementationV2Mock();

        uint majorVersion;
        uint minorVersion;
        uint patchVersion;

        vm.expectEmit(true, true, true, true);
        emit Upgraded(address(toUpgrade1), 1, 0);

        beacon.upgradeTo(address(toUpgrade1), 1, 0, false);

        assertEq(beacon.implementation(), address(toUpgrade1));
        (majorVersion, minorVersion, patchVersion) = beacon.version();
        assertEq(majorVersion, 0);
        assertEq(minorVersion, 1);
        assertEq(patchVersion, 0);

        vm.expectEmit(true, true, true, true);
        emit Upgraded(address(toUpgrade2), 2, 0);

        beacon.upgradeTo(address(toUpgrade2), 2, 0, false);
        (majorVersion, minorVersion, patchVersion) = beacon.version();
        assertEq(majorVersion, 0);
        assertEq(minorVersion, 2);
        assertEq(patchVersion, 0);

        assertEq(beacon.implementation(), address(toUpgrade2));
    }

    function testUpgradeToModifierInPosition() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert(
            abi.encodeWithSelector(
                OZErrors.Ownable__UnauthorizedAccount, address(0xBEEF)
            )
        );
        beacon.upgradeTo(address(this), 1, 0, false);

        vm.expectRevert(
            IInverterBeacon_v1.InverterBeacon__InvalidImplementation.selector
        );
        beacon.upgradeTo(address(0), 1, 0, false);
    }

    //--------------------------------------------------------------------------
    // Test: shutDownImplementation

    function testShutDownImplementation() public {
        ModuleImplementationV1Mock toUpgrade1 = new ModuleImplementationV1Mock();

        beacon.upgradeTo(address(toUpgrade1), 1, 0, false);

        vm.expectEmit(true, true, true, true);
        emit ShutdownInitiated();

        beacon.shutDownImplementation();

        // Check that internal implementation stays the same
        assertEq(beacon.get_implementation(), address(toUpgrade1));
        assertEq(beacon.implementation(), address(reverter));
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

    //--------------------------------------------------------------------------
    // Test: restartImplementation

    function testRestartImplementation() public {
        ModuleImplementationV1Mock toUpgrade1 = new ModuleImplementationV1Mock();

        beacon.upgradeTo(address(toUpgrade1), 1, 0, false);

        beacon.shutDownImplementation();

        vm.expectEmit(true, true, true, true);
        emit ShutdownReversed();

        beacon.restartImplementation();

        // Check that internal implementation stays the same
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

    //--------------------------------------------------------------------------
    // Test: _setImplementation

    function test_setImplementation(
        bool emergencyModeActive,
        bool overrideShutdown
    ) public {
        // Set oldImplementation
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
            // if override shutdown is not active it should stay inactive
            if (!overrideShutdown) {
                assertEq(beacon.implementation(), address(reverter));
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

    //--------------------------------------------------------------------------
    // Test: ERC-165's supportInterface()

    function testSupportsInterface() public {
        assertTrue(
            beacon.supportsInterface(type(IInverterBeacon_v1).interfaceId)
        );
    }
}
