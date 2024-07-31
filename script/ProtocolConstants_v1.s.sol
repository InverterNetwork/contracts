// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

/*
This file contains protocol-wide constants for critical information and addresses in deployments, like the deployer and multisigs. They are loaded from the environment variables.

*/

contract ProtocolConstants_v1 is Script {
    // ------------------------------------------------------------------------
    // Important addresses
    // ------------------------------------------------------------------------

    // Fetch the deployer details
    uint deployerPrivateKey = vm.envUint("ORCHESTRATOR_ADMIN_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    // Fetch the Multisig addresses
    address communityMultisig = vm.envAddress("COMMUNITY_MULTISIG_ADDRESS");
    address teamMultisig = vm.envAddress("TEAM_MULTISIG_ADDRESS");

    // Fetch the treasury address
    address treasury = vm.envAddress("TREASURY_ADDRESS");

    // Fetch the deterministic factory address
    address deterministicFactory =
        vm.envAddress("DETERMINISTIC_FACTORY_ADDRESS");

    // ------------------------------------------------------------------------
    // Important Configuration Data
    // ------------------------------------------------------------------------

    // FeeManager
    uint defaultCollateralFee;
    uint defaultIssuanceFee;

    // Governor
    uint timelockPeriod;
}
