// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {DeploymentScript} from "script/deploymentScript/DeploymentScript.s.sol";

import {DeterministicFactory_v1} from "@df/DeterministicFactory_v1.sol";

import {BancorFormula} from "@fm/bondingCurve/formulas/BancorFormula.sol";
import {ERC20Issuance_v1} from "@ex/token/ERC20Issuance_v1.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {
    OptimisticOracleV3Mock,
    OptimisticOracleV3Interface
} from "test/modules/logicModule/oracle/utils/OptimisiticOracleV3Mock.sol";

/**
 * @title Inverter Testnet Deployment Script
 *
 * @dev Script to deploy the Inverter protocol in a testnet environment.
 *      This means that the script deploys the DeterministicFactory as well.
 *
 * @author Inverter Network
 */
contract TestnetDeploymentScript is DeploymentScript {
    BancorFormula formula;
    ERC20Issuance_v1 issuanceToken;
    OptimisticOracleV3Mock ooV3;

    uint64 immutable DEFAULT_LIVENESS = 25_000;

    function run() public virtual override {
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

        formula = new BancorFormula();

        issuanceToken = new ERC20Issuance_v1(
            "Bonding Curve Token", "BCT", 18, type(uint).max - 1, address(this)
        ); //@note Correct?

        ooV3 = new OptimisticOracleV3Mock(
            IERC20(address(issuanceToken)), DEFAULT_LIVENESS
        ); //@note FeeToken?
    }
}
