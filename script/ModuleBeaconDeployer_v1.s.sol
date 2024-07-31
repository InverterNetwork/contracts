// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import {SingletonDeployer_v1} from "script/SingletonDeployer_v1.sol";

// Modules
// =============================================================================
import {Orchestrator_v1} from "src/orchestrator/Orchestrator_v1.sol";
import {IModule_v1} from "src/modules/base/IModule_v1.sol";

// Funding Managers
import {FM_Rebasing_v1} from "@fm/rebasing/FM_Rebasing_v1.sol";
import {FM_BC_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/FM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
import {FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1.sol";
import {BancorFormula} from "@fm/bondingCurve/formulas/BancorFormula.sol";

// Authorization
import {AUT_Roles_v1} from "@aut/role/AUT_Roles_v1.sol";
import {AUT_TokenGated_Roles_v1} from "@aut/role/AUT_TokenGated_Roles_v1.sol";
import {AUT_EXT_VotingRoles_v1} from
    "src/modules/authorizer/extensions/AUT_EXT_VotingRoles_v1.sol";

// Payment Processors
import {PP_Simple_v1} from "src/modules/paymentProcessor/PP_Simple_v1.sol";
import {PP_Streaming_v1} from "src/modules/paymentProcessor/PP_Streaming_v1.sol";

// Logic Modules
import {LM_PC_Bounties_v1} from "@lm/LM_PC_Bounties_v1.sol";
import {LM_PC_RecurringPayments_v1} from "@lm/LM_PC_RecurringPayments_v1.sol";
import {LM_PC_Staking_v1} from "@lm/LM_PC_Staking_v1.sol";
import {LM_PC_KPIRewarder_v1} from "@lm/LM_PC_KPIRewarder_v1.sol";
import {LM_PC_PaymentRouter_v1} from "@lm/LM_PC_PaymentRouter_v1.sol";

contract ModuleBeaconDeployer is SingletonDeployer {
    ProxyAndBeaconDeployer_v1 public proxyAndBeaconDeployer =
        new ProxyAndBeaconDeployer_v1();

    //ModuleFactory Registration Data
    IModule_v1.Metadata[] initialMetadataRegistration;
    IInverterBeacon_v1[] initialBeaconRegistration;

    // ------------------------------------------------------------------------
    // Module Metadata

    // ------------------------------------------------------------------------
    // Authorizer

    //RoleAuthorizer
    IModule_v1.Metadata roleAuthorizerMetadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "AUT_Roles_v1"
    );

    //TokenGatedRoleAuthorizer
    IModule_v1.Metadata tokenGatedRoleAuthorizerMetadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "AUT_TokenGated_Roles_v1"
    );

    //VotingRoles
    IModule_v1.Metadata votingRolesMetadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "AUT_EXT_VotingRoles_v1"
    );

    // ------------------------------------------------------------------------
    // Funding Manager

    //BancorRedeemingVirtualSupplyFundingManager
    IModule_v1.Metadata bancorRedeemingVirtualSupplyFundingManagerMetadata =
    IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "FM_BC_Bancor_Redeeming_VirtualSupply_v1"
    );

    //RestrictedBancorRedeemingVirtualSupplyFundingManager
    IModule_v1.Metadata
        restrictedBancorRedeemingVirtualSupplyFundingManagerMetadata =
        IModule_v1.Metadata(
            1,
            0,
            0,
            "https://github.com/InverterNetwork/inverter-contracts",
            "FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1"
        );

    //RebasingFundingManager
    IModule_v1.Metadata rebasingFundingManagerMetadata = IModule_v1.Metadata( //@note Do we add this?
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "FM_Rebasing_v1"
    );

    /* 
    //DepositVaultFundingManager
    IModule_v1.Metadata depositVaultFundingManagerMetadata =
    IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "FM_DepositVault_v1"
    ); */

    // ------------------------------------------------------------------------
    // Logic Module

    //Bounties
    IModule_v1.Metadata bountiesMetadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "LM_PC_Bounties_v1"
    );

    //KPIRewarder
    IModule_v1.Metadata kpiRewarderMetadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "LM_PC_KPIRewarder_v1"
    );

    //PaymentRouter
    IModule_v1.Metadata paymentRouterMetadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "LM_PC_PaymentRouter_v1"
    );

    //RecurringPayments
    IModule_v1.Metadata recurringPaymentsMetadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "LM_PC_RecurringPayments_v1"
    );

    //Staking
    IModule_v1.Metadata stakingMetadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "LM_PC_Staking_v1"
    );

    // ------------------------------------------------------------------------
    // Payment Processor

    //SimplePaymentProcessor
    IModule_v1.Metadata simplePaymentProcessorMetadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "PP_Simple_v1"
    );

    //StreamingPaymentProcessor
    IModule_v1.Metadata streamingPaymentProcessorMetadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "PP_Streaming_v1"
    );

    function deployModuleBeaconsAndFillRegistrationData(
        address reverter,
        address governor
    ) public {
        //@todo add Logs

        //--------------------------------------------------------------------------
        //Authorizer

        //RoleAuthorizer
        initialMetadataRegistration.push(roleAuthorizerMetadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                proxyAndBeaconDeployer.deployInverterBeacon(
                    reverter,
                    governor,
                    mod_Aut_Roles_v1,
                    roleAuthorizerMetadata.majorVersion,
                    roleAuthorizerMetadata.minorVersion,
                    roleAuthorizerMetadata.patchVersion
                )
            )
        );

        //TokenGatedRoleAuthorizer
        initialMetadataRegistration.push(tokenGatedRoleAuthorizerMetadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                proxyAndBeaconDeployer.deployInverterBeacon(
                    reverter,
                    governor,
                    mod_Aut_TokenGated_Roles_v1,
                    tokenGatedRoleAuthorizerMetadata.majorVersion,
                    tokenGatedRoleAuthorizerMetadata.minorVersion,
                    tokenGatedRoleAuthorizerMetadata.patchVersion
                )
            )
        );

        //VotingRoles
        initialMetadataRegistration.push(votingRolesMetadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                proxyAndBeaconDeployer.deployInverterBeacon(
                    reverter,
                    governor,
                    mod_Aut_EXT_VotingRoles_v1,
                    votingRolesMetadata.majorVersion,
                    votingRolesMetadata.minorVersion,
                    votingRolesMetadata.patchVersion
                )
            )
        );

        //--------------------------------------------------------------------------
        //Funding Managers

        //BancorRedeemingVirtualSupplyFundingManager
        initialMetadataRegistration.push(
            bancorRedeemingVirtualSupplyFundingManagerMetadata
        );
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                proxyAndBeaconDeployer.deployInverterBeacon(
                    reverter,
                    governor,
                    mod_FM_BC_Bancor_Redeeming_VirtualSupply_v1,
                    bancorRedeemingVirtualSupplyFundingManagerMetadata
                        .majorVersion,
                    bancorRedeemingVirtualSupplyFundingManagerMetadata
                        .minorVersion,
                    bancorRedeemingVirtualSupplyFundingManagerMetadata
                        .patchVersion
                )
            )
        );

        //RestrictedBancorRedeemingVirtualSupplyFundingManager
        initialMetadataRegistration.push(
            restrictedBancorRedeemingVirtualSupplyFundingManagerMetadata
        );
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                proxyAndBeaconDeployer.deployInverterBeacon(
                    reverter,
                    governor,
                    mod_FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1,
                    restrictedBancorRedeemingVirtualSupplyFundingManagerMetadata
                        .majorVersion,
                    restrictedBancorRedeemingVirtualSupplyFundingManagerMetadata
                        .minorVersion,
                    restrictedBancorRedeemingVirtualSupplyFundingManagerMetadata
                        .patchVersion
                )
            )
        );

        //RebasingFundingManager
        initialMetadataRegistration.push(rebasingFundingManagerMetadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                proxyAndBeaconDeployer.deployInverterBeacon(
                    reverter,
                    governor,
                    mod_FM_Rebasing_v1,
                    rebasingFundingManagerMetadata.majorVersion,
                    rebasingFundingManagerMetadata.minorVersion,
                    rebasingFundingManagerMetadata.patchVersion
                )
            )
        );

        /*  
        //DepositVaultFundingManager
        initialMetadataRegistration.push(
            depositVaultFundingManagerMetadata
        );
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                proxyAndBeaconDeployer.deployInverterBeacon(
                    reverter,
                    governor,
                    mod_FM_DepositVault_v1,
                    depositVaultFundingManagerMetadata.majorVersion,
                    depositVaultFundingManagerMetadata.minorVersion,
                    depositVaultFundingManagerMetadata.patchVersion
                )
            )
        ); */

        //--------------------------------------------------------------------------
        //Logic Modules

        //Bounties
        initialMetadataRegistration.push(bountiesMetadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                proxyAndBeaconDeployer.deployInverterBeacon(
                    reverter,
                    governor,
                    mod_LM_PC_Bounties_v1,
                    bountiesMetadata.majorVersion,
                    bountiesMetadata.minorVersion,
                    bountiesMetadata.patchVersion
                )
            )
        );

        //KPIRewarder
        initialMetadataRegistration.push(kpiRewarderMetadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                proxyAndBeaconDeployer.deployInverterBeacon(
                    reverter,
                    governor,
                    mod_LM_PC_KPIRewarder_v1,
                    kpiRewarderMetadata.majorVersion,
                    kpiRewarderMetadata.minorVersion,
                    kpiRewarderMetadata.patchVersion
                )
            )
        );

        //PaymentRouter
        initialMetadataRegistration.push(paymentRouterMetadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                proxyAndBeaconDeployer.deployInverterBeacon(
                    reverter,
                    governor,
                    mod_LM_PC_PaymentRouter_v1,
                    paymentRouterMetadata.majorVersion,
                    paymentRouterMetadata.minorVersion,
                    paymentRouterMetadata.patchVersion
                )
            )
        );

        //RecurringPayments
        initialMetadataRegistration.push(recurringPaymentsMetadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                proxyAndBeaconDeployer.deployInverterBeacon(
                    reverter,
                    governor,
                    mod_LM_PC_RecurringPayments_v1,
                    recurringPaymentsMetadata.majorVersion,
                    recurringPaymentsMetadata.minorVersion,
                    recurringPaymentsMetadata.patchVersion
                )
            )
        );

        //Staking
        initialMetadataRegistration.push(stakingMetadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                proxyAndBeaconDeployer.deployInverterBeacon(
                    reverter,
                    governor,
                    mod_LM_PC_Staking_v1,
                    stakingMetadata.majorVersion,
                    stakingMetadata.minorVersion,
                    stakingMetadata.patchVersion
                )
            )
        );

        //--------------------------------------------------------------------------
        //Payment Processors

        //SimplePaymentProcessor
        initialMetadataRegistration.push(simplePaymentProcessorMetadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                proxyAndBeaconDeployer.deployInverterBeacon(
                    reverter,
                    governor,
                    mod_PP_Simple_v1,
                    simplePaymentProcessorMetadata.majorVersion,
                    simplePaymentProcessorMetadata.minorVersion,
                    simplePaymentProcessorMetadata.patchVersion
                )
            )
        );

        //StreamingPaymentProcessor
        initialMetadataRegistration.push(streamingPaymentProcessorMetadata);
        initialBeaconRegistration.push(
            IInverterBeacon_v1(
                proxyAndBeaconDeployer.deployInverterBeacon(
                    reverter,
                    governor,
                    mod_PP_Streaming_v1,
                    streamingPaymentProcessorMetadata.majorVersion,
                    streamingPaymentProcessorMetadata.minorVersion,
                    streamingPaymentProcessorMetadata.patchVersion
                )
            )
        );
    }
}
