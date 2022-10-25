// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// External Interfaces
import {IBeacon} from
    "@oz/proxy/beacon/IBeacon.sol";

// Internal Dependencies
import {Beacon} from "src/factories/beacon/Beacon.sol";
import {BeaconProxy} from "src/factories/beacon/BeaconProxy.sol";

// Mocks
import {BeaconMock} from "test/utils/mocks/factories/beacon/BeaconMock.sol";
import {ImplementationV1Mock} from
    "test/utils/mocks/factories/beacon/ImplementationV1Mock.sol";

contract BeaconProxyTest is Test {
    // SuT
    BeaconProxy proxy;

    // Mocks
    BeaconMock beacon;
    ImplementationV1Mock implementation;

    // Events copied from SuT
    event BeaconUpgraded(IBeacon indexed beacon);

    function setUp() public {
        beacon = new BeaconMock();

        implementation = new ImplementationV1Mock();
        beacon.overrideImplementation(address(implementation));

        proxy = new BeaconProxy(beacon);
    }

    function testDeploymentInvariants() public {
        vm.expectEmit(true, true, true, true);
        emit BeaconUpgraded(beacon);

        new BeaconProxy(beacon);
    }

    //--------------------------------------------------------------------------------
    // Test: _implementation

    function testImplementation(uint data) public {
        ImplementationV1Mock(address(proxy)).initialize(data);

        assertEq(ImplementationV1Mock(address(proxy)).data(), data);
        assertEq(ImplementationV1Mock(address(proxy)).getVersion(), 1);
    }
}
