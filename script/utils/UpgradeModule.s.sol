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
    IModule_v2,
    IInverterBeacon_v1
} from "@ex/governance/Governor_v1.sol";

import {ModuleFactory_v1} from "src/factories/ModuleFactory_v1.sol";

import {Strings} from "@oz/utils/Strings.sol";

contract UpgradeModule is Script, ProtocolConstants_v1 {
    IDeterministicFactory_v1 public factory =
        IDeterministicFactory_v1(deterministicFactory);

    bytes32 _artifactNotFoundErrorHash = keccak256(
        hex"eeaa9e6f00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000026766d2e676574436f64653a206e6f206d61746368696e6720617274696661637420666f756e640000000000000000000000000000000000000000000000000000"
    );

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
        view
        returns (IInverterBeacon_v1, uint, string memory)
    {
        ModuleFactory_v1 moduleFactory = ModuleFactory_v1(deployedModuleFactory);
        (IInverterBeacon_v1 beacon,) = moduleFactory.getBeaconAndId(
            IModule_v2.Metadata(
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

        try vm.getCode(moduleName) {}
        catch (bytes memory reason) {
            if (keccak256(reason) == _artifactNotFoundErrorHash) {
                console2.log(
                    "\tImplementation for %s was not found, please ensure that you use the right contract name!",
                    moduleName
                );
            } else {
                console2.log(
                    "\tFailed to import implementation of %s, raw error:",
                    moduleName
                );
                console2.log(string(reason));
            }
            console2.log("----------------------------------------");
            revert("Failed to import implementation of module");
        }

        // Deploy the implementation
        vm.startBroadcast(deployerPrivateKey);
        address implementation;
        // use try catch block to catch the error if the deployment fails
        try factory.deployWithCreate2(
            factorySalt, abi.encodePacked(vm.getCode(moduleName), bytes(""))
        ) returns (address deployedAddress) {
            implementation = deployedAddress;
            console2.log("\t%s Implementation: %s", moduleName, deployedAddress);
        } catch (bytes memory reason) {
            bytes32 notAuthorizedError = keccak256(hex"c86af699");
            if (keccak256(reason) == notAuthorizedError) {
                console2.log(
                    "\tFailed to deploy implementation of %s, you are not authorized to use the factory!",
                    moduleName
                );
            } else {
                console2.log(
                    "\tFailed to deploy implementation of %s, raw error signature:",
                    moduleName
                );
                console2.log(vm.toString(reason));
            }
            console2.log("-------------------w---------------------");
            revert("Failed to deploy implementation of module");
        }
        vm.stopBroadcast();

        console2.log("----------------------------------------");
        console2.log("Step (2) Set new Version in Beacon...");

        // If the used network is mainnet, we skip this step, as this only works
        // on testnets or locally. On mainnets we need to use the multisig.
        if (currentNetworkIsMainnet()) {
            console2.log(
                "\tSkipping step, on mainnets the upgrade needs to be manually finalized in Multisig"
            );
            console2.log(
                "\tTo do so, set new implementation for beacon\n\t\t%s",
                address(beacon)
            );
            console2.log("\tto implementation\n\t\t%s", implementation);
            console2.log("\twith version\n\t\t%s", version);
            console2.log("\tin the governor at\n\t\t%s", deployedGovernor);
            console2.log("----------------------------------------");
            console2.log(
                "Deployment complete, Module will be ready to be used once finalized via the Multisig!"
            );
            // Todo: In the future, we should print the exact calldata needed for
            //       the multisig to upgrade the beacon, so it's easy to do.
        } else {
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
        }
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
