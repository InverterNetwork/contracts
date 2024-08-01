// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IModule_v1} from "src/modules/base/IModule_v1.sol";

contract MetadataCollection_v1 {
    // ------------------------------------------------------------------------
    // External Contracts

    //Governor
    IModule_v1.Metadata public governorMetadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "Governor_v1"
    );

    //TransactionForwarder
    IModule_v1.Metadata public forwarderMetadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "TransactionForwarder_v1"
    );

    //FeeManager
    IModule_v1.Metadata public feeManagerMetadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "FeeManager_v1"
    );

    // ------------------------------------------------------------------------
    // Factories

    //ModuleFactory
    IModule_v1.Metadata public moduleFactoryMetadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "ModuleFactory_v1"
    );

    //OrchestratorFactory
    IModule_v1.Metadata public orchestratorFactoryMetadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "OrchestratorFactory_v1"
    );

    // ------------------------------------------------------------------------
    //Orchestrator

    //Orchestrator
    IModule_v1.Metadata public orchestratorMetadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "Orchestrator_v1"
    );

    // ------------------------------------------------------------------------
    // Authorizer

    //RoleAuthorizer
    IModule_v1.Metadata public roleAuthorizerMetadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "AUT_Roles_v1"
    );

    //TokenGatedRoleAuthorizer
    IModule_v1.Metadata public tokenGatedRoleAuthorizerMetadata = IModule_v1
        .Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "AUT_TokenGated_Roles_v1"
    );

    //VotingRoles
    IModule_v1.Metadata public votingRolesMetadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "AUT_EXT_VotingRoles_v1"
    );

    // ------------------------------------------------------------------------
    // Funding Manager

    //BancorRedeemingVirtualSupplyFundingManager
    IModule_v1.Metadata public
        bancorRedeemingVirtualSupplyFundingManagerMetadata = IModule_v1.Metadata(
            1,
            0,
            0,
            "https://github.com/InverterNetwork/inverter-contracts",
            "FM_BC_Bancor_Redeeming_VirtualSupply_v1"
        );

    //RestrictedBancorRedeemingVirtualSupplyFundingManager
    IModule_v1.Metadata public
        restrictedBancorRedeemingVirtualSupplyFundingManagerMetadata =
        IModule_v1.Metadata(
            1,
            0,
            0,
            "https://github.com/InverterNetwork/inverter-contracts",
            "FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1"
        );

    /* 
    //DepositVaultFundingManager
    IModule_v1.Metadata public depositVaultFundingManagerMetadata =
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
    IModule_v1.Metadata public bountiesMetadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "LM_PC_Bounties_v1"
    );

    //KPIRewarder
    IModule_v1.Metadata public kpiRewarderMetadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "LM_PC_KPIRewarder_v1"
    );

    //PaymentRouter
    IModule_v1.Metadata public paymentRouterMetadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "LM_PC_PaymentRouter_v1"
    );

    //RecurringPayments
    IModule_v1.Metadata public recurringPaymentsMetadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "LM_PC_RecurringPayments_v1"
    );

    //Staking
    IModule_v1.Metadata public stakingMetadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "LM_PC_Staking_v1"
    );

    // ------------------------------------------------------------------------
    // Payment Processor

    //SimplePaymentProcessor
    IModule_v1.Metadata public simplePaymentProcessorMetadata = IModule_v1
        .Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "PP_Simple_v1"
    );

    //StreamingPaymentProcessor
    IModule_v1.Metadata public streamingPaymentProcessorMetadata = IModule_v1
        .Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "PP_Streaming_v1"
    );
}
