// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

// Scripts
import {ModuleBeaconDeployer_v1} from
    "script/deploymentSuite/ModuleBeaconDeployer_v1.s.sol";

// Interfaces
import {IDeterministicFactory_v1} from
    "@df/interfaces/IDeterministicFactory_v1.sol";

// Contracts
import {Governor_v1} from "@ex/governance/Governor_v1.sol";
import {FeeManager_v1} from "@ex/fees/FeeManager_v1.sol";
import {TransactionForwarder_v1} from
    "@ex/forwarder/TransactionForwarder_v1.sol";
import {ModuleFactory_v1} from "src/factories/ModuleFactory_v1.sol";
import {OrchestratorFactory_v1} from "src/factories/OrchestratorFactory_v1.sol";
import {
    InverterBeacon_v1,
    IInverterBeacon_v1
} from "src/proxies/InverterBeacon_v1.sol";
import {Orchestrator_v1} from "src/orchestrator/Orchestrator_v1.sol";
import {Module_v1} from "src/modules/base/Module_v1.sol";
import {Ownable} from "@oz/access/Ownable.sol";
import {EIP712} from "@oz/utils/cryptography/EIP712.sol";

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
    // Contracts
    address public inverterReverter;

    address public governor;
    address public forwarder;
    address public feeManager;

    address public moduleFactory;
    address public orchestratorFactory;

    // Beacons
    address public governorBeacon;
    address public forwarderBeacon;
    address public feeManagerBeacon;

    address public moduleFactoryBeacon;
    address public orchestratorFactoryBeacon;

    function run()
        public
        virtual
        verifyRequiredParameters
        verifyDeterministicFactory
    {
        console2.log();
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

        // Create Library Singletons
        createLibrarySingletons();

        // Set InverterReverter Implementation Address to general InverterReverter Address
        inverterReverter = impl_ext_InverterReverter_v1;

        // Deploy External Contracts
        console2.log(
            "--------------------------------------------------------------------------------"
        );
        console2.log(" Deploy External Contracts");

        (governorBeacon, governor) = proxyAndBeaconDeployer
            .deployBeaconAndSetupProxy(
            governorMetadata.title,
            inverterReverter,
            communityMultisig,
            impl_ext_Governor_v1,
            governorMetadata.majorVersion,
            governorMetadata.minorVersion,
            governorMetadata.patchVersion
        );

        (forwarderBeacon, forwarder) = proxyAndBeaconDeployer
            .deployBeaconAndSetupProxy(
            forwarderMetadata.title,
            inverterReverter,
            governor,
            impl_ext_TransactionForwarder_v1,
            forwarderMetadata.majorVersion,
            forwarderMetadata.minorVersion,
            forwarderMetadata.patchVersion
        );

        (feeManagerBeacon, feeManager) = proxyAndBeaconDeployer
            .deployBeaconAndSetupProxy(
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
        console2.log(" Deploy Factory Contracts");

        (moduleFactoryBeacon, moduleFactory) = proxyAndBeaconDeployer
            .deployBeaconAndSetupProxy(
            moduleFactoryMetadata.title,
            inverterReverter,
            governor,
            impl_fac_ModuleFactory_v1,
            moduleFactoryMetadata.majorVersion,
            moduleFactoryMetadata.minorVersion,
            moduleFactoryMetadata.patchVersion
        );

        (orchestratorFactoryBeacon, orchestratorFactory) =
        proxyAndBeaconDeployer.deployBeaconAndSetupProxy(
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
        console2.log();
        console2.log(
            "--------------------------------------------------------------------------------"
        );
        console2.log("Initialize Protocol Contracts");

        logProtocolConfigurationData();

        console2.log(
            "--------------------------------------------------------------------------------"
        );
        vm.startBroadcast(deployerPrivateKey);
        {
            console2.log(" Initializing...");

            // Governor
            Governor_v1(governor).init(
                communityMultisig,
                teamMultisig,
                governor_timelockPeriod,
                feeManager,
                moduleFactory
            );
            console2.log("\t... Governor initialized");

            // FeeManager
            FeeManager_v1(feeManager).init(
                governor,
                treasury,
                feeManager_defaultCollateralFee,
                feeManager_defaultIssuanceFee
            );
            console2.log("\t... FeeManager initialized");

            // TransactionForwarder
            TransactionForwarder_v1(forwarder).init();
            console2.log("\t... TransactionForwarder initialized");

            // ModuleFactory
            ModuleFactory_v1(moduleFactory).init(
                governor, initialMetadataRegistration, initialBeaconRegistration
            );
            console2.log("\t... ModuleFactory initialized");

            // OrchestratorFactory
            OrchestratorFactory_v1(orchestratorFactory).init(
                governor, orchestratorBeacon, moduleFactory
            );
            console2.log("\t... OrchestratorFactory initialized");
            console2.log(
                "--------------------------------------------------------------------------------"
            );
        }
        vm.stopBroadcast();

        // ------------------------------------------------------------------------
        // In order to verify that the deployment was successful, we
        // verify that the contracts have been initialized correctly and all
        // important values have been set as expected.

        verifyDeployment();

        // ------------------------------------------------------------------------
    }

    function verifyDeployment() public {
        // ------------------------------------------------------------------------
        // >>> Governor

        // Verify that the Community Multisig is set correctly
        require(
            Governor_v1(governor).hasRole(
                Governor_v1(governor).COMMUNITY_MULTISIG_ROLE(),
                communityMultisig
            ) == true,
            "Deployment failed - Governor not initialized correctly, Community Multisig is not set correctly."
        );

        // Verify that the Team Multisig is set correctly
        require(
            Governor_v1(governor).hasRole(
                Governor_v1(governor).TEAM_MULTISIG_ROLE(), teamMultisig
            ) == true,
            "Deployment failed - Governor not initialized correctly, Team Multisig is not set correctly."
        );

        // Verify that Module Factory is linked correctly
        require(
            Governor_v1(governor).getModuleFactory() == moduleFactory,
            "Deployment failed - Governor not initialized correctly, ModuleFactory is not correct."
        );

        // Verify that Fee Manager is linked correctly
        require(
            Governor_v1(governor).getFeeManager() == feeManager,
            "Deployment failed - Governor not initialized correctly, FeeManager is not correct."
        );

        // Verify that the Timelock Period is set correctly
        require(
            Governor_v1(governor).timelockPeriod() == governor_timelockPeriod,
            "Deployment failed - Governor not initialized correctly, Timelock Period is not correct."
        );

        // Verify that the Reverter is linked correctly
        require(
            IInverterBeacon_v1(governorBeacon).getReverterAddress()
                == inverterReverter,
            "Deployment failed - Governor Beacon not initialized correctly, Reverter is not correct."
        );

        // ------------------------------------------------------------------------
        // >>> ModuleFactory

        // Verify that the ModuleFactory is owned by the Governor
        require(
            ModuleFactory_v1(moduleFactory).owner() == governor,
            "Deployment failed - ModuleFactory not initialized correctly, not owned by Governor."
        );

        // Verify that the TransactionForwarder is linked correctly
        require(
            ModuleFactory_v1(moduleFactory).trustedForwarder() == forwarder,
            "Deployment failed - ModuleFactory not initialized correctly, Forwarder is not correct."
        );

        // Verify that the Reverter is linked correctly
        require(
            ModuleFactory_v1(moduleFactory).reverter() == inverterReverter,
            "Deployment failed - ModuleFactory not initialized correctly, Reverter is not correct."
        );

        // Verify that the Reverter is linked correctly
        require(
            IInverterBeacon_v1(moduleFactoryBeacon).getReverterAddress()
                == inverterReverter,
            "Deployment failed - ModuleFactory Beacon not initialized correctly, Reverter is not correct."
        );

        // ------------------------------------------------------------------------
        // >>> OrchestratorFactory

        // Verify that the ModuleFactory is linked correctly
        require(
            OrchestratorFactory_v1(orchestratorFactory).moduleFactory()
                == moduleFactory,
            "Deployment failed - OrchestratorFactory not initialized correctly, ModuleFactory is not correct."
        );

        // Verify that the TransactionForwarder is linked correctly
        require(
            OrchestratorFactory_v1(orchestratorFactory).trustedForwarder()
                == forwarder,
            "Deployment failed - OrchestratorFactory not initialized correctly, Forwarder is not correct."
        );

        // Verify that the Reverter is linked correctly
        require(
            IInverterBeacon_v1(orchestratorFactoryBeacon).getReverterAddress()
                == inverterReverter,
            "Deployment failed - OrchestratorFactory Beacon not initialized correctly, Reverter is not correct."
        );

        // ------------------------------------------------------------------------
        // >>> FeeManager

        // Verify that the FeeManager is owned by the Governor
        require(
            FeeManager_v1(feeManager).owner() == governor,
            "Deployment failed - FeeManager not initialized correctly, not owned by Governor."
        );

        // Verify that the Treasury is set correctly
        require(
            FeeManager_v1(feeManager).getDefaultProtocolTreasury() == treasury,
            "Deployment failed - FeeManager not initialized correctly, Treasury is not correct."
        );

        // Verify that the Default Collateral Fee is set correctly
        require(
            FeeManager_v1(feeManager).getDefaultCollateralFee()
                == feeManager_defaultCollateralFee,
            "Deployment failed - FeeManager not initialized correctly, Default Collateral Fee is not correct."
        );

        // Verify that the Default Issuance Fee is set correctly
        require(
            FeeManager_v1(feeManager).getDefaultIssuanceFee()
                == feeManager_defaultIssuanceFee,
            "Deployment failed - FeeManager not initialized correctly, Default Issuance Fee is not correct."
        );

        // Verify that the Reverter is linked correctly
        require(
            IInverterBeacon_v1(feeManagerBeacon).getReverterAddress()
                == inverterReverter,
            "Deployment failed - FeeManager Beacon not initialized correctly, Reverter is not correct."
        );

        // ------------------------------------------------------------------------
        // >>> TransactionForwarder

        // Verify that the TransactionForwarder has been initialized correctly
        (
            ,
            string memory _name,
            string memory _version,
            uint _chainId,
            address _verifyingContract,
            ,
        ) = EIP712(forwarder).eip712Domain();
        require(
            _chainId == block.chainid
                && keccak256(abi.encodePacked(_version))
                    == keccak256(abi.encodePacked("1"))
                && keccak256(abi.encodePacked(_name))
                    == keccak256(abi.encodePacked("Inverter TransactionForwarder_v1"))
                && _verifyingContract == forwarder,
            "Deployment failed - TransactionForwarder not initialized correctly."
        );

        // Verify that the Reverter is linked correctly
        require(
            IInverterBeacon_v1(forwarderBeacon).getReverterAddress()
                == inverterReverter,
            "Deployment failed - TransactionForwarder Beacon not initialized correctly, Reverter is not correct."
        );

        // ------------------------------------------------------------------------
        // >>> Orchestrator

        // Verify that the Orchestrator Beacon is owned by the Governor
        require(
            Ownable(address(orchestratorBeacon)).owner() == governor,
            "Deployment failed - Orchestrator Beacon not initialized correctly, not owned by Governor."
        );

        // Verify that the TransactionForwarder is linked correctly in the Orchestrator
        require(
            Orchestrator_v1(orchestratorBeacon.getImplementationAddress())
                .trustedForwarder() == forwarder,
            "Deployment failed - Orchestrator Beacon not initialized correctly, Forwarder is not correct."
        );

        // Verify that the Orchestrator Beacon references the right version
        (
            uint _orchestratorMajor,
            uint _orchestratorMinor,
            uint _orchestratorPatch
        ) = orchestratorBeacon.version();
        require(
            _orchestratorMajor == orchestratorMetadata.majorVersion
                && _orchestratorMinor == orchestratorMetadata.minorVersion
                && _orchestratorPatch == orchestratorMetadata.patchVersion,
            "Deployment failed - Orchestrator Beacon not initialized correctly, version is not correct."
        );

        // Verify that the Reverter is linked correctly
        require(
            orchestratorBeacon.getReverterAddress() == inverterReverter,
            "Deployment failed - Orchestrator Beacon not initialized correctly, Reverter is not correct."
        );

        // ------------------------------------------------------------------------
        // >>> Modules

        for (uint i; i < initialMetadataRegistration.length; i++) {
            // Verify that the Module Beacon is linked to the right metadata
            (IInverterBeacon_v1 _moduleBeacon,) = ModuleFactory_v1(
                moduleFactory
            ).getBeaconAndId(initialMetadataRegistration[i]);
            require(
                _moduleBeacon == initialBeaconRegistration[i],
                "Deployment failed - Module Metadata doesn't match registration data."
            );

            // Verify that the Module Beacon is owned by the Governor
            require(
                Ownable(address(_moduleBeacon)).owner() == governor,
                "Deployment failed - Module Beacon not initialized correctly, not owned by Governor."
            );

            // Verify that the Module Beacon references the right version
            (uint _major, uint _minor, uint _patch) = _moduleBeacon.version();
            require(
                _major == initialMetadataRegistration[i].majorVersion
                    && _minor == initialMetadataRegistration[i].minorVersion
                    && _patch == initialMetadataRegistration[i].patchVersion,
                "Deployment failed - Module Beacon not initialized correctly, version is not correct."
            );

            // Verify that the Reverter is linked correctly
            require(
                _moduleBeacon.getReverterAddress() == inverterReverter,
                "Deployment failed - Module Beacon not initialized correctly, Reverter is not correct."
            );
        }
    }

    modifier verifyRequiredParameters() {
        require(
            communityMultisig != address(0),
            "Community Multisig address not set - aborting!"
        );
        require(
            teamMultisig != address(0),
            "Team Multisig address not set - aborting!"
        );
        require(treasury != address(0), "Treasury address not set - aborting!");
        require(
            deterministicFactory != address(0),
            "Deterministic Factory address not set correctly - aborting!"
        );
        _;
    }

    modifier verifyDeterministicFactory() {
        require(
            deterministicFactory.code.length != 0,
            "Deterministic Factory does not exist at given address - aborting!"
        );
        require(
            IDeterministicFactory_v1(deterministicFactory).allowedDeployer()
                == deployer,
            "Deterministic Factory hasn't allowed the deployer - aborting!"
        );
        _;
    }
}
