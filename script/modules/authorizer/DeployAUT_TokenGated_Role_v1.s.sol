pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {AUT_TokenGated_Roles_v1} from "@aut/role/AUT_TokenGated_Roles_v1.sol";

/**
 * @title Token Gated Role Authorizer Deployment Script
 *
 * @dev Script to deploy a new Token Gated Role Authorizer.
 *
 *
 * @author Inverter Network
 */
contract DeployAUT_TokenGated_Role_v1 is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("ORCHESTRATOR_ADMIN_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    AUT_TokenGated_Roles_v1 tokenRoleAuthorizer;

    function run() external returns (address) {
        vm.startBroadcast(deployerPrivateKey);
        {
            // Deploy the listAuthorizer.

            tokenRoleAuthorizer = new AUT_TokenGated_Roles_v1();
        }

        vm.stopBroadcast();

        // Log the deployed AUT_Roles_v1 contract address.
        console2.log(
            "Deployment of AUT_TokenGated_Roles_v1 Implementation at address",
            address(tokenRoleAuthorizer)
        );

        return address(tokenRoleAuthorizer);
    }
}
