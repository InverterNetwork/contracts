// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// Internal Dependencies
import {InverterProxyAdmin_v1} from "src/proxies/InverterProxyAdmin_v1.sol";
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

import {OZErrors} from "test/utils/errors/OZErrors.sol";

contract InverterProxyAdmin is Test {
    // SuT
    InverterProxyAdmin_v1 proxyAdmin;
    InverterTransparentUpgradeableProxy_v1 proxy;
    InverterTransparentUpgradeableProxyV1AccessMock proxyMock;

    // Mocks
    InverterBeaconV1Mock beacon;
    ModuleImplementationV1Mock implementation1;
    ModuleImplementationV2Mock implementation2;

    uint initialMajorVersion = 1;
    uint initialMinorVersion = 0;

    address admin = makeAddr("admin");

    // ERC1967Utils
    event AdminChanged(address previousAdmin, address newAdmin);

    function setUp() public {
        beacon = new InverterBeaconV1Mock();

        implementation1 = new ModuleImplementationV1Mock();
        implementation2 = new ModuleImplementationV2Mock();

        beacon.overrideImplementation(address(implementation1));
        beacon.overrideVersion(initialMajorVersion, initialMinorVersion);

        proxyAdmin = new InverterProxyAdmin_v1(admin);
        proxy = new InverterTransparentUpgradeableProxy_v1(
            beacon, address(proxyAdmin), bytes("")
        );

        proxyMock = new InverterTransparentUpgradeableProxyV1AccessMock(
            beacon, address(proxyAdmin), bytes("")
        );
    }

    function testDeploymentInvariants() public {
        beacon = new InverterBeaconV1Mock();

        implementation1 = new ModuleImplementationV1Mock();
        beacon.overrideImplementation(address(implementation1));
        beacon.overrideVersion(initialMajorVersion, initialMinorVersion);

        vm.expectEmit(true, true, true, true);
        emit AdminChanged(address(0), address(proxyAdmin));

        proxyMock = new InverterTransparentUpgradeableProxyV1AccessMock(
            beacon, address(proxyAdmin), bytes("")
        );

        assertEq(proxyMock.direct__admin(), address(proxyAdmin));
        assertEq(proxyMock.direct__beacon(), address(beacon));
        assertEq(proxyMock.direct__implementation(), address(implementation1));
        (uint returnedMajorVersion, uint returnedMinorVersion) =
            proxyMock.version();
        assertEq(returnedMajorVersion, initialMajorVersion);
        assertEq(returnedMinorVersion, initialMinorVersion);
    }

    function testUpgradeToNewestVersionFailsIfNotAdmin(address user) public {
        vm.assume(user != admin);

        beacon.overrideImplementation(address(implementation2));
        beacon.overrideVersion(initialMajorVersion + 1, initialMinorVersion + 1);

        vm.expectRevert(
            abi.encodeWithSelector(OZErrors.Ownable__UnauthorizedAccount, user)
        );

        vm.prank(user);
        proxyAdmin.upgradeToNewestVersion(
            IInverterTransparentUpgradeableProxy_v1(address(proxyMock))
        );

        (uint returnedMajorVersion, uint returnedMinorVersion) =
            proxyMock.version();
        assertEq(returnedMajorVersion, initialMajorVersion);
        assertEq(returnedMinorVersion, initialMinorVersion);
    }

    function testUpgradeToNewestVersion() public {
        beacon.overrideImplementation(address(implementation2));
        beacon.overrideVersion(initialMajorVersion + 1, initialMinorVersion + 1);

        vm.prank(admin);
        proxyAdmin.upgradeToNewestVersion(
            IInverterTransparentUpgradeableProxy_v1(address(proxyMock))
        );

        (uint returnedMajorVersion, uint returnedMinorVersion) =
            proxyMock.version();
        assertEq(returnedMajorVersion, initialMajorVersion + 1);
        assertEq(returnedMinorVersion, initialMinorVersion + 1);
    }
}
