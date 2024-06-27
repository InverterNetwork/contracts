pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {FM_Rebasing_v1} from "@fm/rebasing/FM_Rebasing_v1.sol";

/**
 * @title Rebasing Funding Manager Deployment Script
 *
 * @dev Script to deploy a new Rebasing Funding Manager.
 *
 * @author Inverter Network
 */
contract DeployFM_Rebasing_v1 is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("ORCHESTRATOR_ADMIN_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    FM_Rebasing_v1 fundingManager;

    function run() external returns (address) {
        vm.startBroadcast(deployerPrivateKey);
        {
            // Deploy the FM_Rebasing_v1.

            fundingManager = new FM_Rebasing_v1();
        }

        vm.stopBroadcast();
        // Log the deployed FM_Rebasing_v1 contract address.
        console2.log(
            "Deployment of FM_Rebasing_v1 Implementation at address: ",
            address(fundingManager)
        );

        return address(fundingManager);
    }
}
