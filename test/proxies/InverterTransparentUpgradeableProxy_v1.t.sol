// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// Internal Dependencies
import {InverterTransparentUpgradeableProxy_v1} from
    "src/proxies/InverterTransparentUpgradeableProxy_v1.sol";
import {
    InverterBeacon_v1,
    IInverterBeacon_v1
} from "src/proxies/InverterBeacon_v1.sol";
import {InverterBeaconProxy_v1} from "src/proxies/InverterBeaconProxy_v1.sol";

// Internal Interfaces
import {IInverterTransparentUpgradeableProxy_v1} from
    "src/proxies/interfaces/IInverterTransparentUpgradeableProxy_v1.sol";

// Mocks
import {
    InverterTransparentUpgradeableProxy_v1,
    InverterTransparentUpgradeableProxyV1AccessMock
} from
    "test/utils/mocks/proxies/InverterTransparentUpgradeableProxyV1AccessMock.sol";
import {InverterBeaconV1Mock} from
    "test/utils/mocks/proxies/InverterBeaconV1Mock.sol";
import {ModuleImplementationV1Mock} from
    "test/utils/mocks/proxies/ModuleImplementationV1Mock.sol";
import {ModuleImplementationV2Mock} from
    "test/utils/mocks/proxies/ModuleImplementationV2Mock.sol";

contract InverterTransparentUpgradeableProxyV1Test is Test {
    // SuT
    InverterTransparentUpgradeableProxy_v1 proxy;
    InverterTransparentUpgradeableProxyV1AccessMock proxyMock;

    // Mocks
    InverterBeaconV1Mock beacon;
    ModuleImplementationV1Mock implementation1;
    ModuleImplementationV2Mock implementation2;

    uint initialMajorVersion = 1;
    uint initialMinorVersion = 0;
    uint initialPatchVersion = 0;

    address admin = makeAddr("admin");

    // ERC1967Utils
    event AdminChanged(address previousAdmin, address newAdmin);

    function setUp() public {
        beacon = new InverterBeaconV1Mock();

        implementation1 = new ModuleImplementationV1Mock();
        implementation2 = new ModuleImplementationV2Mock();

        beacon.overrideImplementation(address(implementation1));
        beacon.overrideVersion(
            initialMajorVersion, initialMinorVersion, initialPatchVersion
        );

        proxy =
            new InverterTransparentUpgradeableProxy_v1(beacon, admin, bytes(""));

        proxyMock = new InverterTransparentUpgradeableProxyV1AccessMock(
            beacon, admin, bytes("")
        );
    }

    function testDeploymentInvariants() public {
        beacon = new InverterBeaconV1Mock();

        implementation1 = new ModuleImplementationV1Mock();
        beacon.overrideImplementation(address(implementation1));
        beacon.overrideVersion(
            initialMajorVersion, initialMinorVersion, initialPatchVersion
        );

        vm.expectEmit(true, true, true, true);
        emit AdminChanged(address(0), admin);

        proxyMock = new InverterTransparentUpgradeableProxyV1AccessMock(
            beacon, admin, bytes("")
        );

        assertEq(proxyMock.direct__admin(), admin);
        assertEq(proxyMock.direct__beacon(), address(beacon));
        assertEq(proxyMock.direct__implementation(), address(implementation1));
        (
            uint returnedMajorVersion,
            uint returnedMinorVersion,
            uint returnedPatchVersion
        ) = proxyMock.version();
        assertEq(returnedMajorVersion, initialMajorVersion);
        assertEq(returnedMinorVersion, initialMinorVersion);
        assertEq(returnedPatchVersion, initialPatchVersion);
    }

    function test_fallbackUsesProxyForEveryoneButAdmin(address user) public {
        vm.assume(user != admin);

        vm.prank(user);
        ModuleImplementationV1Mock(address(proxy)).getMockVersion();
    }

    function test_fallbackFailsIfAdminCallsWithWrongMsgSig(bytes4 sig) public {
        vm.assume(
            sig
                != IInverterTransparentUpgradeableProxy_v1
                    .upgradeToNewestVersion
                    .selector
        );

        vm.expectRevert(
            InverterTransparentUpgradeableProxy_v1
                .InverterTransparentUpgradeableProxy__ProxyDeniedAdminAccess
                .selector
        );

        vm.prank(admin);
        (bool success,) = address(proxy).call(abi.encode(sig));
        assertEq(success, true);
    }

    function test_fallbackWorksIfAdminCallsUpgradeToNewestVersion() public {
        proxyMock.flipUpgradeToNewestVersionActive();

        vm.prank(admin);
        (bool success,) = address(proxyMock).call(
            abi.encode(
                IInverterTransparentUpgradeableProxy_v1
                    .upgradeToNewestVersion
                    .selector
            )
        );
        assertEq(success, true);
        assertEq(proxyMock.upgradeToNewestVersionCalledCounter(), 1);
    }

    function testDirectUpgradeToNewestVersion() public {
        beacon.overrideImplementation(address(implementation2));
        beacon.overrideVersion(
            initialMajorVersion + 1,
            initialMinorVersion + 1,
            initialPatchVersion + 1
        );

        proxyMock.direct_upgradeToNewestVersion();
        assertEq(
            ModuleImplementationV2Mock(address(proxyMock)).getMockVersion(), 2
        );

        (
            uint returnedMajorVersion,
            uint returnedMinorVersion,
            uint returnedPatchVersion
        ) = proxyMock.version();
        assertEq(returnedMajorVersion, initialMajorVersion + 1);
        assertEq(returnedMinorVersion, initialMinorVersion + 1);
        assertEq(returnedPatchVersion, initialPatchVersion + 1);
    }
}
