pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {InverterBeacon_v1} from "src/proxies/InverterBeacon_v1.sol";

/**
 * @title InverterBeacon_v1 Deployment Script
 *
 * @dev Script to deploy a new Inverter Beacon.
 *
 *
 * @author Inverter Network
 */
contract DeployInverterBeacon_v1 is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("ORCHESTRATOR_OWNER_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    InverterBeacon_v1 beacon;

    function run(
        address owner,
        uint majorVersion,
        address implementation,
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
        console2.log("Deployment of Beacon at address", address(beacon));

        return address(beacon);
    }
}
