// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {ProtocolConstants_v1} from
    "script/deploymentSuite/ProtocolConstants_v1.s.sol";

import {ProxyAndBeaconDeployer_v1} from
    "script/deploymentSuite/ProxyAndBeaconDeployer_v1.s.sol";

import {IDeterministicFactory_v1} from
    "@df/interfaces/IDeterministicFactory_v1.sol";

import {
    Governor_v1,
    IModule_v1,
    IInverterBeacon_v1
} from "@ex/governance/Governor_v1.sol";

import {Strings} from "@oz/utils/Strings.sol";

contract DeployNewModule is Script, ProtocolConstants_v1 {
    IDeterministicFactory_v1 public factory =
        IDeterministicFactory_v1(deterministicFactory);

    ProxyAndBeaconDeployer_v1 public proxyAndBeaconDeployer =
        new ProxyAndBeaconDeployer_v1();

    function run(
        string memory moduleName,
        uint majorVersion,
        uint minorVersion,
        uint patchVersion
    ) external verifyRequiredParameters {
        loadDeployedContracts();

        string memory version =
            _convertVersionString(majorVersion, minorVersion, patchVersion);

        console2.log("----------------------------------------");
        console2.log("Deploying new Module - %s (%s)", moduleName, version);
        console2.log("Steps:");
        console2.log("\t(1) Deploy Implementation");
        console2.log("\t(2) Deploy Beacon");
        console2.log("\t(3) Register Metadata");
        console2.log("----------------------------------------");

        console2.log("Step (1) Deploy Implementation...");
        // Deploy the implementation
        vm.startBroadcast(deployerPrivateKey);
        address implementation = factory.deployWithCreate2(
            factorySalt, abi.encodePacked(vm.getCode(moduleName), bytes(""))
        );
        vm.stopBroadcast();

        console2.log("\t%s Implementation: %s", moduleName, implementation);
        console2.log("----------------------------------------");

        console2.log("Step (2) Deploy Beacon...");
        // Deploy the beacon
        address beacon = proxyAndBeaconDeployer.deployInverterBeacon(
            moduleName,
            deployedReverter,
            deployedGovernor,
            implementation,
            majorVersion,
            minorVersion,
            patchVersion
        );
        console2.log("----------------------------------------");

        console2.log("Step (3) Register Metadata in Factory...");
        // Register the metadata
        Governor_v1 governor = Governor_v1(deployedGovernor);
        vm.startBroadcast(deployerPrivateKey);
        governor.registerMetadataInModuleFactory(
            IModule_v1.Metadata(
                majorVersion,
                minorVersion,
                patchVersion,
                moduleName,
                "https://github.com/InverterNetwork/contracts"
            ),
            IInverterBeacon_v1(beacon)
        );
        vm.stopBroadcast();

        console2.log("\t%s registered as version %s", moduleName, version);
        console2.log("----------------------------------------");
        console2.log("Deployment complete, Module is ready to be used!");
        console2.log("----------------------------------------");
    }

    function _convertVersionString(uint major, uint minor, uint patch)
        internal
        pure
        returns (string memory)
    {
        bytes memory rawVersion = abi.encodePacked(
            "v",
            Strings.toString(major),
            ".",
            Strings.toString(minor),
            ".",
            Strings.toString(patch)
        );
        return string(rawVersion);
    }

    modifier verifyRequiredParameters() {
        require(
            deterministicFactory != address(0),
            "Deterministic Factory address not set - aborting!"
        );
        _;
    }
}
