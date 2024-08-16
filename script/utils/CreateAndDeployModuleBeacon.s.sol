// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {ProtocolConstants_v1} from
    "script/deploymentSuite/ProtocolConstants_v1.s.sol";

import {ProxyAndBeaconDeployer_v1} from
    "script/deploymentSuite/ProxyAndBeaconDeployer_v1.s.sol";

import {IDeterministicFactory_v1} from
    "@df/interfaces/IDeterministicFactory_v1.sol";

contract CreateAndDeployModuleBeacon is Script, ProtocolConstants_v1 {
    IDeterministicFactory_v1 public factory =
        IDeterministicFactory_v1(deterministicFactory);

    ProxyAndBeaconDeployer_v1 public proxyAndBeaconDeployer =
        new ProxyAndBeaconDeployer_v1();

    // How to use:
    // forge script
    // script/utils/CreateAndDeployModuleBeacon.s.sol
    // "run(string,string,address,address,uint,uint,uint)"
    // "ExampleModule" "src/module/ExampleModule.sol" ??? "0x0000000000000000000000000000000000000001" "0x0000000000000000000000000000000000000002" 1 0 0

    // @TODO Above explanation is lacking the bytes-encoded optionalParams

    function run(
        string memory moduleName,
        string memory modulePath,
        bytes memory optionalParams,
        address reverter,
        address owner,
        uint majorVersion,
        uint minorVersion,
        uint patchVersion
    ) external verifyRequiredParameters {
        vm.startBroadcast(deployerPrivateKey);
        {
            // Deploy the implementation
            address implementation = factory.deployWithCreate2(
                factorySalt,
                abi.encodePacked(vm.getCode(modulePath), optionalParams)
            );
            console2.log(
                "Deployed %s implementation at address %s",
                moduleName,
                implementation
            );

            // Deploy the beacon
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
        }
        vm.stopBroadcast();
    }

    modifier verifyRequiredParameters() {
        require(
            deterministicFactory != address(0),
            "Deterministic Factory address not set - aborting!"
        );
        _;
    }
}
