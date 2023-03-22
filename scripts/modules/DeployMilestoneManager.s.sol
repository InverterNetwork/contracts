pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {MilestoneManager} from "../../src/modules/MilestoneManager.sol";

 /**
  * @title MilestoneManager Deployment Script
  *
  * @dev Script to deploy a new MilestoneManager.
  *
  *
  * @author byterocket
  */

contract DeployMilestoneManager is Script {

    MilestoneManager milestoneManager;

    function run() external {

        // Deploy the milestoneManager.
        vm.startBroadcast();
        {
            milestoneManager = new MilestoneManager();
        }
        vm.stopBroadcast();

        // Log the deployed MilestoneManager contract address.
        console2.log("Deployment of MilestoneManager at address",
            address(milestoneManager));
    }

}
