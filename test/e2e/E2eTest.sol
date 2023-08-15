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
import {RebasingFundingManager} from
    "src/modules/fundingManager/RebasingFundingManager.sol";
import {SimplePaymentProcessor} from
    "src/modules/paymentProcessor/SimplePaymentProcessor.sol";
import {StreamingPaymentProcessor} from
    "src/modules/paymentProcessor/StreamingPaymentProcessor.sol";
import {BountyManager} from "src/modules/logicModule/BountyManager.sol";
import {RecurringPaymentManager} from
    "src/modules/logicModule/RecurringPaymentManager.sol";
import {RoleAuthorizer} from "src/modules/authorizer/RoleAuthorizer.sol";
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

    //-- Module implementations, beacons, config for factory, and metadata.

    RebasingFundingManager rebasingFundingManagerImpl;
    Beacon rebasingFundingManagerBeacon;
    address rebasingFundingManagerBeaconOwner = address(0x3BEAC0);
    IModule.Metadata rebasingFundingManagerMetadata = IModule.Metadata(
        1,
        1,
        "https://github.com/inverter/funding-manager",
        "RebasingFundingManager"
    );
    //IOrchestratorFactory.ModuleConfig has to be set with token address, so needs a later Injection -> see _createNewOrchestratorWithAllModules()

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

    SimplePaymentProcessor paymentProcessorImpl;
    StreamingPaymentProcessor streamingPaymentProcessorImpl;

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

    function setUp() public {
        // Deploy Orchestrator implementation.
        orchestratorImpl = new Orchestrator();

        // Deploy module implementations.
        rebasingFundingManagerImpl = new RebasingFundingManager();
        paymentProcessorImpl = new SimplePaymentProcessor();
        streamingPaymentProcessorImpl = new StreamingPaymentProcessor();

        bountyManagerImpl = new BountyManager();
        recurringPaymentManagerImpl = new RecurringPaymentManager();
        authorizerImpl = new AuthorizerMock();
        roleAuthorizerImpl = new RoleAuthorizer();
        singleVoteGovernorImpl = new SingleVoteGovernor();

        // Deploy module beacons.
        vm.prank(rebasingFundingManagerBeaconOwner);
        rebasingFundingManagerBeacon = new Beacon();
        vm.prank(paymentProcessorBeaconOwner);
        paymentProcessorBeacon = new Beacon();
        vm.prank(streamingPaymentProcessorBeaconOwner);
        streamingPaymentProcessorBeacon = new Beacon();
        vm.prank(bountyManagerBeaconOwner);
        bountyManagerBeacon = new Beacon();
        vm.prank(recurringPaymentManagerBeaconOwner);
        recurringPaymentManagerBeacon = new Beacon();
        vm.prank(authorizerBeaconOwner);
        authorizerBeacon = new Beacon();
        vm.prank(roleAuthorizerBeaconOwner);
        roleAuthorizerBeacon = new Beacon();
        vm.prank(singleVoteGovernorBeaconOwner);
        singleVoteGovernorBeacon = new Beacon();

        // Set beacon's implementations.
        vm.prank(rebasingFundingManagerBeaconOwner);
        rebasingFundingManagerBeacon.upgradeTo(
            address(rebasingFundingManagerImpl)
        );
        vm.prank(paymentProcessorBeaconOwner);
        paymentProcessorBeacon.upgradeTo(address(paymentProcessorImpl));
        vm.prank(streamingPaymentProcessorBeaconOwner);
        streamingPaymentProcessorBeacon.upgradeTo(
            address(streamingPaymentProcessorImpl)
        );
        vm.prank(bountyManagerBeaconOwner);
        bountyManagerBeacon.upgradeTo(address(bountyManagerImpl));
        vm.prank(recurringPaymentManagerBeaconOwner);
        recurringPaymentManagerBeacon.upgradeTo(
            address(recurringPaymentManagerImpl)
        );
        vm.prank(authorizerBeaconOwner);
        authorizerBeacon.upgradeTo(address(authorizerImpl));

        vm.prank(roleAuthorizerBeaconOwner);
        roleAuthorizerBeacon.upgradeTo(address(roleAuthorizerImpl));

        vm.prank(singleVoteGovernorBeaconOwner);
        singleVoteGovernorBeacon.upgradeTo(address(singleVoteGovernorImpl));

        // Deploy Factories.
        moduleFactory = new ModuleFactory();
        orchestratorFactory =
        new OrchestratorFactory(address(orchestratorImpl), address(moduleFactory));

        // Register modules at moduleFactory.
        moduleFactory.registerMetadata(
            rebasingFundingManagerMetadata,
            IBeacon(rebasingFundingManagerBeacon)
        );
        moduleFactory.registerMetadata(
            paymentProcessorMetadata, IBeacon(paymentProcessorBeacon)
        );
        moduleFactory.registerMetadata(
            streamingPaymentProcessorMetadata,
            IBeacon(streamingPaymentProcessorBeacon)
        );
        moduleFactory.registerMetadata(
            bountyManagerMetadata, IBeacon(bountyManagerBeacon)
        );
        moduleFactory.registerMetadata(
            recurringPaymentManagerMetadata,
            IBeacon(recurringPaymentManagerBeacon)
        );
        moduleFactory.registerMetadata(
            authorizerMetadata, IBeacon(authorizerBeacon)
        );
        moduleFactory.registerMetadata(
            roleAuthorizerMetadata, IBeacon(roleAuthorizerBeacon)
        );
        moduleFactory.registerMetadata(
            singleVoteGovernorMetadata, IBeacon(singleVoteGovernorBeacon)
        );
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
            authorizerFactoryConfig,
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
}
