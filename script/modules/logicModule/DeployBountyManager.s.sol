pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {BountyManager} from "src/modules/logicModule/BountyManager.sol";

/**
 * @title BountyManager Deployment Script
 *
 * @dev Script to deploy a new BountyManager.
 *
 *
 * @author Inverter Network
 */
contract DeployBountyManager is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("ORCHESTRATOR_OWNER_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    BountyManager bountyManager;

    function run() external returns (address) {
        vm.startBroadcast(deployerPrivateKey);
        {
            // Deploy the BountyManager.

            bountyManager = new BountyManager();
        }

        vm.stopBroadcast();

        // Log the deployed BountyManager contract address.
        console2.log(
            "Deployment of BountyManager Implementation at address",
            address(bountyManager)
        );

        return address(bountyManager);
    }
}
