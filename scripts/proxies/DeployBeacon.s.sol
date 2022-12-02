pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {Beacon} from "../src/factories/beacon/Beacon.sol";

 /**
  * @title Beacon Deployment Script
  *
  * @dev Script to deploy a new Beacon.
  *
  *
  * @author byterocket
  */

contract DeployBeacon is Script {

    Beacon beacon;

    function run() external {

        // Deploy the beacon.
        vm.startBroadcast();
        {
            beacon = new Beacon();
        }
        vm.stopBroadcast();

        // Log the deployed Beacon contract address.
        console2.log("Deployment of Beacon at address",
            address(beacon));
    }

}
