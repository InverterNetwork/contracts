// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// Internal Dependencies
import {
    InverterBeacon,
    IInverterBeacon
} from "src/factories/beacon/InverterBeacon.sol";
import {InverterBeaconProxy} from "src/factories/beacon/InverterBeaconProxy.sol";

// Mocks
import {InverterBeaconMock} from
    "test/utils/mocks/factories/beacon/InverterBeaconMock.sol";
import {ModuleImplementationV1Mock} from
    "test/utils/mocks/factories/beacon/ModuleImplementationV1Mock.sol";

contract InverterBeaconProxyTest is Test {
    // SuT
    InverterBeaconProxy proxy;

    // Mocks
    InverterBeaconMock beacon;
    ModuleImplementationV1Mock implementation;

    // Events copied from SuT
    event BeaconUpgraded(IInverterBeacon indexed beacon);

    function setUp() public {
        beacon = new InverterBeaconMock();

        implementation = new ModuleImplementationV1Mock();
        beacon.overrideImplementation(address(implementation));

        proxy = new InverterBeaconProxy(beacon);
    }

    function testDeploymentInvariants() public {
        vm.expectEmit(true, true, true, true);
        emit BeaconUpgraded(beacon);

        InverterBeaconProxy localProxy = new InverterBeaconProxy(beacon);

        (uint majorVersion, uint minorVersion) = localProxy.version();
        assertEq(majorVersion, 0);
        assertEq(minorVersion, 0);
    }

    //--------------------------------------------------------------------------------
    // Test: _implementation

    function testImplementation(uint data) public {
        ModuleImplementationV1Mock(address(proxy)).initialize(data);

        assertEq(ModuleImplementationV1Mock(address(proxy)).data(), data);
        assertEq(ModuleImplementationV1Mock(address(proxy)).getVersion(), 1);
    }

    function testVersion(uint majorVersion, uint minorVersion) public {
        beacon.overrideVersion(majorVersion, minorVersion);
        (uint localMajorVersion, uint localMinorVersion) = proxy.version();
        assertEq(majorVersion, localMajorVersion);
        assertEq(minorVersion, localMinorVersion);
    }
}
