// SPDX-License-Identifier: UNLICENSED
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

    // ------------------------------------------------------------------------
    // Deployment Salt
    // ------------------------------------------------------------------------

    string public constant factorySaltString = "inverter-deployment-1";

    bytes32 public factorySalt = keccak256(abi.encodePacked(factorySaltString));

    // ------------------------------------------------------------------------
    // Important Configuration Data
    // ------------------------------------------------------------------------

    // TODO: load from env?
    // FeeManager
    uint public feeManager_defaultCollateralFee = 100;
    uint public feeManager_defaultIssuanceFee = 100;

    // Governor
    uint public governor_timelockPeriod = 1 weeks;

    // Function to log data in a readable format
    function logProtocolMultisigsAndAddresses() public view {
        console2.log(
            "--------------------------------------------------------------------------------"
        );
        console2.log(" Protocol-Level Addresses Used for the Deployment");
        console2.log("\tDeployer: %s", deployer);
        console2.log("\tCommunity Multisig: %s", communityMultisig);
        console2.log("\tTeam Multisig: %s", teamMultisig);
        console2.log("\tTreasury: %s", treasury);
        console2.log("\tDeterministicFactory: %s", deterministicFactory);
        console2.log("\t -> Salt used: \"%s\"", factorySaltString);
    }

    // Function to log the protocol configuration in a readable format
    function logProtocolConfigurationData() public view {
        console2.log(
            "--------------------------------------------------------------------------------"
        );
        console2.log(" Protocol Configuration Data Used for Initialization:");

        console2.log("\tFeeManager:");
        console2.log(
            "\t\tDefault Collateral Fee: %s BPS",
            feeManager_defaultCollateralFee
        );
        console2.log(
            "\t\tDefault Issuance Fee: %s BPS", feeManager_defaultIssuanceFee
        );
        console2.log("\tGovernor:");
        console2.log("\t\tTimelock Period: %s seconds", governor_timelockPeriod);
    }
}
