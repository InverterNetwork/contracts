pragma solidity 0.8.19;

import "forge-std/Script.sol";

import {Proposal} from "src/proposal/Proposal.sol";

 /**
  * @title Proposal Deployment Script
  *
  * @dev Script to deploy a new Proposal.
  *
  *
  * @author byterocket
  */

contract DeployProposal is Script {

    Proposal proposal;

    function run() external {

        // Deploy the proposal.
        vm.startBroadcast();
        {
            proposal = new Proposal();
        }
        vm.stopBroadcast();

        // Log the deployed Proposal contract address.
        console2.log("Deployment of Proposal at address",
            address(proposal));
    }

}
