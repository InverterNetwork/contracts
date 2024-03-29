pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {InverterBeacon} from "src/factories/beacon/InverterBeacon.sol";

/**
 * @title Beacon Deployment Script
 *
 * @dev Script to deploy a new Beacon.
 *
 *
 * @author Inverter Network
 */
contract DeployBeacon is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    InverterBeacon beacon;

    function run() external returns (address) {
        //Start on a regular basis with major version 1
        return run(1);
    }

    function run(uint _majorVersion) public returns (address) {
        vm.startBroadcast(deployerPrivateKey);
        {
            // Deploy the beacon.
            beacon = new InverterBeacon(_majorVersion);
        }

        vm.stopBroadcast();

        // Log the deployed Beacon contract address.
        console2.log("Deployment of Beacon at address", address(beacon));

        return address(beacon);
    }
}
