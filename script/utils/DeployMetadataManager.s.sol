pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {MetadataManager_v1} from "src/modules/utils/MetadataManager_v1.sol";

/**
 * @title MetadataManager_v1 Deployment Script
 *
 * @dev Script to deploy a new MetadataManager_v1.
 *
 *
 * @author Inverter Network
 */
contract DeployMetadataManager is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("ORCHESTRATOR_OWNER_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    MetadataManager_v1 metadataManager;

    function run() external returns (address) {
        vm.startBroadcast(deployerPrivateKey);
        {
            // Deploy the MetadataManager_v1.

            metadataManager = new MetadataManager_v1();
        }

        vm.stopBroadcast();

        // Log the deployed MetadataManager_v1 contract address.
        console2.log(
            "Deployment of MetadataManager_v1 Implementation at address",
            address(metadataManager)
        );

        return address(metadataManager);
    }
}
