pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {OrchestratorFactory} from "src/factories/OrchestratorFactory.sol";

/**
 * @title OrchestratorFactory Deployment Script
 *
 * @dev Script to deploy a new OrchestratorFactory.
 *
 *      The implementation and moduleFactory addresses can be supplied directly or read from the following environment variables:
 *      - DEPLOYMENT_ORCHESTRATOR_FACTORY_TARGET
 *      - DEPLOYMENT_ORCHESTRATOR_FACTORY_MODULE_FACTORY
 *
 * @author Inverter Network
 */

contract DeployOrchestratorFactory is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("ORCHESTRATOR_OWNER_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    OrchestratorFactory orchestratorFactory;

    function run() external returns (address) {
        // Read deployment settings from environment variables.
        address target = vm.envAddress("DEPLOYMENT_ORCHESTRATOR_FACTORY_TARGET");
        address moduleFactory =
            vm.envAddress("DEPLOYMENT_ORCHESTRATOR_FACTORY_MODULE_FACTORY");
        address forwarder = vm.envAddress("FORWARDER_ADDRESS");
        // Check settings.
        require(
            target != address(0),
            "DeployOrchestratorFactory: Missing env variable: target"
        );
        require(
            moduleFactory != address(0),
            "DeployOrchestratorFactory: Missing env variable: moduleFactory"
        );

        // Deploy the orchestratorFactory.
        return run(target, moduleFactory, forwarder);
    }

    function run(address target, address moduleFactory, address forwarder)
        public
        returns (address)
    {
        vm.startBroadcast(deployerPrivateKey);
        {
            // Deploy the orchestratorFactory.
            orchestratorFactory =
                new OrchestratorFactory(target, moduleFactory, forwarder);
        }

        vm.stopBroadcast();

        // Log the deployed OrchestratorFactory contract address.
        console2.log(
            "Deployment of OrchestratorFactory at address",
            address(orchestratorFactory)
        );

        return address(orchestratorFactory);
    }
}
