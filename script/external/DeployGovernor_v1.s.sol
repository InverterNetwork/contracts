pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {Governor_v1} from "src/external/governance/Governor_v1.sol";

// External Dependencies
import {TransparentUpgradeableProxy} from
    "@oz/proxy/transparent/TransparentUpgradeableProxy.sol";

/**
 * @title Governor_v1 Deployment Script
 *
 * @dev Script to deploy a new Governor_v1.
 *
 *
 * @author Inverter Network
 */
contract DeployGovernor_v1 is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("ORCHESTRATOR_ADMIN_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    Governor_v1 govImplementation;
    Governor_v1 gov;

    function run() external returns (address, address) {
        // Read deployment settings from environment variables.

        address communityMultisig = vm.envAddress("COMMUNITY_MULTISIG_ADDRESS");
        address teamMultisig = vm.envAddress("TEAM_MULTISIG_ADDRESS");
        address feeManager = vm.envAddress("FEE_MANAGER_ADDRESS");
        uint timelockPeriod = 1 weeks;
        // Check settings.

        require(
            communityMultisig != address(0),
            "DeployGovernor_v1: Missing env variable: community multisig"
        );

        require(
            teamMultisig != address(0),
            "DeployGovernor_v1: Missing env variable: team multisig"
        );

        require(
            feeManager != address(0),
            "DeployGovernor_v1: Missing env variable: feeManager"
        );

        // Deploy the Governor_v1.
        return run(communityMultisig, teamMultisig, timelockPeriod, feeManager);
    }

    function run(
        address communityMultisig,
        address teamMultisig,
        uint timelockPeriod,
        address initialFeeManager
    ) public returns (address, address) {
        vm.startBroadcast(deployerPrivateKey);
        {
            // Deploy the Governor_v1.
            govImplementation = new Governor_v1();

            // Deploy Governance Contract
            gov = Governor_v1(
                address(
                    new TransparentUpgradeableProxy( // based on openzeppelins TransparentUpgradeableProxy
                        address(govImplementation), // Implementation Address
                        communityMultisig, // Admin
                        bytes("") // data field that could have been used for calls, but not necessary
                    )
                )
            );
            gov.init(
                communityMultisig,
                teamMultisig,
                timelockPeriod,
                initialFeeManager
            );
        }

        vm.stopBroadcast();

        // Log the deployed Governor_v1 address.
        console2.log(
            "Deployment of Governor_v1 implementation at address", address(gov)
        );
        console2.log("Deployment of Governor_v1 at address", address(gov));

        return (address(gov), address(govImplementation));
    }
}
