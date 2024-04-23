pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {OrchestratorFactory_v1} from "src/factories/OrchestratorFactory_v1.sol";

/**
 * @title OrchestratorFactory_v1 Deployment Script
 *
 * @dev Script to deploy a new OrchestratorFactory_v1.
 *
 *      The implementation and moduleFactory_v1 addresses can be supplied directly or read from the following environment variables:
 *      - DEPLOYMENT_ORCHESTRATOR_FACTORY_TARGET
 *      - DEPLOYMENT_ORCHESTRATOR_FACTORY_MODULE_FACTORY
 *
 * @author Inverter Network
 */
contract DeployOrchestratorFactory_v1 is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("ORCHESTRATOR_OWNER_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    OrchestratorFactory_v1 orchestratorFactory;

    function run() external returns (address) {
        // Read deployment settings from environment variables.
        address target = vm.envAddress("DEPLOYMENT_ORCHESTRATOR_FACTORY_TARGET");
        address moduleFactory =
            vm.envAddress("DEPLOYMENT_ORCHESTRATOR_FACTORY_MODULE_FACTORY");
        address forwarder = vm.envAddress("FORWARDER_ADDRESS");
        // Check settings.
        require(
            target != address(0),
            "DeployOrchestratorFactory_v1: Missing env variable: target"
        );
        require(
            moduleFactory != address(0),
            "DeployOrchestratorFactory_v1: Missing env variable: moduleFactory"
        );
        require(
            forwarder != address(0),
            "DeployOrchestratorFactory_v1: Missing env variable: forwarder"
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
                new OrchestratorFactory_v1(target, moduleFactory, forwarder);
        }

        vm.stopBroadcast();

        // Log the deployed OrchestratorFactory_v1 contract address.
        console2.log(
            "Deployment of OrchestratorFactory_v1 at address",
            address(orchestratorFactory)
        );

        return address(orchestratorFactory);
    }
}
