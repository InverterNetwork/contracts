// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

/*
This file contains protocol-wide constants for critical roles and addresses in deployments, like the deployer and multisigs. They are loaded from the environment variables.

*/

contract ProtocolConstants is Script {
    // Fetch the deployer details
    uint deployerPrivateKey = vm.envUint("ORCHESTRATOR_ADMIN_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    // Fetch the Multisig addresses
    address communityMultisig = vm.envAddress("COMMUNITY_MULTISIG_ADDRESS");
    address teamMultisig = vm.envAddress("TEAM_MULTISIG_ADDRESS");

    // Fetch the treasury address
    address treasury = vm.envAddress("TREASURY_ADDRESS");
}
