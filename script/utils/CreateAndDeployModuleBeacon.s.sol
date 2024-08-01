// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";

import "forge-std/Test.sol";

import {ProtocolConstants_v1} from
    "script/deploymentSuite/ProtocolConstants_v1.s.sol";

import {ProxyAndBeaconDeployer_v1} from
    "script/deploymentSuite/ProxyAndBeaconDeployer_v1.s.sol";

import {IDeterministicFactory_v1} from
    "script/deterministicFactory/interfaces/IDeterministicFactory.sol";

contract CreateAndDeployModuleBeacon is Script, ProtocolConstants_v1 {
    IDeterministicFactory_v1 public factory =
        IDeterministicFactory_v1(deterministicFactory);

    ProxyAndBeaconDeployer_v1 public proxyAndBeaconDeployer =
        new ProxyAndBeaconDeployer_v1();

    // @todo Run with forge script
    // script/utils/CreateAndDeployModuleBeacon.s.sol
    // "run(string,string,address,address,uint,uint,uint)"
    // "ExampleModule" "src/module/ExampleModule.sol" "0x0000000000000000000000000000000000000001" "0x0000000000000000000000000000000000000002" 1 0 0

    function run(
        string memory moduleName,
        string memory modulePath,
        address reverter,
        address owner,
        uint majorVersion,
        uint minorVersion,
        uint patchVersion
    ) external {
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the implementation.
        address implementation = factory.deployWithCreate2(
            factorySalt, abi.encodePacked(vm.getCode(modulePath))
        );
        console2.log(
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
        console2.log("Deployed %s beacon at address %s", moduleName, beacon);

        vm.stopBroadcast();
    }
}
