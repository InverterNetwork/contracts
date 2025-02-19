// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

// Scripts
import {ProtocolConstants_v1} from
    "script/deploymentSuite/ProtocolConstants_v1.s.sol";

// Interfaces
import {IDeterministicFactory_v1} from
    "@df/interfaces/IDeterministicFactory_v1.sol";

// Libraries
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

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

    // Libraries
    address public impl_lib_BancorFormula;

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
    address public impl_mod_FM_DepositVault_v1;

    // Logic Modules
    address public impl_mod_LM_PC_Bounties_v2;
    address public impl_mod_LM_PC_KPIRewarder_v2;
    address public impl_mod_LM_PC_PaymentRouter_v2;
    address public impl_mod_LM_PC_RecurringPayments_v2;
    address public impl_mod_LM_PC_Staking_v2;

    // Payment Processors
    address public impl_mod_PP_Simple_v1;
    address public impl_mod_PP_Streaming_v2;

    // Orchestrator
    address public impl_orc_Orchestrator_v1;

    //--------------------------------------------------------------------------
    // Factory Usage

    // Example of the Governor_v1 deployment.
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
        ); 
    */

    function createExternalSingletons() public {
        console2.log(
            "--------------------------------------------------------------------------------"
        );
        console2.log(" Create External Implementation Singletons");

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

    function createLibrarySingletons() public {
        console2.log(
            "--------------------------------------------------------------------------------"
        );
        console2.log(" Create Library Implementation Singletons");

        impl_lib_BancorFormula = deployAndLogWithCreate2(
            "BancorFormula", vm.getCode("BancorFormula.sol:BancorFormula")
        );
    }

    function createWorkflowAndFactorySingletons(address transactionForwarder)
        public
    {
        console2.log(
            "--------------------------------------------------------------------------------"
        );
        console2.log(" Create Factory and Workflow Implementation Singletons");

        // Factories
        console2.log("  - Factories");

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
                abi.encode(transactionForwarder)
            )
        );

        // Modules
        console2.log("  - Modules");

        // Authorizer
        console2.log("  -- Authorizer");

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
        console2.log("  -- Funding Managers");

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

        impl_mod_FM_DepositVault_v1 = deployAndLogWithCreate2(
            "FM_DepositVault_v1",
            vm.getCode("FM_DepositVault_v1.sol:FM_DepositVault_v1")
        );

        // Logic Modules
        console2.log("  -- Logic Modules");

        impl_mod_LM_PC_Bounties_v2 = deployAndLogWithCreate2(
            "LM_PC_Bounties_v2",
            vm.getCode("LM_PC_Bounties_v2.sol:LM_PC_Bounties_v2")
        );
        impl_mod_LM_PC_KPIRewarder_v2 = deployAndLogWithCreate2(
            "LM_PC_KPIRewarder_v2",
            vm.getCode("LM_PC_KPIRewarder_v2.sol:LM_PC_KPIRewarder_v2")
        );
        impl_mod_LM_PC_PaymentRouter_v2 = deployAndLogWithCreate2(
            "LM_PC_PaymentRouter_v2",
            vm.getCode("LM_PC_PaymentRouter_v2.sol:LM_PC_PaymentRouter_v2")
        );
        impl_mod_LM_PC_RecurringPayments_v2 = deployAndLogWithCreate2(
            "LM_PC_RecurringPayments_v2",
            vm.getCode(
                "LM_PC_RecurringPayments_v2.sol:LM_PC_RecurringPayments_v2"
            )
        );
        impl_mod_LM_PC_Staking_v2 = deployAndLogWithCreate2(
            "LM_PC_Staking_v2",
            vm.getCode("LM_PC_Staking_v2.sol:LM_PC_Staking_v2")
        );

        // Payment Processors
        console2.log("  -- Payment Processors");

        impl_mod_PP_Simple_v1 = deployAndLogWithCreate2(
            "PP_Simple_v1", vm.getCode("PP_Simple_v1.sol:PP_Simple_v1")
        );
        impl_mod_PP_Streaming_v2 = deployAndLogWithCreate2(
            "PP_Streaming_v2", vm.getCode("PP_Streaming_v2.sol:PP_Streaming_v2")
        );

        // Orchestrator
        console2.log("  - Orchestrator");

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
    ) internal returns (address implementation) {
        vm.startBroadcast(deployerPrivateKey);
        {
            implementation =
                factory.deployWithCreate2(factorySalt, creationCode);
        }
        vm.stopBroadcast();

        console2.log(
            "\t%s Implementation: %s", implementationName, implementation
        );
    }
}
