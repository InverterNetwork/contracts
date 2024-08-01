// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import {ProtocolConstants_v1} from
    "script/deploymentSuite/ProtocolConstants_v1.s.sol";
import {IDeterministicFactory_v1} from
    "script/deterministicFactory/interfaces/IDeterministicFactory.sol";

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

contract SingletonDeployer_v1 is ProtocolConstants_v1 {
    using Strings for string;

    IDeterministicFactory_v1 public factory =
        IDeterministicFactory_v1(deterministicFactory);

    function setFactory(address _factory) internal {
        factory = IDeterministicFactory_v1(_factory);
    }

    // External contracts

    address public impl_ext_InverterReverter_v1;
    address public impl_ext_Governor_v1;
    address public impl_ext_TransactionForwarder_v1;
    address public impl_ext_FeeManager_v1;

    // Factories
    address public impl_fac_ModuleFactory_v1;
    address public impl_fac_OrchestratorFactory_v1;

    // Modules

    // Authorizer
    address public impl_mod_Aut_Roles_v1;
    address public impl_mod_Aut_TokenGated_Roles_v1;
    address public impl_mod_Aut_Ext_VotingRoles_v1;

    // Funding Managers
    address public impl_mod_FM_BC_Bancor_Redeeming_VirtualSupply_v1;
    address public impl_mod_FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1;
    // address public impl_mod_FM_DepositVault_v1;

    // Logic Modules
    address public impl_mod_LM_PC_Bounties_v1;
    address public impl_mod_LM_PC_KPIRewarder_v1;
    address public impl_mod_LM_PC_PaymentRouter_v1;
    address public impl_mod_LM_PC_RecurringPayments_v1;
    address public impl_mod_LM_PC_Staking_v1;

    // Payment Processors
    address public impl_mod_PP_Simple_v1;
    address public impl_mod_PP_Streaming_v1;

    // Orchestrator
    address public impl_orc_Orchestrator_v1;

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
        console2.log(
            "--------------------------------------------------------------------------------"
        );
        console2.log("Create External Implementation Singletons");
        console2.log("-External Contracts");

        // External contracts
        impl_ext_InverterReverter_v1 = deployAndLogWithCreate2(
            "InverterReverter_v1",
            vm.getCode("InverterReverter_v1.sol:InverterReverter_v1")
        );

        impl_ext_Governor_v1 = deployAndLogWithCreate2(
            "Governor_v1", vm.getCode("Governor_v1.sol:Governor_v1")
        );

        impl_ext_TransactionForwarder_v1 = deployAndLogWithCreate2(
            "TransactionForwarder_v1",
            vm.getCode("TransactionForwarder_v1.sol:TransactionForwarder_v1")
        );

        impl_ext_FeeManager_v1 = deployAndLogWithCreate2(
            "FeeManager_v1", vm.getCode("FeeManager_v1.sol:FeeManager_v1")
        );
    }

    function createWorkflowAndFactorySingletons(address transactionForwarder)
        public
    {
        console2.log(
            "--------------------------------------------------------------------------------"
        );
        console2.log("Create Workflow and Factory Implementation Singletons");

        // Factories
        console2.log("-Factories");

        impl_fac_ModuleFactory_v1 = deployAndLogWithCreate2(
            "ModuleFactory_v1",
            abi.encodePacked(
                vm.getCode("ModuleFactory_v1.sol:ModuleFactory_v1"),
                abi.encode(impl_ext_InverterReverter_v1, transactionForwarder)
            )
        );

        impl_fac_OrchestratorFactory_v1 = deployAndLogWithCreate2(
            "OrchestratorFactory_v1",
            abi.encodePacked(
                vm.getCode("OrchestratorFactory_v1.sol:OrchestratorFactory_v1"),
                abi.encode(impl_ext_InverterReverter_v1, transactionForwarder)
            )
        );

        // Modules
        console2.log("-Modules");

        // Authorizer
        console2.log("--Authorizer");

        impl_mod_Aut_Roles_v1 = deployAndLogWithCreate2(
            "AUT_Roles_v1", vm.getCode("AUT_Roles_v1.sol:AUT_Roles_v1")
        );
        impl_mod_Aut_TokenGated_Roles_v1 = deployAndLogWithCreate2(
            "AUT_TokenGated_Roles_v1",
            vm.getCode("AUT_TokenGated_Roles_v1.sol:AUT_TokenGated_Roles_v1")
        );
        impl_mod_Aut_Ext_VotingRoles_v1 = deployAndLogWithCreate2(
            "AUT_EXT_VotingRoles_v1",
            vm.getCode("AUT_EXT_VotingRoles_v1.sol:AUT_EXT_VotingRoles_v1")
        );

        // Funding Managers
        console2.log("--Funding Managers");

        impl_mod_FM_BC_Bancor_Redeeming_VirtualSupply_v1 =
        deployAndLogWithCreate2(
            "FM_BC_Bancor_Redeeming_VirtualSupply_v1",
            vm.getCode(
                "FM_BC_Bancor_Redeeming_VirtualSupply_v1.sol:FM_BC_Bancor_Redeeming_VirtualSupply_v1"
            )
        );
        impl_mod_FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1 =
        deployAndLogWithCreate2(
            "FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1",
            vm.getCode(
                "FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1.sol:FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1"
            )
        );

        /* impl_mod_FM_DepositVault_v1 = deployAndLogWithCreate2(
            "FM_DepositVault_v1",
            
            vm.getCode("FM_DepositVault_v1.sol:FM_DepositVault_v1")
        ); */

        // Logic Modules
        console2.log("--Logic Modules");

        impl_mod_LM_PC_Bounties_v1 = deployAndLogWithCreate2(
            "LM_PC_Bounties_v1",
            vm.getCode("LM_PC_Bounties_v1.sol:LM_PC_Bounties_v1")
        );
        impl_mod_LM_PC_KPIRewarder_v1 = deployAndLogWithCreate2(
            "LM_PC_KPIRewarder_v1",
            vm.getCode("LM_PC_KPIRewarder_v1.sol:LM_PC_KPIRewarder_v1")
        );
        impl_mod_LM_PC_PaymentRouter_v1 = deployAndLogWithCreate2(
            "LM_PC_PaymentRouter_v1",
            vm.getCode("LM_PC_PaymentRouter_v1.sol:LM_PC_PaymentRouter_v1")
        );
        impl_mod_LM_PC_RecurringPayments_v1 = deployAndLogWithCreate2(
            "LM_PC_RecurringPayments_v1",
            vm.getCode(
                "LM_PC_RecurringPayments_v1.sol:LM_PC_RecurringPayments_v1"
            )
        );
        impl_mod_LM_PC_Staking_v1 = deployAndLogWithCreate2(
            "LM_PC_Staking_v1",
            vm.getCode("LM_PC_Staking_v1.sol:LM_PC_Staking_v1")
        );

        // Payment Processors
        console2.log("--Payment Processors");

        impl_mod_PP_Simple_v1 = deployAndLogWithCreate2(
            "PP_Simple_v1", vm.getCode("PP_Simple_v1.sol:PP_Simple_v1")
        );
        impl_mod_PP_Streaming_v1 = deployAndLogWithCreate2(
            "PP_Streaming_v1", vm.getCode("PP_Streaming_v1.sol:PP_Streaming_v1")
        );

        // Orchestrator
        console2.log("-Orchestrator");

        impl_orc_Orchestrator_v1 = deployAndLogWithCreate2(
            "Orchestrator_v1",
            abi.encodePacked(
                vm.getCode("Orchestrator_v1.sol:Orchestrator_v1"),
                abi.encode(transactionForwarder)
            )
        );
    }

    function deployAndLogWithCreate2(
        string memory implementationName,
        bytes memory creationCode
    ) internal returns (address) {
        vm.startBroadcast(deployerPrivateKey);
        address implementation =
            factory.deployWithCreate2(factorySalt, creationCode);
        vm.stopBroadcast();

        console2.log(
            "Deployment of %s Implementation at address %s",
            implementationName,
            implementation
        );

        return implementation;
    }
}
