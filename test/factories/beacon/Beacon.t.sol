// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// External Libraries
import "lib/openzeppelin-contracts/contracts/utils/Address.sol";

// Internal Dependencies
import {Beacon} from "src/factories/beacon/Beacon.sol";

// Mocks
import {ImplementationV1Mock} from
    "test/utils/mocks/factories/beacon/ImplementationV1Mock.sol";
import {ImplementationV2Mock} from
    "test/utils/mocks/factories/beacon/ImplementationV2Mock.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

contract BeaconTest is Test {
    Beacon beacon;

    event Upgraded(address indexed implementation);

    //--------------------------------------------------------------------------------
    // SETUP

    function setUp() public {
        beacon = new Beacon();
    }

    //--------------------------------------------------------------------------------
    // TEST MAIN

    function testDeployment() public {
        assertTrue(beacon.implementation() == address(0));
    }

    function testUpgradeToOnlyCallableByOwner(address caller) public {
        vm.assume(caller != address(this));
        vm.prank(caller);

        vm.expectRevert(OZErrors.Ownable2Step__CallerNotOwner);
        beacon.upgradeTo(address(0));
    }

    function testImplemenationIsNotAContract(address implementation) public {
        if (!Address.isContract(implementation)) {
            vm.expectRevert(
                Beacon.Beacon__ImplementationIsNotAContract.selector
            );
        }
        beacon.upgradeTo(implementation);
    }

    function testUpgradeTo() public {
        ImplementationV1Mock toUpgrade1 = new ImplementationV1Mock();
        ImplementationV2Mock toUpgrade2 = new ImplementationV2Mock();

        vm.expectEmit(true, true, true, true);
        emit Upgraded(address(toUpgrade1));

        beacon.upgradeTo(address(toUpgrade1));

        assertTrue(beacon.implementation() == address(toUpgrade1));

        vm.expectEmit(true, true, true, true);
        emit Upgraded(address(toUpgrade2));

        beacon.upgradeTo(address(toUpgrade2));

        assertTrue(beacon.implementation() == address(toUpgrade2));
    }
}
