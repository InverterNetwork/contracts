pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {StreamingPaymentProcessor} from
    "src/modules/paymentProcessor/StreamingPaymentProcessor.sol";

/**
 * @title PaymentProcessor Deployment Script
 *
 * @dev Script to deploy a new PaymentProcessor.
 *
 * @author byterocket
 */

contract DeployStreamingPaymentProcessor is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("PROPOSAL_OWNER_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    StreamingPaymentProcessor paymentProcessor;

    function run() external returns (address) {
        vm.startBroadcast(deployerPrivateKey);
        {
            // Deploy the milestoneManager.

            paymentProcessor = new StreamingPaymentProcessor();
        }
        vm.stopBroadcast();

        // Log the deployed MilestoneManager contract address.
        console2.log(
            "Deployment of StreamingPaymentProcessor Implementation at address",
            address(paymentProcessor)
        );

        return address(paymentProcessor);
    }
}
