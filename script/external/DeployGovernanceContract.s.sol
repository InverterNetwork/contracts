pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {GovernanceContract} from
    "src/external/governance/GovernanceContract.sol";

/**
 * @title GovernanceContract Deployment Script
 *
 * @dev Script to deploy a new GovernanceContract.
 *
 *
 * @author Inverter Network
 */
contract DeployGovernanceContract is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("ORCHESTRATOR_OWNER_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    GovernanceContract gov;

    function run() external returns (address) {
        // Read deployment settings from environment variables.

        address communityMultisig = vm.envAddress("COMMUNITY_MULTISIG_ADDRESS");
        address teamMultisig = vm.envAddress("TEAM_MULTISIG_ADDRESS");
        uint timelockPeriod = 1 weeks;
        // Check settings.

        require(
            communityMultisig != address(0),
            "DeployOrchestratorFactory: Missing env variable: community multisig"
        );

        require(
            teamMultisig != address(0),
            "DeployOrchestratorFactory: Missing env variable: team multisig"
        );

        // Deploy the GovernanceContract.
        return run(communityMultisig, teamMultisig, timelockPeriod);
    }

    function run(
        address communityMultisig,
        address teamMultisig,
        uint timelockPeriod
    ) public returns (address) {
        vm.startBroadcast(deployerPrivateKey);
        {
            // Deploy the GovernanceContract.
            gov = new GovernanceContract();
            gov.init(communityMultisig, teamMultisig, timelockPeriod); //@todo
        }

        vm.stopBroadcast();

        // Log the deployed GovernanceContract address.
        console2.log(
            "Deployment of GovernanceContract at address", address(gov)
        );

        return address(gov);
    }
}
