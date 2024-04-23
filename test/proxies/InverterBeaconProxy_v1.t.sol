// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// Internal Dependencies
import {
    InverterBeacon_v1,
    IInverterBeacon_v1
} from "src/proxies/InverterBeacon_v1.sol";
import {InverterBeaconProxy_v1} from "src/proxies/InverterBeaconProxy_v1.sol";

// Mocks
import {InverterBeaconV1Mock} from
    "test/utils/mocks/proxies/InverterBeaconV1Mock.sol";
import {ModuleImplementationV1Mock} from
    "test/utils/mocks/proxies/ModuleImplementationV1Mock.sol";

contract InverterBeaconProxyV1Test is Test {
    // SuT
    InverterBeaconProxy_v1 proxy;

    // Mocks
    InverterBeaconV1Mock beacon;
    ModuleImplementationV1Mock implementation;

    // Events copied from SuT
    event BeaconUpgraded(IInverterBeacon_v1 indexed beacon);

    function setUp() public {
        beacon = new InverterBeaconV1Mock();

        implementation = new ModuleImplementationV1Mock();
        beacon.overrideImplementation(address(implementation));

        proxy = new InverterBeaconProxy_v1(beacon);
    }

    function testDeploymentInvariants() public {
        vm.expectEmit(true, true, true, true);
        emit BeaconUpgraded(beacon);

        InverterBeaconProxy_v1 localProxy = new InverterBeaconProxy_v1(beacon);

        (uint majorVersion, uint minorVersion) = localProxy.version();
        assertEq(majorVersion, 0);
        assertEq(minorVersion, 0);
    }
}
