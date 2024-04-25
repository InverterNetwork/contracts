pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {VotingRoleManager_v1} from "src/modules/utils/VotingRoleManager_v1.sol";

/**
 * @title VotingRoleManager_v1 Deployment Script
 *
 * @dev Script to deploy a new VotingRoleManager_v1.
 *
 *
 * @author Inverter Network
 */
contract DeployVotingRoleManager_v1 is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("ORCHESTRATOR_OWNER_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    VotingRoleManager_v1 singleVoteGovernor;

    function run() external returns (address) {
        vm.startBroadcast(deployerPrivateKey);
        {
            // Deploy the singleVoteGovernor.

            singleVoteGovernor = new VotingRoleManager_v1();
        }

        vm.stopBroadcast();

        // Log the deployed VotingRoleManager_v1 contract address.
        console2.log(
            "Deployment of VotingRoleManager_v1 Implementation at address",
            address(singleVoteGovernor)
        );

        return address(singleVoteGovernor);
    }
}
