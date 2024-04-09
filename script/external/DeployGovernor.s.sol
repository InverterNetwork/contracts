pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {Governor} from "src/external/governance/Governor.sol";

/**
 * @title Governor Deployment Script
 *
 * @dev Script to deploy a new Governor.
 *
 *
 * @author Inverter Network
 */
contract DeployGovernor is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("ORCHESTRATOR_OWNER_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    Governor gov;

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

        // Deploy the Governor.
        return run(communityMultisig, teamMultisig, timelockPeriod);
    }

    function run(
        address communityMultisig,
        address teamMultisig,
        uint timelockPeriod
    ) public returns (address) {
        vm.startBroadcast(deployerPrivateKey);
        {
            // Deploy the Governor.
            gov = new Governor();
            gov.init(communityMultisig, teamMultisig, timelockPeriod); //@todo
        }

        vm.stopBroadcast();

        // Log the deployed Governor address.
        console2.log("Deployment of Governor at address", address(gov));

        return address(gov);
    }
}
