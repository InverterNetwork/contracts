pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {SimplePaymentProcessor} from
    "src/modules/paymentProcessor/SimplePaymentProcessor.sol";

/**
 * @title PaymentProcessor Deployment Script
 *
 * @dev Script to deploy a new PaymentProcessor.
 *
 * @author Inverter Network
 */

contract DeployPaymentProcessor is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("ORCHESTRATOR_OWNER_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    SimplePaymentProcessor paymentProcessor;

    function run() external returns (address) {
        vm.startBroadcast(deployerPrivateKey);
        {
            // Deploy the SimplePaymentProcessor.

            paymentProcessor = new SimplePaymentProcessor();
        }

        vm.stopBroadcast();

        // Log the deployed SimplePaymentProcessor contract address.
        console2.log(
            "Deployment of SimplePaymentProcessor Implementation at address",
            address(paymentProcessor)
        );

        return address(paymentProcessor);
    }
}
