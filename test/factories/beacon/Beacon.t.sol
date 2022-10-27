// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// External Libraries
import "@oz/utils/Address.sol";

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
    // SuT
    Beacon beacon;

    // Events copied from SuT
    event Upgraded(address indexed implementation);

    function setUp() public {
        beacon = new Beacon();
    }

    function testDeploymentInvariants() public {
        assertEq(beacon.implementation(), address(0));
    }

    //--------------------------------------------------------------------------------
    // Test: upgradeTo

    function testUpgradeTo() public {
        ImplementationV1Mock toUpgrade1 = new ImplementationV1Mock();
        ImplementationV2Mock toUpgrade2 = new ImplementationV2Mock();

        vm.expectEmit(true, true, true, true);
        emit Upgraded(address(toUpgrade1));

        beacon.upgradeTo(address(toUpgrade1));

        assertEq(beacon.implementation(), address(toUpgrade1));

        vm.expectEmit(true, true, true, true);
        emit Upgraded(address(toUpgrade2));

        beacon.upgradeTo(address(toUpgrade2));

        assertEq(beacon.implementation(), address(toUpgrade2));
    }

    function testUpgradeToOnlyCallableByOwner(address caller) public {
        vm.assume(caller != address(this));
        vm.prank(caller);

        vm.expectRevert(OZErrors.Ownable2Step__CallerNotOwner);
        beacon.upgradeTo(address(0));
    }

    function testUpgradeToFailsIfImplementationNotContract() public {
        // Note that address(0xCAFE) is EOA.
        vm.expectRevert(Beacon.Beacon__InvalidImplementation.selector);
        beacon.upgradeTo(address(0xCAFE));
    }

    //--------------------------------------------------------------------------------
    // Test: ERC-165

    function testERC165Supported() public {
        // @todo felix, mp: Add test to check for following interfaces:
        //          - ERC 165
        //          - IBeacon
    }
}
