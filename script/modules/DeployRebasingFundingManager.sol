pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {RebasingFundingManager} from
    "src/modules/fundingManager/RebasingFundingManager.sol";

/**
 * @title PaymentProcessor Deployment Script
 *
 * @dev Script to deploy a new PaymentProcessor.
 *
 * @author byterocket
 */

contract DeployRebasingFundingManager is Script {
    RebasingFundingManager fundingManager;

    function run() external returns (address) {
        // Deploy the milestoneManager.
        vm.startBroadcast();
        {
            fundingManager = new RebasingFundingManager();
        }
        vm.stopBroadcast();

        // Log the deployed MilestoneManager contract address.
        console2.log(
            "Deployment of RebasingFundingManager Implementation at address: ",
            address(fundingManager)
        );

        return address(fundingManager);
    }
}
