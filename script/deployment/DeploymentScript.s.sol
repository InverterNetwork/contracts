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

contract DeploymentScript is ModuleRegistry, Script {
    error BeaconProxyDeploymentFailed();

    // ------------------------------------------------------------------------

    // Beacon
    DeployAndSetUpInverterBeacon_v1 deployAndSetupInverterBeacon_v1 =
        new DeployAndSetUpInverterBeacon_v1();

    // ------------------------------------------------------------------------
    // Deployed Implementation Contracts

    // ------------------------------------------------------------------------
    // Beacons

    // TransactionForwarder_v1
    address forwarder;
    address forwarderBeacon;

    address governor;
    address feeManager;

    // Funding Manager
    address rebasingFundingManagerBeacon;
    address bancorBondingCurveFundingManagerBeacon;
    address restrictedBancorBondingCurveFundingManagerBeacon;
    // Authorizer
    address roleAuthorizerBeacon;
    address tokenGatedRoleAuthorizerBeacon;
    // Payment Processor
    address simplePaymentProcessorBeacon;
    address streamingPaymentProcessorBeacon;
    // Logic Module
    address bountyManagerBeacon;
    address recurringPaymentManagerBeacon;
    address paymentRouterBeacon;
    address kpiRewarderBeacon;
    // Utils
    address singleVoteGovernorBeacon;

    IModule_v1.Metadata[] initialMetadataRegistration;
    IInverterBeacon_v1[] initialBeaconRegistration;

    /// @notice Deploys all necessary factories, beacons and implementations
    /// @return factory The addresses of the fully deployed orchestrator factory. All other addresses should be accessible from this.
    function run() public virtual returns (address factory) {
        // Fetch the deployer details
        uint deployerPrivateKey = vm.envUint("ORCHESTRATOR_ADMIN_PRIVATE_KEY");
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

        feeManager = deployFeeManager.createProxy(
            reverter_Implementation, communityMultisig
        ); //@note owner of the FeeManagerBeacon will be the communityMultisig. Is that alright or should I change it to Governor? Needs more refactoring that way

        console2.log(
            "-----------------------------------------------------------------------------"
        );
        console2.log("Governance Contract \n");

        (governor, governor_Implementation) = deployGovernor.run(
            communityMultisig, teamMultisig, 1 weeks, feeManager
        );

        console2.log(
            "-----------------------------------------------------------------------------"
        );

        console2.log("Init Fee Manager \n");

        deployFeeManager.init(
            feeManager,
            address(governor),
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
        (forwarderBeacon, forwarder) = deployAndSetupInverterBeacon_v1
            .deployBeaconAndSetupProxy(
            reverter_Implementation,
            address(governor),
            forwarder_Implementation,
            1,
            0,
            0
        );

        if (
            forwarder == forwarder_Implementation
                || forwarder == forwarderBeacon
        ) {
            revert BeaconProxyDeploymentFailed();
        }

        console2.log(
            "-----------------------------------------------------------------------------"
        );
        console2.log("Deploy Modules Implementations \n");
        // Deploy implementation contracts.

        // Funding Manager
        FM_Rebasing_v1_Implementation = deployRebasingFundingManager.run();
        FM_BC_Bancor_Redeeming_VirtualSupply_v1_Implementation =
            deployBancorVirtualSupplyBondingCurveFundingManager.run();
        FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1_Implementation =
            deployRestrictedBancorVirtualSupplyBondingCurveFundingManager.run();
        // Authorizer
        AUT_Roles_v1_Implementation = deployRoleAuthorizer.run();
        AUT_TokenGated_Roles_v1_Implementation =
            deployTokenGatedRoleAuthorizer.run();
        // Payment Processor
        PP_Simple_v1_Implementation = deploySimplePaymentProcessor.run();
        PP_Streaming_v1_Implementation = deployStreamingPaymentProcessor.run();
        // Logic Module
        LM_PC_Bounties_v1_Implementation = deployBountyManager.run();
        LM_PC_RecurringPayments_v1_Implementation =
            deployRecurringPaymentManager.run();
        LM_PC_PaymentRouter_v1_Implementation = deployPaymentRouter.run();
        LM_PC_KPIRewarder_v1_Implementation = deployKPIRewarder.run();
        // Utils
        AUT_EXT_VotingRoles_v1_Implementation = deploySingleVoteGovernor.run();

        console2.log(
            "-----------------------------------------------------------------------------"
        );
        console2.log(
            "Deploy module beacons and register in module factory v1 \n"
        );
        // Deploy Modules and fill the intitial init list

        // Funding Manager

        initialMetadataRegistration.push(FM_Rebasing_v1_Metadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                deployAndSetupInverterBeacon_v1.deployInverterBeacon(
                    reverter_Implementation,
                    address(governor),
                    FM_Rebasing_v1_Implementation,
                    FM_Rebasing_v1_Metadata.majorVersion,
                    FM_Rebasing_v1_Metadata.minorVersion,
                    FM_Rebasing_v1_Metadata.patchVersion
                )
            )
        );
        initialMetadataRegistration.push(
            FM_BC_Bancor_Redeeming_VirtualSupply_v1_Metadata
        );
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                deployAndSetupInverterBeacon_v1.deployInverterBeacon(
                    reverter_Implementation,
                    address(governor),
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
        initialMetadataRegistration.push(
            FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1_Metadata
        );

        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                deployAndSetupInverterBeacon_v1.deployInverterBeacon(
                    reverter_Implementation,
                    address(governor),
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
        // Authorizer
        initialMetadataRegistration.push(AUT_Roles_v1_Metadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                deployAndSetupInverterBeacon_v1.deployInverterBeacon(
                    reverter_Implementation,
                    address(governor),
                    AUT_Roles_v1_Implementation,
                    AUT_Roles_v1_Metadata.majorVersion,
                    AUT_Roles_v1_Metadata.minorVersion,
                    AUT_Roles_v1_Metadata.patchVersion
                )
            )
        );
        initialMetadataRegistration.push(AUT_TokenGated_Roles_v1_Metadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                deployAndSetupInverterBeacon_v1.deployInverterBeacon(
                    reverter_Implementation,
                    address(governor),
                    AUT_TokenGated_Roles_v1_Implementation,
                    AUT_TokenGated_Roles_v1_Metadata.majorVersion,
                    AUT_TokenGated_Roles_v1_Metadata.minorVersion,
                    AUT_TokenGated_Roles_v1_Metadata.patchVersion
                )
            )
        );

        initialMetadataRegistration.push(AUT_EXT_VotingRoles_v1_Metadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                deployAndSetupInverterBeacon_v1.deployInverterBeacon(
                    reverter_Implementation,
                    address(governor),
                    AUT_EXT_VotingRoles_v1_Implementation,
                    AUT_EXT_VotingRoles_v1_Metadata.majorVersion,
                    AUT_EXT_VotingRoles_v1_Metadata.minorVersion,
                    AUT_EXT_VotingRoles_v1_Metadata.patchVersion
                )
            )
        );
        // Payment Processor
        initialMetadataRegistration.push(PP_Simple_v1_Metadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                deployAndSetupInverterBeacon_v1.deployInverterBeacon(
                    reverter_Implementation,
                    address(governor),
                    PP_Simple_v1_Implementation,
                    PP_Simple_v1_Metadata.majorVersion,
                    PP_Simple_v1_Metadata.minorVersion,
                    PP_Simple_v1_Metadata.patchVersion
                )
            )
        );
        initialMetadataRegistration.push(PP_Streaming_v1_Metadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                deployAndSetupInverterBeacon_v1.deployInverterBeacon(
                    reverter_Implementation,
                    address(governor),
                    PP_Streaming_v1_Implementation,
                    PP_Streaming_v1_Metadata.majorVersion,
                    PP_Streaming_v1_Metadata.minorVersion,
                    PP_Streaming_v1_Metadata.patchVersion
                )
            )
        );
        // Logic Module
        initialMetadataRegistration.push(LM_PC_Bounties_v1_Metadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                deployAndSetupInverterBeacon_v1.deployInverterBeacon(
                    reverter_Implementation,
                    address(governor),
                    LM_PC_Bounties_v1_Implementation,
                    LM_PC_Bounties_v1_Metadata.majorVersion,
                    LM_PC_Bounties_v1_Metadata.minorVersion,
                    LM_PC_Bounties_v1_Metadata.patchVersion
                )
            )
        );
        initialMetadataRegistration.push(LM_PC_RecurringPayments_v1_Metadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                deployAndSetupInverterBeacon_v1.deployInverterBeacon(
                    reverter_Implementation,
                    address(governor),
                    LM_PC_RecurringPayments_v1_Implementation,
                    LM_PC_RecurringPayments_v1_Metadata.majorVersion,
                    LM_PC_RecurringPayments_v1_Metadata.minorVersion,
                    LM_PC_RecurringPayments_v1_Metadata.patchVersion
                )
            )
        );
        initialMetadataRegistration.push(LM_PC_KPIRewarder_v1_Metadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                deployAndSetupInverterBeacon_v1.deployInverterBeacon(
                    reverter_Implementation,
                    address(governor),
                    LM_PC_KPIRewarder_v1_Implementation,
                    LM_PC_KPIRewarder_v1_Metadata.majorVersion,
                    LM_PC_KPIRewarder_v1_Metadata.minorVersion,
                    LM_PC_KPIRewarder_v1_Metadata.patchVersion
                )
            )
        );
        initialMetadataRegistration.push(LM_PC_PaymentRouter_v1_Metadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                deployAndSetupInverterBeacon_v1.deployInverterBeacon(
                    reverter_Implementation,
                    address(governor),
                    LM_PC_PaymentRouter_v1_Implementation,
                    LM_PC_PaymentRouter_v1_Metadata.majorVersion,
                    LM_PC_PaymentRouter_v1_Metadata.minorVersion,
                    LM_PC_PaymentRouter_v1_Metadata.patchVersion
                )
            )
        );

        console2.log(
            "-----------------------------------------------------------------------------"
        );
        console2.log("Deploy factory implementations \n");

        // Deploy module factory v1 implementation
        moduleFactory = deployModuleFactory.run(
            reverter_Implementation,
            forwarder,
            address(governor),
            initialMetadataRegistration,
            initialBeaconRegistration
        );

        // Deploy orchestrator Factory implementation
        orchestratorFactory = deployOrchestratorFactory.run(
            address(governor),
            orchestrator_Implementation,
            moduleFactory,
            forwarder
        );

        console2.log(
            "-----------------------------------------------------------------------------"
        );

        return (orchestratorFactory);
    }
}
