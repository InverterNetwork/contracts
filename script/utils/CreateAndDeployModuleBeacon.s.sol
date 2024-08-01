// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {Test} from "forge-std/Test.sol";

import {ProtocolConstants} from
    "scrript/deploymentSuite/ProtocolConstants_v1.s.sol";

import {ProxyAndBeaconDeployer_v1} from
    "script/deploymentSuite/ProxyAndBeaconDeployer_v1.s.sol";

import {IDeterministicFactory} from "src/interfaces/IDeterministicFactory.sol";

contract CreateAndDeployModuleBeacon is Script, ProtocolConstants_v1 {
    IDeterministicFactory public factory =
        IDeterministicFactory_v1(deterministicFactory);

    bytes32 factorySalt = keccak256(abi.encodePacked("inverter-deployment"));

    ProxyAndBeaconDeployer_v1 public proxyAndBeaconDeployer =
        new ProxyAndBeaconDeployer_v1();

    function run(
        string memory moduleName,
        string memory modulePath,
        address reverter,
        address owner,
        address implementation,
        uint majorVersion,
        uint minorVersion,
        uint patchVersion
    ) external {
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the implementation.
        address implementation = factory.deployWithCreate2(
            factorySalt, abi.encodePacked(vm.getCode(modulePath))
        );
        console2_log(
            "Deployed %s implementation at address %s",
            moduleName,
            implementation
        );

        // Deploy the beacon.
        address beacon = proxyAndBeaconDeployer.deployInverterBeacon(
            moduleName,
            reverter,
            owner,
            implementation,
            majorVersion,
            minorVersion,
            patchVersion
        );
        console2_log("Deployed %s beacon at address %s", moduleName, beacon);
    }
}
