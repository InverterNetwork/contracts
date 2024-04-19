pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {PP_Streaming_v1} from "src/modules/paymentProcessor/PP_Streaming_v1.sol";

/**
 * @title PaymentProcessor Deployment Script
 *
 * @dev Script to deploy a new PaymentProcessor.
 *
 * @author Inverter Network
 */
contract DeployPP_Streaming_v1 is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("ORCHESTRATOR_OWNER_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    PP_Streaming_v1 paymentProcessor;

    function run() external returns (address) {
        vm.startBroadcast(deployerPrivateKey);
        {
            // Deploy the PP_Streaming_v1.

            paymentProcessor = new PP_Streaming_v1();
        }
        vm.stopBroadcast();

        // Log the deployed PP_Streaming_v1 contract address.
        console2.log(
            "Deployment of PP_Streaming_v1 Implementation at address",
            address(paymentProcessor)
        );

        return address(paymentProcessor);
    }
}
