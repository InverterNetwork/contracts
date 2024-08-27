// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/console.sol";


import { Restricted_PIM_Factory_v1 } from "src/factories/workflow-specific/Restricted_PIM_Factory_v1.sol";

contract DeployRestrictedPimFactory is Script {
    function run() public {
        address orchestratorFactory = vm.envAddress("ORCHESTRATOR_FACTORY_ADDRESS");
        address trustedForwarder = vm.envAddress("TRUSTED_FORWARDER_ADDRESS");

        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        {
            console2.log(
                "Deploying Restricted_PIM_Factory_v1 at address: ",
                address(new Restricted_PIM_Factory_v1(orchestratorFactory, trustedForwarder))
            );
        }
        vm.stopBroadcast();
    }
}