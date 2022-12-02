pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {SingleVoteGovernance} from "../src/modules/governance/SingleVoteGovernance.sol";

 /**
  * @title SingleVoteGovernance Deployment Script
  *
  * @dev Script to deploy a new SingleVoteGovernance.
  *
  *
  * @author byterocket
  */

contract DeploySingleVoteGovernance is Script {

    SingleVoteGovernance singleVoteGovernance;

    function run() external {

        // Deploy the singleVoteGovernance.
        vm.startBroadcast();
        {
            singleVoteGovernance = new SingleVoteGovernance();
        }
        vm.stopBroadcast();

        // Log the deployed SingleVoteGovernance contract address.
        console2.log("Deployment of SingleVoteGovernance at address",
            address(singleVoteGovernance));
    }

}
