// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Interfaces
import {IModule_v1} from "src/modules/base/IModule_v1.sol";

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
    IModule_v1.Metadata public governorMetadata = IModule_v1.Metadata(
        1, 0, 0, "https://github.com/InverterNetwork/contracts", "Governor_v1"
    );

    // TransactionForwarder
    IModule_v1.Metadata public forwarderMetadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/contracts",
        "TransactionForwarder_v1"
    );

    // FeeManager
    IModule_v1.Metadata public feeManagerMetadata = IModule_v1.Metadata(
        1, 0, 0, "https://github.com/InverterNetwork/contracts", "FeeManager_v1"
    );

    // ------------------------------------------------------------------------
    // Factories

    // ModuleFactory
    IModule_v1.Metadata public moduleFactoryMetadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/contracts",
        "ModuleFactory_v1"
    );

    // OrchestratorFactory
    IModule_v1.Metadata public orchestratorFactoryMetadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/contracts",
        "OrchestratorFactory_v1"
    );

    // ------------------------------------------------------------------------
    // Orchestrator

    // Orchestrator
    IModule_v1.Metadata public orchestratorMetadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/contracts",
        "Orchestrator_v1"
    );

    // ------------------------------------------------------------------------
    // Authorizer

    // RoleAuthorizer
    IModule_v1.Metadata public roleAuthorizerMetadata = IModule_v1.Metadata(
        1, 0, 0, "https://github.com/InverterNetwork/contracts", "AUT_Roles_v2"
    );

    // TokenGatedRoleAuthorizer
    IModule_v1.Metadata public tokenGatedRoleAuthorizerMetadata = IModule_v1
        .Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/contracts",
        "AUT_TokenGated_Roles_v1"
    );

    // VotingRoles
    IModule_v1.Metadata public votingRolesMetadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/contracts",
        "AUT_EXT_VotingRoles_v2"
    );

    // ------------------------------------------------------------------------
    // Funding Manager

    // BancorRedeemingVirtualSupplyFundingManager
    IModule_v1.Metadata public
        bancorRedeemingVirtualSupplyFundingManagerMetadata = IModule_v1.Metadata(
            1,
            0,
            0,
            "https://github.com/InverterNetwork/contracts",
            "FM_BC_Bancor_Redeeming_VirtualSupply_v1"
        );

    // BondingSurfaceRedeemingFundingManager
    IModule_v1.Metadata public bondingSurfaceRedeemingFundingManagerMetadata =
    IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/contracts",
        "FM_BC_BondingSurface_Redeeming_v1"
    );

    // BondingSurfaceRedeemingRestrictedRepayerSeizableFundingManager
    IModule_v1.Metadata public
        bondingSurfaceRedeemingRestrictedRepayerSeizableFundingManagerMetadata =
        IModule_v1.Metadata(
            1,
            0,
            0,
            "https://github.com/InverterNetwork/contracts",
            "FM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1"
        );

    // DepositVaultFundingManager
    IModule_v1.Metadata public depositVaultFundingManagerMetadata = IModule_v1
        .Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/contracts",
        "FM_DepositVault_v1"
    );

    // OracleRedeemingFundingManager
    IModule_v1.Metadata public oracleRedeemingFundingManagerMetadata =
    IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/contracts",
        "FM_PC_Oracle_Redeeming_v1"
    );

    // Funding Manager - Extensions

    // FM_EXT_TokenVault_v1
    IModule_v1.Metadata public tokenVaultMetadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/contracts",
        "FM_EXT_TokenVault_v1"
    );

    // ------------------------------------------------------------------------
    // Logic Module

    // Oracle_Permissioned
    IModule_v1.Metadata public oraclePermissionedMetadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/contracts",
        "LM_Oracle_Permissioned_v1"
    );

    // Bounties
    IModule_v1.Metadata public bountiesMetadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/contracts",
        "LM_PC_Bounties_v2"
    );

    // KPIRewarder
    IModule_v1.Metadata public kpiRewarderMetadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/contracts",
        "LM_PC_KPIRewarder_v2"
    );

    // PaymentRouter
    IModule_v1.Metadata public paymentRouterMetadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/contracts",
        "LM_PC_PaymentRouter_v2"
    );

    // RecurringPayments
    IModule_v1.Metadata public recurringPaymentsMetadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/contracts",
        "LM_PC_RecurringPayments_v2"
    );

    // Staking
    IModule_v1.Metadata public stakingMetadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/contracts",
        "LM_PC_Staking_v2"
    );

    // ------------------------------------------------------------------------
    // Payment Processor

    // QueueManualExecutionPaymentProcessor
    IModule_v1.Metadata public queueManualExecutionPaymentProcessorMetadata =
    IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/contracts",
        "PP_Queue_ManualExecution_v1"
    );

    // QueuePaymentProcessor
    IModule_v1.Metadata public queuePaymentProcessorMetadata = IModule_v1
        .Metadata(
        1, 0, 0, "https://github.com/InverterNetwork/contracts", "PP_Queue_v1"
    );

    // SimplePaymentProcessor
    IModule_v1.Metadata public simplePaymentProcessorMetadata = IModule_v1
        .Metadata(
        1, 0, 0, "https://github.com/InverterNetwork/contracts", "PP_Simple_v2"
    );

    // StreamingPaymentProcessor
    IModule_v1.Metadata public streamingPaymentProcessorMetadata = IModule_v1
        .Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/contracts",
        "PP_Streaming_v2"
    );
}
