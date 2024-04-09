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
        // Read deployment settings from environment variables.

        address governor = vm.envAddress("COVERNANCE_CONTRACT_ADDRESS");
        address forwarder = vm.envAddress("FORWARDER_ADDRESS");
        // Check settings.

        require(
            governor != address(0),
            "DeployOrchestratorFactory: Missing env variable: governor contract"
        );

        require(
            forwarder != address(0),
            "DeployOrchestratorFactory: Missing env variable: forwarder"
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
            moduleFactory = new ModuleFactory(governor, forwarder);
        }

        vm.stopBroadcast();

        // Log the deployed ModuleFactory contract address.
        console2.log(
            "Deployment of ModuleFactory at address", address(moduleFactory)
        );

        return address(moduleFactory);
    }
}
