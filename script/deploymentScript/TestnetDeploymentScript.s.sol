// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

// Scripts
import {DeploymentScript} from "script/deploymentScript/DeploymentScript.s.sol";

// Contracts
import {DeterministicFactory_v1} from "@df/DeterministicFactory_v1.sol";

// Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Mocks
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
    OptimisticOracleV3Mock ooV3;
    ERC20Mock mockCollateralToken;

    uint64 immutable DEFAULT_LIVENESS = 25_000;

    function run() public virtual override {
        console2.log();
        console2.log(
            "================================================================================"
        );
        console2.log("Start Testnet Deployment Script");
        console2.log(
            "================================================================================"
        );

        // Set required parameters to testnet values
        // For a testnet deployment, this means that if not set otherwise,
        // the deployer will also act as both multisigs and the treasury.
        if (communityMultisig == address(0)) {
            communityMultisig = deployer;
        }
        if (teamMultisig == address(0)) {
            teamMultisig = deployer;
        }
        if (treasury == address(0)) {
            treasury = deployer;
        }

        vm.startBroadcast(deployerPrivateKey);
        {
            console2.log(" Set up dependency contracts ");

            // Deploy and setup DeterministicFactory
            deterministicFactory =
                address(new DeterministicFactory_v1(deployer));
            DeterministicFactory_v1(deterministicFactory).setAllowedDeployer(
                deployer
            );
            console2.log("\tDeterministic Factory: %s", deterministicFactory);

            console2.log(" Set up mocks");

            // Deploy and setup UMA's OptimisticOracleV3Mock
            ooV3 = new OptimisticOracleV3Mock(
                IERC20(address(mockCollateralToken)), DEFAULT_LIVENESS
            ); // @note FeeToken?
            console2.log("\tOptimisticOracleV3Mock: %s", address(ooV3));

            // Deploy and setup Mock Collateral Token
            mockCollateralToken = new ERC20Mock("Inverter USD", "iUSD");
            console2.log("\tERC20Mock iUSD: %s", address(mockCollateralToken));
        }
        vm.stopBroadcast();

        // Set DeterministicFactory so it's used in the DeploymentScript
        // downstream
        setFactory(deterministicFactory);
        proxyAndBeaconDeployer.setFactory(deterministicFactory);

        super.run();
    }
}
