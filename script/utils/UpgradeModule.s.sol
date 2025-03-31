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

import {ModuleFactory_v1} from "src/factories/ModuleFactory_v1.sol";

import {Strings} from "@oz/utils/Strings.sol";

contract UpgradeModule is Script, ProtocolConstants_v1 {
    IDeterministicFactory_v1 public factory =
        IDeterministicFactory_v1(deterministicFactory);

    // This function automatically increments the minor version to the next number
    // and sets the patch version to zero.
    function run(string memory moduleName, uint majorVersion)
        external
        verifyRequiredParameters
    {
        loadDeployedContracts();

        (
            IInverterBeacon_v1 beacon,
            uint currentMinor,
            string memory currentVersion
        ) = _getCurrentVersion(moduleName, majorVersion);

        _upgradeModule(
            moduleName,
            majorVersion,
            currentMinor + 1,
            0,
            beacon,
            currentVersion
        );
    }

    // This function allows you to manually set the minor and patch version.
    function run(
        string memory moduleName,
        uint majorVersion,
        uint minorVersion,
        uint patchVersion
    ) external verifyRequiredParameters {
        loadDeployedContracts();

        (IInverterBeacon_v1 beacon,, string memory currentVersion) =
            _getCurrentVersion(moduleName, majorVersion);

        _upgradeModule(
            moduleName,
            majorVersion,
            minorVersion,
            patchVersion,
            beacon,
            currentVersion
        );
    }

    function _getCurrentVersion(string memory moduleName, uint majorVersion)
        internal
        returns (IInverterBeacon_v1, uint, string memory)
    {
        ModuleFactory_v1 moduleFactory = ModuleFactory_v1(deployedModuleFactory);
        (IInverterBeacon_v1 beacon,) = moduleFactory.getBeaconAndId(
            IModule_v1.Metadata(
                majorVersion,
                0,
                0,
                "https://github.com/InverterNetwork/contracts",
                moduleName
            )
        );

        (, uint currentMinor, uint currentPatch) = beacon.version();

        string memory version =
            _convertVersionString(majorVersion, currentMinor, currentPatch);

        return (beacon, currentMinor, version);
    }

    function _upgradeModule(
        string memory moduleName,
        uint majorVersion,
        uint minorVersion,
        uint patchVersion,
        IInverterBeacon_v1 beacon,
        string memory currentVersion
    ) internal {
        string memory version =
            _convertVersionString(majorVersion, minorVersion, patchVersion);

        console2.log("----------------------------------------");
        console2.log(
            "Upgrading Module - %s (%s to %s)",
            moduleName,
            currentVersion,
            version
        );
        console2.log("Steps:");
        console2.log("\t(1) Deploy Implementation");
        console2.log("\t(2) Set new Version in Beacon");
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
        console2.log("Step (2) Set new Version in Beacon...");
        // Register the metadata
        Governor_v1 governor = Governor_v1(deployedGovernor);
        vm.startBroadcast(deployerPrivateKey);
        governor.forceUpgradeBeaconAndRestartImplementation(
            address(beacon), implementation, minorVersion, patchVersion
        );
        vm.stopBroadcast();

        console2.log("\t%s updated to version %s", moduleName, version);
        console2.log("----------------------------------------");
        console2.log("Upgrade complete, Module is ready to be used!");
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
