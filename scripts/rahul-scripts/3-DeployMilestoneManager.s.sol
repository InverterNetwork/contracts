// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {MilestoneManager} from "../../src/modules/MilestoneManager.sol";

contract DeployMilestoneManagerContract is Script {
    MilestoneManager milestoneManager;
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("ANVIL_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        {
            milestoneManager = new MilestoneManager();
        }
        vm.stopBroadcast();

        console2.log("Milestone Manager Contract Deployed at: ", address(milestoneManager));
    }
}