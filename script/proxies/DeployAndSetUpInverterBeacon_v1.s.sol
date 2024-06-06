pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {InverterBeacon_v1} from "src/proxies/InverterBeacon_v1.sol";
import {InverterBeaconProxy_v1} from "src/proxies/InverterBeaconProxy_v1.sol";
import {IModule_v1} from "src/modules/base/IModule_v1.sol";

import {ModuleFactory_v1} from "src/factories/ModuleFactory_v1.sol";

/**
 * @title DeployAndSetupInverterBeacon_v1 Deployment Script
 *
 * @dev Script to deploy and setup new InverterBeacon_v1.
 *
 *
 * @author Inverter Network
 */
contract DeployAndSetUpInverterBeacon_v1 is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("ORCHESTRATOR_OWNER_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    InverterBeacon_v1 beacon;

    function deployAndRegisterInFactory(
        address owner,
        address implementation,
        address moduleFactory,
        IModule_v1.Metadata calldata metadata
    ) external returns (address) {
        vm.startBroadcast(deployerPrivateKey);
        {
            // Deploy the beacon.
            beacon = new InverterBeacon_v1(
                owner,
                metadata.majorVersion,
                implementation,
                metadata.minorVersion
            );

            // Register Metadata at the ModuleFactory_v1
            ModuleFactory_v1(moduleFactory).registerMetadata(metadata, beacon);
        }
        vm.stopBroadcast();

        // Log the deployed Beacon contract address.
        console2.log(
            "Deployment of InverterBeacon_v1 at address", address(beacon)
        );
        console2.log("Implementation upgraded and Metadata registered");

        return address(beacon);
    }

    function deployBeaconAndSetupProxy(
        address owner,
        address implementation,
        uint majorVersion,
        uint minorVersion
    ) external returns (address beaconAddress, address proxy) {
        vm.startBroadcast(deployerPrivateKey);
        {
            // Deploy the beacon.
            beacon = new InverterBeacon_v1(
                owner, majorVersion, implementation, minorVersion
            );

            // return the proxy after creation
            proxy =
                address(new InverterBeaconProxy_v1(InverterBeacon_v1(beacon)));

            // cast to address for return
            beaconAddress = address(beacon);
        }
        vm.stopBroadcast();

        // Log the deployed Beacon contract address.
        console2.log(
            "Deployment of InverterBeacon_v1 at address: ", beaconAddress
        );
        console2.log(
            "Creation of InverterBeaconProxy_v1 at address: ", address(proxy)
        );
    }

    function deployInverterBeacon(
        address owner,
        address implementation,
        uint majorVersion,
        uint minorVersion
    ) public returns (address) {
        vm.startBroadcast(deployerPrivateKey);
        {
            // Deploy the beacon.

            beacon = new InverterBeacon_v1(
                owner, majorVersion, implementation, minorVersion
            );
        }

        vm.stopBroadcast();

        // Log the deployed Beacon contract address.
        console2.log(
            "Deployment of InverterBeacon_v1 at address", address(beacon)
        );

        return address(beacon);
    }
}
