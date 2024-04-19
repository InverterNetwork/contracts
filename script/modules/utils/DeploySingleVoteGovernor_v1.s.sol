pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {SingleVoteGovernor_v1} from
    "src/modules/utils/SingleVoteGovernor_v1.sol";

/**
 * @title SingleVoteGovernor_v1 Deployment Script
 *
 * @dev Script to deploy a new SingleVoteGovernor_v1.
 *
 *
 * @author Inverter Network
 */
contract DeploySingleVoteGovernor_v1 is Script {
    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("ORCHESTRATOR_OWNER_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    SingleVoteGovernor_v1 singleVoteGovernor;

    function run() external returns (address) {
        vm.startBroadcast(deployerPrivateKey);
        {
            // Deploy the singleVoteGovernor.

            singleVoteGovernor = new SingleVoteGovernor_v1();
        }

        vm.stopBroadcast();

        // Log the deployed SingleVoteGovernor_v1 contract address.
        console2.log(
            "Deployment of SingleVoteGovernor_v1 Implementation at address",
            address(singleVoteGovernor)
        );

        return address(singleVoteGovernor);
    }
}
