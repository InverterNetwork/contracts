// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {IBeacon} from "lib/openzeppelin-contracts/contracts/proxy/beacon/IBeacon.sol";
import {Beacon} from "src/factories/beacon-fundamentals/Beacon.sol";
import {BeaconProxy} from "src/factories/beacon-fundamentals/BeaconProxy.sol";
import {ImplementationV1Mock} from "test/utils/mocks/factories/beacon-fundamentals/ImplementationV1Mock.sol";

contract BeaconProxyTest is Test {
    Beacon beacon;
    BeaconProxy proxy;
    ImplementationV1Mock implementation;

    event BeaconUpgraded(IBeacon indexed beacon);

    //--------------------------------------------------------------------------------
    // SETUP

    function setUp() public {
        beacon = new Beacon();

        implementation = new ImplementationV1Mock();
        beacon.upgradeTo(address(implementation));

        proxy = new BeaconProxy(beacon);
    }

    //--------------------------------------------------------------------------------
    // TEST MAIN

    function testDeployment() public {
        vm.expectEmit(true, true, true, true);
        emit BeaconUpgraded(beacon);

        new BeaconProxy(beacon);
    }

    function testImplementation(uint256 data) public {
        ImplementationV1Mock(address(proxy)).initialize(data);

        assertTrue(ImplementationV1Mock(address(proxy)).data() == data);
        assertTrue(ImplementationV1Mock(address(proxy)).getVersion() == 1);
    }
}
