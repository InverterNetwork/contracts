// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

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

// Import scripts:
import {
    ModuleFactory_v1

} from "src/factories/ModuleFactory_v1.sol";
import {
    OrchestratorFactory_v1

} from "src/factories/OrchestratorFactory_v1.sol";

//--------------------------------------------------------------------------
// General Module Registry Information
//--------------------------------------------------------------------------
// # TEMPLATE
// For each Module, this file should declare:
//      address moduleImplementation;  // The implementation address owill be stored here
//      IModule_v1.Metadata moduleMetadata = IModule_v1.Metadata(
//          1, 1, "https://github.com/inverter/module", "ModuleName"
//      );
//--------------------------------------------------------------------------

contract ModuleRegistry is Script {
    using Strings for string;
    // ------------------------------------------------------------------------
    // Fetch Environment Variables

    uint deployerPrivateKey = vm.envUint("ORCHESTRATOR_ADMIN_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    function deployImplementation(
        string memory contractName,
        bytes memory constructorArgs
    ) public returns (address implementation) {
        vm.startBroadcast(deployerPrivateKey);
        {
            // Deploy the Module Implementation.

            implementation = giantSwitchFromHell(contractName, constructorArgs);
        }

        vm.stopBroadcast();

        // Log the deployed Module contract address.
        console2.log(
            "Deployment of %s Implementation at address %s",
            contractName,
            implementation
        );
    }

    function giantSwitchFromHell(
        string memory contractName,
        bytes memory constructorArgs
    ) internal returns (address) {
        // Orchestrator
        if (Strings.equal(contractName, "Orchestrator_v1")) {
            address forwarder = abi.decode(constructorArgs, (address));
            return address(new Orchestrator_v1(forwarder));
        }
        // Protocol Contracts
        else if (Strings.equal(contractName, "Governor_v1")) {
            return address(new Governor_v1());
        } else if (Strings.equal(contractName, "FeeManager_v1")) {
            return address(new FeeManager_v1());
        } else if (Strings.equal(contractName, "InverterReverter_v1")) {
            return address(new InverterReverter_v1());
        } else if (Strings.equal(contractName, "TransactionForwarder_v1")) {
            string memory name = abi.decode(constructorArgs, (string));
            return address(new TransactionForwarder_v1(name));
        }
        // Factories
        else if (Strings.equal(contractName, "ModuleFactory_v1")) {
            (address reverter, address forwarder) =
                abi.decode(constructorArgs, (address, address));
            return address(new ModuleFactory_v1(reverter, forwarder));
        } else if (Strings.equal(contractName, "OrchestratorFactory_v1")) {
            address forwarder = abi.decode(constructorArgs, (address));
            return address(new OrchestratorFactory_v1(forwarder));
        }
        // Funding Managers
        else if (Strings.equal(contractName, "FM_Rebasing_v1")) {
            return address(new FM_Rebasing_v1());
        } else if (
            Strings.equal(
                contractName, "FM_BC_Bancor_Redeeming_VirtualSupply_v1"
            )
        ) {
            return address(new FM_BC_Bancor_Redeeming_VirtualSupply_v1());
        } else if (
            Strings.equal(
                contractName,
                "FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1"
            )
        ) {
            return address(
                new FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1()
            );
        }
        // Authorizer
        else if (Strings.equal(contractName, "AUT_Roles_v1")) {
            return address(new AUT_Roles_v1());
        } else if (Strings.equal(contractName, "AUT_TokenGated_Roles_v1")) {
            return address(new AUT_TokenGated_Roles_v1());
        } else if (Strings.equal(contractName, "AUT_EXT_VotingRoles_v1")) {
            return address(new AUT_EXT_VotingRoles_v1());
        }
        // Payment Processors
        else if (Strings.equal(contractName, "PP_Simple_v1")) {
            return address(new PP_Simple_v1());
        } else if (Strings.equal(contractName, "PP_Streaming_v1")) {
            return address(new PP_Streaming_v1());
        }
        // Logic Modules
        else if (Strings.equal(contractName, "LM_PC_PaymentRouter_v1")) {
            return address(new LM_PC_PaymentRouter_v1());
        } else if (Strings.equal(contractName, "LM_PC_Bounties_v1")) {
            return address(new LM_PC_Bounties_v1());
        } else if (Strings.equal(contractName, "LM_PC_RecurringPayments_v1")) {
            return address(new LM_PC_RecurringPayments_v1());
        } else if (Strings.equal(contractName, "LM_PC_KPIRewarder_v1")) {
            return address(new LM_PC_KPIRewarder_v1());
        } else if (Strings.equal(contractName, "LM_PC_Staking_v1")) {
            return address(new LM_PC_Staking_v1());
        }
        revert("Unknown Module");
    }

    //  FACTORIES AND BEACONS
    //--------------------------------------------------------------------------

    // OrchestratorFactory
    address orchestratorFactory;
    IModule_v1.Metadata orchestratorFactory_Metadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "OrchestratorFactory_v1"
    ); // Stored for practical use in the scripts, the metadata is not stored onchain
    // No Metadata

    // ModuleFactory
    address moduleFactory;
    IModule_v1.Metadata moduleFactory_Metadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "ModuleFactory_v1"
    ); // Stored for practical use in the scripts, the metadata is not stored onchain

    // PROTOCOL GOVERNANCE
    // -----------------------------------------------------------------------------

    // Governor_v1
    address governor_Implementation;
    IModule_v1.Metadata governor_Metadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "Governor_v1"
    ); // Stored for practical use in the scripts, the metadata is not stored onchain

    // FeeManager
    address feeManager_Implementation;
    IModule_v1.Metadata feeManager_Metadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "FeeManager_v1"
    ); // Stored for practical use in the scripts, the metadata is not stored onchain

    // InverterReverter_v1
    address reverter_Implementation;
    IModule_v1.Metadata reverter_Metadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "InverterReverter_v1"
    ); // Stored for practical use in the scripts, the metadata is not stored onchain

    // TransactionForwarder_v1
    address forwarder_Implementation;
    IModule_v1.Metadata forwarder_Metadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "TransactionForwarder_v1"
    ); // Stored for practical use in the scripts, the metadata is not stored onchain

    // -----------------------------------------------------------------------------
    // ORCHESTRATOR AND MODULES
    // -----------------------------------------------------------------------------

    // Orchestrator_v1
    address orchestrator_Implementation;
    IModule_v1.Metadata orchestrator_Metadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "Orchestrator_v1"
    ); // Stored for practical use in the scripts, the metadata is not stored onchain

    // -----------------------------------------------------------------------------

    // FUNDING MANAGERS
    // -----------------------------------------------------------------------------

    // Rebasing Funding Manager
    address FM_Rebasing_v1_Implementation;
    IModule_v1.Metadata FM_Rebasing_v1_Metadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "FM_Rebasing_v1"
    );

    // Bancor Virtual Supply Bonding Curve Funding Manager
    address FM_BC_Bancor_Redeeming_VirtualSupply_v1_Implementation;
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
    IModule_v1.Metadata AUT_Roles_v1_Metadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "AUT_Roles_v1"
    );

    // TokenGated RoleAuthorizer
    address AUT_TokenGated_Roles_v1_Implementation;
    IModule_v1.Metadata AUT_TokenGated_Roles_v1_Metadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "AUT_TokenGated_Roles_v1"
    );

    // Single Vote Governor
    address AUT_EXT_VotingRoles_v1_Implementation;
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
    IModule_v1.Metadata PP_Simple_v1_Metadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "PP_Simple_v1"
    );

    // Streaming Payment Processor
    address PP_Streaming_v1_Implementation;
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
    IModule_v1.Metadata LM_PC_Bounties_v1_Metadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "LM_PC_Bounties_v1"
    );

    // Recurring Payment Manager
    address LM_PC_RecurringPayments_v1_Implementation;
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
    IModule_v1.Metadata LM_PC_PaymentRouter_v1_Metadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "LM_PC_PaymentRouter_v1"
    );

    // KPI Rewarder
    address LM_PC_KPIRewarder_v1_Implementation;
    IModule_v1.Metadata LM_PC_KPIRewarder_v1_Metadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "LM_PC_KPIRewarder_v1"
    );
}
