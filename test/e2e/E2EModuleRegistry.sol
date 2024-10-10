// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// Factories
import {ModuleFactory_v1} from "src/factories/ModuleFactory_v1.sol";
import {IOrchestratorFactory_v1} from
    "src/factories/interfaces/IOrchestratorFactory_v1.sol";

// Governance
import {Governor_v1} from "@ex/governance/Governor_v1.sol";

// Modules
import {IModule_v1} from "src/modules/base/IModule_v1.sol";
import {FM_Rebasing_v1} from "@fm/rebasing/FM_Rebasing_v1.sol";
import {FM_BC_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/FM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
import {BancorFormula} from "@fm/bondingCurve/formulas/BancorFormula.sol";
import {PP_Simple_v1} from "src/modules/paymentProcessor/PP_Simple_v1.sol";
import {PP_Streaming_v1} from "src/modules/paymentProcessor/PP_Streaming_v1.sol";
import {LM_PC_Bounties_v1} from "@lm/LM_PC_Bounties_v1.sol";
import {LM_PC_RecurringPayments_v1} from "@lm/LM_PC_RecurringPayments_v1.sol";
import {LM_PC_PaymentRouter_v1} from "@lm/LM_PC_PaymentRouter_v1.sol";
import {LM_PC_Staking_v1} from "@lm/LM_PC_Staking_v1.sol";
import {LM_PC_KPIRewarder_v1} from "@lm/LM_PC_KPIRewarder_v1.sol";
import {AUT_Roles_v1} from "@aut/role/AUT_Roles_v1.sol";
import {AUT_TokenGated_Roles_v1} from "@aut/role/AUT_TokenGated_Roles_v1.sol";
import {AUT_EXT_VotingRoles_v1} from
    "src/modules/authorizer/extensions/AUT_EXT_VotingRoles_v1.sol";

// Beacon
import {
    InverterBeacon_v1,
    IInverterBeacon_v1
} from "src/proxies/InverterBeacon_v1.sol";

contract E2EModuleRegistry is Test {
    // General Storage and QOL-constants
    ModuleFactory_v1 moduleFactory;
    Governor_v1 gov;

    address communityMultisig = makeAddr("communityMultisig");
    address teamMultisig = makeAddr("teamMultisig");
    address treasury = makeAddr("treasury");

    address public DEFAULT_BEACON_OWNER = address(0x3BEAC0);

    //--------------------------------------------------------------------------
    // General Module Information
    //--------------------------------------------------------------------------
    // # TEMPLATE
    // Each module should declare:
    //      Module moduleImpl;
    //      InverterBeacon_v1 moduleBeacon;
    //      address moduleBeaconOwner = DEFAULT_BEACON_OWNER;
    //      IModule_v1.Metadata moduleMetadata = IModule_v1.Metadata(
    //          1, 1, "https://github.com/inverter/module", "ModuleName"
    //      );
    // And AS A COMMENT:
    // /*
    //  // Example Config:
    //      IOrchestratorFactory_v1.ModuleConfig(
    //          moduleMetadata,
    //          abi.encode(address(this)),
    //
    //      );
    // */
    // Followed by the  setUpModule() function.
    // This config can be copied to the setup function of each specific E2ETest contract and modified accordingly
    //--------------------------------------------------------------------------

    //--------------------------------------------------------------------------
    // Funding Managers
    //--------------------------------------------------------------------------

    // FM_Rebasing_v1

    FM_Rebasing_v1 rebasingFundingManagerImpl;

    InverterBeacon_v1 rebasingFundingManagerBeacon;

    IModule_v1.Metadata rebasingFundingManagerMetadata = IModule_v1.Metadata(
        1, 0, 0, "https://github.com/inverter/funding-manager", "FM_Rebasing_v1"
    );

    /*
    IOrchestratorFactory_v1.ModuleConfig rebasingFundingManagerFactoryConfig =
        IOrchestratorFactory_v1.ModuleConfig(
            rebasingFundingManagerMetadata,
            abi.encode(address(token)),
             
        )
    */

    function setUpRebasingFundingManager() internal {
        // Deploy module implementations.
        rebasingFundingManagerImpl = new FM_Rebasing_v1();

        // Deploy module beacons.
        rebasingFundingManagerBeacon = new InverterBeacon_v1(
            moduleFactory.reverter(),
            DEFAULT_BEACON_OWNER,
            rebasingFundingManagerMetadata.majorVersion,
            address(rebasingFundingManagerImpl),
            rebasingFundingManagerMetadata.minorVersion,
            rebasingFundingManagerMetadata.patchVersion
        );

        // Register modules at moduleFactory.
        vm.prank(teamMultisig);
        gov.registerMetadataInModuleFactory(
            rebasingFundingManagerMetadata,
            IInverterBeacon_v1(rebasingFundingManagerBeacon)
        );
    }

    // FM_BC_Bancor_Redeeming_VirtualSupply_v1

    BancorFormula formula = new BancorFormula();

    FM_BC_Bancor_Redeeming_VirtualSupply_v1
        bancorVirtualSupplyBondingCurveFundingManagerImpl;

    InverterBeacon_v1 bancorVirtualSupplyBondingCurveFundingManagerBeacon;

    IModule_v1.Metadata bancorVirtualSupplyBondingCurveFundingManagerMetadata =
    IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/inverter/bonding-curve-funding-manager",
        "FM_BC_Bancor_Redeeming_VirtualSupply_v1"
    );

    /*
        IFM_BC_Bancor_Redeeming_VirtualSupply_v1.IssuanceToken memory
            issuanceToken = IFM_BC_Bancor_Redeeming_VirtualSupply_v1
                .IssuanceToken({
                name: bytes32(abi.encodePacked("Bonding Curve Token")),
                symbol: bytes32(abi.encodePacked("BCT")),
                decimals: uint8(18)
            });

        IFM_BC_Bancor_Redeeming_VirtualSupply_v1.BondingCurveProperties
            memory bc_properties =
            IFM_BC_Bancor_Redeeming_VirtualSupply_v1
                .BondingCurveProperties({
                formula: address(formula),
                reserveRatioForBuying: 200_000,
                reserveRatioForSelling: 200_000,
                buyFee: 0,
                sellFee: 0,
                buyIsOpen: true,
                sellIsOpen: true,
                initialIssuanceSupply: 100,
                initialCollateralSupply: 100
            });

        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                bancorVirtualSupplyBondingCurveFundingManagerMetadata,
                abi.encode(issuanceToken, bc_properties, token)
                 
            )
        );
    */

    function setUpBancorVirtualSupplyBondingCurveFundingManager() internal {
        // Deploy module implementations.
        bancorVirtualSupplyBondingCurveFundingManagerImpl =
            new FM_BC_Bancor_Redeeming_VirtualSupply_v1();

        // Deploy module beacons.
        bancorVirtualSupplyBondingCurveFundingManagerBeacon = new InverterBeacon_v1(
            moduleFactory.reverter(),
            DEFAULT_BEACON_OWNER,
            bancorVirtualSupplyBondingCurveFundingManagerMetadata.majorVersion,
            address(bancorVirtualSupplyBondingCurveFundingManagerImpl),
            bancorVirtualSupplyBondingCurveFundingManagerMetadata.minorVersion,
            bancorVirtualSupplyBondingCurveFundingManagerMetadata.patchVersion
        );

        // Register modules at moduleFactory.
        vm.prank(teamMultisig);
        gov.registerMetadataInModuleFactory(
            bancorVirtualSupplyBondingCurveFundingManagerMetadata,
            IInverterBeacon_v1(
                bancorVirtualSupplyBondingCurveFundingManagerBeacon
            )
        );
    }

    //--------------------------------------------------------------------------
    // Authorizers
    //--------------------------------------------------------------------------

    // Role Authorizer

    AUT_Roles_v1 roleAuthorizerImpl;

    InverterBeacon_v1 roleAuthorizerBeacon;

    IModule_v1.Metadata roleAuthorizerMetadata = IModule_v1.Metadata(
        1, 0, 0, "https://github.com/inverter/roleAuthorizer", "AUT_Roles_v1"
    );

    /* 
    // Note that AUT_Roles_v1 owner and manager are the same
    IOrchestratorFactory_v1.ModuleConfig roleAuthorizerFactoryConfig =
    IOrchestratorFactory_v1.ModuleConfig(
        roleAuthorizerMetadata,
        abi.encode(address(this))  
    );
    */
    function setUpRoleAuthorizer() internal {
        // Deploy module implementations.
        roleAuthorizerImpl = new AUT_Roles_v1();

        // Deploy module beacons.
        roleAuthorizerBeacon = new InverterBeacon_v1(
            moduleFactory.reverter(),
            DEFAULT_BEACON_OWNER,
            roleAuthorizerMetadata.majorVersion,
            address(roleAuthorizerImpl),
            roleAuthorizerMetadata.minorVersion,
            roleAuthorizerMetadata.patchVersion
        );

        // Register modules at moduleFactory.
        vm.prank(teamMultisig);
        gov.registerMetadataInModuleFactory(
            roleAuthorizerMetadata, IInverterBeacon_v1(roleAuthorizerBeacon)
        );
    }

    // Token Gated Role Authorizer

    AUT_TokenGated_Roles_v1 tokenRoleAuthorizerImpl;

    InverterBeacon_v1 tokenRoleAuthorizerBeacon;

    IModule_v1.Metadata tokenRoleAuthorizerMetadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/inverter/tokenRoleAuthorizer",
        "AUT_TokenGated_Roles_v1"
    );

    /* 
    // Note that AUT_Roles_v1 owner and manager are the same
    IOrchestratorFactory_v1.ModuleConfig tokenRoleAuthorizerFactoryConfig =
    IOrchestratorFactory_v1.ModuleConfig(
        tokenRoleAuthorizerMetadata,
        abi.encode(address(this))  
    ); 
    */

    function setUpTokenGatedRoleAuthorizer() internal {
        // Deploy module implementations.
        tokenRoleAuthorizerImpl = new AUT_TokenGated_Roles_v1();

        // Deploy module beacons.
        tokenRoleAuthorizerBeacon = new InverterBeacon_v1(
            moduleFactory.reverter(),
            DEFAULT_BEACON_OWNER,
            tokenRoleAuthorizerMetadata.majorVersion,
            address(tokenRoleAuthorizerImpl),
            tokenRoleAuthorizerMetadata.minorVersion,
            tokenRoleAuthorizerMetadata.patchVersion
        );

        // Register modules at moduleFactory.
        vm.prank(teamMultisig);
        gov.registerMetadataInModuleFactory(
            tokenRoleAuthorizerMetadata,
            IInverterBeacon_v1(tokenRoleAuthorizerBeacon)
        );
    }

    //--------------------------------------------------------------------------
    // Payment Processors
    //--------------------------------------------------------------------------

    // PP_Simple_v1

    PP_Simple_v1 simplePaymentProcessorImpl;

    InverterBeacon_v1 simplePaymentProcessorBeacon;

    IModule_v1.Metadata simplePaymentProcessorMetadata = IModule_v1.Metadata(
        1, 0, 0, "https://github.com/inverter/payment-processor", "PP_Simple_v1"
    );

    /*
     IOrchestratorFactory_v1.ModuleConfig simplePaymentProcessorFactoryConfig =
    IOrchestratorFactory_v1.ModuleConfig(
        simplePaymentProcessorMetadata,
        bytes("")  
    );
    */
    function setUpSimplePaymentProcessor() internal {
        // Deploy module implementations.
        simplePaymentProcessorImpl = new PP_Simple_v1();

        // Deploy module beacons.
        simplePaymentProcessorBeacon = new InverterBeacon_v1(
            moduleFactory.reverter(),
            DEFAULT_BEACON_OWNER,
            simplePaymentProcessorMetadata.majorVersion,
            address(simplePaymentProcessorImpl),
            simplePaymentProcessorMetadata.minorVersion,
            simplePaymentProcessorMetadata.patchVersion
        );

        // Register modules at moduleFactory.
        vm.prank(teamMultisig);
        gov.registerMetadataInModuleFactory(
            simplePaymentProcessorMetadata,
            IInverterBeacon_v1(simplePaymentProcessorBeacon)
        );
    }

    // PP_Streaming_v1

    PP_Streaming_v1 streamingPaymentProcessorImpl;

    InverterBeacon_v1 streamingPaymentProcessorBeacon;

    IModule_v1.Metadata streamingPaymentProcessorMetadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/inverter/streaming-payment-processor",
        "PP_Streaming_v1"
    );

    /*
     IOrchestratorFactory_v1.ModuleConfig streamingPaymentProcessorFactoryConfig =
    IOrchestratorFactory_v1.ModuleConfig(
        streamingPaymentProcessorMetadata,
        bytes(""),
         HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
    );
    */
    function setUpStreamingPaymentProcessor() internal {
        // Deploy module implementations.
        streamingPaymentProcessorImpl = new PP_Streaming_v1();

        // Deploy module beacons.
        streamingPaymentProcessorBeacon = new InverterBeacon_v1(
            moduleFactory.reverter(),
            DEFAULT_BEACON_OWNER,
            streamingPaymentProcessorMetadata.majorVersion,
            address(streamingPaymentProcessorImpl),
            streamingPaymentProcessorMetadata.minorVersion,
            streamingPaymentProcessorMetadata.patchVersion
        );

        // Register modules at moduleFactory.
        vm.prank(teamMultisig);
        gov.registerMetadataInModuleFactory(
            streamingPaymentProcessorMetadata,
            IInverterBeacon_v1(streamingPaymentProcessorBeacon)
        );
    }

    //--------------------------------------------------------------------------
    // logicModules

    // LM_PC_RecurringPayments_v1

    LM_PC_RecurringPayments_v1 recurringPaymentManagerImpl;

    InverterBeacon_v1 recurringPaymentManagerBeacon;

    IModule_v1.Metadata recurringPaymentManagerMetadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/inverter/recurring-payment-manager",
        "LM_PC_RecurringPayments_v1"
    );
    /*
    IOrchestratorFactory_v1.ModuleConfig recurringPaymentManagerFactoryConfig =
    IOrchestratorFactory_v1.ModuleConfig(
        recurringPaymentManagerMetadata,
        abi.encode(1 weeks)  
    );
    */

    function setUpRecurringPaymentManager() internal {
        // Deploy module implementations.
        recurringPaymentManagerImpl = new LM_PC_RecurringPayments_v1();

        // Deploy module beacons.
        recurringPaymentManagerBeacon = new InverterBeacon_v1(
            moduleFactory.reverter(),
            DEFAULT_BEACON_OWNER,
            recurringPaymentManagerMetadata.majorVersion,
            address(recurringPaymentManagerImpl),
            recurringPaymentManagerMetadata.minorVersion,
            recurringPaymentManagerMetadata.patchVersion
        );

        // Register modules at moduleFactory.
        vm.prank(teamMultisig);
        gov.registerMetadataInModuleFactory(
            recurringPaymentManagerMetadata,
            IInverterBeacon_v1(recurringPaymentManagerBeacon)
        );
    }

    // LM_PC_Bounties_v1

    LM_PC_Bounties_v1 bountyManagerImpl;

    InverterBeacon_v1 bountyManagerBeacon;

    IModule_v1.Metadata bountyManagerMetadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/inverter/bounty-manager",
        "LM_PC_Bounties_v1"
    );
    /*
     IOrchestratorFactory_v1.ModuleConfig bountyManagerFactoryConfig =
    IOrchestratorFactory_v1.ModuleConfig(
        bountyManagerMetadata,
        bytes(""),
        abi.encode(true, EMPTY_DEPENDENCY_LIST)
    ); 
    */

    function setUpBountyManager() internal {
        // Deploy module implementations.
        bountyManagerImpl = new LM_PC_Bounties_v1();

        // Deploy module beacons.
        bountyManagerBeacon = new InverterBeacon_v1(
            moduleFactory.reverter(),
            DEFAULT_BEACON_OWNER,
            bountyManagerMetadata.majorVersion,
            address(bountyManagerImpl),
            bountyManagerMetadata.minorVersion,
            bountyManagerMetadata.patchVersion
        );

        // Register modules at moduleFactory.
        vm.prank(teamMultisig);
        gov.registerMetadataInModuleFactory(
            bountyManagerMetadata, IInverterBeacon_v1(bountyManagerBeacon)
        );
    }

    // LM_PC_PaymentRouter_v1
    LM_PC_PaymentRouter_v1 paymentRouterImpl;

    InverterBeacon_v1 paymentRouterBeacon;

    IModule_v1.Metadata public paymentRouterMetadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/InverterNetwork/contracts",
        "LM_PC_PaymentRouter_v1"
    );

    /*
     IOrchestratorFactory_v1.ModuleConfig paymentRouterFactoryConfig =
    IOrchestratorFactory_v1.ModuleConfig(
        paymentRouterMetadata,
        bytes(""),
        HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
    );
    */

    function setUpPaymentRouter() internal {
        // Deploy module implementations.
        paymentRouterImpl = new LM_PC_PaymentRouter_v1();

        // Deploy module beacons.
        paymentRouterBeacon = new InverterBeacon_v1(
            moduleFactory.reverter(),
            DEFAULT_BEACON_OWNER,
            paymentRouterMetadata.majorVersion,
            address(paymentRouterImpl),
            paymentRouterMetadata.minorVersion,
            paymentRouterMetadata.patchVersion
        );

        // Register modules at moduleFactory.
        vm.prank(teamMultisig);
        gov.registerMetadataInModuleFactory(
            paymentRouterMetadata, IInverterBeacon_v1(paymentRouterBeacon)
        );
    }

    // LM_PC_Staking_v1

    LM_PC_Staking_v1 LM_PC_Staking_v1Impl;

    InverterBeacon_v1 LM_PC_Staking_v1Beacon;

    IModule_v1.Metadata LM_PC_Staking_v1Metadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/inverter/staking-manager",
        "LM_PC_Staking_v1"
    );

    /*
     IOrchestratorFactory_v1.ModuleConfig LM_PC_Staking_v1FactoryConfig =
    IOrchestratorFactory_v1.ModuleConfig(
        LM_PC_Staking_v1Metadata,
        bytes(address(stakingToken))  
    ); 
    */

    function setUpLM_PC_Staking_v1() internal {
        // Deploy module implementations.
        LM_PC_Staking_v1Impl = new LM_PC_Staking_v1();

        // Deploy module beacons.
        LM_PC_Staking_v1Beacon = new InverterBeacon_v1(
            moduleFactory.reverter(),
            DEFAULT_BEACON_OWNER,
            LM_PC_Staking_v1Metadata.majorVersion,
            address(LM_PC_Staking_v1Impl),
            LM_PC_Staking_v1Metadata.minorVersion,
            LM_PC_Staking_v1Metadata.patchVersion
        );

        // Register modules at moduleFactory.
        vm.prank(teamMultisig);
        gov.registerMetadataInModuleFactory(
            LM_PC_Staking_v1Metadata, IInverterBeacon_v1(LM_PC_Staking_v1Beacon)
        );
    }

    // LM_PC_KPIRewarder_v1

    LM_PC_KPIRewarder_v1 LM_PC_KPIRewarder_v1Impl;

    InverterBeacon_v1 LM_PC_KPIRewarder_v1Beacon;

    IModule_v1.Metadata LM_PC_KPIRewarder_v1Metadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/inverter/KPI-Rewarder",
        "LM_PC_KPIRewarder_v1"
    );

    /*
     IOrchestratorFactory_v1.ModuleConfig LM_PC_KPIRewarder_v1FactoryConfig =
    IOrchestratorFactory_v1.ModuleConfig(
        LM_PC_KPIRewarder_v1Metadata,
        abi.encode(address(stakingToken), address(oracleBondToken), address(OptimisticOracleV3Address), uint64(assertionLiveness) )  
    ); 
    */

    function setUpLM_PC_KPIRewarder_v1() internal {
        // Deploy module implementations.
        LM_PC_KPIRewarder_v1Impl = new LM_PC_KPIRewarder_v1();

        // Deploy module beacons.
        LM_PC_KPIRewarder_v1Beacon = new InverterBeacon_v1(
            moduleFactory.reverter(),
            DEFAULT_BEACON_OWNER,
            LM_PC_KPIRewarder_v1Metadata.majorVersion,
            address(LM_PC_KPIRewarder_v1Impl),
            LM_PC_KPIRewarder_v1Metadata.minorVersion,
            LM_PC_KPIRewarder_v1Metadata.patchVersion
        );

        // Register modules at moduleFactory.
        vm.prank(teamMultisig);
        gov.registerMetadataInModuleFactory(
            LM_PC_KPIRewarder_v1Metadata,
            IInverterBeacon_v1(LM_PC_KPIRewarder_v1Beacon)
        );
    }

    //--------------------------------------------------------------------------
    // utils

    // AUT_EXT_VotingRoles_v1

    AUT_EXT_VotingRoles_v1 votingRolesImpl;

    InverterBeacon_v1 votingRolesBeacon;

    IModule_v1.Metadata votingRolesMetadata = IModule_v1.Metadata(
        1,
        0,
        0,
        "https://github.com/inverter/single-vote-governor",
        "AUT_EXT_VotingRoles_v1"
    );

    /*    
    address[] initialVoters =
        [makeAddr("voter1"), makeAddr("voter2"), makeAddr("voter3")];

    IOrchestratorFactory_v1.ModuleConfig votingRolesFactoryConfig =
    IOrchestratorFactory_v1.ModuleConfig(
        votingRolesMetadata,
        abi.encode(initialVoters, 2, 3 days)  
    ); 
    */

    function setUpVotingRoles() internal {
        // Deploy module implementations.
        votingRolesImpl = new AUT_EXT_VotingRoles_v1();

        // Deploy module beacons.
        votingRolesBeacon = new InverterBeacon_v1(
            moduleFactory.reverter(),
            DEFAULT_BEACON_OWNER,
            votingRolesMetadata.majorVersion,
            address(votingRolesImpl),
            votingRolesMetadata.minorVersion,
            votingRolesMetadata.patchVersion
        );

        // Register modules at moduleFactory.
        vm.prank(teamMultisig);
        gov.registerMetadataInModuleFactory(
            votingRolesMetadata, IInverterBeacon_v1(votingRolesBeacon)
        );
    }
}
