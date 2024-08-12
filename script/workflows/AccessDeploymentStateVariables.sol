// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {TestnetDeploymentScript} from
    "script/deploymentScript/TestnetDeploymentScript.s.sol";

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
struct DeploymentState {
    // factories
    address orchestratorFactory;
    address moduleFactory;
    // Protocol level addresses
    address communityMultisig;
    address teamMultisig;
    address treasury;
    address deterministicFactory;
    // Protocol Singletons
    address reverter;
    address feeManager;
    address forwarder;
    address governor;
    // Testnet Variables
    address formula;
    address ooV3;
    address mockUSDToken;
}

contract AccessDeploymentStateVariables is TestnetDeploymentScript {
    // Here we will store the addresses of the chain state
    DeploymentState chain_state;

    function createTestnetDeploymentAndReturnState()
        public
        virtual
        returns (DeploymentState memory)
    {
        // Call the run function from TestnetDeploymentScript and store it
        run();

        chain_state = DeploymentState({
            orchestratorFactory: orchestratorFactory,
            moduleFactory: moduleFactory,
            communityMultisig: communityMultisig,
            teamMultisig: teamMultisig,
            treasury: treasury,
            deterministicFactory: deterministicFactory,
            feeManager: feeManager,
            forwarder: forwarder,
            reverter: inverterReverter,
            governor: governor,
            formula: impl_lib_BancorFormula,
            ooV3: address(ooV3),
            mockUSDToken: address(mockCollateralToken)
        });

        return chain_state;
    }

    function getExistingDeploymentInfoFromEnv()
        public
        virtual
        returns (DeploymentState memory)
    {
        address orchestratorFactory =
            vm.envAddress("ORCHESTRATOR_FACTORY_ADDRESS");
        address moduleFactory = vm.envAddress("MODULE_FACTORY_ADDRESS");
        address communityMultisig = vm.envAddress("COMMUNITY_MULTISIG_ADDRESS");
        address teamMultisig = vm.envAddress("TEAM_MULTISIG_ADDRESS");
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        address deterministicFactory =
            vm.envAddress("DETERMINISTIC_FACTORY_ADDRESS");

        address feeManager = vm.envAddress("FEE_MANAGER_ADDRESS");
        address forwarder = vm.envAddress("TRANSACTION_FORWARDER_ADDRESS");
        address reverter = vm.envAddress("INVERTER_REVERTER_ADDRESS");
        address governor = vm.envAddress("GOVERNOR_ADDRESS");

        address formula = vm.envAddress("BANCOR_FORMULA_ADDRESS");
        address ooV3 = vm.envAddress("OPTIMISTIC_ORACLE_V3_ADDRESS");
        address mockUSDToken = vm.envAddress("MOCK_USD_TOKEN_ADDRESS");

        chain_state = DeploymentState({
            orchestratorFactory: orchestratorFactory,
            moduleFactory: moduleFactory,
            communityMultisig: communityMultisig,
            teamMultisig: teamMultisig,
            treasury: treasury,
            deterministicFactory: deterministicFactory,
            feeManager: feeManager,
            forwarder: forwarder,
            reverter: reverter,
            governor: governor,
            formula: formula,
            ooV3: ooV3,
            mockUSDToken: mockUSDToken
        });

        return chain_state;
    }
}
