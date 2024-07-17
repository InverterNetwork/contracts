// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// Factories
import {ModuleFactory_v1} from "src/factories/ModuleFactory_v1.sol";
import {IOrchestratorFactory_v1} from
    "src/factories/interfaces/IOrchestratorFactory_v1.sol";

// Protocol Governance
import {Governor_v1} from "@ex/governance/Governor_v1.sol";
import {InverterReverter_v1} from
    "src/external/reverter/InverterReverter_v1.sol";

// Beacon
import {
    InverterBeacon_v1,
    IInverterBeacon_v1
} from "src/proxies/InverterBeacon_v1.sol";

// Modules
// =============================================================================
import {IModule_v1} from "src/modules/base/IModule_v1.sol";

// Funding Managers
import {FM_Rebasing_v1} from "@fm/rebasing/FM_Rebasing_v1.sol";
import {FM_BC_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/FM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
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

// Import scripts:
import {DeployModuleFactory_v1} from
    "script/factories/DeployModuleFactory_v1.s.sol";
import {DeployOrchestratorFactory_v1} from
    "script/factories/DeployOrchestratorFactory_v1.s.sol";
import {DeployLM_PC_Bounties_v1} from
    "script/modules/logicModule/DeployLM_PC_Bounties_v1.s.sol";

import {DeployGovernor_v1} from "script/external/DeployGovernor_v1.s.sol";
import {DeployFeeManager_v1} from "script/external/DeployFeeManager_v1.s.sol";
import {DeployInverterReverter_v1} from
    "script/external/DeployInverterReverter_v1.s.sol";
import {DeployTransactionForwarder_v1} from
    "script/external/DeployTransactionForwarder_v1.s.sol";
import {DeployOrchestrator_v1} from
    "script/orchestrator/DeployOrchestrator_v1.s.sol";
import {DeployPP_Simple_v1} from
    "script/modules/paymentProcessor/DeployPP_Simple_v1.s.sol";
import {DeployFM_Rebasing_v1} from
    "script/modules/fundingManager/DeployFM_Rebasing_v1.s.sol";
import {DeployFM_BC_Bancor_Redeeming_VirtualSupply_v1} from
    "script/modules/fundingManager/DeployFM_BC_Bancor_Redeeming_VirtualSupply_v1.s.sol";
import {DeployFM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1} from
    "script/modules/fundingManager/DeployFM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1.s.sol";
import {DeployAUT_Role_v1} from
    "script/modules/authorizer/DeployAUT_Role_v1.s.sol";
import {DeployAUT_TokenGated_Role_v1} from
    "script/modules/authorizer/DeployAUT_TokenGated_Role_v1.s.sol";
import {DeployPP_Streaming_v1} from
    "script/modules/paymentProcessor/DeployPP_Streaming_v1.s.sol";
import {DeployLM_PC_RecurringPayments_v1} from
    "script/modules/logicModule/DeployLM_PC_RecurringPayments_v1.s.sol";
import {DeployLM_PC_PaymentRouter_v1} from
    "script/modules/logicModule/DeployLM_PC_PaymentRouter_v1.s.sol";
import {DeployLM_PC_KPIRewarder_v1} from
    "script/modules/logicModule/DeployLM_PC_KPIRewarder.s.sol";
import {DeployAUT_EXT_VotingRoles_v1} from
    "script/modules/authorizer/extensions/DeployAUT_EXT_VotingRoles_v1.s.sol";

//--------------------------------------------------------------------------
// General Module Registry Information
//--------------------------------------------------------------------------
// # TEMPLATE
// For each Module, this file should declare:
//      address moduleInstance;
//      DeployModule deployModule = new DeployModule();
//      IModule_v1.Metadata moduleMetadata = IModule_v1.Metadata(
//          1, 1, "https://github.com/inverter/module", "ModuleName"
//      );
//--------------------------------------------------------------------------

contract ModuleRegistry {
    //  FACTORIES
    //--------------------------------------------------------------------------

    // OrchestratorFactory
    address orchestratorFactory;
    DeployOrchestratorFactory_v1 deployOrchestratorFactory =
        new DeployOrchestratorFactory_v1();
    // No Metadata

    // ModuleFactory
    address moduleFactory;
    DeployModuleFactory_v1 deployModuleFactory = new DeployModuleFactory_v1();
    // No Metadata

    // PROTOCOL GOVERNANCE
    // -----------------------------------------------------------------------------

    // Governor_v1
    address governor_Implementation;
    DeployGovernor_v1 deployGovernor = new DeployGovernor_v1();
    // No Metadata

    // FeeManager
    address feeManager_Implementation;
    DeployFeeManager_v1 deployFeeManager = new DeployFeeManager_v1();
    // No Metadata

    // InverterReverter_v1
    address reverter_Implementation;
    DeployInverterReverter_v1 deployInverterReverter =
        new DeployInverterReverter_v1();
    // No Metadata

    // TransactionForwarder_v1
    address forwarder_Implementation;
    DeployTransactionForwarder_v1 deployTransactionForwarder =
        new DeployTransactionForwarder_v1();
    // No Metadata

    // -----------------------------------------------------------------------------
    // ORCHESTRATOR AND MODULES
    // -----------------------------------------------------------------------------

    // Orchestrator_v1
    address orchestrator_Implementation;
    DeployOrchestrator_v1 deployOrchestrator = new DeployOrchestrator_v1();
    // No Metadata

    // -----------------------------------------------------------------------------

    // FUNDING MANAGERS
    // -----------------------------------------------------------------------------

    // Rebasing Funding Manager
    address FM_Rebasing_v1_Implementation;
    DeployFM_Rebasing_v1 deployRebasingFundingManager =
        new DeployFM_Rebasing_v1();
    IModule_v1.Metadata FM_Rebasing_v1_Metadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "FM_Rebasing_v1"
    );

    // Bancor Virtual Supply Bonding Curve Funding Manager
    address FM_BC_Bancor_Redeeming_VirtualSupply_v1_Implementation;
    DeployFM_BC_Bancor_Redeeming_VirtualSupply_v1
        deployBancorVirtualSupplyBondingCurveFundingManager =
            new DeployFM_BC_Bancor_Redeeming_VirtualSupply_v1();
    IModule_v1.Metadata FM_BC_Bancor_Redeeming_VirtualSupply_v1_Metadata =
    IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "FM_BC_Bancor_Redeeming_VirtualSupply_v1"
    );

    // Restricted Bancor Virtual Supply Bonding Curve Funding Manager
    address FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1_Implementation;
    DeployFM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1
        deployRestrictedBancorVirtualSupplyBondingCurveFundingManager =
            new DeployFM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1();
    IModule_v1.Metadata
        FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1_Metadata = IModule_v1
            .Metadata(
            1,
            0,
            0,
            "https://github.com/InverterNetwork/inverter-contracts",
            "FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1"
        );

    // AUTHORIZATION
    // -----------------------------------------------------------------------------
    // RoleAuthorizer
    address AUT_Roles_v1_Implementation;
    DeployAUT_Role_v1 deployRoleAuthorizer = new DeployAUT_Role_v1();
    IModule_v1.Metadata AUT_Roles_v1_Metadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "AUT_Roles_v1"
    );

    // TokenGated RoleAuthorizer
    address AUT_TokenGated_Roles_v1_Implementation;
    DeployAUT_TokenGated_Role_v1 deployTokenGatedRoleAuthorizer =
        new DeployAUT_TokenGated_Role_v1();
    IModule_v1.Metadata AUT_TokenGated_Roles_v1_Metadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "AUT_TokenGated_Roles_v1"
    );

    // Single Vote Governor
    address AUT_EXT_VotingRoles_v1_Implementation;
    DeployAUT_EXT_VotingRoles_v1 deploySingleVoteGovernor =
        new DeployAUT_EXT_VotingRoles_v1();
    IModule_v1.Metadata AUT_EXT_VotingRoles_v1_Metadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "AUT_EXT_VotingRoles_v1"
    );

    // PAYMENT PROCESSORS
    // -----------------------------------------------------------------------------
    // Simple Payment Processor
    address PP_Simple_v1_Implementation;
    DeployPP_Simple_v1 deploySimplePaymentProcessor = new DeployPP_Simple_v1();
    IModule_v1.Metadata PP_Simple_v1_Metadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "PP_Simple_v1"
    );

    // Streaming Payment Processor
    address PP_Streaming_v1_Implementation;
    DeployPP_Streaming_v1 deployStreamingPaymentProcessor =
        new DeployPP_Streaming_v1();
    IModule_v1.Metadata PP_Streaming_v1_Metadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "PP_Streaming_v1"
    );

    // LOGIC MODULES
    // -----------------------------------------------------------------------------

    // Bounty Manager
    address LM_PC_Bounties_v1_Implementation;
    DeployLM_PC_Bounties_v1 deployBountyManager = new DeployLM_PC_Bounties_v1();
    IModule_v1.Metadata LM_PC_Bounties_v1_Metadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "LM_PC_Bounties_v1"
    );

    // Recurring Payment Manager
    address LM_PC_RecurringPayments_v1_Implementation;
    DeployLM_PC_RecurringPayments_v1 deployRecurringPaymentManager =
        new DeployLM_PC_RecurringPayments_v1();
    IModule_v1.Metadata LM_PC_RecurringPayments_v1_Metadata = IModule_v1
        .Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "LM_PC_RecurringPayments_v1"
    );

    // Payment Router
    address LM_PC_PaymentRouter_v1_Implementation;
    DeployLM_PC_PaymentRouter_v1 deployPaymentRouter =
        new DeployLM_PC_PaymentRouter_v1();
    IModule_v1.Metadata LM_PC_PaymentRouter_v1_Metadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "LM_PC_PaymentRouter_v1"
    );

    // KPI Rewarder
    address LM_PC_KPIRewarder_v1_Implementation;
    DeployLM_PC_KPIRewarder_v1 deployKPIRewarder =
        new DeployLM_PC_KPIRewarder_v1();
    IModule_v1.Metadata LM_PC_KPIRewarder_v1_Metadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "LM_PC_KPIRewarder_v1"
    );
}
