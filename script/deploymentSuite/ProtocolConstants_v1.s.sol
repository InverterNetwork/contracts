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

    // Function to log data in a readable format
    function logProtocolMultisigsAndAddresses() public {
        console.log(
            "--------------------------------------------------------------------------------"
        );
        console.log("\tProtocol-level Addresses Used for the Deployment");
        console.log(
            "--------------------------------------------------------------------------------"
        );
        console2.log("\tDeployer: %s", deployer);
        console2.log("\tCommunity Multisig: %s", communityMultisig);
        console2.log("\tTeam Multisig: %s", teamMultisig);
        console2.log("\tTreasury: %s", treasury);
        console2.log("\tDeterministicFactory: %s", deterministicFactory);
    }

    // ------------------------------------------------------------------------
    // Important Configuration Data
    // ------------------------------------------------------------------------

    // FeeManager
    uint public feeManager_defaultCollateralFee = 100;
    uint public feeManager_defaultIssuanceFee = 100;

    // Governor
    uint public governor_timelockPeriod = 1 weeks;

    //TODO: load from env?

    // Function to log data in a readable format
    function logProtocolConfigurationData() public {
        console.log(
            "--------------------------------------------------------------------------------"
        );
        console.log("Protocol Configuration Data Used for Initialization:");
        /*console.log(
            "--------------------------------------------------------------------------------"
        );*/
        console.log("\tFeeManager:");
        console2.log(
            "\t\tDefault Collateral Fee: %s", feeManager_defaultCollateralFee
        );
        console2.log(
            "\t\tDefault Issuance Fee: %s", feeManager_defaultIssuanceFee
        );
        console.log("\tGovernor:");
        console2.log("\t\tTimelock Period: %s", governor_timelockPeriod);
    }
}
