pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {Proposal} from "src/proposal/Proposal.sol";

/**
 * @title Proposal Deployment Script
 *
 * @dev Script to deploy a new Proposal.
 *
 *
 * @author Inverter Network
 */

contract DeployProposal is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("PROPOSAL_OWNER_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    Proposal proposal;

    function run() external returns (address) {
        vm.startBroadcast(deployerPrivateKey);
        {
            // Deploy the proposal.

            proposal = new Proposal();
        }

        vm.stopBroadcast();

        // Log the deployed Proposal contract address.
        console2.log(
            "Deployment of Proposal Implementation at address",
            address(proposal)
        );

        return address(proposal);
    }
}
