pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {RebasingFundingManager} from
    "src/modules/fundingManager/rebasing/RebasingFundingManager.sol";

/**
 * @title PaymentProcessor Deployment Script
 *
 * @dev Script to deploy a new PaymentProcessor.
 *
 * @author Inverter Network
 */
contract DeployRebasingFundingManager is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("ORCHESTRATOR_OWNER_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    RebasingFundingManager fundingManager;

    function run() external returns (address) {
        vm.startBroadcast(deployerPrivateKey);
        {
            // Deploy the RebasingFundingManager.

            fundingManager = new RebasingFundingManager();
        }

        vm.stopBroadcast();
        // Log the deployed RebasingFundingManager contract address.
        console2.log(
            "Deployment of RebasingFundingManager Implementation at address: ",
            address(fundingManager)
        );

        return address(fundingManager);
    }
}
