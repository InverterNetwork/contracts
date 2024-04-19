pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {AUT_Role_v1} from "@aut/role/AUT_Role_v1.sol";

/**
 * @title ListAuthorizer Deployment Script
 *
 * @dev Script to deploy a new ListAuthorizer.
 *
 *
 * @author Inverter Network
 */
contract DeployAUT_Role_v1 is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("ORCHESTRATOR_OWNER_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    AUT_Role_v1 roleAuthorizer;

    function run() external returns (address) {
        vm.startBroadcast(deployerPrivateKey);
        {
            // Deploy the listAuthorizer.

            roleAuthorizer = new AUT_Role_v1();
        }

        vm.stopBroadcast();

        // Log the deployed AUT_Role_v1 contract address.
        console2.log(
            "Deployment of AUT_Role_v1 Implementation at address",
            address(roleAuthorizer)
        );

        return address(roleAuthorizer);
    }
}
