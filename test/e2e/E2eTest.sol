// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

// Factories
import {ModuleFactory, IModuleFactory} from "src/factories/ModuleFactory.sol";
import {
    OrchestratorFactory,
    IOrchestratorFactory
} from "src/factories/OrchestratorFactory.sol";

// Orchestrator
import {Orchestrator, IOrchestrator} from "src/orchestrator/Orchestrator.sol";

// Modules
import {IModule} from "src/modules/base/IModule.sol";
import {IBancorVirtualSupplyBondingCurveFundingManager} from
    "src/modules/fundingManager/bondingCurveFundingManager/IBancorVirtualSupplyBondingCurveFundingManager.sol";
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
import {StakingManager} from "src/modules/logicModule/StakingManager.sol";
import {
    KPIRewarder
} from "src/modules/logicModule/KPIRewarder.sol";
import {RoleAuthorizer} from "src/modules/authorizer/RoleAuthorizer.sol";
import {TokenGatedRoleAuthorizer} from
    "src/modules/authorizer/TokenGatedRoleAuthorizer.sol";
import {SingleVoteGovernor} from "src/modules/utils/SingleVoteGovernor.sol";

//Mocks
import {AuthorizerMock} from "test/utils/mocks/modules/AuthorizerMock.sol";

// Beacon
import {Beacon, IBeacon} from "src/factories/beacon/Beacon.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
/**
 * @dev Base contract for e2e tests.
 */

contract E2eTest is Test {
    bool hasDependency;
    string[] dependencies = new string[](0);

    // Factory instances.
    ModuleFactory moduleFactory;
    OrchestratorFactory orchestratorFactory;

    // Orchestrator implementation.
    Orchestrator orchestratorImpl;

    //--------------------------------------------------------------------------
    // fundingManager

    // RebasingFundingManager

    RebasingFundingManager rebasingFundingManagerImpl;
    Beacon rebasingFundingManagerBeacon;
    address rebasingFundingManagerBeaconOwner = address(0x3BEAC0);
    IModule.Metadata rebasingFundingManagerMetadata = IModule.Metadata(
        1,
        1,
        "https://github.com/inverter/funding-manager",
        "RebasingFundingManager"
    );

    function setUpRebasingFundingManager() private {
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

    // BancorVirtualSupplyBondingCurveFundingManager

    BancorVirtualSupplyBondingCurveFundingManager
        bancorVirtualSupplyBondingCurveFundingManagerImpl;
    Beacon bancorVirtualSupplyBondingCurveFundingManagerBeacon;
    address bancorVirtualSupplyBondingCurveFundingManagerBeaconOwner =
        address(0x3BEAC0);
    IModule.Metadata bancorVirtualSupplyBondingCurveFundingManagerMetadata =
    IModule.Metadata(
        1,
        1,
        "https://github.com/inverter/bonding-curve-funding-manager",
        "BancorVirtualSupplyBondingCurveFundingManager"
    );

    function setUpBancorVirtualSupplyBondingCurveFundingManager() private {
        // Deploy module implementations.
        bancorVirtualSupplyBondingCurveFundingManagerImpl =
            new BancorVirtualSupplyBondingCurveFundingManager();

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
    // authorizer

    // AuthorizerMock

    AuthorizerMock authorizerImpl;
    Beacon authorizerBeacon;
    address authorizerBeaconOwner = address(0x3BEAC0);
    IModule.Metadata authorizerMetadata = IModule.Metadata(
        1, 1, "https://github.com/inverter/authorizer", "Authorizer"
    );
    // Note that the IAuthorizer's first authorized address is address(this).
    IOrchestratorFactory.ModuleConfig authorizerFactoryConfig =
    IOrchestratorFactory.ModuleConfig(
        authorizerMetadata,
        abi.encode(address(this)),
        abi.encode(hasDependency, dependencies)
    );

    function setUpAuthorizerMock() private {
        // Deploy module implementations.
        authorizerImpl = new AuthorizerMock();

        // Deploy module beacons.
        vm.prank(authorizerBeaconOwner);
        authorizerBeacon = new Beacon();

        // Set beacon's implementations.
        vm.prank(authorizerBeaconOwner);
        authorizerBeacon.upgradeTo(address(authorizerImpl));

        // Register modules at moduleFactory.
        moduleFactory.registerMetadata(
            authorizerMetadata, IBeacon(authorizerBeacon)
        );
    }

    RoleAuthorizer roleAuthorizerImpl;
    Beacon roleAuthorizerBeacon;
    address roleAuthorizerBeaconOwner = address(0x3BEAC0);
    IModule.Metadata roleAuthorizerMetadata = IModule.Metadata(
        1, 1, "https://github.com/inverter/roleAuthorizer", "RoleAuthorizer"
    );
    // Note that RoleAuthorizer owner and manager are the same
    IOrchestratorFactory.ModuleConfig roleAuthorizerFactoryConfig =
    IOrchestratorFactory.ModuleConfig(
        roleAuthorizerMetadata,
        abi.encode(address(this), address(this)),
        abi.encode(hasDependency, dependencies)
    );

    function setUpRoleAuthorizer() private {
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

    TokenGatedRoleAuthorizer tokenRoleAuthorizerImpl;
    Beacon tokenRoleAuthorizerBeacon;
    address tokenRoleAuthorizerBeaconOwner = address(0x3BEAC0);
    IModule.Metadata tokenRoleAuthorizerMetadata = IModule.Metadata(
        1,
        1,
        "https://github.com/inverter/tokenRoleAuthorizer",
        "TokenGatedRoleAuthorizer"
    );
    // Note that RoleAuthorizer owner and manager are the same
    IOrchestratorFactory.ModuleConfig tokenRoleAuthorizerFactoryConfig =
    IOrchestratorFactory.ModuleConfig(
        tokenRoleAuthorizerMetadata,
        abi.encode(address(this), address(this)),
        abi.encode(hasDependency, dependencies)
    );

    function setUpTokenGatedRoleAuthorizer() private {
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
    // paymentProcessor

    // SimplePaymentProcessor

    SimplePaymentProcessor paymentProcessorImpl;
    Beacon paymentProcessorBeacon;
    address paymentProcessorBeaconOwner = address(0x1BEAC0);
    IModule.Metadata paymentProcessorMetadata = IModule.Metadata(
        1,
        1,
        "https://github.com/inverter/payment-processor",
        "SimplePaymentProcessor"
    );
    IOrchestratorFactory.ModuleConfig paymentProcessorFactoryConfig =
    IOrchestratorFactory.ModuleConfig(
        paymentProcessorMetadata,
        bytes(""),
        abi.encode(hasDependency, dependencies)
    );

    function setUpSimplePaymentProcessor() private {
        // Deploy module implementations.
        paymentProcessorImpl = new SimplePaymentProcessor();

        // Deploy module beacons.
        vm.prank(paymentProcessorBeaconOwner);
        paymentProcessorBeacon = new Beacon();

        // Set beacon's implementations.
        vm.prank(paymentProcessorBeaconOwner);
        paymentProcessorBeacon.upgradeTo(address(paymentProcessorImpl));

        // Register modules at moduleFactory.
        moduleFactory.registerMetadata(
            paymentProcessorMetadata, IBeacon(paymentProcessorBeacon)
        );
    }

    // StreamingPaymentProcessor

    StreamingPaymentProcessor streamingPaymentProcessorImpl;
    Beacon streamingPaymentProcessorBeacon;
    address streamingPaymentProcessorBeaconOwner =
        makeAddr("streaming payment processor beacon owner");
    IModule.Metadata streamingPaymentProcessorMetadata = IModule.Metadata(
        1,
        1,
        "https://github.com/inverter/streaming-payment-processor",
        "StreamingPaymentProcessor"
    );
    IOrchestratorFactory.ModuleConfig streamingPaymentProcessorFactoryConfig =
    IOrchestratorFactory.ModuleConfig(
        streamingPaymentProcessorMetadata,
        bytes(""),
        abi.encode(hasDependency, dependencies)
    );

    function setUpStreamingPaymentProcessor() private {
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
    address recurringPaymentManagerBeaconOwner =
        makeAddr("recurring payment manager beacon owner");
    IModule.Metadata recurringPaymentManagerMetadata = IModule.Metadata(
        1,
        1,
        "https://github.com/inverter/recurring-payment-manager",
        "RecurringPaymentManager"
    );
    IOrchestratorFactory.ModuleConfig recurringPaymentManagerFactoryConfig =
    IOrchestratorFactory.ModuleConfig(
        recurringPaymentManagerMetadata,
        abi.encode(1 weeks),
        abi.encode(hasDependency, dependencies)
    );

    function setUpRecurringPaymentManager() private {
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
    address bountyManagerBeaconOwner = address(0x3BEAC0);
    IModule.Metadata bountyManagerMetadata = IModule.Metadata(
        1, 1, "https://github.com/inverter/bounty-manager", "BountyManager"
    );
    IOrchestratorFactory.ModuleConfig bountyManagerFactoryConfig =
    IOrchestratorFactory.ModuleConfig(
        bountyManagerMetadata, bytes(""), abi.encode(true, dependencies)
    );

    function setUpBountyManager() private {
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

    // StakingManager

    StakingManager stakingManagerImpl;
    Beacon stakingManagerBeacon;
    address stakingManagerBeaconOwner = address(0x3BEAC0);
    IModule.Metadata stakingManagerMetadata = IModule.Metadata(
        1, 1, "https://github.com/inverter/staking-manager", "StakingManager"
    );
    IOrchestratorFactory.ModuleConfig stakingManagerFactoryConfig;

    function setUpStakingManager() private {
        // Deploy module implementations.
        stakingManagerImpl = new StakingManager();

        // Deploy module beacons.
        vm.prank(stakingManagerBeaconOwner);
        stakingManagerBeacon = new Beacon();

        // Set beacon's implementations.
        vm.prank(stakingManagerBeaconOwner);
        stakingManagerBeacon.upgradeTo(address(stakingManagerImpl));

        // Register modules at moduleFactory.
        moduleFactory.registerMetadata(
            stakingManagerMetadata, IBeacon(stakingManagerBeacon)
        );
    }

    // KPIRewarder

    KPIRewarder kpiRewarderImpl;
    Beacon kpiRewarderBeacon;
    address kpiRewarderBeaconOwner = address(0x3BEAC0);
    IModule.Metadata kpiRewarderMetadata = IModule.Metadata(
        1, 1, "https://github.com/inverter/kpiRewarder", "KPIRewarder"
    );
    IOrchestratorFactory.ModuleConfig kpiRewarderFactoryConfig;

    function setUpKPIRewarder() private {
        // Deploy module implementations.
        kpiRewarderImpl =  new KPIRewarder();

        // Deploy module beacons.
        vm.prank(kpiRewarderBeaconOwner);
        kpiRewarderBeacon = new Beacon();

        // Set beacon's implementations.
        vm.prank(kpiRewarderBeaconOwner);
        kpiRewarderBeacon.upgradeTo(address(kpiRewarderImpl));

        // Register modules at moduleFactory.
        moduleFactory.registerMetadata(
            kpiRewarderMetadata, IBeacon(kpiRewarderBeacon)
        );
    }


    //--------------------------------------------------------------------------
    // utils

    // SingleVoteGovernor

    SingleVoteGovernor singleVoteGovernorImpl;
    Beacon singleVoteGovernorBeacon;
    address singleVoteGovernorBeaconOwner =
        makeAddr("single vote governor manager beacon owner");
    IModule.Metadata singleVoteGovernorMetadata = IModule.Metadata(
        1,
        1,
        "https://github.com/inverter/single-vote-governor",
        "SingleVoteGovernor"
    );

    address[] initialVoters =
        [makeAddr("voter1"), makeAddr("voter2"), makeAddr("voter3")];

    IOrchestratorFactory.ModuleConfig singleVoteGovernorFactoryConfig =
    IOrchestratorFactory.ModuleConfig(
        singleVoteGovernorMetadata,
        abi.encode(initialVoters, 2, 3 days),
        abi.encode(hasDependency, dependencies)
    );

    function setSingleVoteGovernor() private {
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

    function setUp() public {
        // Deploy Orchestrator implementation.
        orchestratorImpl = new Orchestrator();

        // Deploy Factories.
        moduleFactory = new ModuleFactory();

        orchestratorFactory = new OrchestratorFactory(
            address(orchestratorImpl), address(moduleFactory)
        );

        //FundingManager
        setUpRebasingFundingManager();
        setUpBancorVirtualSupplyBondingCurveFundingManager();

        //Authorizer
        setUpAuthorizerMock();
        setUpRoleAuthorizer();
        setUpTokenGatedRoleAuthorizer();

        //PaymentProcessor
        setUpSimplePaymentProcessor();
        setUpStreamingPaymentProcessor();

        //LogicModule
        setUpRecurringPaymentManager();
        setUpBountyManager();
        setUpStakingManager();

        //utils
        setSingleVoteGovernor();
    }

    function _createNewOrchestratorWithAllModules(
        IOrchestratorFactory.OrchestratorConfig memory config
    ) internal returns (IOrchestrator) {
        IOrchestratorFactory.ModuleConfig[] memory optionalModules =
            new IOrchestratorFactory.ModuleConfig[](1);
        optionalModules[0] = bountyManagerFactoryConfig;

        IOrchestratorFactory.ModuleConfig memory
            rebasingFundingManagerFactoryConfig = IOrchestratorFactory
                .ModuleConfig(
                rebasingFundingManagerMetadata,
                abi.encode(address(config.token)),
                abi.encode(hasDependency, dependencies)
            );

        return orchestratorFactory.createOrchestrator(
            config,
            rebasingFundingManagerFactoryConfig,
            roleAuthorizerFactoryConfig,
            paymentProcessorFactoryConfig,
            optionalModules
        );
    }

    function _createNewOrchestratorWithAllModules_withRecurringPaymentManagerAndStreamingPaymentProcessor(
        IOrchestratorFactory.OrchestratorConfig memory config
    ) internal returns (IOrchestrator) {
        IOrchestratorFactory.ModuleConfig[] memory optionalModules =
            new IOrchestratorFactory.ModuleConfig[](1);
        optionalModules[0] = recurringPaymentManagerFactoryConfig;

        IOrchestratorFactory.ModuleConfig memory
            rebasingFundingManagerFactoryConfig = IOrchestratorFactory
                .ModuleConfig(
                rebasingFundingManagerMetadata,
                abi.encode(address(config.token)),
                abi.encode(hasDependency, dependencies)
            );

        return orchestratorFactory.createOrchestrator(
            config,
            rebasingFundingManagerFactoryConfig,
            authorizerFactoryConfig,
            streamingPaymentProcessorFactoryConfig,
            optionalModules
        );
    }

    function _createNewOrchestratorWithAllModules_withRoleBasedAuthorizerAndBountyManager(
        IOrchestratorFactory.OrchestratorConfig memory config
    ) internal returns (IOrchestrator) {
        IOrchestratorFactory.ModuleConfig[] memory optionalModules =
            new IOrchestratorFactory.ModuleConfig[](1);
        optionalModules[0] = bountyManagerFactoryConfig;

        IOrchestratorFactory.ModuleConfig memory
            rebasingFundingManagerFactoryConfig = IOrchestratorFactory
                .ModuleConfig(
                rebasingFundingManagerMetadata,
                abi.encode(address(config.token)),
                abi.encode(hasDependency, dependencies)
            );

        return orchestratorFactory.createOrchestrator(
            config,
            rebasingFundingManagerFactoryConfig,
            roleAuthorizerFactoryConfig,
            paymentProcessorFactoryConfig,
            optionalModules
        );
    }

    function _createNewOrchestratorWithAllModules_StakingManager(
        IOrchestratorFactory.OrchestratorConfig memory config,
        address stakingToken
    ) internal returns (IOrchestrator) {
        IOrchestratorFactory.ModuleConfig[] memory optionalModules =
            new IOrchestratorFactory.ModuleConfig[](1);

        stakingManagerFactoryConfig = IOrchestratorFactory.ModuleConfig(
            stakingManagerMetadata,
            abi.encode(stakingToken),
            abi.encode(true, dependencies)
        );

        optionalModules[0] = stakingManagerFactoryConfig;

        IOrchestratorFactory.ModuleConfig memory
            rebasingFundingManagerFactoryConfig = IOrchestratorFactory
                .ModuleConfig(
                rebasingFundingManagerMetadata,
                abi.encode(address(config.token)),
                abi.encode(hasDependency, dependencies)
            );

        return orchestratorFactory.createOrchestrator(
            config,
            rebasingFundingManagerFactoryConfig,
            roleAuthorizerFactoryConfig,
            paymentProcessorFactoryConfig,
            optionalModules
        );
    }

    function _createNewOrchestratorWithAllModules_withKPIRewarder(
        IOrchestratorFactory.OrchestratorConfig memory config,
        address bondToken, address stakingToken, address rewarderOracle
    ) internal returns (IOrchestrator) {
        IOrchestratorFactory.ModuleConfig[] memory optionalModules =
            new IOrchestratorFactory.ModuleConfig[](1);

        kpiRewarderFactoryConfig = IOrchestratorFactory.ModuleConfig(
            kpiRewarderMetadata,
            abi.encode(bondToken, stakingToken, rewarderOracle),
            abi.encode(true, dependencies)
        );

        optionalModules[0] = kpiRewarderFactoryConfig;

        IOrchestratorFactory.ModuleConfig memory
            rebasingFundingManagerFactoryConfig = IOrchestratorFactory
                .ModuleConfig(
                rebasingFundingManagerMetadata,
                abi.encode(address(config.token)),
                abi.encode(hasDependency, dependencies)
            );

        return orchestratorFactory.createOrchestrator(
            config,
            rebasingFundingManagerFactoryConfig,
            roleAuthorizerFactoryConfig,
            paymentProcessorFactoryConfig,
            optionalModules
        );
    }

    function _createNewOrchestratorWithAllModules_withBondingCurveFundingManager(
        IOrchestratorFactory.OrchestratorConfig memory config,
        address acceptedToken
    ) internal returns (IOrchestrator) {
        IOrchestratorFactory.ModuleConfig[] memory optionalModules =
            new IOrchestratorFactory.ModuleConfig[](1);
        optionalModules[0] = bountyManagerFactoryConfig;

        IBancorVirtualSupplyBondingCurveFundingManager.IssuanceToken memory
            issuanceToken;
        IBancorVirtualSupplyBondingCurveFundingManager.BondingCurveProperties
            memory bc_properties;
        BancorFormula formula = new BancorFormula();

        issuanceToken.name = bytes32(abi.encodePacked("Bonding Curve Token"));
        issuanceToken.symbol = bytes32(abi.encodePacked("BCT"));
        issuanceToken.decimals = uint8(18);

        bc_properties.formula = address(formula);
        bc_properties.reserveRatioForBuying = 200_000;
        bc_properties.reserveRatioForSelling = 200_000;
        bc_properties.buyFee = 0;
        bc_properties.sellFee = 0;
        bc_properties.buyIsOpen = true;
        bc_properties.sellIsOpen = true;
        bc_properties.initialTokenSupply = 100;
        bc_properties.initialCollateralSupply = 100;

        IOrchestratorFactory.ModuleConfig memory
            bancorVirtualSupplyBondingCurveFundingManagerConfig =
            IOrchestratorFactory.ModuleConfig(
                bancorVirtualSupplyBondingCurveFundingManagerMetadata,
                abi.encode(issuanceToken, bc_properties, acceptedToken),
                abi.encode(hasDependency, dependencies)
            );
        return orchestratorFactory.createOrchestrator(
            config,
            bancorVirtualSupplyBondingCurveFundingManagerConfig,
            roleAuthorizerFactoryConfig,
            paymentProcessorFactoryConfig,
            optionalModules
        );
    }
}
