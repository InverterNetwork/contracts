// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Interfaces
import {IModule_v2} from "src/modules/base/IModule_v2.sol";

/**
 * @title Inverter Metadata Collection
 *
 * @dev Contains metadata for all the modules and contracts in the Inverter
 *      protocol.
 *
 * @author Inverter Network
 */
contract MetadataCollection_v1 {
    // ------------------------------------------------------------------------
    // External Contracts

    // Governor
    IModule_v2.Metadata public governorMetadata = IModule_v2.Metadata(
        1, 0, 0, "https://github.com/InverterNetwork/contracts", "Governor_v1"
    );

    // TransactionForwarder
    IModule_v2.Metadata public forwarderMetadata = IModule_v2.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/contracts",
        "TransactionForwarder_v1"
    );

    // FeeManager
    IModule_v2.Metadata public feeManagerMetadata = IModule_v2.Metadata(
        1, 0, 0, "https://github.com/InverterNetwork/contracts", "FeeManager_v1"
    );

    // ------------------------------------------------------------------------
    // Factories

    // ModuleFactory
    IModule_v2.Metadata public moduleFactoryMetadata = IModule_v2.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/contracts",
        "ModuleFactory_v1"
    );

    // OrchestratorFactory
    IModule_v2.Metadata public orchestratorFactoryMetadata = IModule_v2.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/contracts",
        "OrchestratorFactory_v1"
    );

    // ------------------------------------------------------------------------
    // Orchestrator

    // Orchestrator
    IModule_v2.Metadata public orchestratorMetadata = IModule_v2.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/contracts",
        "Orchestrator_v1"
    );

    // ------------------------------------------------------------------------
    // Authorizer

    // RoleAuthorizer
    IModule_v2.Metadata public roleAuthorizerMetadata = IModule_v2.Metadata(
        1, 0, 0, "https://github.com/InverterNetwork/contracts", "AUT_Roles_v2"
    );

    // TokenGatedRoleAuthorizer
    IModule_v2.Metadata public tokenGatedRoleAuthorizerMetadata = IModule_v2
        .Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/contracts",
        "AUT_TokenGated_Roles_v2"
    );

    // VotingRoles
    IModule_v2.Metadata public votingRolesMetadata = IModule_v2.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/contracts",
        "AUT_EXT_VotingRoles_v2"
    );

    // ------------------------------------------------------------------------
    // Funding Manager

    // BancorRedeemingVirtualSupplyFundingManager
    IModule_v2.Metadata public
        bancorRedeemingVirtualSupplyFundingManagerMetadata = IModule_v2.Metadata(
            1,
            0,
            0,
            "https://github.com/InverterNetwork/contracts",
            "FM_BC_Bancor_Redeeming_VirtualSupply_v2"
        );

    // BondingSurfaceRedeemingFundingManager
    IModule_v2.Metadata public bondingSurfaceRedeemingFundingManagerMetadata =
    IModule_v2.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/contracts",
        "FM_BC_BondingSurface_Redeeming_v2"
    );

    // BondingSurfaceRedeemingRestrictedRepayerSeizableFundingManager
    IModule_v2.Metadata public
        bondingSurfaceRedeemingRestrictedRepayerSeizableFundingManagerMetadata =
        IModule_v2.Metadata(
            1,
            0,
            0,
            "https://github.com/InverterNetwork/contracts",
            "FM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v2"
        );

    // DepositVaultFundingManager
    IModule_v2.Metadata public depositVaultFundingManagerMetadata = IModule_v2
        .Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/contracts",
        "FM_DepositVault_v1"
    );

    // OracleRedeemingFundingManager
    IModule_v2.Metadata public oracleRedeemingFundingManagerMetadata =
    IModule_v2.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/contracts",
        "FM_PC_Oracle_Redeeming_v2"
    );

    // Funding Manager - Extensions

    // FM_EXT_TokenVault_v2
    IModule_v2.Metadata public tokenVaultMetadata = IModule_v2.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/contracts",
        "FM_EXT_TokenVault_v2"
    );

    // ------------------------------------------------------------------------
    // Logic Module

    // Oracle_Permissioned
    IModule_v2.Metadata public oraclePermissionedMetadata = IModule_v2.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/contracts",
        "LM_Oracle_Permissioned_v2"
    );

    // Bounties
    IModule_v2.Metadata public bountiesMetadata = IModule_v2.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/contracts",
        "LM_PC_Bounties_v3"
    );

    // KPIRewarder
    IModule_v2.Metadata public kpiRewarderMetadata = IModule_v2.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/contracts",
        "LM_PC_KPIRewarder_v3"
    );

    // PaymentRouter
    IModule_v2.Metadata public paymentRouterMetadata = IModule_v2.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/contracts",
        "LM_PC_PaymentRouter_v3"
    );

    // RecurringPayments
    IModule_v2.Metadata public recurringPaymentsMetadata = IModule_v2.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/contracts",
        "LM_PC_RecurringPayments_v2"
    );

    // Staking
    IModule_v2.Metadata public stakingMetadata = IModule_v2.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/contracts",
        "LM_PC_Staking_v2"
    );

    // ------------------------------------------------------------------------
    // Payment Processor

    // QueueManualExecutionPaymentProcessor
    IModule_v2.Metadata public queueManualExecutionPaymentProcessorMetadata =
    IModule_v2.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/contracts",
        "PP_Queue_ManualExecution_v1"
    );

    // QueuePaymentProcessor
    IModule_v2.Metadata public queuePaymentProcessorMetadata = IModule_v2
        .Metadata(
        1, 0, 0, "https://github.com/InverterNetwork/contracts", "PP_Queue_v1"
    );

    // SimplePaymentProcessor
    IModule_v2.Metadata public simplePaymentProcessorMetadata = IModule_v2
        .Metadata(
        1, 0, 0, "https://github.com/InverterNetwork/contracts", "PP_Simple_v2"
    );

    // StreamingPaymentProcessor
    IModule_v2.Metadata public streamingPaymentProcessorMetadata = IModule_v2
        .Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/contracts",
        "PP_Streaming_v2"
    );
}
