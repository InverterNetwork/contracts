// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {Immutable_PIM_Factory_v1} from
    "src/factories/workflow-specific/Immutable_PIM_Factory_v1.sol";

contract DeployImmutablePIM is Script {
    function run() public {
        // insert your pk
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        {
            console2.log(
                "Deploying Restricted_PIM_Factory_v1 at address: ",
                address(
                    new Immutable_PIM_Factory_v1(
                        vm.envAddress("ORCHESTRATOR_FACTORY"),
                        vm.envAddress("TRUSTED_FORWARDER")
                    )
                )
            );
        }
        vm.stopBroadcast();
    }
}
