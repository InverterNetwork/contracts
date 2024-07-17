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
    address governor;
    DeployGovernor_v1 deployGovernor = new DeployGovernor_v1();
    // No Metadata

    // FeeManager
    address feeManager;
    DeployFeeManager_v1 deployFeeManager = new DeployFeeManager_v1();
    // No Metadata

    // InverterReverter_v1
    address reverter;
    DeployInverterReverter_v1 deployInverterReverter =
        new DeployInverterReverter_v1();
    // No Metadata

    // TransactionForwarder_v1
    address forwarder;
    DeployTransactionForwarder_v1 deployTransactionForwarder =
        new DeployTransactionForwarder_v1();
    // No Metadata

    // -----------------------------------------------------------------------------
    // MODULES
    // -----------------------------------------------------------------------------

    // FUNDING MANAGERS
    // -----------------------------------------------------------------------------

    // Rebasing Funding Manager
    address rebasingFundingManager;
    DeployFM_Rebasing_v1 deployRebasingFundingManager =
        new DeployFM_Rebasing_v1();
    IModule_v1.Metadata rebasingFundingManagerMetadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "FM_Rebasing_v1"
    );

    // Bancor Virtual Supply Bonding Curve Funding Manager
    address bancorBondingCurveFundingManager;
    DeployFM_BC_Bancor_Redeeming_VirtualSupply_v1
        deployBancorVirtualSupplyBondingCurveFundingManager =
            new DeployFM_BC_Bancor_Redeeming_VirtualSupply_v1();
    IModule_v1.Metadata bancorVirtualSupplyBondingCurveFundingManagerMetadata =
    IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "FM_BC_Bancor_Redeeming_VirtualSupply_v1"
    );

    // AUTHORIZATION
    // -----------------------------------------------------------------------------

    // PAYMENT PROCESSORS
    // -----------------------------------------------------------------------------

    // LOGIC MODULES
    // -----------------------------------------------------------------------------
}
