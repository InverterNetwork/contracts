// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {DeploymentScript} from "script/deploymentScript/DeploymentScript.s.sol";

import {DeterministicFactory_v1} from "@df/DeterministicFactory_v1.sol";

import {BancorFormula} from "@fm/bondingCurve/formulas/BancorFormula.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {
    OptimisticOracleV3Mock,
    OptimisticOracleV3Interface
} from "test/modules/logicModule/oracle/utils/OptimisiticOracleV3Mock.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

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
    OptimisticOracleV3Mock ooV3;
    ERC20Mock mockCollateralToken;

    uint64 immutable DEFAULT_LIVENESS = 25_000;

    function run() public virtual override {
        // Deploy Deterministic Factory

        console2.log(
            "--------------------------------------------------------------------------------"
        );
        console2.log("Start Testnet Deployment Script");

        vm.startBroadcast(deployerPrivateKey);

        console2.log(
            "--------------------------------------------------------------------------------\n"
        );
        console2.log("Testnet Dependency Deployment: ");
        console2.log(
            "--------------------------------------------------------------------------------\n"
        );
        console2.log("\tSet up dependency contracts ");

        deterministicFactory = address(new DeterministicFactory_v1(deployer));

        DeterministicFactory_v1(deterministicFactory).setAllowedDeployer(
            deployer
        );
        console2.log("\t\t-Deterministic Factory: %s", deterministicFactory);
        formula = new BancorFormula();
        console2.log("\t\t-BancorFormula: %s", address(formula));

        console.log("\tSet up mocks");
        // BancorFormula, ERC20Mock and UMAoracleMock

        ooV3 = new OptimisticOracleV3Mock(
            IERC20(address(mockCollateralToken)), DEFAULT_LIVENESS
        ); //@note FeeToken?
        console2.log("\t\t-OptimisticOracleV3Mock: %s", address(ooV3));

        mockCollateralToken = new ERC20Mock("Inverter USD", "iUSD");
        console2.log("\t\t-ERC20Mock iUSD: %s", address(mockCollateralToken));

        vm.stopBroadcast();

        setFactory(deterministicFactory);
        proxyAndBeaconDeployer.setFactory(deterministicFactory);

        super.run();
    }
}
