// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ModuleBeaconDeployer_v1} from "script/ModuleBeaconDeployer_v1.s.sol";

contract DeploymentScript is ModuleBeaconDeployer_v1 {
    //@note not upgradable right?
    address public inverterReverter = ext_InnverterReverter_v1;
    address public governor;
    address public forwarder;
    address public feeManager;

    address public moduleFactory;
    address public orchestratorFactory;

    //@todo do logs
    function run() public {
        //Create External Singletons
        createExternalSingletons();

        //Deploy External Contracts

        governor = proxyAndBeaconDeployer.deployBeaconAndSetupProxy(
            governorMetadata.title,
            inverterReverter,
            communityMultisig,
            ext_Governor_v1,
            governanceMetadata.majorVersion,
            governanceMetadata.minorVersion,
            governanceMetadata.patchVersion
        );

        forwarder = proxyAndBeaconDeployer.deployBeaconAndSetupProxy(
            forwarderMetadata.title,
            inverterReverter,
            governor,
            ext_TransactionForwarder_v1,
            forwarderMetadata.majorVersion,
            forwarderMetadata.minorVersion,
            forwarderMetadata.patchVersion
        );

        feeManager = proxyAndBeaconDeployer.deployBeaconAndSetupProxy(
            feeManagerMetadata.title,
            inverterReverter,
            governor,
            ext_FeeManager_v1,
            feeManagerMetadata.majorVersion,
            feeManagerMetadata.minorVersion,
            feeManagerMetadata.patchVersion
        );

        //Deploy Module,Orchestrator and Factory Singletons
        createWorkflowAndFactorySingletons(forwarder);

        //Deploy Factory Contracts
        moduleFactory = proxyAndBeaconDeployer.deployBeaconAndSetupProxy(
            moduleFactoryMetadata.title,
            inverterReverter,
            governor,
            fac_ModuleFactory_v1,
            moduleFactoryMetadata.majorVersion,
            moduleFactoryMetadata.minorVersion,
            moduleFactoryMetadata.patchVersion
        );

        orchestratorFactory = proxyAndBeaconDeployer.deployBeaconAndSetupProxy(
            orchestratorFactoryMetadata.title,
            inverterReverter,
            governor,
            fac_OrchestratorFactory_v1,
            orchestratorFactoryMetadata.majorVersion,
            orchestratorFactoryMetadata.minorVersion,
            orchestratorFactoryMetadata.patchVersion
        );

        //Deploy Module Beacons
        deployModuleBeaconsAndFillRegistrationData(reverter, forwarder);

        //Initialize Protocol Contracts

        governor.init(communityMultisig, teamMultisig, 1 weeks, feeManager);
        feeManager.init(governor, treasury, 100, 100);
        moduleFactory.init(
            governor, initialMetadataRegistration, initialBeaconRegistration
        );
        orchestratorFactory.init(governor, orchestratorBeacon, moduleFactory);
    }
}
