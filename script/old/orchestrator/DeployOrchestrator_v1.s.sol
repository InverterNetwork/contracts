pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {Orchestrator_v1} from "src/orchestrator/Orchestrator_v1.sol";

/**
 * @title Orchestrator_v1 Deployment Script
 *
 * @dev Script to deploy a new Orchestrator_v1.
 *
 *
 * @author Inverter Network
 */
contract DeployOrchestrator_v1 is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("ORCHESTRATOR_ADMIN_PRIVATE_KEY");
    address forwarderAddress = vm.envAddress("FORWARDER_ADDRESS");
    address deployer = vm.addr(deployerPrivateKey);

    Orchestrator_v1 orchestrator;

    function run() external returns (address) {
        vm.startBroadcast(deployerPrivateKey);
        {
            // Deploy the orchestrator.

            orchestrator = new Orchestrator_v1(forwarderAddress);
        }

        vm.stopBroadcast();

        // Log the deployed Orchestrator_v1 contract address.
        console2.log(
            "Deployment of Orchestrator_v1 implementation at address",
            address(orchestrator)
        );

        return address(orchestrator);
    }
}
