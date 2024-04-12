pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {InverterBeacon} from "src/factories/beacon/InverterBeacon.sol";
import {IModule} from "src/modules/base/IModule.sol";

import {ModuleFactory} from "src/factories/ModuleFactory.sol";
import {DeployBeacon} from "script/proxies/DeployBeacon.s.sol";

/**
 * @title InverterBeacon Deployment Script
 *
 * @dev Script to deploy a new InverterBeacon.
 *
 *
 * @author Inverter Network
 */
contract DeployAndSetUpBeacon is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("ORCHESTRATOR_OWNER_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    InverterBeacon beacon;

    function run(
        address implementation,
        address moduleFactory,
        IModule.Metadata calldata metadata
    ) external returns (address) {
        vm.startBroadcast(deployerPrivateKey);
        {
            // Deploy the beacon.
            beacon = new InverterBeacon(metadata.majorVersion);

            // Upgrade the Beacon to the chosen implementation
            beacon.upgradeTo(
                address(implementation), metadata.minorVersion, false
            );

            // Register Metadata at the ModuleFactory
            ModuleFactory(moduleFactory).registerMetadata(metadata, beacon);
        }
        vm.stopBroadcast();

        // Log the deployed Beacon contract address.
        console2.log("Deployment of Beacon at address", address(beacon));
        console2.log("Implementation upgraded and Metadata registered");

        return address(beacon);
    }
}
