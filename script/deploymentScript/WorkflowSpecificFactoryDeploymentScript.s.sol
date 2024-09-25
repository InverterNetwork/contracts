// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {Restricted_PIM_Factory_v1} from
    "src/factories/workflow-specific/Restricted_PIM_Factory_v1.sol";
import {Immutable_PIM_Factory_v1} from
    "src/factories/workflow-specific/Immutable_PIM_Factory_v1.sol";

contract WorkflowSpecificFactoryDeploymentScript is Script {
    function run() public virtual {
        address orchestratorFactory =
            vm.envAddress("ORCHESTRATOR_FACTORY_ADDRESS");
        address trustedForwarder = vm.envAddress("TRUSTED_FORWARDER_ADDRESS");
        string memory factoryType = vm.envString("FACTORY_TYPE");
        _deploy(orchestratorFactory, trustedForwarder, factoryType);
    }

    function deploy(address orchestratorFactory, address trustedForwarder)
        public
    {
        console2.log();
        console2.log(
            "================================================================================"
        );
        console2.log("Start Workflow Specific Factory Deployment Script");
        console2.log(
            "================================================================================"
        );

        _deploy(orchestratorFactory, trustedForwarder, "RESTRICTED");
        _deploy(orchestratorFactory, trustedForwarder, "IMMUTABLE");
    }

    function _deploy(
        address orchestratorFactory,
        address trustedForwarder,
        string memory factoryType
    ) public validateInputs(orchestratorFactory, trustedForwarder) {
        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        if (_isEqual(factoryType, "RESTRICTED")) {
            {
                console2.log(
                    "Deploying Restricted_PIM_Factory_v1 at address: ",
                    address(
                        new Restricted_PIM_Factory_v1(
                            orchestratorFactory, trustedForwarder
                        )
                    )
                );
            }
        } else if (_isEqual(factoryType, "IMMUTABLE")) {
            {
                console2.log(
                    "Deploying Immutable_PIM_Factory_v1 at address: ",
                    address(
                        new Immutable_PIM_Factory_v1(
                            orchestratorFactory, trustedForwarder
                        )
                    )
                );
            }
        } else {
            revert("Invalid factory type - aborting!");
        }

        vm.stopBroadcast();
    }

    function _isEqual(string memory a, string memory b)
        internal
        pure
        returns (bool)
    {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }

    modifier validateInputs(
        address orchestratorFactory,
        address trustedForwarder
    ) {
        require(
            orchestratorFactory != address(0),
            "Orchestrator Factory address not set - aborting!"
        );
        require(
            trustedForwarder != address(0),
            "Trusted Forwarder address not set - aborting!"
        );
        _;
    }
}
