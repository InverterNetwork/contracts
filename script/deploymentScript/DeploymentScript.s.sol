// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {ModuleBeaconDeployer_v1} from
    "script/deploymentSuite/ModuleBeaconDeployer_v1.s.sol";

import {Governor_v1} from "@ex/governance/Governor_v1.sol";
import {FeeManager_v1} from "@ex/fees/FeeManager_v1.sol";
import {ModuleFactory_v1} from "src/factories/ModuleFactory_v1.sol";
import {OrchestratorFactory_v1} from "src/factories/OrchestratorFactory_v1.sol";

/**
 * @title Inverter Deployment Script
 *
 * @dev Script to deploy the Inverter protocol. Relies on certain contracts
 *      being deployed externally, like the DeterministicFactory - and the
 *      multisigs and treasury being set as well. These need to be set in the
 *      environment variables.
 *
 * @author Inverter Network
 */
contract DeploymentScript is ModuleBeaconDeployer_v1 {
    address public inverterReverter;

    address public governor;
    address public forwarder;
    address public feeManager;

    address public moduleFactory;
    address public orchestratorFactory;

    function run() public virtual {
        console2.log("\n");
        console2.log(
            "================================================================================"
        );
        console2.log("Start Core Protocol Deployment Script");
        console2.log(
            "================================================================================"
        );

        logProtocolMultisigsAndAddresses();

        // Create External Singletons
        createExternalSingletons();

        // Set InverterReverter Implementation Address to general InverterReverter Address
        inverterReverter = impl_ext_InverterReverter_v1;

        // Deploy External Contracts
        console2.log(
            "--------------------------------------------------------------------------------\n"
        );
        console2.log("Deploy External Contracts");

        governor = proxyAndBeaconDeployer.deployBeaconAndSetupProxy(
            governorMetadata.title,
            inverterReverter,
            communityMultisig,
            impl_ext_Governor_v1,
            governorMetadata.majorVersion,
            governorMetadata.minorVersion,
            governorMetadata.patchVersion
        );

        forwarder = proxyAndBeaconDeployer.deployBeaconAndSetupProxy(
            forwarderMetadata.title,
            inverterReverter,
            governor,
            impl_ext_TransactionForwarder_v1,
            forwarderMetadata.majorVersion,
            forwarderMetadata.minorVersion,
            forwarderMetadata.patchVersion
        );

        feeManager = proxyAndBeaconDeployer.deployBeaconAndSetupProxy(
            feeManagerMetadata.title,
            inverterReverter,
            governor,
            impl_ext_FeeManager_v1,
            feeManagerMetadata.majorVersion,
            feeManagerMetadata.minorVersion,
            feeManagerMetadata.patchVersion
        );

        // Deploy Module,Orchestrator and Factory Singletons
        createWorkflowAndFactorySingletons(forwarder);

        // Deploy Factory Contracts
        console2.log(
            "--------------------------------------------------------------------------------"
        );
        console2.log("Deploy Factory Contracts");

        moduleFactory = proxyAndBeaconDeployer.deployBeaconAndSetupProxy(
            moduleFactoryMetadata.title,
            inverterReverter,
            governor,
            impl_fac_ModuleFactory_v1,
            moduleFactoryMetadata.majorVersion,
            moduleFactoryMetadata.minorVersion,
            moduleFactoryMetadata.patchVersion
        );

        orchestratorFactory = proxyAndBeaconDeployer.deployBeaconAndSetupProxy(
            orchestratorFactoryMetadata.title,
            inverterReverter,
            governor,
            impl_fac_OrchestratorFactory_v1,
            orchestratorFactoryMetadata.majorVersion,
            orchestratorFactoryMetadata.minorVersion,
            orchestratorFactoryMetadata.patchVersion
        );

        // Deploy Module Beacons
        deployModuleBeaconsAndFillRegistrationData(inverterReverter, governor);

        // Initialize Protocol Contracts
        console2.log(
            "\n--------------------------------------------------------------------------------"
        );
        console2.log("Initialize Protocol Contracts");

        logProtocolConfigurationData();

        console2.log(
            "--------------------------------------------------------------------------------"
        );
        console2.log("Initializing...");
        // Governor
        Governor_v1(governor).init(
            communityMultisig, teamMultisig, governor_timelockPeriod, feeManager
        );
        console2.log("\t...Governor Initialized");

        // FeeManager
        FeeManager_v1(feeManager).init(
            governor,
            treasury,
            feeManager_defaultCollateralFee,
            feeManager_defaultIssuanceFee
        );
        console2.log("\t...FeeManager Initialized");

        // ModuleFactory
        ModuleFactory_v1(moduleFactory).init(
            governor, initialMetadataRegistration, initialBeaconRegistration
        );
        console2.log("\t...ModuleFactory Initialized");

        // OrchestratorFactory
        OrchestratorFactory_v1(orchestratorFactory).init(
            governor, orchestratorBeacon, moduleFactory
        );
        console2.log("\t...OrchestratorFactory Initialized");
    }
}
