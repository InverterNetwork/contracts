pragma solidity 0.8.19;

import "forge-std/Script.sol";

import {SimplePaymentProcessor} from
    "src/modules/paymentProcessor/SimplePaymentProcessor.sol";

/**
 * @title PaymentProcessor Deployment Script
 *
 * @dev Script to deploy a new PaymentProcessor.
 *
 * @author byterocket
 */

contract DeployPaymentProcessor is Script {
    SimplePaymentProcessor paymentProcessor;

    function run() external {
        // Deploy the milestoneManager.
        vm.startBroadcast();
        {
            paymentProcessor = new SimplePaymentProcessor();
        }
        vm.stopBroadcast();

        // Log the deployed MilestoneManager contract address.
        console2.log(
            "Deployment of PaymentProcessor at address",
            address(paymentProcessor)
        );
    }
}
