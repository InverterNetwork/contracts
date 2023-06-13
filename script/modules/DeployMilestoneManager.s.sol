pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {MilestoneManager} from "src/modules/logicModule/MilestoneManager.sol";

/**
 * @title MilestoneManager Deployment Script
 *
 * @dev Script to deploy a new MilestoneManager.
 *
 *
 * @author Inverter Network
 */

contract DeployMilestoneManager is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("PROPOSAL_OWNER_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    MilestoneManager milestoneManager;

    function run() external returns (address) {
        vm.startBroadcast(deployerPrivateKey);
        {
            // Deploy the milestoneManager.

            milestoneManager = new MilestoneManager();
        }

        vm.stopBroadcast();
        // Log the deployed MilestoneManager contract address.
        console2.log(
            "Deployment of MilestoneManager Implementation at address",
            address(milestoneManager)
        );

        return address(milestoneManager);
    }
}
