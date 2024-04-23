pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {ModuleFactory_v1} from "src/factories/ModuleFactory_v1.sol";

/**
 * @title ModuleFactory_v1 Deployment Script
 *
 * @dev Script to deploy a new ModuleFactory_v1.
 *
 *
 * @author Inverter Network
 */
contract DeployModuleFactory_v1 is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("ORCHESTRATOR_OWNER_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    ModuleFactory_v1 moduleFactory;

    function run() external returns (address) {
        // Read deployment settings from environment variables.

        address governor = vm.envAddress("GOVERNOR_ADDRESS");
        address forwarder = vm.envAddress("FORWARDER_ADDRESS");
        // Check settings.

        require(
            governor != address(0),
            "DeployOrchestratorFactory_v1: Missing env variable: governor contract"
        );

        require(
            forwarder != address(0),
            "DeployOrchestratorFactory_v1: Missing env variable: forwarder"
        );

        // Deploy the moduleFactory.
        return run(governor, forwarder);
    }

    function run(address governor, address forwarder)
        public
        returns (address)
    {
        vm.startBroadcast(deployerPrivateKey);
        {
            // Deploy the moduleFactory.
            moduleFactory = new ModuleFactory_v1(governor, forwarder);
        }

        vm.stopBroadcast();

        // Log the deployed ModuleFactory_v1 contract address.
        console2.log(
            "Deployment of ModuleFactory_v1 at address", address(moduleFactory)
        );

        return address(moduleFactory);
    }
}
