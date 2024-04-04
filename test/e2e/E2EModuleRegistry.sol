// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// Factories
import {ModuleFactory} from "src/factories/ModuleFactory.sol";
import {IOrchestratorFactory} from "src/factories/IOrchestratorFactory.sol";

// Modules
import {IModule} from "src/modules/base/IModule.sol";
import {RebasingFundingManager} from
    "src/modules/fundingManager/rebasing/RebasingFundingManager.sol";
import {FM_BC_Bancor_Redeeming_VirtualIssuance_VirtualCollateral_v1} from
    "src/modules/fundingManager/bondingCurve/FM_BC_Bancor_Redeeming_VirtualIssuance_VirtualCollateral_v1.sol";
import {BancorFormula} from
    "src/modules/fundingManager/bondingCurve/formulas/BancorFormula.sol";
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
import {Beacon, IBeacon} from "src/factories/beacon/Beacon.sol";

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
    //      Beacon moduleBeacon;
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
    //--------------------------------------------------------------------------

    //--------------------------------------------------------------------------
    // Funding Managers
    //--------------------------------------------------------------------------

    // RebasingFundingManager

    RebasingFundingManager rebasingFundingManagerImpl;

    Beacon rebasingFundingManagerBeacon;

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
        rebasingFundingManagerBeacon = new Beacon();

        // Set beacon's implementations.
        vm.prank(rebasingFundingManagerBeaconOwner);
        rebasingFundingManagerBeacon.upgradeTo(
            address(rebasingFundingManagerImpl)
        );

        // Register modules at moduleFactory.
        moduleFactory.registerMetadata(
            rebasingFundingManagerMetadata,
            IBeacon(rebasingFundingManagerBeacon)
        );
    }

    // FM_BC_Bancor_Redeeming_VirtualIssuance_VirtualCollateral_v1

    BancorFormula formula = new BancorFormula();

    FM_BC_Bancor_Redeeming_VirtualIssuance_VirtualCollateral_v1
        bancorVirtualSupplyBondingCurveFundingManagerImpl;

    Beacon bancorVirtualSupplyBondingCurveFundingManagerBeacon;

    address bancorVirtualSupplyBondingCurveFundingManagerBeaconOwner =
        DEFAULT_BEACON_OWNER;

    IModule.Metadata bancorVirtualSupplyBondingCurveFundingManagerMetadata =
    IModule.Metadata(
        1,
        1,
        "https://github.com/inverter/bonding-curve-funding-manager",
        "FM_BC_Bancor_Redeeming_VirtualIssuance_VirtualCollateral_v1"
    );

    /*
        IFM_BC_Bancor_Redeeming_VirtualIssuance_VirtualCollateral_v1.IssuanceToken memory
            issuanceToken = IFM_BC_Bancor_Redeeming_VirtualIssuance_VirtualCollateral_v1
                .IssuanceToken({
                name: bytes32(abi.encodePacked("Bonding Curve Token")),
                symbol: bytes32(abi.encodePacked("BCT")),
                decimals: uint8(18)
            });

        IFM_BC_Bancor_Redeeming_VirtualIssuance_VirtualCollateral_v1.BondingCurveProperties
            memory bc_properties =
            IFM_BC_Bancor_Redeeming_VirtualIssuance_VirtualCollateral_v1
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
            new FM_BC_Bancor_Redeeming_VirtualIssuance_VirtualCollateral_v1();

        // Deploy module beacons.
        vm.prank(bancorVirtualSupplyBondingCurveFundingManagerBeaconOwner);
        bancorVirtualSupplyBondingCurveFundingManagerBeacon = new Beacon();

        // Set beacon's implementations.
        vm.prank(bancorVirtualSupplyBondingCurveFundingManagerBeaconOwner);
        bancorVirtualSupplyBondingCurveFundingManagerBeacon.upgradeTo(
            address(bancorVirtualSupplyBondingCurveFundingManagerImpl)
        );

        // Register modules at moduleFactory.
        moduleFactory.registerMetadata(
            bancorVirtualSupplyBondingCurveFundingManagerMetadata,
            IBeacon(bancorVirtualSupplyBondingCurveFundingManagerBeacon)
        );
    }

    //--------------------------------------------------------------------------
    // Authorizers
    //--------------------------------------------------------------------------

    // Role Authorizer

    RoleAuthorizer roleAuthorizerImpl;

    Beacon roleAuthorizerBeacon;

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
        roleAuthorizerBeacon = new Beacon();

        // Set beacon's implementations.
        vm.prank(roleAuthorizerBeaconOwner);
        roleAuthorizerBeacon.upgradeTo(address(roleAuthorizerImpl));

        // Register modules at moduleFactory.
        moduleFactory.registerMetadata(
            roleAuthorizerMetadata, IBeacon(roleAuthorizerBeacon)
        );
    }

    // Token Gated Role Authorizer

    TokenGatedRoleAuthorizer tokenRoleAuthorizerImpl;

    Beacon tokenRoleAuthorizerBeacon;

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
        tokenRoleAuthorizerBeacon = new Beacon();

        // Set beacon's implementations.
        vm.prank(tokenRoleAuthorizerBeaconOwner);
        tokenRoleAuthorizerBeacon.upgradeTo(address(tokenRoleAuthorizerImpl));

        // Register modules at moduleFactory.
        moduleFactory.registerMetadata(
            tokenRoleAuthorizerMetadata, IBeacon(tokenRoleAuthorizerBeacon)
        );
    }

    //--------------------------------------------------------------------------
    // Payment Processors
    //--------------------------------------------------------------------------

    // SimplePaymentProcessor

    SimplePaymentProcessor simplePaymentProcessorImpl;

    Beacon simplePaymentProcessorBeacon;

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
        simplePaymentProcessorBeacon = new Beacon();

        // Set beacon's implementations.
        vm.prank(simplePaymentProcessorBeaconOwner);
        simplePaymentProcessorBeacon.upgradeTo(
            address(simplePaymentProcessorImpl)
        );

        // Register modules at moduleFactory.
        moduleFactory.registerMetadata(
            simplePaymentProcessorMetadata,
            IBeacon(simplePaymentProcessorBeacon)
        );
    }

    // StreamingPaymentProcessor

    StreamingPaymentProcessor streamingPaymentProcessorImpl;

    Beacon streamingPaymentProcessorBeacon;

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
        streamingPaymentProcessorBeacon = new Beacon();

        // Set beacon's implementations.
        vm.prank(streamingPaymentProcessorBeaconOwner);
        streamingPaymentProcessorBeacon.upgradeTo(
            address(streamingPaymentProcessorImpl)
        );

        // Register modules at moduleFactory.
        moduleFactory.registerMetadata(
            streamingPaymentProcessorMetadata,
            IBeacon(streamingPaymentProcessorBeacon)
        );
    }

    //--------------------------------------------------------------------------
    // logicModules

    // RecurringPaymentManager

    RecurringPaymentManager recurringPaymentManagerImpl;

    Beacon recurringPaymentManagerBeacon;

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
        recurringPaymentManagerBeacon = new Beacon();

        // Set beacon's implementations.
        vm.prank(recurringPaymentManagerBeaconOwner);
        recurringPaymentManagerBeacon.upgradeTo(
            address(recurringPaymentManagerImpl)
        );

        // Register modules at moduleFactory.
        moduleFactory.registerMetadata(
            recurringPaymentManagerMetadata,
            IBeacon(recurringPaymentManagerBeacon)
        );
    }

    // BountyManager

    BountyManager bountyManagerImpl;

    Beacon bountyManagerBeacon;

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
        bountyManagerBeacon = new Beacon();

        // Set beacon's implementations.
        vm.prank(bountyManagerBeaconOwner);
        bountyManagerBeacon.upgradeTo(address(bountyManagerImpl));

        // Register modules at moduleFactory.
        moduleFactory.registerMetadata(
            bountyManagerMetadata, IBeacon(bountyManagerBeacon)
        );
    }

    //--------------------------------------------------------------------------
    // utils

    // SingleVoteGovernor

    SingleVoteGovernor singleVoteGovernorImpl;

    Beacon singleVoteGovernorBeacon;

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
        singleVoteGovernorBeacon = new Beacon();

        // Set beacon's implementations.
        vm.prank(singleVoteGovernorBeaconOwner);
        singleVoteGovernorBeacon.upgradeTo(address(singleVoteGovernorImpl));

        // Register modules at moduleFactory.
        moduleFactory.registerMetadata(
            singleVoteGovernorMetadata, IBeacon(singleVoteGovernorBeacon)
        );
    }

    // MetadataManager

    MetadataManager metadataManagerImpl;

    Beacon metadataManagerBeacon;

    address metadataManagerBeaconOwner = DEFAULT_BEACON_OWNER;

    IModule.Metadata metadataManagerMetadata = IModule.Metadata(
        1, 1, "https://github.com/inverter/metadata-manager", "MetadataManager"
    );

    function setUpMetadataManager() internal {
        // Deploy module implementations.
        metadataManagerImpl = new MetadataManager();

        // Deploy module beacons.
        vm.prank(metadataManagerBeaconOwner);
        metadataManagerBeacon = new Beacon();

        // Set beacon's implementations.
        vm.prank(metadataManagerBeaconOwner);
        metadataManagerBeacon.upgradeTo(address(metadataManagerImpl));

        // Register modules at moduleFactory.
        moduleFactory.registerMetadata(
            metadataManagerMetadata, IBeacon(metadataManagerBeacon)
        );
    }
}
