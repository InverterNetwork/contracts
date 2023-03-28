// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {Proposal} from "../../src/proposal/Proposal.sol";
import {PaymentProcessor} from "../../src/modules/PaymentProcessor.sol";
import {MilestoneManager} from "../../src/modules/MilestoneManager.sol";

contract DeployMilestoneManagerContract is Script {
    Proposal proposal;
    PaymentProcessor paymentProcessor;
    MilestoneManager milestoneManager;
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("ANVIL_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        {
            proposal = new Proposal();
            paymentProcessor = new PaymentProcessor();
            milestoneManager = new MilestoneManager();
        }
        vm.stopBroadcast();

        console2.log("Proposal Contract Deployed at: ", address(proposal));
        console2.log("Payment Processor Contract Deployed at: ", address(paymentProcessor));
        console2.log("Milestone Manager Contract Deployed at: ", address(milestoneManager));
    }
}