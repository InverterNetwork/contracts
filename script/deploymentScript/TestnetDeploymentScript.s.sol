// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {DeploymentScript} from "script/deploymentScript/DeploymentScript.s.sol";

import {DeterministicFactory_v1} from "@df/DeterministicFactory_v1.sol";

/**
 * @title Inverter Testnet Deployment Script
 *
 * @dev Script to deploy the Inverter protocol in a testnet environment.
 *      This means that the script deploys the DeterministicFactory as well.
 *
 * @author Inverter Network
 */
contract TestnetDeploymentScript is DeploymentScript {
    function run() public override {
        // Deploy Deterministic Factory

        console2.log(
            "--------------------------------------------------------------------------------"
        );
        console2.log("Start Testnet Deployment Script");

        vm.startBroadcast(deployerPrivateKey);

        console2.log(
            "--------------------------------------------------------------------------------"
        );

        deterministicFactory = address(new DeterministicFactory_v1(deployer));
        console2.log(
            "Deploy Deterministic Factory with Deployer as owner at address %s",
            deterministicFactory
        );
        DeterministicFactory_v1(deterministicFactory).setAllowedDeployer(
            deployer
        );

        vm.stopBroadcast();

        setFactory(deterministicFactory);
        proxyAndBeaconDeployer.setFactory(deterministicFactory);

        super.run();

        // BancorFormula, ERC20Mock and UMAoracleMock
    }
}
