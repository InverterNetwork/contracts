// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

// Factories
import {ModuleFactory, IModuleFactory} from "src/factories/ModuleFactory.sol";
import {
    ProposalFactory,
    IProposalFactory
} from "src/factories/ProposalFactory.sol";

// Proposal
import {Proposal, IProposal} from "src/proposal/Proposal.sol";

// Modules
import {IModule} from "src/modules/base/IModule.sol";
import {RebasingFundingManager} from
    "src/modules/fundingManager/RebasingFundingManager.sol";
import {SimplePaymentProcessor} from
    "src/modules/paymentProcessor/SimplePaymentProcessor.sol";
import {StreamingPaymentProcessor} from
    "src/modules/paymentProcessor/StreamingPaymentProcessor.sol";
import {MilestoneManager} from "src/modules/logicModule/MilestoneManager.sol";
import {BountyManager} from "src/modules/logicModule/BountyManager.sol";
import {RecurringPaymentManager} from
    "src/modules/logicModule/RecurringPaymentManager.sol";
import {RoleAuthorizer} from "src/modules/authorizer/RoleAuthorizer.sol";

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
    ProposalFactory proposalFactory;

    // Proposal implementation.
    Proposal proposalImpl;

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
    IProposalFactory.ModuleConfig authorizerFactoryConfig = IProposalFactory
        .ModuleConfig(
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
    IProposalFactory.ModuleConfig roleAuthorizerFactoryConfig = IProposalFactory
        .ModuleConfig(
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
    IProposalFactory.ModuleConfig paymentProcessorFactoryConfig =
    IProposalFactory.ModuleConfig(
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
    IProposalFactory.ModuleConfig streamingPaymentProcessorFactoryConfig =
    IProposalFactory.ModuleConfig(
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

    // MilestoneManager

    MilestoneManager milestoneManagerImpl;
    Beacon milestoneManagerBeacon;
    address milestoneManagerBeaconOwner = address(0x2BEAC0);
    IModule.Metadata milestoneManagerMetadata = IModule.Metadata(
        1,
        1,
        "https://github.com/inverter/milestone-manager",
        "MilestoneManager"
    );
    IProposalFactory.ModuleConfig milestoneManagerFactoryConfig =
    IProposalFactory.ModuleConfig(
        milestoneManagerMetadata,
        abi.encode(100_000_000, 1_000_000, makeAddr("treasury")),
        abi.encode(hasDependency, dependencies)
    );

    function setUpMilestoneManager() private {
        // Deploy module implementations.
        milestoneManagerImpl = new MilestoneManager();

        // Deploy module beacons.
        vm.prank(milestoneManagerBeaconOwner);
        milestoneManagerBeacon = new Beacon();

        // Set beacon's implementations.
        vm.prank(milestoneManagerBeaconOwner);
        milestoneManagerBeacon.upgradeTo(address(milestoneManagerImpl));

        // Register modules at moduleFactory.
        moduleFactory.registerMetadata(
            milestoneManagerMetadata, IBeacon(milestoneManagerBeacon)
        );
    }

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
    IProposalFactory.ModuleConfig recurringPaymentManagerFactoryConfig =
    IProposalFactory.ModuleConfig(
        recurringPaymentManagerMetadata,
        abi.encode(1 weeks),
        abi.encode(hasDependency, dependencies)
    );

    function setUpRecurringPaymentManager() private {
        // Deploy module implementations.
        recurringPaymentManagerImpl = new RecurringPaymentManager();

        console.log(2);
        // Deploy module beacons.
        vm.prank(recurringPaymentManagerBeaconOwner);
        recurringPaymentManagerBeacon = new Beacon();

        console.log(3);
        // Set beacon's implementations.
        vm.prank(recurringPaymentManagerBeaconOwner);
        recurringPaymentManagerBeacon.upgradeTo(
            address(recurringPaymentManagerImpl)
        );

        console.log(4);
        // Register modules at moduleFactory.
        moduleFactory.registerMetadata(
            recurringPaymentManagerMetadata,
            IBeacon(recurringPaymentManagerBeacon)
        );

        console.log(5);
    }

    // BountyManager

    BountyManager bountyManagerImpl;
    Beacon bountyManagerBeacon;
    address bountyManagerBeaconOwner = address(0x3BEAC0);
    IModule.Metadata bountyManagerMetadata = IModule.Metadata(
        1, 1, "https://github.com/inverter/bounty-manager", "BountyManager"
    );
    IProposalFactory.ModuleConfig bountyManagerFactoryConfig = IProposalFactory
        .ModuleConfig(
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

    event checker(uint);

    function setUp() public {
        // Deploy Proposal implementation.
        proposalImpl = new Proposal();

        // Deploy Factories.
        moduleFactory = new ModuleFactory();

        proposalFactory =
            new ProposalFactory(address(proposalImpl), address(moduleFactory));

        //FundingManager
        setUpRebasingFundingManager();

        //Authorizer
        setUpAuthorizerMock();
        setUpRoleAuthorizer();
        //PaymentProcessor
        setUpSimplePaymentProcessor();
        setUpStreamingPaymentProcessor();

        //LogicModule
        setUpMilestoneManager();
        console.log(1);
        setUpRecurringPaymentManager();
        setUpBountyManager();
    }

    function _createNewProposalWithAllModules(
        IProposalFactory.ProposalConfig memory config
    ) internal returns (IProposal) {
        IProposalFactory.ModuleConfig[] memory optionalModules =
            new IProposalFactory.ModuleConfig[](2);
        optionalModules[0] = milestoneManagerFactoryConfig;
        optionalModules[1] = bountyManagerFactoryConfig;

        IProposalFactory.ModuleConfig memory rebasingFundingManagerFactoryConfig =
        IProposalFactory.ModuleConfig(
            rebasingFundingManagerMetadata,
            abi.encode(address(config.token)),
            abi.encode(hasDependency, dependencies)
        );

        return proposalFactory.createProposal(
            config,
            rebasingFundingManagerFactoryConfig,
            authorizerFactoryConfig,
            paymentProcessorFactoryConfig,
            optionalModules
        );
    }

    function _createNewProposalWithAllModules_withRecurringPaymentManagerAndStreamingPaymentProcessor(
        IProposalFactory.ProposalConfig memory config
    ) internal returns (IProposal) {
        IProposalFactory.ModuleConfig[] memory optionalModules =
            new IProposalFactory.ModuleConfig[](1);
        optionalModules[0] = recurringPaymentManagerFactoryConfig;

        IProposalFactory.ModuleConfig memory rebasingFundingManagerFactoryConfig =
        IProposalFactory.ModuleConfig(
            rebasingFundingManagerMetadata,
            abi.encode(address(config.token)),
            abi.encode(hasDependency, dependencies)
        );

        return proposalFactory.createProposal(
            config,
            rebasingFundingManagerFactoryConfig,
            authorizerFactoryConfig,
            streamingPaymentProcessorFactoryConfig,
            optionalModules
        );
    }

    function _createNewProposalWithAllModules_withRoleBasedAuthorizerAndBountyManager(
        IProposalFactory.ProposalConfig memory config
    ) internal returns (IProposal) {
        IProposalFactory.ModuleConfig[] memory optionalModules =
            new IProposalFactory.ModuleConfig[](1);
        optionalModules[0] = bountyManagerFactoryConfig;

        IProposalFactory.ModuleConfig memory rebasingFundingManagerFactoryConfig =
        IProposalFactory.ModuleConfig(
            rebasingFundingManagerMetadata,
            abi.encode(address(config.token)),
            abi.encode(hasDependency, dependencies)
        );

        return proposalFactory.createProposal(
            config,
            rebasingFundingManagerFactoryConfig,
            roleAuthorizerFactoryConfig,
            paymentProcessorFactoryConfig,
            optionalModules
        );
    }
}
