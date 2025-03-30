// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {OrchestratorFactory_v1} from "src/factories/OrchestratorFactory_v1.sol";

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
    // Deployment Details
    // ------------------------------------------------------------------------

    string public constant factorySaltString = "inverter-deployment-1";

    bytes32 public factorySalt = keccak256(abi.encodePacked(factorySaltString));

    // Deployment Addresses for Key Contracts needed for Protocol Updates/Maintenance
    address public deployedOrchestratorFactory;
    address public deployedModuleFactory;
    address public deployedGovernor;
    address public deployedReverter;

    // Chain IDs for Networks with Deployments
    // If the current chainid is not part of any array, we assume that we are working locally.
    uint[] public mainnets = [10, 137, 1101];
    uint[] public testnets = [2442, 80_002, 84_532, 11_155_111, 11_155_420];

    // Internal Storage for the deployment addresses (hardcoded as they don't change)
    address private constant governorMainnet = 0x0B7c73e778d04533286752BEb7d4BA42AEa2f57D;
    address private constant governorTestnet = 0x38D712491cC8A9B725AB867D56A4B0b25D9E0E3B;
    address private constant orchestratorFactoryMainnet = 0x6ecA5f791d9635e4a1874cCD95564F914fBCF73d;
    address private constant orchestratorFactoryTestnet = 0x535BdbC1D369d43fed8546024D273eE5274fFF65;
    address private constant reverterMainnet = 0x6270b15Ac19eeC3d62920ed7f3a635a93E9C8B4C;
    address private constant reverterTestnet = 0x54C1116BE44184619A8CB37Ef6E924f737C8F734;

    // ------------------------------------------------------------------------
    // Important Configuration Data
    // ------------------------------------------------------------------------

    // TODO: load from env?
    // FeeManager
    uint public feeManager_defaultCollateralFee = 100;
    uint public feeManager_defaultIssuanceFee = 100;

    // Governor
    uint public governor_timelockPeriod = 1 weeks;

    // Function to load the protocol constants
    function loadDeployedContracts() public {
        deployedOrchestratorFactory = getDeployedOrchestratorFactory();
        deployedModuleFactory = getDeployedModuleFactory();
        deployedGovernor = getDeployedGovernor();
        deployedReverter = getDeployedReverter();
    }

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

    function getDeployedOrchestratorFactory() public view returns (address) {
        uint chainId = block.chainid;

        // Mainnet Deployments
        for (uint i = 0; i < mainnets.length; i++) {
            if (chainId == mainnets[i]) {
                return orchestratorFactoryMainnet;
            }
        }

        // Testnet Deployments
        for (uint i = 0; i < testnets.length; i++) {
            if (chainId == testnets[i]) {
                return orchestratorFactoryTestnet;
            }
        }

        // Set to 0 for Local Deployments
        return 0x0000000000000000000000000000000000000000;
    }

    function getDeployedModuleFactory() public view returns (address) {
        if (
            deployedOrchestratorFactory
                != 0x0000000000000000000000000000000000000000
        ) {
            OrchestratorFactory_v1 orchestratorFactory =
                OrchestratorFactory_v1(deployedOrchestratorFactory);
            return address(orchestratorFactory.moduleFactory());
        }

        // Set to 0 for Local Deployments
        return 0x0000000000000000000000000000000000000000;
    }

    function getDeployedGovernor() public view returns (address) {
        uint chainId = block.chainid;

        // Mainnet Deployments
        for (uint i = 0; i < mainnets.length; i++) {
            if (chainId == mainnets[i]) {
                return governorMainnet;
            }
        }

        // Testnet Deployments
        for (uint i = 0; i < testnets.length; i++) {
            if (chainId == testnets[i]) {
                return governorTestnet;
            }
        }

        // Set to 0 for Local Deployments
        return 0x0000000000000000000000000000000000000000;
    }

    function getDeployedReverter() public view returns (address) {
        uint chainId = block.chainid;

        // Mainnet Deployments
        for (uint i = 0; i < mainnets.length; i++) {
            if (chainId == mainnets[i]) {
                return reverterMainnet;
            }
        }

        // Testnet Deployments
        for (uint i = 0; i < testnets.length; i++) {
            if (chainId == testnets[i]) {
                return reverterTestnet;
            }
        }

        // Set to 0 for Local Deployments
        return 0x0000000000000000000000000000000000000000;
    }
}
