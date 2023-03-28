// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {Proposal} from "../../src/proposal/Proposal.sol";
import {PaymentProcessor} from "../../src/modules/PaymentProcessor.sol";
import {MilestoneManager} from "../../src/modules/MilestoneManager.sol";

import {Beacon, IBeacon} from "../../src/factories/beacon/Beacon.sol";

contract DeployMilestoneManagerContract is Script {
    address paymentProcessorBeaconOwner = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    address milestoneManagerBeaconOwner = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
    address authorizerBeaconOwner = 0x90F79bf6EB2c4f870365E785982E1f101E93b906;
    
    Proposal proposal;
    PaymentProcessor paymentProcessor;
    MilestoneManager milestoneManager;

    Beacon paymentProcessorBeacon;
    Beacon milestoneManagerBeacon;
    Beacon authorizerBeacon;
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("ANVIL_PRIVATE_KEY");
        uint256 paymentProcessorBeaconOwnerPrivateKey = vm.envUint("PPBO_PRIVATE_KEY");
        uint256 milestoneManagerBeaconOwnerPrivateKey = vm.envUint("MMBO_PRIVATE_KEY");
        uint256 authorizerBeaconOwnerPrivateKey = vm.envUint("ABO_PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        {
            proposal = new Proposal();
            paymentProcessor = new PaymentProcessor();
            milestoneManager = new MilestoneManager();
        }
        vm.stopBroadcast();

        vm.startBroadcast(paymentProcessorBeaconOwnerPrivateKey);
        {
            paymentProcessorBeacon = new Beacon();
        }
        vm.stopBroadcast();

        vm.startBroadcast(milestoneManagerBeaconOwnerPrivateKey);
        {
            milestoneManagerBeacon = new Beacon();
        }
        vm.stopBroadcast();

        vm.startBroadcast(authorizerBeaconOwnerPrivateKey);
        {
            authorizerBeacon = new Beacon();
        }
        vm.stopBroadcast();


        console2.log("Proposal Contract Deployed at: ", address(proposal));
        console2.log("Payment Processor Contract Deployed at: ", address(paymentProcessor));
        console2.log("Milestone Manager Contract Deployed at: ", address(milestoneManager));
        console2.log("Payment Processor Beacon Deployed at: ", address(paymentProcessorBeacon));
        console2.log("Payment Processor Beacon Deployed at: ", address(milestoneManagerBeacon));
        console2.log("Payment Processor Beacon Deployed at: ", address(authorizerBeacon));
    }
}