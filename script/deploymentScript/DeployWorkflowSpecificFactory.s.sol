// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/console.sol";


import { Restricted_PIM_Factory_v1 } from "src/factories/workflow-specific/Restricted_PIM_Factory_v1.sol";
import { Immutable_PIM_Factory_v1 } from "src/factories/workflow-specific/Immutable_PIM_Factory_v1.sol";


contract DeployWorkflowSpecificFactory is Script {
    function run() public {
        address orchestratorFactory = vm.envAddress("ORCHESTRATOR_FACTORY_ADDRESS");
        address trustedForwarder = vm.envAddress("TRUSTED_FORWARDER_ADDRESS");
        string memory factoryType = vm.envString("FACTORY_TYPE");


        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        if (isEqual(factoryType, "RESTRICTED")) {
            {
                console2.log(
                    "Deploying Restricted_PIM_Factory_v1 at address: ",
                    address(new Restricted_PIM_Factory_v1(orchestratorFactory, trustedForwarder))
                );
            }
        } else if (isEqual(factoryType, "IMMUTABLE")) {
            {
                console2.log(
                    "Deploying Immutable_PIM_Factory_v1 at address: ",
                    address(new Immutable_PIM_Factory_v1(orchestratorFactory, trustedForwarder))
                );
            }
        }
        
        vm.stopBroadcast();
    }

    function isEqual(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));

    }
}