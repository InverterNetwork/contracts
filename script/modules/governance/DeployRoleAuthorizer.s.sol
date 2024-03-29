pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {RoleAuthorizer} from "src/modules/authorizer/RoleAuthorizer.sol";

/**
 * @title ListAuthorizer Deployment Script
 *
 * @dev Script to deploy a new ListAuthorizer.
 *
 *
 * @author Inverter Network
 */
contract DeployRoleAuthorizer is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    RoleAuthorizer roleAuthorizer;

    function run() external returns (address) {
        vm.startBroadcast(deployerPrivateKey);
        {
            // Deploy the listAuthorizer.

            roleAuthorizer = new RoleAuthorizer();
        }

        vm.stopBroadcast();

        // Log the deployed RoleAuthorizer contract address.
        console2.log(
            "Deployment of RoleAuthorizer Implementation at address",
            address(roleAuthorizer)
        );

        return address(roleAuthorizer);
    }
}
