// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {Restricted_PIM_Factory_v1} from
    "src/factories/custom/Restricted_PIM_Factory_v1.sol";
import {Immutable_PIM_Factory_v1} from
    "src/factories/custom/Immutable_PIM_Factory_v1.sol";
import {Migrating_PIM_Factory_v1} from
    "src/factories/custom/Migrating_PIM_Factory_v1.sol";

import {ERC2771Context} from "@oz/metatx/ERC2771Context.sol";

// Constants
import {uniswapV2FactoryBytecode} from
    "test/lib/uniswap/uniswapV2FactoryBytecode.sol";
import {uniswapV2Router02Bytecode} from
    "test/lib/uniswap/uniswapV2Router02Bytecode.sol";

import {UniswapV2Adapter} from
    "src/external/immutable-migration/UniswapV2Adapter.sol";

address constant uniswapFactoryAddress =
    0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
address constant uniswapRouterAddress =
    0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

contract CustomFactoryDeploymentScript is Script {
    address public orchestratorFactory =
        vm.envOr("ORCHESTRATOR_FACTORY_ADDRESS", address(0));

    function run() public virtual {
        console2.log(
            "Deploying Custom Factory, attached to Orchestrator Factory at %s:",
            orchestratorFactory
        );
        _deploy(vm.envString("FACTORY_TYPE"));
    }

    function deploy(address orchestratorFactory_) public {
        // Take Orchestrator Factory from function parameter
        // and not from the env file.
        orchestratorFactory = orchestratorFactory_;

        console2.log();
        console2.log(
            "================================================================================"
        );
        console2.log("Start Custom Factory Deployment Script");
        console2.log(
            "================================================================================"
        );
        console2.log(
            "--------------------------------------------------------------------------------"
        );
        console2.log(" Deploying Custom Factories:");

        _deploy("RESTRICTED");
        _deploy("IMMUTABLE");
        _deploy("MIGRATING");

        console2.log(
            "--------------------------------------------------------------------------------"
        );

        deployUniswapAdapter();
    }

    function _deploy(string memory factoryType_) public validateInputs {
        // Obtain the correct trusted forwarder from the orchestrator factory.
        address trustedForwarder =
            ERC2771Context(orchestratorFactory).trustedForwarder();
        require(
            trustedForwarder != address(0),
            "Trusted Forwarder address not set - aborting!"
        );

        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        if (_isEqual(factoryType_, "RESTRICTED")) {
            {
                console2.log(
                    "\tRestricted_PIM_Factory_v1: %s",
                    address(
                        new Restricted_PIM_Factory_v1(
                            orchestratorFactory, trustedForwarder
                        )
                    )
                );
            }
        } else if (_isEqual(factoryType_, "IMMUTABLE")) {
            {
                console2.log(
                    "\tImmutable_PIM_Factory_v1: %s",
                    address(
                        new Immutable_PIM_Factory_v1(
                            orchestratorFactory, trustedForwarder
                        )
                    )
                );
            }
        } else if (_isEqual(factoryType_, "MIGRATING")) {
            {
                console2.log(
                    "\tMigrating_PIM_Factory_v1: %s",
                    address(
                        new Migrating_PIM_Factory_v1(
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

    function _isEqual(string memory a_, string memory b_)
        internal
        pure
        returns (bool)
    {
        return
            keccak256(abi.encodePacked(a_)) == keccak256(abi.encodePacked(b_));
    }

    function deployUniswapAdapter() internal returns (address) {
        console2.log("\tDeploying UniswapV2Adapter...");
        vm.etch(uniswapFactoryAddress, uniswapV2FactoryBytecode);
        vm.etch(uniswapRouterAddress, uniswapV2Router02Bytecode);

        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        address adapter = address(
            new UniswapV2Adapter(uniswapFactoryAddress, uniswapRouterAddress)
        );
        vm.stopBroadcast();

        console2.log("\tUniswapV2Adapter: %s", adapter);
        return adapter;
    }

    modifier validateInputs() {
        require(
            orchestratorFactory != address(0),
            "Orchestrator Factory address not set - aborting!"
        );
        _;
    }
}
