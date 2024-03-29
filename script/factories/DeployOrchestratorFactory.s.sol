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
    uint deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    OrchestratorFactory orchestratorFactory;

    function run(address _target, address _moduleFactory, address _forwarder)
        public
        returns (address)
    {
        address target = _target != address(0)
            ? _target
            : vm.envAddress("DEPLOYMENT_ORCHESTRATOR_FACTORY_TARGET");

        address moduleFactory = _moduleFactory != address(0)
            ? _moduleFactory
            : vm.envAddress("DEPLOYMENT_ORCHESTRATOR_FACTORY_MODULE_FACTORY");

        address forwarder = _forwarder != address(0)
            ? _forwarder
            : vm.envAddress("FORWARDER_ADDRESS");

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

    function run() external returns (address) {
        return run(address(0), address(0), address(0));
    }
}
