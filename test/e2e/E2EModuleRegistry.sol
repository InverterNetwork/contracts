// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// Factories
import {ModuleFactory_v1} from "src/factories/ModuleFactory_v1.sol";
import {IOrchestratorFactory_v1} from
    "src/factories/interfaces/IOrchestratorFactory_v1.sol";

// Modules
import {IModule_v1} from "src/modules/base/IModule_v1.sol";
import {FM_Rebasing_v1} from "@fm/rebasing/FM_Rebasing_v1.sol";
import {FM_BC_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/FM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
import {BancorFormula} from "@fm/bondingCurve/formulas/BancorFormula.sol";
import {SimplePaymentProcessor} from
    "src/modules/paymentProcessor/SimplePaymentProcessor.sol";
import {StreamingPaymentProcessor} from
    "src/modules/paymentProcessor/StreamingPaymentProcessor.sol";
import {BountyManager} from "src/modules/logicModule/BountyManager.sol";
import {RecurringPaymentManager} from
    "src/modules/logicModule/RecurringPaymentManager.sol";
import {RoleAuthorizer} from "src/modules/authorizer/RoleAuthorizer.sol";
import {TokenGatedRoleAuthorizer} from
    "src/modules/authorizer/TokenGatedRoleAuthorizer.sol";
import {SingleVoteGovernor} from "src/modules/utils/SingleVoteGovernor.sol";
import {MetadataManager} from "src/modules/utils/MetadataManager.sol";

// Beacon
import {
    InverterBeacon_v1,
    IInverterBeacon_v1
} from "src/proxies/InverterBeacon_v1.sol";

contract E2EModuleRegistry is Test {
    // General Storage and  QOL-constants
    ModuleFactory_v1 moduleFactory;

    address public DEFAULT_BEACON_OWNER = address(0x3BEAC0);

    bool constant HAS_NO_DEPENDENCIES = false;
    string[] EMPTY_DEPENDENCY_LIST = new string[](0);

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
    //  //Example Config:
    //      IOrchestratorFactory_v1.ModuleConfig(
    //          moduleMetadata,
    //          abi.encode(address(this)),
    //          abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
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
        1, 0, "https://github.com/inverter/funding-manager", "FM_Rebasing_v1"
    );

    /*
    IOrchestratorFactory_v1.ModuleConfig rebasingFundingManagerFactoryConfig =
        IOrchestratorFactory_v1.ModuleConfig(
            rebasingFundingManagerMetadata,
            abi.encode(address(token)),
            abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
        )
    */

    function setUpRebasingFundingManager() internal {
        // Deploy module implementations.
        rebasingFundingManagerImpl = new FM_Rebasing_v1();

        // Deploy module beacons.
        rebasingFundingManagerBeacon = new InverterBeacon_v1(
            DEFAULT_BEACON_OWNER,
            rebasingFundingManagerMetadata.majorVersion,
            address(rebasingFundingManagerImpl),
            rebasingFundingManagerMetadata.minorVersion
        );

        // Register modules at moduleFactory.
        moduleFactory.registerMetadata(
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
                abi.encode(issuanceToken, bc_properties, token),
                abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
            )
        );
    */

    function setUpBancorVirtualSupplyBondingCurveFundingManager() internal {
        // Deploy module implementations.
        bancorVirtualSupplyBondingCurveFundingManagerImpl =
            new FM_BC_Bancor_Redeeming_VirtualSupply_v1();

        // Deploy module beacons.
        bancorVirtualSupplyBondingCurveFundingManagerBeacon = new InverterBeacon_v1(
            DEFAULT_BEACON_OWNER,
            bancorVirtualSupplyBondingCurveFundingManagerMetadata.majorVersion,
            address(bancorVirtualSupplyBondingCurveFundingManagerImpl),
            bancorVirtualSupplyBondingCurveFundingManagerMetadata.minorVersion
        );

        // Register modules at moduleFactory.
        moduleFactory.registerMetadata(
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

    RoleAuthorizer roleAuthorizerImpl;

    InverterBeacon_v1 roleAuthorizerBeacon;

    IModule_v1.Metadata roleAuthorizerMetadata = IModule_v1.Metadata(
        1, 0, "https://github.com/inverter/roleAuthorizer", "RoleAuthorizer"
    );

    /* 
    // Note that RoleAuthorizer owner and manager are the same
    IOrchestratorFactory_v1.ModuleConfig roleAuthorizerFactoryConfig =
    IOrchestratorFactory_v1.ModuleConfig(
        roleAuthorizerMetadata,
        abi.encode(address(this), address(this)),
        abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
    );
    */
    function setUpRoleAuthorizer() internal {
        // Deploy module implementations.
        roleAuthorizerImpl = new RoleAuthorizer();

        // Deploy module beacons.
        roleAuthorizerBeacon = new InverterBeacon_v1(
            DEFAULT_BEACON_OWNER,
            roleAuthorizerMetadata.majorVersion,
            address(roleAuthorizerImpl),
            roleAuthorizerMetadata.minorVersion
        );

        // Register modules at moduleFactory.
        moduleFactory.registerMetadata(
            roleAuthorizerMetadata, IInverterBeacon_v1(roleAuthorizerBeacon)
        );
    }

    // Token Gated Role Authorizer

    TokenGatedRoleAuthorizer tokenRoleAuthorizerImpl;

    InverterBeacon_v1 tokenRoleAuthorizerBeacon;

    IModule_v1.Metadata tokenRoleAuthorizerMetadata = IModule_v1.Metadata(
        1,
        0,
        "https://github.com/inverter/tokenRoleAuthorizer",
        "TokenGatedRoleAuthorizer"
    );

    /* 
    // Note that RoleAuthorizer owner and manager are the same
    IOrchestratorFactory_v1.ModuleConfig tokenRoleAuthorizerFactoryConfig =
    IOrchestratorFactory_v1.ModuleConfig(
        tokenRoleAuthorizerMetadata,
        abi.encode(address(this), address(this)),
        abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
    ); 
    */

    function setUpTokenGatedRoleAuthorizer() internal {
        // Deploy module implementations.
        tokenRoleAuthorizerImpl = new TokenGatedRoleAuthorizer();

        // Deploy module beacons.
        tokenRoleAuthorizerBeacon = new InverterBeacon_v1(
            DEFAULT_BEACON_OWNER,
            tokenRoleAuthorizerMetadata.majorVersion,
            address(tokenRoleAuthorizerImpl),
            tokenRoleAuthorizerMetadata.minorVersion
        );

        // Register modules at moduleFactory.
        moduleFactory.registerMetadata(
            tokenRoleAuthorizerMetadata,
            IInverterBeacon_v1(tokenRoleAuthorizerBeacon)
        );
    }

    //--------------------------------------------------------------------------
    // Payment Processors
    //--------------------------------------------------------------------------

    // SimplePaymentProcessor

    SimplePaymentProcessor simplePaymentProcessorImpl;

    InverterBeacon_v1 simplePaymentProcessorBeacon;

    IModule_v1.Metadata simplePaymentProcessorMetadata = IModule_v1.Metadata(
        1,
        0,
        "https://github.com/inverter/payment-processor",
        "SimplePaymentProcessor"
    );

    /*
     IOrchestratorFactory_v1.ModuleConfig simplePaymentProcessorFactoryConfig =
    IOrchestratorFactory_v1.ModuleConfig(
        simplePaymentProcessorMetadata,
        bytes(""),
        abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
    );
    */
    function setUpSimplePaymentProcessor() internal {
        // Deploy module implementations.
        simplePaymentProcessorImpl = new SimplePaymentProcessor();

        // Deploy module beacons.
        simplePaymentProcessorBeacon = new InverterBeacon_v1(
            DEFAULT_BEACON_OWNER,
            simplePaymentProcessorMetadata.majorVersion,
            address(simplePaymentProcessorImpl),
            simplePaymentProcessorMetadata.minorVersion
        );

        // Register modules at moduleFactory.
        moduleFactory.registerMetadata(
            simplePaymentProcessorMetadata,
            IInverterBeacon_v1(simplePaymentProcessorBeacon)
        );
    }

    // StreamingPaymentProcessor

    StreamingPaymentProcessor streamingPaymentProcessorImpl;

    InverterBeacon_v1 streamingPaymentProcessorBeacon;

    IModule_v1.Metadata streamingPaymentProcessorMetadata = IModule_v1.Metadata(
        1,
        0,
        "https://github.com/inverter/streaming-payment-processor",
        "StreamingPaymentProcessor"
    );

    /*
     IOrchestratorFactory_v1.ModuleConfig streamingPaymentProcessorFactoryConfig =
    IOrchestratorFactory_v1.ModuleConfig(
        streamingPaymentProcessorMetadata,
        bytes(""),
        abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
    );
    */
    function setUpStreamingPaymentProcessor() internal {
        // Deploy module implementations.
        streamingPaymentProcessorImpl = new StreamingPaymentProcessor();

        // Deploy module beacons.
        streamingPaymentProcessorBeacon = new InverterBeacon_v1(
            DEFAULT_BEACON_OWNER,
            streamingPaymentProcessorMetadata.majorVersion,
            address(streamingPaymentProcessorImpl),
            streamingPaymentProcessorMetadata.minorVersion
        );

        // Register modules at moduleFactory.
        moduleFactory.registerMetadata(
            streamingPaymentProcessorMetadata,
            IInverterBeacon_v1(streamingPaymentProcessorBeacon)
        );
    }

    //--------------------------------------------------------------------------
    // logicModules

    // RecurringPaymentManager

    RecurringPaymentManager recurringPaymentManagerImpl;

    InverterBeacon_v1 recurringPaymentManagerBeacon;

    IModule_v1.Metadata recurringPaymentManagerMetadata = IModule_v1.Metadata(
        1,
        0,
        "https://github.com/inverter/recurring-payment-manager",
        "RecurringPaymentManager"
    );
    /*
    IOrchestratorFactory_v1.ModuleConfig recurringPaymentManagerFactoryConfig =
    IOrchestratorFactory_v1.ModuleConfig(
        recurringPaymentManagerMetadata,
        abi.encode(1 weeks),
        abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
    );
    */

    function setUpRecurringPaymentManager() internal {
        // Deploy module implementations.
        recurringPaymentManagerImpl = new RecurringPaymentManager();

        // Deploy module beacons.
        recurringPaymentManagerBeacon = new InverterBeacon_v1(
            DEFAULT_BEACON_OWNER,
            recurringPaymentManagerMetadata.majorVersion,
            address(recurringPaymentManagerImpl),
            recurringPaymentManagerMetadata.minorVersion
        );

        // Register modules at moduleFactory.
        moduleFactory.registerMetadata(
            recurringPaymentManagerMetadata,
            IInverterBeacon_v1(recurringPaymentManagerBeacon)
        );
    }

    // BountyManager

    BountyManager bountyManagerImpl;

    InverterBeacon_v1 bountyManagerBeacon;

    IModule_v1.Metadata bountyManagerMetadata = IModule_v1.Metadata(
        1, 0, "https://github.com/inverter/bounty-manager", "BountyManager"
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
        bountyManagerImpl = new BountyManager();

        // Deploy module beacons.
        bountyManagerBeacon = new InverterBeacon_v1(
            DEFAULT_BEACON_OWNER,
            bountyManagerMetadata.majorVersion,
            address(bountyManagerImpl),
            bountyManagerMetadata.minorVersion
        );

        // Register modules at moduleFactory.
        moduleFactory.registerMetadata(
            bountyManagerMetadata, IInverterBeacon_v1(bountyManagerBeacon)
        );
    }

    //--------------------------------------------------------------------------
    // utils

    // SingleVoteGovernor

    SingleVoteGovernor singleVoteGovernorImpl;

    InverterBeacon_v1 singleVoteGovernorBeacon;

    IModule_v1.Metadata singleVoteGovernorMetadata = IModule_v1.Metadata(
        1,
        0,
        "https://github.com/inverter/single-vote-governor",
        "SingleVoteGovernor"
    );

    /*    
    address[] initialVoters =
        [makeAddr("voter1"), makeAddr("voter2"), makeAddr("voter3")];

    IOrchestratorFactory_v1.ModuleConfig singleVoteGovernorFactoryConfig =
    IOrchestratorFactory_v1.ModuleConfig(
        singleVoteGovernorMetadata,
        abi.encode(initialVoters, 2, 3 days),
        abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
    ); 
    */

    function setUpSingleVoteGovernor() internal {
        // Deploy module implementations.
        singleVoteGovernorImpl = new SingleVoteGovernor();

        // Deploy module beacons.
        singleVoteGovernorBeacon = new InverterBeacon_v1(
            DEFAULT_BEACON_OWNER,
            singleVoteGovernorMetadata.majorVersion,
            address(singleVoteGovernorImpl),
            singleVoteGovernorMetadata.minorVersion
        );

        // Register modules at moduleFactory.
        moduleFactory.registerMetadata(
            singleVoteGovernorMetadata,
            IInverterBeacon_v1(singleVoteGovernorBeacon)
        );
    }

    // MetadataManager

    MetadataManager metadataManagerImpl;

    InverterBeacon_v1 metadataManagerBeacon;

    IModule_v1.Metadata metadataManagerMetadata = IModule_v1.Metadata(
        1, 0, "https://github.com/inverter/metadata-manager", "MetadataManager"
    );

    function setUpMetadataManager() internal {
        // Deploy module implementations.
        metadataManagerImpl = new MetadataManager();

        // Deploy module beacons.
        metadataManagerBeacon = new InverterBeacon_v1(
            DEFAULT_BEACON_OWNER,
            metadataManagerMetadata.majorVersion,
            address(metadataManagerImpl),
            metadataManagerMetadata.minorVersion
        );

        // Register modules at moduleFactory.
        moduleFactory.registerMetadata(
            metadataManagerMetadata, IInverterBeacon_v1(metadataManagerBeacon)
        );
    }
}
