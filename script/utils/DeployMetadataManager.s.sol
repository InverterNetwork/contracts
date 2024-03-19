pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {MetadataManager} from "src/modules/utils/MetadataManager.sol";

/**
 * @title MetadataManager Deployment Script
 *
 * @dev Script to deploy a new MetadataManager.
 *
 *
 * @author Inverter Network
 */
contract DeployMetadataManager is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("ORCHESTRATOR_OWNER_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    MetadataManager metadataManager;

    function run() external returns (address) {
        vm.startBroadcast(deployerPrivateKey);
        {
            // Deploy the MetadataManager.

            metadataManager = new MetadataManager();
        }

        vm.stopBroadcast();

        // Log the deployed MetadataManager contract address.
        console2.log(
            "Deployment of MetadataManager Implementation at address",
            address(metadataManager)
        );

        return address(metadataManager);
    }
}
