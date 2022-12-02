pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {PaymentManager} from "../src/modules/PaymentManager.sol";

 /**
  * @title PaymentManager Deployment Script
  *
  * @dev Script to deploy a new PaymentManager.
  *
  *
  * @author byterocket
  */

contract DeployPaymentManager is Script {

    PaymentManager paymentManager;

    function run() external {

        // Deploy the paymentManager.
        vm.startBroadcast();
        {
            paymentManager = new PaymentManager();
        }
        vm.stopBroadcast();

        // Log the deployed PaymentManager contract address.
        console2.log("Deployment of PaymentManager at address",
            address(paymentManager));
    }

}
