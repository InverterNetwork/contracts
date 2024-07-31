// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import {ProtocolConstants_v1} from "script/ProtocolConstants_v1.sol";
import {IDeterministicFactory_v1} from
    "script/deterministicFactory/interfaces/IDeterministicFactory_v1.sol";

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

// Factories
import {ModuleFactory_v1} from "src/factories/ModuleFactory_v1.sol";
import {IOrchestratorFactory_v1} from
    "src/factories/interfaces/IOrchestratorFactory_v1.sol";

// Protocol Governance
import {Governor_v1} from "@ex/governance/Governor_v1.sol";
import {InverterReverter_v1} from
    "src/external/reverter/InverterReverter_v1.sol";
import {FeeManager_v1} from "@ex/fees/FeeManager_v1.sol";
import {TransactionForwarder_v1} from
    "@ex/forwarder/TransactionForwarder_v1.sol";

// Beacon
import {
    InverterBeacon_v1,
    IInverterBeacon_v1
} from "src/proxies/InverterBeacon_v1.sol";

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

// Factories
import {ModuleFactory_v1} from "src/factories/ModuleFactory_v1.sol";
import {OrchestratorFactory_v1} from "src/factories/OrchestratorFactory_v1.sol";

//--------------------------------------------------------------------------
// General Singelton Deployer Information
//--------------------------------------------------------------------------
// This file acts as a general deployer for all singeltons in the inverter protocol.
// It uses a deterministic factory to deploy all contracts needed for the inverter protocol to work.
//--------------------------------------------------------------------------

contract SingletonDeployer_v1 is ProtocolConstants {
    using Strings for string;

    IDeterministicFactory_v1 public factory =
        IDeterministicFactory_v1(deterministicFactory);

    bytes32 factorySalt = keccak256(abi.encodePacked("inverter-deployment"));

    //External contracts

    address public ext_InverterReverter_v1;
    address public ext_FeeManager_v1;
    address public ext_TransactionForwarder_v1;
    address public ext_Governor_v1;

    //@note Add Token here?

    //Factories
    address public fac_ModuleFactory_v1;
    address public fac_OrchestratorFactory_v1;

    //Modules

    //Authorizer
    address public mod_Aut_Roles_v1;
    address public mod_Aut_TokenGated_Roles_v1;
    address public mod_Aut_EXT_VotingRoles_v1;

    //Funding Managers
    address public mod_FM_BC_Bancor_Redeeming_VirtualSupply_v1;
    address public mod_FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1;
    address public mod_FM_Rebasing_v1; //@note Do we add this?
    //address public mod_FM_DepositVault_v1;

    //Logic Modules
    address public mod_LM_PC_Bounties_v1;
    address public mod_LM_PC_KPIRewarder_v1;
    address public mod_LM_PC_PaymentRouter_v1;
    address public mod_LM_PC_RecurringPayments_v1;
    address public mod_LM_PC_Staking_v1;

    //Payment Processors
    address public mod_PP_Simple_v1;
    address public mod_PP_Streaming_v1;

    //Orchestrator
    address public orc_Orchestrator_v1;

    //--------------------------------------------------------------------------
    // Factory Usage

    // Deploy the Governor_v1.
    /*
    // Deploy without Arguments
    bytes memory implBytecode = vm.getCode("Governor_v1.sol:Governor_v1");
    govImplementation = factory.deployWithCreate2(salt, implBytecode);

    // Deploy with Arguments
    bytes memory proxyArgs = abi.encode(address(govImplementation), communityMultisig, bytes(""));
    bytes memory proxyCode = vm.getCode("TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy");
    bytes memory proxyBytecode = abi.encodePacked(proxyCode, proxyArgs);
    gov = Governor_v1(
        address(
                factory.deployWithCreate2(salt, proxyBytecode)
        )
    ); */

    function createExternalSingletons() public {
        //@todo add Logs
        //External contracts
        ext_InverterReverter_v1 = factory.deployWithCreate2( //@note no Beacon strcuture here right?
        factorySalt, vm.getCode("InverterReverte_v1.sol:InverterReverter_v1"));

        ext_TransactionForwarder_v1 = factory.deployWithCreate2(
            factorySalt,
            vm.getCode("TransactionForwarder_v1.sol:TransactionForwarder_v1")
        );
        ext_Governor_v1 = factory.deployWithCreate2(
            factorySalt, vm.getCode("Governor_v1.sol:Governor_v1")
        );
        ext_FeeManager_v1 = factory.deployWithCreate2(
            factorySalt, vm.getCode("FeeManager_v1.sol:FeeManager_v1")
        );
    }

    function createWorkflowAndFactorySingletons(address transactionForwarder)
        public
    {
        //@todo add Logs

        //Factories
        fac_ModuleFactory_v1 = factory.deployWithCreate2(
            factorySalt,
            abi.encodePacked(
                vm.getCode("ModuleFactory_v1.sol:ModuleFactory_v1"),
                abi.encode(ext_InverterReverter_v1, transactionForwarder)
            )
        );

        fac_OrchestratorFactory_v1 = factory.deployWithCreate2(
            factorySalt,
            abi.encodePacked(
                vm.getCode("OrchestratorFactory_v1.sol:OrchestratorFactory_v1"),
                abi.encode(ext_InverterReverter_v1, transactionForwarder)
            )
        );

        //Modules

        //Authorizer
        mod_Aut_Roles_v1 = factory.deployWithCreate2(
            factorySalt, vm.getCode("AUT_Roles_v1.sol:AUT_Roles_v1")
        );
        mod_Aut_TokenGated_Roles_v1 = factory.deployWithCreate2(
            factorySalt,
            vm.getCode("AUT_TokenGated_Roles_v1.sol:AUT_TokenGated_Roles_v1")
        );
        mod_Aut_EXT_VotingRoles_v1 = factory.deployWithCreate2(
            factorySalt,
            vm.getCode("AUT_EXT_VotingRoles_v1.sol:AUT_EXT_VotingRoles_v1")
        );

        //Funding Managers
        mod_FM_BC_Bancor_Redeeming_VirtualSupply_v1 = factory.deployWithCreate2(
            factorySalt,
            vm.getCode(
                "FM_BC_Bancor_Redeeming_VirtualSupply_v1.sol:FM_BC_Bancor_Redeeming_VirtualSupply_v1"
            )
        );
        mod_FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1 = factory
            .deployWithCreate2(
            factorySalt,
            vm.getCode(
                "FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1.sol:FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1"
            )
        );
        mod_FM_Rebasing_v1 = factory.deployWithCreate2( //@note Do we add this?
        factorySalt, vm.getCode("FM_Rebasing_v1.sol:FM_Rebasing_v1"));

        /* mod_FM_DepositVault_v1 = factory.deployWithCreate2(
            factorySalt,
            vm.getCode("FM_DepositVault_v1.sol:FM_DepositVault_v1")
        ); */

        //Logic Modules
        mod_LM_PC_Bounties_v1 = factory.deployWithCreate2(
            factorySalt, vm.getCode("LM_PC_Bounties_v1.sol:LM_PC_Bounties_v1")
        );
        mod_LM_PC_KPIRewarder_v1 = factory.deployWithCreate2(
            factorySalt,
            vm.getCode("LM_PC_KPIRewarder_v1.sol:LM_PC_KPIRewarder_v1")
        );
        mod_LM_PC_PaymentRouter_v1 = factory.deployWithCreate2(
            factorySalt,
            vm.getCode("LM_PC_PaymentRouter_v1.sol:LM_PC_PaymentRouter_v1")
        );
        mod_LM_PC_RecurringPayments_v1 = factory.deployWithCreate2(
            factorySalt,
            vm.getCode(
                "LM_PC_RecurringPayments_v1.sol:LM_PC_RecurringPayments_v1"
            )
        );
        mod_LM_PC_Staking_v1 = factory.deployWithCreate2(
            factorySalt, vm.getCode("LM_PC_Staking_v1.sol:LM_PC_Staking_v1")
        );

        //Payment Processors
        mod_PP_Simple_v1 = factory.deployWithCreate2(
            factorySalt, vm.getCode("PP_Simple_v1.sol:PP_Simple_v1")
        );
        mod_PP_Streaming_v1 = factory.deployWithCreate2(
            factorySalt, vm.getCode("PP_Streaming_v1.sol:PP_Streaming_v1")
        );

        //Orchestrator
        orc_Orchestrator_v1 = factory.deployWithCreate2(
            factorySalt, vm.getCode("Orchestrator_v1.sol:Orchestrator_v1")
        );
    }
}
