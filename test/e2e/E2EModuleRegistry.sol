// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// Factories
import {ModuleFactory} from "src/factories/ModuleFactory.sol";
import {IOrchestratorFactory} from "src/factories/IOrchestratorFactory.sol";

// Modules
import {IModule} from "src/modules/base/IModule.sol";
import {RebasingFundingManager} from
    "src/modules/fundingManager/RebasingFundingManager.sol";
import {BancorVirtualSupplyBondingCurveFundingManager} from
    "src/modules/fundingManager/bondingCurveFundingManager/BancorVirtualSupplyBondingCurveFundingManager.sol";
import {BancorFormula} from
    "src/modules/fundingManager/bondingCurveFundingManager/formula/BancorFormula.sol";
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
    InverterBeacon,
    IInverterBeacon
} from "src/factories/beacon/InverterBeacon.sol";

contract E2EModuleRegistry is Test {
    // General Storage and  QOL-constants
    ModuleFactory moduleFactory;

    address constant DEFAULT_BEACON_OWNER = address(0x3BEAC0);

    bool constant HAS_NO_DEPENDENCIES = false;
    string[] EMPTY_DEPENDENCY_LIST = new string[](0);

    //--------------------------------------------------------------------------
    // General Module Information
    //--------------------------------------------------------------------------
    // # TEMPLATE
    // Each module should declare:
    //      Module moduleImpl;
    //      InverterBeacon moduleBeacon;
    //      address moduleBeaconOwner = DEFAULT_BEACON_OWNER;
    //      IModule.Metadata moduleMetadata = IModule.Metadata(
    //          1, 1, "https://github.com/inverter/module", "ModuleName"
    //      );
    // And AS A COMMENT:
    // /*
    //  //Example Config:
    //      IOrchestratorFactory.ModuleConfig(
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

    // RebasingFundingManager

    RebasingFundingManager rebasingFundingManagerImpl;

    InverterBeacon rebasingFundingManagerBeacon;

    address rebasingFundingManagerBeaconOwner = DEFAULT_BEACON_OWNER;

    IModule.Metadata rebasingFundingManagerMetadata = IModule.Metadata(
        1,
        1,
        "https://github.com/inverter/funding-manager",
        "RebasingFundingManager"
    );

    /*
    IOrchestratorFactory.ModuleConfig rebasingFundingManagerFactoryConfig =
        IOrchestratorFactory.ModuleConfig(
            rebasingFundingManagerMetadata,
            abi.encode(address(token)),
            abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
        )
    */

    function setUpRebasingFundingManager() internal {
        // Deploy module implementations.
        rebasingFundingManagerImpl = new RebasingFundingManager();

        // Deploy module beacons.
        vm.prank(rebasingFundingManagerBeaconOwner);
        rebasingFundingManagerBeacon =
            new InverterBeacon(rebasingFundingManagerMetadata.majorVersion);

        // Set beacon's implementations.
        vm.prank(rebasingFundingManagerBeaconOwner);
        rebasingFundingManagerBeacon.upgradeTo(
            address(rebasingFundingManagerImpl),
            rebasingFundingManagerMetadata.minorVersion,
            false
        );

        // Register modules at moduleFactory.
        moduleFactory.registerMetadata(
            rebasingFundingManagerMetadata,
            IInverterBeacon(rebasingFundingManagerBeacon)
        );
    }

    // BancorVirtualSupplyBondingCurveFundingManager

    BancorFormula formula = new BancorFormula();

    BancorVirtualSupplyBondingCurveFundingManager
        bancorVirtualSupplyBondingCurveFundingManagerImpl;

    InverterBeacon bancorVirtualSupplyBondingCurveFundingManagerBeacon;

    address bancorVirtualSupplyBondingCurveFundingManagerBeaconOwner =
        DEFAULT_BEACON_OWNER;

    IModule.Metadata bancorVirtualSupplyBondingCurveFundingManagerMetadata =
    IModule.Metadata(
        1,
        1,
        "https://github.com/inverter/bonding-curve-funding-manager",
        "BancorVirtualSupplyBondingCurveFundingManager"
    );

    /*
        IBancorVirtualSupplyBondingCurveFundingManager.IssuanceToken memory
            issuanceToken = IBancorVirtualSupplyBondingCurveFundingManager
                .IssuanceToken({
                name: bytes32(abi.encodePacked("Bonding Curve Token")),
                symbol: bytes32(abi.encodePacked("BCT")),
                decimals: uint8(18)
            });

        IBancorVirtualSupplyBondingCurveFundingManager.BondingCurveProperties
            memory bc_properties =
            IBancorVirtualSupplyBondingCurveFundingManager
                .BondingCurveProperties({
                formula: address(formula),
                reserveRatioForBuying: 200_000,
                reserveRatioForSelling: 200_000,
                buyFee: 0,
                sellFee: 0,
                buyIsOpen: true,
                sellIsOpen: true,
                initialTokenSupply: 100,
                initialCollateralSupply: 100
            });

        moduleConfigurations.push(
            IOrchestratorFactory.ModuleConfig(
                bancorVirtualSupplyBondingCurveFundingManagerMetadata,
                abi.encode(issuanceToken, bc_properties, token),
                abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
            )
        );
    */

    function setUpBancorVirtualSupplyBondingCurveFundingManager() internal {
        // Deploy module implementations.
        bancorVirtualSupplyBondingCurveFundingManagerImpl =
            new BancorVirtualSupplyBondingCurveFundingManager();

        // Deploy module beacons.
        vm.prank(bancorVirtualSupplyBondingCurveFundingManagerBeaconOwner);
        bancorVirtualSupplyBondingCurveFundingManagerBeacon = new InverterBeacon(
            bancorVirtualSupplyBondingCurveFundingManagerMetadata.majorVersion
        );

        // Set beacon's implementations.
        vm.prank(bancorVirtualSupplyBondingCurveFundingManagerBeaconOwner);
        bancorVirtualSupplyBondingCurveFundingManagerBeacon.upgradeTo(
            address(bancorVirtualSupplyBondingCurveFundingManagerImpl),
            bancorVirtualSupplyBondingCurveFundingManagerMetadata.minorVersion,
            false
        );

        // Register modules at moduleFactory.
        moduleFactory.registerMetadata(
            bancorVirtualSupplyBondingCurveFundingManagerMetadata,
            IInverterBeacon(bancorVirtualSupplyBondingCurveFundingManagerBeacon)
        );
    }

    //--------------------------------------------------------------------------
    // Authorizers
    //--------------------------------------------------------------------------

    // Role Authorizer

    RoleAuthorizer roleAuthorizerImpl;

    InverterBeacon roleAuthorizerBeacon;

    address roleAuthorizerBeaconOwner = DEFAULT_BEACON_OWNER;

    IModule.Metadata roleAuthorizerMetadata = IModule.Metadata(
        1, 1, "https://github.com/inverter/roleAuthorizer", "RoleAuthorizer"
    );

    /* 
    // Note that RoleAuthorizer owner and manager are the same
    IOrchestratorFactory.ModuleConfig roleAuthorizerFactoryConfig =
    IOrchestratorFactory.ModuleConfig(
        roleAuthorizerMetadata,
        abi.encode(address(this), address(this)),
        abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
    );
    */
    function setUpRoleAuthorizer() internal {
        // Deploy module implementations.
        roleAuthorizerImpl = new RoleAuthorizer();

        // Deploy module beacons.
        vm.prank(roleAuthorizerBeaconOwner);
        roleAuthorizerBeacon =
            new InverterBeacon(roleAuthorizerMetadata.majorVersion);

        // Set beacon's implementations.
        vm.prank(roleAuthorizerBeaconOwner);
        roleAuthorizerBeacon.upgradeTo(
            address(roleAuthorizerImpl),
            roleAuthorizerMetadata.minorVersion,
            false
        );

        // Register modules at moduleFactory.
        moduleFactory.registerMetadata(
            roleAuthorizerMetadata, IInverterBeacon(roleAuthorizerBeacon)
        );
    }

    // Token Gated Role Authorizer

    TokenGatedRoleAuthorizer tokenRoleAuthorizerImpl;

    InverterBeacon tokenRoleAuthorizerBeacon;

    address tokenRoleAuthorizerBeaconOwner = DEFAULT_BEACON_OWNER;

    IModule.Metadata tokenRoleAuthorizerMetadata = IModule.Metadata(
        1,
        1,
        "https://github.com/inverter/tokenRoleAuthorizer",
        "TokenGatedRoleAuthorizer"
    );

    /* 
    // Note that RoleAuthorizer owner and manager are the same
    IOrchestratorFactory.ModuleConfig tokenRoleAuthorizerFactoryConfig =
    IOrchestratorFactory.ModuleConfig(
        tokenRoleAuthorizerMetadata,
        abi.encode(address(this), address(this)),
        abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
    ); 
    */

    function setUpTokenGatedRoleAuthorizer() internal {
        // Deploy module implementations.
        tokenRoleAuthorizerImpl = new TokenGatedRoleAuthorizer();

        // Deploy module beacons.
        vm.prank(tokenRoleAuthorizerBeaconOwner);
        tokenRoleAuthorizerBeacon =
            new InverterBeacon(tokenRoleAuthorizerMetadata.majorVersion);

        // Set beacon's implementations.
        vm.prank(tokenRoleAuthorizerBeaconOwner);
        tokenRoleAuthorizerBeacon.upgradeTo(
            address(tokenRoleAuthorizerImpl),
            tokenRoleAuthorizerMetadata.minorVersion,
            false
        );

        // Register modules at moduleFactory.
        moduleFactory.registerMetadata(
            tokenRoleAuthorizerMetadata,
            IInverterBeacon(tokenRoleAuthorizerBeacon)
        );
    }

    //--------------------------------------------------------------------------
    // Payment Processors
    //--------------------------------------------------------------------------

    // SimplePaymentProcessor

    SimplePaymentProcessor simplePaymentProcessorImpl;

    InverterBeacon simplePaymentProcessorBeacon;

    address simplePaymentProcessorBeaconOwner = DEFAULT_BEACON_OWNER;

    IModule.Metadata simplePaymentProcessorMetadata = IModule.Metadata(
        1,
        1,
        "https://github.com/inverter/payment-processor",
        "SimplePaymentProcessor"
    );

    /*
     IOrchestratorFactory.ModuleConfig simplePaymentProcessorFactoryConfig =
    IOrchestratorFactory.ModuleConfig(
        simplePaymentProcessorMetadata,
        bytes(""),
        abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
    );
    */
    function setUpSimplePaymentProcessor() internal {
        // Deploy module implementations.
        simplePaymentProcessorImpl = new SimplePaymentProcessor();

        // Deploy module beacons.
        vm.prank(simplePaymentProcessorBeaconOwner);
        simplePaymentProcessorBeacon =
            new InverterBeacon(simplePaymentProcessorMetadata.majorVersion);

        // Set beacon's implementations.
        vm.prank(simplePaymentProcessorBeaconOwner);
        simplePaymentProcessorBeacon.upgradeTo(
            address(simplePaymentProcessorImpl),
            simplePaymentProcessorMetadata.minorVersion,
            false
        );

        // Register modules at moduleFactory.
        moduleFactory.registerMetadata(
            simplePaymentProcessorMetadata,
            IInverterBeacon(simplePaymentProcessorBeacon)
        );
    }

    // StreamingPaymentProcessor

    StreamingPaymentProcessor streamingPaymentProcessorImpl;

    InverterBeacon streamingPaymentProcessorBeacon;

    address streamingPaymentProcessorBeaconOwner = DEFAULT_BEACON_OWNER;

    IModule.Metadata streamingPaymentProcessorMetadata = IModule.Metadata(
        1,
        1,
        "https://github.com/inverter/streaming-payment-processor",
        "StreamingPaymentProcessor"
    );

    /*
     IOrchestratorFactory.ModuleConfig streamingPaymentProcessorFactoryConfig =
    IOrchestratorFactory.ModuleConfig(
        streamingPaymentProcessorMetadata,
        bytes(""),
        abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
    );
    */
    function setUpStreamingPaymentProcessor() internal {
        // Deploy module implementations.
        streamingPaymentProcessorImpl = new StreamingPaymentProcessor();

        // Deploy module beacons.
        vm.prank(streamingPaymentProcessorBeaconOwner);
        streamingPaymentProcessorBeacon =
            new InverterBeacon(streamingPaymentProcessorMetadata.majorVersion);

        // Set beacon's implementations.
        vm.prank(streamingPaymentProcessorBeaconOwner);
        streamingPaymentProcessorBeacon.upgradeTo(
            address(streamingPaymentProcessorImpl),
            streamingPaymentProcessorMetadata.minorVersion,
            false
        );

        // Register modules at moduleFactory.
        moduleFactory.registerMetadata(
            streamingPaymentProcessorMetadata,
            IInverterBeacon(streamingPaymentProcessorBeacon)
        );
    }

    //--------------------------------------------------------------------------
    // logicModules

    // RecurringPaymentManager

    RecurringPaymentManager recurringPaymentManagerImpl;

    InverterBeacon recurringPaymentManagerBeacon;

    address recurringPaymentManagerBeaconOwner = DEFAULT_BEACON_OWNER;

    IModule.Metadata recurringPaymentManagerMetadata = IModule.Metadata(
        1,
        1,
        "https://github.com/inverter/recurring-payment-manager",
        "RecurringPaymentManager"
    );
    /*
    IOrchestratorFactory.ModuleConfig recurringPaymentManagerFactoryConfig =
    IOrchestratorFactory.ModuleConfig(
        recurringPaymentManagerMetadata,
        abi.encode(1 weeks),
        abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
    );
    */

    function setUpRecurringPaymentManager() internal {
        // Deploy module implementations.
        recurringPaymentManagerImpl = new RecurringPaymentManager();

        // Deploy module beacons.
        vm.prank(recurringPaymentManagerBeaconOwner);
        recurringPaymentManagerBeacon =
            new InverterBeacon(recurringPaymentManagerMetadata.majorVersion);

        // Set beacon's implementations.
        vm.prank(recurringPaymentManagerBeaconOwner);
        recurringPaymentManagerBeacon.upgradeTo(
            address(recurringPaymentManagerImpl),
            recurringPaymentManagerMetadata.minorVersion,
            false
        );

        // Register modules at moduleFactory.
        moduleFactory.registerMetadata(
            recurringPaymentManagerMetadata,
            IInverterBeacon(recurringPaymentManagerBeacon)
        );
    }

    // BountyManager

    BountyManager bountyManagerImpl;

    InverterBeacon bountyManagerBeacon;

    address bountyManagerBeaconOwner = DEFAULT_BEACON_OWNER;

    IModule.Metadata bountyManagerMetadata = IModule.Metadata(
        1, 1, "https://github.com/inverter/bounty-manager", "BountyManager"
    );
    /*
     IOrchestratorFactory.ModuleConfig bountyManagerFactoryConfig =
    IOrchestratorFactory.ModuleConfig(
        bountyManagerMetadata,
        bytes(""),
        abi.encode(true, EMPTY_DEPENDENCY_LIST)
    ); 
    */

    function setUpBountyManager() internal {
        // Deploy module implementations.
        bountyManagerImpl = new BountyManager();

        // Deploy module beacons.
        vm.prank(bountyManagerBeaconOwner);
        bountyManagerBeacon =
            new InverterBeacon(bountyManagerMetadata.majorVersion);

        // Set beacon's implementations.
        vm.prank(bountyManagerBeaconOwner);
        bountyManagerBeacon.upgradeTo(
            address(bountyManagerImpl),
            bountyManagerMetadata.minorVersion,
            false
        );

        // Register modules at moduleFactory.
        moduleFactory.registerMetadata(
            bountyManagerMetadata, IInverterBeacon(bountyManagerBeacon)
        );
    }

    //--------------------------------------------------------------------------
    // utils

    // SingleVoteGovernor

    SingleVoteGovernor singleVoteGovernorImpl;

    InverterBeacon singleVoteGovernorBeacon;

    address singleVoteGovernorBeaconOwner = DEFAULT_BEACON_OWNER;

    IModule.Metadata singleVoteGovernorMetadata = IModule.Metadata(
        1,
        1,
        "https://github.com/inverter/single-vote-governor",
        "SingleVoteGovernor"
    );

    /*    
    address[] initialVoters =
        [makeAddr("voter1"), makeAddr("voter2"), makeAddr("voter3")];

    IOrchestratorFactory.ModuleConfig singleVoteGovernorFactoryConfig =
    IOrchestratorFactory.ModuleConfig(
        singleVoteGovernorMetadata,
        abi.encode(initialVoters, 2, 3 days),
        abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
    ); 
    */

    function setUpSingleVoteGovernor() internal {
        // Deploy module implementations.
        singleVoteGovernorImpl = new SingleVoteGovernor();

        // Deploy module beacons.
        vm.prank(singleVoteGovernorBeaconOwner);
        singleVoteGovernorBeacon =
            new InverterBeacon(singleVoteGovernorMetadata.majorVersion);

        // Set beacon's implementations.
        vm.prank(singleVoteGovernorBeaconOwner);
        singleVoteGovernorBeacon.upgradeTo(
            address(singleVoteGovernorImpl),
            singleVoteGovernorMetadata.minorVersion,
            false
        );

        // Register modules at moduleFactory.
        moduleFactory.registerMetadata(
            singleVoteGovernorMetadata,
            IInverterBeacon(singleVoteGovernorBeacon)
        );
    }

    // MetadataManager

    MetadataManager metadataManagerImpl;

    InverterBeacon metadataManagerBeacon;

    address metadataManagerBeaconOwner = DEFAULT_BEACON_OWNER;

    IModule.Metadata metadataManagerMetadata = IModule.Metadata(
        1, 1, "https://github.com/inverter/metadata-manager", "MetadataManager"
    );

    function setUpMetadataManager() internal {
        // Deploy module implementations.
        metadataManagerImpl = new MetadataManager();

        // Deploy module beacons.
        vm.prank(metadataManagerBeaconOwner);
        metadataManagerBeacon =
            new InverterBeacon(metadataManagerMetadata.majorVersion);

        // Set beacon's implementations.
        vm.prank(metadataManagerBeaconOwner);
        metadataManagerBeacon.upgradeTo(
            address(metadataManagerImpl),
            metadataManagerMetadata.minorVersion,
            false
        );

        // Register modules at moduleFactory.
        moduleFactory.registerMetadata(
            metadataManagerMetadata, IInverterBeacon(metadataManagerBeacon)
        );
    }
}
