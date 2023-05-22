pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {PaymentProcessor} from "src/modules/PaymentProcessor.sol";

 /**
  * @title PaymentProcessor Deployment Script
  *
  * @dev Script to deploy a new PaymentProcessor.
  *
  *
  * @author byterocket
  */

contract DeployPaymentProcessor is Script {

    PaymentProcessor paymentProcessor;

    function run() external {

        // Deploy the milestoneManager.
        vm.startBroadcast();
        {
            paymentProcessor = new PaymentProcessor();
        }
        vm.stopBroadcast();

        // Log the deployed MilestoneManager contract address.
        console2.log("Deployment of PaymentProcessor at address",
            address(paymentProcessor));
    }

}
