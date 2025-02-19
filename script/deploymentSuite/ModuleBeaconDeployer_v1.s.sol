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

        //--------------------------------------------------------------------------
        // Logic Modules

        // Bounties
        initialMetadataRegistration.push(bountiesMetadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                proxyAndBeaconDeployer.deployInverterBeacon(
                    bountiesMetadata.title,
                    reverter,
                    governor,
                    impl_mod_LM_PC_Bounties_v2,
                    bountiesMetadata.majorVersion,
                    bountiesMetadata.minorVersion,
                    bountiesMetadata.patchVersion
                )
            )
        );

        // KPIRewarder
        initialMetadataRegistration.push(kpiRewarderMetadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                proxyAndBeaconDeployer.deployInverterBeacon(
                    kpiRewarderMetadata.title,
                    reverter,
                    governor,
                    impl_mod_LM_PC_KPIRewarder_v2,
                    kpiRewarderMetadata.majorVersion,
                    kpiRewarderMetadata.minorVersion,
                    kpiRewarderMetadata.patchVersion
                )
            )
        );

        // PaymentRouter
        initialMetadataRegistration.push(paymentRouterMetadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                proxyAndBeaconDeployer.deployInverterBeacon(
                    paymentRouterMetadata.title,
                    reverter,
                    governor,
                    impl_mod_LM_PC_PaymentRouter_v2,
                    paymentRouterMetadata.majorVersion,
                    paymentRouterMetadata.minorVersion,
                    paymentRouterMetadata.patchVersion
                )
            )
        );

        // RecurringPayments
        initialMetadataRegistration.push(recurringPaymentsMetadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                proxyAndBeaconDeployer.deployInverterBeacon(
                    recurringPaymentsMetadata.title,
                    reverter,
                    governor,
                    impl_mod_LM_PC_RecurringPayments_v2,
                    recurringPaymentsMetadata.majorVersion,
                    recurringPaymentsMetadata.minorVersion,
                    recurringPaymentsMetadata.patchVersion
                )
            )
        );

        // Staking
        initialMetadataRegistration.push(stakingMetadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                proxyAndBeaconDeployer.deployInverterBeacon(
                    stakingMetadata.title,
                    reverter,
                    governor,
                    impl_mod_LM_PC_Staking_v2,
                    stakingMetadata.majorVersion,
                    stakingMetadata.minorVersion,
                    stakingMetadata.patchVersion
                )
            )
        );

        //--------------------------------------------------------------------------
        // Payment Processors

        // SimplePaymentProcessor
        initialMetadataRegistration.push(simplePaymentProcessorMetadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                proxyAndBeaconDeployer.deployInverterBeacon(
                    simplePaymentProcessorMetadata.title,
                    reverter,
                    governor,
                    impl_mod_PP_Simple_v1,
                    simplePaymentProcessorMetadata.majorVersion,
                    simplePaymentProcessorMetadata.minorVersion,
                    simplePaymentProcessorMetadata.patchVersion
                )
            )
        );

        // StreamingPaymentProcessor
        initialMetadataRegistration.push(streamingPaymentProcessorMetadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                proxyAndBeaconDeployer.deployInverterBeacon(
                    streamingPaymentProcessorMetadata.title,
                    reverter,
                    governor,
                    impl_mod_PP_Streaming_v2,
                    streamingPaymentProcessorMetadata.majorVersion,
                    streamingPaymentProcessorMetadata.minorVersion,
                    streamingPaymentProcessorMetadata.patchVersion
                )
            )
        );
    }
}
