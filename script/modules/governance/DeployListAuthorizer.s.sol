pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {ListAuthorizer} from "src/modules/authorizer/ListAuthorizer.sol";

/**
 * @title ListAuthorizer Deployment Script
 *
 * @dev Script to deploy a new ListAuthorizer.
 *
 *
 * @author Inverter Network
 */

contract DeployListAuthorizer is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("PROPOSAL_OWNER_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    ListAuthorizer listAuthorizer;

    function run() external returns (address) {
        vm.startBroadcast(deployerPrivateKey);
        {
            // Deploy the listAuthorizer.

            listAuthorizer = new ListAuthorizer();
        }

        vm.stopBroadcast();

        // Log the deployed ListAuthorizer contract address.
        console2.log(
            "Deployment of ListAuthorizer Implementation at address",
            address(listAuthorizer)
        );

        return address(listAuthorizer);
    }
}
