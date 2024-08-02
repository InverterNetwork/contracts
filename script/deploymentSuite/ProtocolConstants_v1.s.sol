// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

/**
 * @title Inverter Protocol Deployment Constants
 *
 * @dev Contains protocol-wide constants for critical information and addresses in 
 *      deployments, like the deployer and multisigs. They are loaded from the 
 *      environment variables.
 *
 * @author Inverter Network
 */
contract ProtocolConstants_v1 is Script {
    // ------------------------------------------------------------------------
    // Important addresses
    // ------------------------------------------------------------------------

    // Fetch the deployer details
    uint public deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address public deployer = vm.addr(deployerPrivateKey);

    // Fetch the Multisig addresses
    address public communityMultisig =
        vm.envAddress("COMMUNITY_MULTISIG_ADDRESS");
    address public teamMultisig = vm.envAddress("TEAM_MULTISIG_ADDRESS");

    // Fetch the treasury address
    address public treasury = vm.envAddress("TREASURY_ADDRESS");

    // Fetch the deterministic factory address
    address public deterministicFactory =
        vm.envAddress("DETERMINISTIC_FACTORY_ADDRESS");

    bytes32 public factorySalt =
        keccak256(abi.encodePacked("inverter-deployment"));

    // ------------------------------------------------------------------------
    // Important Configuration Data
    // ------------------------------------------------------------------------

    // FeeManager
    uint public defaultCollateralFee;
    uint public defaultIssuanceFee;

    // Governor
    uint public timelockPeriod;
}
