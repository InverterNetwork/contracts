pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {Beacon} from "src/factories/beacon/Beacon.sol";

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
    uint deployerPrivateKey = vm.envUint("PROPOSAL_OWNER_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    Beacon beacon;

    function run() external returns (address) {
        vm.startBroadcast(deployerPrivateKey);
        {
            // Deploy the beacon.

            beacon = new Beacon();
        }

        vm.stopBroadcast();

        // Log the deployed Beacon contract address.
        console2.log("Deployment of Beacon at address", address(beacon));

        return address(beacon);
    }
}
