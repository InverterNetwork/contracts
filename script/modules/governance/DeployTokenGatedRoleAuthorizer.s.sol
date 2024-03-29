pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {TokenGatedRoleAuthorizer} from
    "src/modules/authorizer/TokenGatedRoleAuthorizer.sol";

/**
 * @title Token Gated Role Authorizer Deployment Script
 *
 * @dev Script to deploy a new Token Gated Role Authorizer.
 *
 *
 * @author Inverter Network
 */
contract DeployTokenGatedRoleAuthorizer is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    TokenGatedRoleAuthorizer tokenRoleAuthorizer;

    function run() external returns (address) {
        vm.startBroadcast(deployerPrivateKey);
        {
            // Deploy the listAuthorizer.

            tokenRoleAuthorizer = new TokenGatedRoleAuthorizer();
        }

        vm.stopBroadcast();

        // Log the deployed RoleAuthorizer contract address.
        console2.log(
            "Deployment of TokenGatedRoleAuthorizer Implementation at address",
            address(tokenRoleAuthorizer)
        );

        return address(tokenRoleAuthorizer);
    }
}
