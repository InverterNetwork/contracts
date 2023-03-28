// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {PaymentProcessor} from "../../src/modules/PaymentProcessor.sol";

contract DeployPaymentProcessorContract is Script {
    PaymentProcessor paymentProcessor;
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("ANVIL_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        {
            paymentProcessor = new PaymentProcessor();
        }
        vm.stopBroadcast();

        console2.log("Payment Processor Contract Deployed at: ", address(paymentProcessor));
    }
}