pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {Orchestrator} from "src/orchestrator/Orchestrator.sol";

/**
 * @title Orchestrator Deployment Script
 *
 * @dev Script to deploy a new Orchestrator.
 *
 *
 * @author Inverter Network
 */
contract DeployOrchestrator is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    Orchestrator orchestrator;

    function run(address _forwarder) public returns (address) {
        address forwarderAddress = _forwarder != address(0)
            ? _forwarder
            : vm.envAddress("FORWARDER_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);
        {
            // Deploy the orchestrator.

            orchestrator = new Orchestrator(forwarderAddress);
        }

        vm.stopBroadcast();

        // Log the deployed Orchestrator contract address.
        console2.log(
            "Deployment of Orchestrator Implementation at address",
            address(orchestrator)
        );

        return address(orchestrator);
    }

    function run() external returns (address) {
        return run(address(0));
    }
}
