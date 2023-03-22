pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {ModuleFactory} from "../../src/factories/ModuleFactory.sol";

 /**
  * @title ModuleFactory Deployment Script
  *
  * @dev Script to deploy a new ModuleFactory.
  *
  *
  * @author byterocket
  */

contract DeployModuleFactory is Script {

    ModuleFactory moduleFactory;

    function run() external {

        // Deploy the moduleFactory.
        vm.startBroadcast();
        {
            moduleFactory = new ModuleFactory();
        }
        vm.stopBroadcast();

        // Log the deployed ModuleFactory contract address.
        console2.log("Deployment of ModuleFactory at address",
            address(moduleFactory));
    }

}
