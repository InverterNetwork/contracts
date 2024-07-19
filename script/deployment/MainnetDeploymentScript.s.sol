// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {ModuleRegistry} from "script/ModuleRegistry.sol";

// Import interfaces:

import {IModule_v1} from "src/modules/base/IModule_v1.sol";
import {IModuleFactory_v1} from "src/factories/ModuleFactory_v1.sol";
import {IInverterBeacon_v1} from "src/proxies/interfaces/IInverterBeacon_v1.sol";

// Import scripts:
import {DeployAndSetUpInverterBeacon_v1} from
    "script/proxies/DeployAndSetUpInverterBeacon_v1.s.sol";

contract MainnetDeploymentScript is ModuleRegistry {
    error BeaconProxyDeploymentFailed();

    // ------------------------------------------------------------------------

    // Beacon Deployment Script
    DeployAndSetUpInverterBeacon_v1 deployAndSetupInverterBeacon_v1 =
        new DeployAndSetUpInverterBeacon_v1();

    // TransactionForwarder_v1
    address forwarder_Proxy;
    address forwarder_Beacon;

    address governor_Proxy;
    address feeManager_Proxy;

    IModule_v1.Metadata[] initialMetadataRegistration;
    IInverterBeacon_v1[] initialBeaconRegistration;

    /// @notice Deploys all necessary factories, beacons and implementations
    /// @return factory The addresses of the fully deployed orchestrator factory. All other addresses should be accessible from this.
    function run() public virtual returns (address factory) {
        // TODO: Salted deployments! Check where the commit is and add it.

        // Fetch the deployer details
        uint deployerPrivateKey = vm.envUint("WALLET_DEPLOYER_PK");
        address deployer = vm.addr(deployerPrivateKey);

        // Fetch the Multisig addresses
        address communityMultisig = vm.envAddress("COMMUNITY_MULTISIG_ADDRESS");
        address teamMultisig = vm.envAddress("TEAM_MULTISIG_ADDRESS");

        // Fetch the treasury address
        address treasury = vm.envAddress("TREASURY_ADDRESS");

        console2.log(
            "-----------------------------------------------------------------------------"
        );
        console2.log("Deploy reverter\n");
        // Reverter
        reverter_Implementation = deployInverterReverter.run();

        console2.log(
            "-----------------------------------------------------------------------------"
        );

        console2.log("Deploy Fee Manager \n");

        feeManager_Proxy = deployFeeManager.createProxy(
            reverter_Implementation, communityMultisig
        ); //@note owner of the FeeManagerBeacon will be the communityMultisig. Is that alright or should I change it to Governor? Needs more refactoring that way

        console2.log(
            "-----------------------------------------------------------------------------"
        );
        console2.log("Governance Contract \n");

        (governor_Proxy, governor_Implementation) = deployGovernor.run(
            communityMultisig, teamMultisig, 1 weeks, feeManager_Proxy
        );

        console2.log(
            "-----------------------------------------------------------------------------"
        );

        console2.log("Init Fee Manager \n");

        deployFeeManager.init(
            feeManager_Proxy,
            address(governor_Proxy),
            treasury, // treasury
            100, // Collateral Fee 1%
            100 // Issuance Fee 1%
        );

        console2.log(
            "-----------------------------------------------------------------------------"
        );

        console2.log("Deploy orchestrator implementation \n");
        // Orchestrator_v1
        orchestrator_Implementation = deployOrchestrator.run();

        console2.log(
            "-----------------------------------------------------------------------------"
        );
        console2.log("Deploy forwarder implementation and proxy \n");
        // Deploy TransactionForwarder_v1 implementation
        forwarder_Implementation = deployTransactionForwarder.run();

        // Deploy beacon and actual proxy
        (forwarder_Beacon, forwarder_Proxy) = deployAndSetupInverterBeacon_v1
            .deployBeaconAndSetupProxy(
            reverter_Implementation,
            address(governor_Proxy),
            forwarder_Implementation,
            1,
            0,
            0
        );

        if (
            forwarder_Proxy == forwarder_Implementation
                || forwarder_Proxy == forwarder_Beacon
        ) {
            revert BeaconProxyDeploymentFailed();
        }

        // =============================================================================
        // Deploy Module Implementations, Beacons and prepare their metadata registration
        // =============================================================================

        console2.log(
            "-----------------------------------------------------------------------------"
        );
        console2.log(
            "Deploy module implementations, beacons and register in module factory v1 \n"
        );

        // Deploy Modules and fill the intitial init list

        // Funding Manager

        _setup_FundingManagers();

        // Authorizer

        _setup_Authorizers();

        // Payment Processor

        _setup_PaymentProcessors();

        // Logic Module

        _setup_LogicModules();

        // =============================================================================
        // Deploy Factories and register all modules
        // =============================================================================

        console2.log(
            "-----------------------------------------------------------------------------"
        );
        console2.log("Deploy factory implementations \n");

        // Deploy module factory v1 implementation
        moduleFactory = deployModuleFactory.run(
            reverter_Implementation,
            forwarder_Proxy,
            address(governor_Proxy),
            initialMetadataRegistration,
            initialBeaconRegistration
        );

        // Deploy orchestrator Factory implementation
        orchestratorFactory = deployOrchestratorFactory.run(
            address(governor_Proxy),
            orchestrator_Implementation,
            moduleFactory,
            forwarder_Proxy
        );

        console2.log(
            "-----------------------------------------------------------------------------"
        );

        return (orchestratorFactory);
    }

    function _setup_FundingManagers() internal {
        // Rebasing Funding Manager
        FM_Rebasing_v1_Implementation =
            deployImplementation(FM_Rebasing_v1_Metadata.title);
        initialMetadataRegistration.push(FM_Rebasing_v1_Metadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                deployAndSetupInverterBeacon_v1.deployInverterBeacon(
                    reverter_Implementation,
                    address(governor_Proxy),
                    FM_Rebasing_v1_Implementation,
                    FM_Rebasing_v1_Metadata.majorVersion,
                    FM_Rebasing_v1_Metadata.minorVersion,
                    FM_Rebasing_v1_Metadata.patchVersion
                )
            )
        );

        // Bancor Virtual Supply Bonding Curve Funding Manager
        FM_BC_Bancor_Redeeming_VirtualSupply_v1_Implementation =
        deployImplementation(
            FM_BC_Bancor_Redeeming_VirtualSupply_v1_Metadata.title
        );

        initialMetadataRegistration.push(
            FM_BC_Bancor_Redeeming_VirtualSupply_v1_Metadata
        );

        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                deployAndSetupInverterBeacon_v1.deployInverterBeacon(
                    reverter_Implementation,
                    address(governor_Proxy),
                    FM_BC_Bancor_Redeeming_VirtualSupply_v1_Implementation,
                    FM_BC_Bancor_Redeeming_VirtualSupply_v1_Metadata
                        .majorVersion,
                    FM_BC_Bancor_Redeeming_VirtualSupply_v1_Metadata
                        .minorVersion,
                    FM_BC_Bancor_Redeeming_VirtualSupply_v1_Metadata
                        .patchVersion
                )
            )
        );

        // Restricted Bancor Virtual Supply Bonding Curve Funding Manager
        FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1_Implementation =
        deployImplementation(
            FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1_Metadata.title
        );

        initialMetadataRegistration.push(
            FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1_Metadata
        );

        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                deployAndSetupInverterBeacon_v1.deployInverterBeacon(
                    reverter_Implementation,
                    address(governor_Proxy),
                    FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1_Implementation,
                    FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1_Metadata
                        .majorVersion,
                    FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1_Metadata
                        .minorVersion,
                    FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1_Metadata
                        .patchVersion
                )
            )
        );
    }

    function _setup_Authorizers() internal {
        // RoleAuthorizer
        AUT_Roles_v1_Implementation = deployRoleAuthorizer.run();

        initialMetadataRegistration.push(AUT_Roles_v1_Metadata);

        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                deployAndSetupInverterBeacon_v1.deployInverterBeacon(
                    reverter_Implementation,
                    address(governor_Proxy),
                    AUT_Roles_v1_Implementation,
                    AUT_Roles_v1_Metadata.majorVersion,
                    AUT_Roles_v1_Metadata.minorVersion,
                    AUT_Roles_v1_Metadata.patchVersion
                )
            )
        );

        // TokenGated RoleAuthorizer
        AUT_TokenGated_Roles_v1_Implementation =
            deployTokenGatedRoleAuthorizer.run();

        initialMetadataRegistration.push(AUT_TokenGated_Roles_v1_Metadata);

        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                deployAndSetupInverterBeacon_v1.deployInverterBeacon(
                    reverter_Implementation,
                    address(governor_Proxy),
                    AUT_TokenGated_Roles_v1_Implementation,
                    AUT_TokenGated_Roles_v1_Metadata.majorVersion,
                    AUT_TokenGated_Roles_v1_Metadata.minorVersion,
                    AUT_TokenGated_Roles_v1_Metadata.patchVersion
                )
            )
        );

        // Single Vote Governor
        AUT_EXT_VotingRoles_v1_Implementation = deploySingleVoteGovernor.run();
        initialMetadataRegistration.push(AUT_EXT_VotingRoles_v1_Metadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                deployAndSetupInverterBeacon_v1.deployInverterBeacon(
                    reverter_Implementation,
                    address(governor_Proxy),
                    AUT_EXT_VotingRoles_v1_Implementation,
                    AUT_EXT_VotingRoles_v1_Metadata.majorVersion,
                    AUT_EXT_VotingRoles_v1_Metadata.minorVersion,
                    AUT_EXT_VotingRoles_v1_Metadata.patchVersion
                )
            )
        );
    }

    function _setup_PaymentProcessors() internal {
        //  Simple Payment Processor
        PP_Simple_v1_Implementation = deploySimplePaymentProcessor.run();

        initialMetadataRegistration.push(PP_Simple_v1_Metadata);

        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                deployAndSetupInverterBeacon_v1.deployInverterBeacon(
                    reverter_Implementation,
                    address(governor_Proxy),
                    PP_Simple_v1_Implementation,
                    PP_Simple_v1_Metadata.majorVersion,
                    PP_Simple_v1_Metadata.minorVersion,
                    PP_Simple_v1_Metadata.patchVersion
                )
            )
        );

        //  Streaming Payment Processor
        PP_Streaming_v1_Implementation = deployStreamingPaymentProcessor.run();

        initialMetadataRegistration.push(PP_Streaming_v1_Metadata);

        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                deployAndSetupInverterBeacon_v1.deployInverterBeacon(
                    reverter_Implementation,
                    address(governor_Proxy),
                    PP_Streaming_v1_Implementation,
                    PP_Streaming_v1_Metadata.majorVersion,
                    PP_Streaming_v1_Metadata.minorVersion,
                    PP_Streaming_v1_Metadata.patchVersion
                )
            )
        );
    }

    function _setup_LogicModules() internal {
        // Bounty Manager
        LM_PC_Bounties_v1_Implementation = deployBountyManager.run();

        initialMetadataRegistration.push(LM_PC_Bounties_v1_Metadata);

        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                deployAndSetupInverterBeacon_v1.deployInverterBeacon(
                    reverter_Implementation,
                    address(governor_Proxy),
                    LM_PC_Bounties_v1_Implementation,
                    LM_PC_Bounties_v1_Metadata.majorVersion,
                    LM_PC_Bounties_v1_Metadata.minorVersion,
                    LM_PC_Bounties_v1_Metadata.patchVersion
                )
            )
        );

        // Recurring Payment Manager
        LM_PC_RecurringPayments_v1_Implementation =
            deployRecurringPaymentManager.run();

        initialMetadataRegistration.push(LM_PC_RecurringPayments_v1_Metadata);

        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                deployAndSetupInverterBeacon_v1.deployInverterBeacon(
                    reverter_Implementation,
                    address(governor_Proxy),
                    LM_PC_RecurringPayments_v1_Implementation,
                    LM_PC_RecurringPayments_v1_Metadata.majorVersion,
                    LM_PC_RecurringPayments_v1_Metadata.minorVersion,
                    LM_PC_RecurringPayments_v1_Metadata.patchVersion
                )
            )
        );

        // Payment Router
        LM_PC_PaymentRouter_v1_Implementation = deployPaymentRouter.run();

        initialMetadataRegistration.push(LM_PC_KPIRewarder_v1_Metadata);

        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                deployAndSetupInverterBeacon_v1.deployInverterBeacon(
                    reverter_Implementation,
                    address(governor_Proxy),
                    LM_PC_KPIRewarder_v1_Implementation,
                    LM_PC_KPIRewarder_v1_Metadata.majorVersion,
                    LM_PC_KPIRewarder_v1_Metadata.minorVersion,
                    LM_PC_KPIRewarder_v1_Metadata.patchVersion
                )
            )
        );

        // KPI Rewarder
        LM_PC_KPIRewarder_v1_Implementation = deployKPIRewarder.run();

        initialMetadataRegistration.push(LM_PC_PaymentRouter_v1_Metadata);

        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                deployAndSetupInverterBeacon_v1.deployInverterBeacon(
                    reverter_Implementation,
                    address(governor_Proxy),
                    LM_PC_PaymentRouter_v1_Implementation,
                    LM_PC_PaymentRouter_v1_Metadata.majorVersion,
                    LM_PC_PaymentRouter_v1_Metadata.minorVersion,
                    LM_PC_PaymentRouter_v1_Metadata.patchVersion
                )
            )
        );
    }
}
