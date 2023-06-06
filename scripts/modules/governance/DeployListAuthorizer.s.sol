pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {ListAuthorizer} from "src/modules/authorizer/ListAuthorizer.sol";

/**
 * @title ListAuthorizer Deployment Script
 *
 * @dev Script to deploy a new ListAuthorizer.
 *
 *
 * @author byterocket
 */

contract DeployListAuthorizer is Script {
    ListAuthorizer listAuthorizer;

    function run() external {
        // Deploy the listAuthorizer.
        vm.startBroadcast();
        {
            listAuthorizer = new ListAuthorizer();
        }
        vm.stopBroadcast();

        // Log the deployed ListAuthorizer contract address.
        console2.log(
            "Deployment of ListAuthorizer at address", address(listAuthorizer)
        );
    }
}
