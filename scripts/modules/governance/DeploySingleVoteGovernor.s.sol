pragma solidity 0.8.19;

import "forge-std/Script.sol";

import {SingleVoteGovernor} from "src/modules/authorizer/SingleVoteGovernor.sol";

/**
 * @title SingleVoteGovernor Deployment Script
 *
 * @dev Script to deploy a new SingleVoteGovernor.
 *
 *
 * @author byterocket
 */

contract DeploySingleVoteGovernor is Script {
    SingleVoteGovernor singleVoteGovernor;

    function run() external {
        // Deploy the singleVoteGovernor.
        vm.startBroadcast();
        {
            singleVoteGovernor = new SingleVoteGovernor();
        }
        vm.stopBroadcast();

        // Log the deployed SingleVoteGovernor contract address.
        console2.log(
            "Deployment of SingleVoteGovernor at address",
            address(singleVoteGovernor)
        );
    }
}
