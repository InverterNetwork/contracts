// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

// Scripts
import {SingletonDeployer_v1} from
    "script/deploymentSuite/SingletonDeployer_v1.s.sol";
import {MetadataCollection_v1} from
    "script/deploymentSuite/MetadataCollection_v1.s.sol";
import {ProxyAndBeaconDeployer_v1} from
    "script/deploymentSuite/ProxyAndBeaconDeployer_v1.s.sol";

// Interfaces
import {IInverterBeacon_v1} from "src/proxies/interfaces/IInverterBeacon_v1.sol";
import {IModule_v1} from "src/modules/base/IModule_v1.sol";

/**
 * @title Inverter Module Beacon Deployer Script
 *
 * @dev Script to deploy and setup InverterBeacon_v1's for all modules.
 *
 * @author Inverter Network
 */
contract ModuleBeaconDeployer_v1 is
    SingletonDeployer_v1,
    MetadataCollection_v1
{
    ProxyAndBeaconDeployer_v1 public proxyAndBeaconDeployer =
        new ProxyAndBeaconDeployer_v1();

    // ModuleFactory Registration Data
    IModule_v1.Metadata[] initialMetadataRegistration;
    IInverterBeacon_v1[] initialBeaconRegistration;

    // Orchestrator Beacon
    IInverterBeacon_v1 orchestratorBeacon;

    function deployModuleBeaconsAndFillRegistrationData(
        address reverter,
        address governor
    ) public {
        console2.log(
            "--------------------------------------------------------------------------------"
        );
        console2.log(" Deploy Module Beacons and Set Registration Data");

        // Create Orchestrator Beacon
        orchestratorBeacon = IInverterBeacon_v1(
            proxyAndBeaconDeployer.deployInverterBeacon(
                orchestratorMetadata.title,
                reverter,
                governor,
                impl_orc_Orchestrator_v1,
                orchestratorMetadata.majorVersion,
                orchestratorMetadata.minorVersion,
                orchestratorMetadata.patchVersion
            )
        );

        //--------------------------------------------------------------------------
        // Authorizer

        // RoleAuthorizer
        initialMetadataRegistration.push(roleAuthorizerMetadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                proxyAndBeaconDeployer.deployInverterBeacon(
                    roleAuthorizerMetadata.title,
                    reverter,
                    governor,
                    impl_mod_Aut_Roles_v1,
                    roleAuthorizerMetadata.majorVersion,
                    roleAuthorizerMetadata.minorVersion,
                    roleAuthorizerMetadata.patchVersion
                )
            )
        );

        // TokenGatedRoleAuthorizer
        initialMetadataRegistration.push(tokenGatedRoleAuthorizerMetadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                proxyAndBeaconDeployer.deployInverterBeacon(
                    tokenGatedRoleAuthorizerMetadata.title,
                    reverter,
                    governor,
                    impl_mod_Aut_TokenGated_Roles_v1,
                    tokenGatedRoleAuthorizerMetadata.majorVersion,
                    tokenGatedRoleAuthorizerMetadata.minorVersion,
                    tokenGatedRoleAuthorizerMetadata.patchVersion
                )
            )
        );

        // VotingRoles
        initialMetadataRegistration.push(votingRolesMetadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                proxyAndBeaconDeployer.deployInverterBeacon(
                    votingRolesMetadata.title,
                    reverter,
                    governor,
                    impl_mod_Aut_Ext_VotingRoles_v1,
                    votingRolesMetadata.majorVersion,
                    votingRolesMetadata.minorVersion,
                    votingRolesMetadata.patchVersion
                )
            )
        );

        //--------------------------------------------------------------------------
        // Funding Managers

        // BancorRedeemingVirtualSupplyFundingManager
        initialMetadataRegistration.push(
            bancorRedeemingVirtualSupplyFundingManagerMetadata
        );
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                proxyAndBeaconDeployer.deployInverterBeacon(
                    bancorRedeemingVirtualSupplyFundingManagerMetadata.title,
                    reverter,
                    governor,
                    impl_mod_FM_BC_Bancor_Redeeming_VirtualSupply_v1,
                    bancorRedeemingVirtualSupplyFundingManagerMetadata
                        .majorVersion,
                    bancorRedeemingVirtualSupplyFundingManagerMetadata
                        .minorVersion,
                    bancorRedeemingVirtualSupplyFundingManagerMetadata
                        .patchVersion
                )
            )
        );

        // RestrictedBancorRedeemingVirtualSupplyFundingManager
        initialMetadataRegistration.push(
            restrictedBancorRedeemingVirtualSupplyFundingManagerMetadata
        );
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                proxyAndBeaconDeployer.deployInverterBeacon(
                    restrictedBancorRedeemingVirtualSupplyFundingManagerMetadata
                        .title,
                    reverter,
                    governor,
                    impl_mod_FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1,
                    restrictedBancorRedeemingVirtualSupplyFundingManagerMetadata
                        .majorVersion,
                    restrictedBancorRedeemingVirtualSupplyFundingManagerMetadata
                        .minorVersion,
                    restrictedBancorRedeemingVirtualSupplyFundingManagerMetadata
                        .patchVersion
                )
            )
        );

        // BondingSurfaceRedeemingFundingManager
        initialMetadataRegistration.push(
            bondingSurfaceRedeemingFundingManagerMetadata
        );
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                proxyAndBeaconDeployer.deployInverterBeacon(
                    bondingSurfaceRedeemingFundingManagerMetadata.title,
                    reverter,
                    governor,
                    impl_mod_FM_BC_BondingSurface_Redeeming_v1,
                    bondingSurfaceRedeemingFundingManagerMetadata.majorVersion,
                    bondingSurfaceRedeemingFundingManagerMetadata.minorVersion,
                    bondingSurfaceRedeemingFundingManagerMetadata.patchVersion
                )
            )
        );

        // BondingSurfaceRedeemingRestrictedRepayerSeizableFundingManager
        initialMetadataRegistration.push(
            bondingSurfaceRedeemingRestrictedRepayerSeizableFundingManagerMetadata
        );
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                proxyAndBeaconDeployer.deployInverterBeacon(
                    bondingSurfaceRedeemingRestrictedRepayerSeizableFundingManagerMetadata
                        .title,
                    reverter,
                    governor,
                    impl_mod_FM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1,
                    bondingSurfaceRedeemingRestrictedRepayerSeizableFundingManagerMetadata
                        .majorVersion,
                    bondingSurfaceRedeemingRestrictedRepayerSeizableFundingManagerMetadata
                        .minorVersion,
                    bondingSurfaceRedeemingRestrictedRepayerSeizableFundingManagerMetadata
                        .patchVersion
                )
            )
        );

        // DepositVaultFundingManager
        initialMetadataRegistration.push(depositVaultFundingManagerMetadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                proxyAndBeaconDeployer.deployInverterBeacon(
                    depositVaultFundingManagerMetadata.title,
                    reverter,
                    governor,
                    impl_mod_FM_DepositVault_v1,
                    depositVaultFundingManagerMetadata.majorVersion,
                    depositVaultFundingManagerMetadata.minorVersion,
                    depositVaultFundingManagerMetadata.patchVersion
                )
            )
        );

        // OracleRedeemingFundingManager
        initialMetadataRegistration.push(oracleRedeemingFundingManagerMetadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                proxyAndBeaconDeployer.deployInverterBeacon(
                    oracleRedeemingFundingManagerMetadata.title,
                    reverter,
                    governor,
                    impl_mod_FM_PC_Oracle_Redeeming_v1,
                    oracleRedeemingFundingManagerMetadata.majorVersion,
                    oracleRedeemingFundingManagerMetadata.minorVersion,
                    oracleRedeemingFundingManagerMetadata.patchVersion
                )
            )
        );

        // Funding Managers - Extensions

        // TokenVault
        initialMetadataRegistration.push(tokenVaultMetadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                proxyAndBeaconDeployer.deployInverterBeacon(
                    tokenVaultMetadata.title,
                    reverter,
                    governor,
                    impl_mod_FM_EXT_TokenVault_v1,
                    tokenVaultMetadata.majorVersion,
                    tokenVaultMetadata.minorVersion,
                    tokenVaultMetadata.patchVersion
                )
            )
        );

        //--------------------------------------------------------------------------
        // Logic Modules

        // Oracle_Permissioned
        initialMetadataRegistration.push(oraclePermissionedMetadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                proxyAndBeaconDeployer.deployInverterBeacon(
                    oraclePermissionedMetadata.title,
                    reverter,
                    governor,
                    impl_mod_LM_PC_Oracle_Permissioned_v1,
                    oraclePermissionedMetadata.majorVersion,
                    oraclePermissionedMetadata.minorVersion,
                    oraclePermissionedMetadata.patchVersion
                )
            )
        );

        // Bounties
        initialMetadataRegistration.push(bountiesV1Metadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                proxyAndBeaconDeployer.deployInverterBeacon(
                    bountiesV1Metadata.title,
                    reverter,
                    governor,
                    impl_mod_LM_PC_Bounties_v1,
                    bountiesV1Metadata.majorVersion,
                    bountiesV1Metadata.minorVersion,
                    bountiesV1Metadata.patchVersion
                )
            )
        );

        initialMetadataRegistration.push(bountiesV2Metadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                proxyAndBeaconDeployer.deployInverterBeacon(
                    bountiesV2Metadata.title,
                    reverter,
                    governor,
                    impl_mod_LM_PC_Bounties_v2,
                    bountiesV2Metadata.majorVersion,
                    bountiesV2Metadata.minorVersion,
                    bountiesV2Metadata.patchVersion
                )
            )
        );

        // KPIRewarder
        initialMetadataRegistration.push(kpiRewarderV1Metadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                proxyAndBeaconDeployer.deployInverterBeacon(
                    kpiRewarderV1Metadata.title,
                    reverter,
                    governor,
                    impl_mod_LM_PC_KPIRewarder_v1,
                    kpiRewarderV1Metadata.majorVersion,
                    kpiRewarderV1Metadata.minorVersion,
                    kpiRewarderV1Metadata.patchVersion
                )
            )
        );

        initialMetadataRegistration.push(kpiRewarderV2Metadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                proxyAndBeaconDeployer.deployInverterBeacon(
                    kpiRewarderV2Metadata.title,
                    reverter,
                    governor,
                    impl_mod_LM_PC_KPIRewarder_v2,
                    kpiRewarderV2Metadata.majorVersion,
                    kpiRewarderV2Metadata.minorVersion,
                    kpiRewarderV2Metadata.patchVersion
                )
            )
        );

        // PaymentRouter
        initialMetadataRegistration.push(paymentRouterV1Metadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                proxyAndBeaconDeployer.deployInverterBeacon(
                    paymentRouterV1Metadata.title,
                    reverter,
                    governor,
                    impl_mod_LM_PC_PaymentRouter_v1,
                    paymentRouterV1Metadata.majorVersion,
                    paymentRouterV1Metadata.minorVersion,
                    paymentRouterV1Metadata.patchVersion
                )
            )
        );

        initialMetadataRegistration.push(paymentRouterV2Metadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                proxyAndBeaconDeployer.deployInverterBeacon(
                    paymentRouterV2Metadata.title,
                    reverter,
                    governor,
                    impl_mod_LM_PC_PaymentRouter_v2,
                    paymentRouterV2Metadata.majorVersion,
                    paymentRouterV2Metadata.minorVersion,
                    paymentRouterV2Metadata.patchVersion
                )
            )
        );

        // RecurringPayments
        initialMetadataRegistration.push(recurringPaymentsV1Metadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                proxyAndBeaconDeployer.deployInverterBeacon(
                    recurringPaymentsV1Metadata.title,
                    reverter,
                    governor,
                    impl_mod_LM_PC_RecurringPayments_v1,
                    recurringPaymentsV1Metadata.majorVersion,
                    recurringPaymentsV1Metadata.minorVersion,
                    recurringPaymentsV1Metadata.patchVersion
                )
            )
        );

        initialMetadataRegistration.push(recurringPaymentsV2Metadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                proxyAndBeaconDeployer.deployInverterBeacon(
                    recurringPaymentsV2Metadata.title,
                    reverter,
                    governor,
                    impl_mod_LM_PC_RecurringPayments_v2,
                    recurringPaymentsV2Metadata.majorVersion,
                    recurringPaymentsV2Metadata.minorVersion,
                    recurringPaymentsV2Metadata.patchVersion
                )
            )
        );

        // Staking
        initialMetadataRegistration.push(stakingV1Metadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                proxyAndBeaconDeployer.deployInverterBeacon(
                    stakingV1Metadata.title,
                    reverter,
                    governor,
                    impl_mod_LM_PC_Staking_v1,
                    stakingV1Metadata.majorVersion,
                    stakingV1Metadata.minorVersion,
                    stakingV1Metadata.patchVersion
                )
            )
        );

        initialMetadataRegistration.push(stakingV2Metadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                proxyAndBeaconDeployer.deployInverterBeacon(
                    stakingV2Metadata.title,
                    reverter,
                    governor,
                    impl_mod_LM_PC_Staking_v2,
                    stakingV2Metadata.majorVersion,
                    stakingV2Metadata.minorVersion,
                    stakingV2Metadata.patchVersion
                )
            )
        );

        //--------------------------------------------------------------------------
        // Payment Processors

        // QueueManualExecutionPaymentProcessor
        initialMetadataRegistration.push(
            queueManualExecutionPaymentProcessorMetadata
        );
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                proxyAndBeaconDeployer.deployInverterBeacon(
                    queueManualExecutionPaymentProcessorMetadata.title,
                    reverter,
                    governor,
                    impl_mod_PP_Queue_ManualExecution_v1,
                    queueManualExecutionPaymentProcessorMetadata.majorVersion,
                    queueManualExecutionPaymentProcessorMetadata.minorVersion,
                    queueManualExecutionPaymentProcessorMetadata.patchVersion
                )
            )
        );

        // QueuePaymentProcessor
        initialMetadataRegistration.push(queuePaymentProcessorMetadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                proxyAndBeaconDeployer.deployInverterBeacon(
                    queuePaymentProcessorMetadata.title,
                    reverter,
                    governor,
                    impl_mod_PP_Queue_v1,
                    queuePaymentProcessorMetadata.majorVersion,
                    queuePaymentProcessorMetadata.minorVersion,
                    queuePaymentProcessorMetadata.patchVersion
                )
            )
        );

        // SimplePaymentProcessor
        initialMetadataRegistration.push(simplePaymentProcessorV1Metadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                proxyAndBeaconDeployer.deployInverterBeacon(
                    simplePaymentProcessorV1Metadata.title,
                    reverter,
                    governor,
                    impl_mod_PP_Simple_v1,
                    simplePaymentProcessorV1Metadata.majorVersion,
                    simplePaymentProcessorV1Metadata.minorVersion,
                    simplePaymentProcessorV1Metadata.patchVersion
                )
            )
        );

        initialMetadataRegistration.push(simplePaymentProcessorV2Metadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                proxyAndBeaconDeployer.deployInverterBeacon(
                    simplePaymentProcessorV2Metadata.title,
                    reverter,
                    governor,
                    impl_mod_PP_Simple_v2,
                    simplePaymentProcessorV2Metadata.majorVersion,
                    simplePaymentProcessorV2Metadata.minorVersion,
                    simplePaymentProcessorV2Metadata.patchVersion
                )
            )
        );

        // StreamingPaymentProcessor
        initialMetadataRegistration.push(streamingPaymentProcessorV1Metadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                proxyAndBeaconDeployer.deployInverterBeacon(
                    streamingPaymentProcessorV1Metadata.title,
                    reverter,
                    governor,
                    impl_mod_PP_Streaming_v1,
                    streamingPaymentProcessorV1Metadata.majorVersion,
                    streamingPaymentProcessorV1Metadata.minorVersion,
                    streamingPaymentProcessorV1Metadata.patchVersion
                )
            )
        );

        initialMetadataRegistration.push(streamingPaymentProcessorV2Metadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                proxyAndBeaconDeployer.deployInverterBeacon(
                    streamingPaymentProcessorV2Metadata.title,
                    reverter,
                    governor,
                    impl_mod_PP_Streaming_v2,
                    streamingPaymentProcessorV2Metadata.majorVersion,
                    streamingPaymentProcessorV2Metadata.minorVersion,
                    streamingPaymentProcessorV2Metadata.patchVersion
                )
            )
        );
    }
}
