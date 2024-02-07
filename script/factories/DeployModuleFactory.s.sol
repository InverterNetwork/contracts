pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {ModuleFactory} from "src/factories/ModuleFactory.sol";

/**
 * @title ModuleFactory Deployment Script
 *
 * @dev Script to deploy a new ModuleFactory.
 *
 *
 * @author Inverter Network
 */
contract DeployModuleFactory is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("ORCHESTRATOR_OWNER_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    ModuleFactory moduleFactory;

    function run() external returns (address) {
        vm.startBroadcast(deployerPrivateKey);
        {
            // Deploy the moduleFactory.
            moduleFactory = new ModuleFactory();
        }

        vm.stopBroadcast();

        // Log the deployed ModuleFactory contract address.
        console2.log(
            "Deployment of ModuleFactory at address", address(moduleFactory)
        );

        return address(moduleFactory);
    }
}
