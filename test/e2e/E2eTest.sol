// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

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
import {FundingManager} from "src/modules/FundingManager/FundingManager.sol";
import {SimplePaymentProcessor} from
    "src/modules/PaymentProcessor/SimplePaymentProcessor.sol";
import {MilestoneManager} from "src/modules/LogicModule/MilestoneManager.sol";

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
    // Factory instances.
    ModuleFactory moduleFactory;
    ProposalFactory proposalFactory;

    // Proposal implementation.
    Proposal proposalImpl;

    //-- Module implementations, beacons, config for factory, and metadata.

    FundingManager fundingManagerImpl;
    Beacon fundingManagerBeacon;
    address fundingManagerBeaconOwner = address(0x3BEAC0);
    IModule.Metadata fundingManagerMetadata = IModule.Metadata(
        1, 1, "https://github.com/inverter/funding-manager", "FundingManager"
    );
    //IProposalFactory.ModuleConfig has to be set with token address, so needs a later Injection -> see _createNewProposalWithAllModules()

    AuthorizerMock authorizerImpl;
    Beacon authorizerBeacon;
    address authorizerBeaconOwner = address(0x3BEAC0);
    IModule.Metadata authorizerMetadata = IModule.Metadata(
        1, 1, "https://github.com/inverter/authorizer", "Authorizer"
    );
    // Note that the IAuthorizer's first authorized address is address(this).
    IProposalFactory.ModuleConfig authorizerFactoryConfig = IProposalFactory
        .ModuleConfig(authorizerMetadata, abi.encode(address(this)));

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
        IProposalFactory.ModuleConfig(paymentProcessorMetadata, bytes(""));

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
        abi.encode(100_000_000, 1_000_000, makeAddr("treasury"))
    );

    function setUp() public {
        // Deploy Proposal implementation.
        proposalImpl = new Proposal();

        // Deploy module implementations.
        fundingManagerImpl = new FundingManager();
        paymentProcessorImpl = new SimplePaymentProcessor();
        milestoneManagerImpl = new MilestoneManager();
        authorizerImpl = new AuthorizerMock();

        // Deploy module beacons.
        vm.prank(fundingManagerBeaconOwner);
        fundingManagerBeacon = new Beacon();
        vm.prank(paymentProcessorBeaconOwner);
        paymentProcessorBeacon = new Beacon();
        vm.prank(milestoneManagerBeaconOwner);
        milestoneManagerBeacon = new Beacon();
        vm.prank(authorizerBeaconOwner);
        authorizerBeacon = new Beacon();

        // Set beacon's implementations.
        vm.prank(fundingManagerBeaconOwner);
        fundingManagerBeacon.upgradeTo(address(fundingManagerImpl));
        vm.prank(paymentProcessorBeaconOwner);
        paymentProcessorBeacon.upgradeTo(address(paymentProcessorImpl));
        vm.prank(milestoneManagerBeaconOwner);
        milestoneManagerBeacon.upgradeTo(address(milestoneManagerImpl));
        vm.prank(authorizerBeaconOwner);
        authorizerBeacon.upgradeTo(address(authorizerImpl));

        // Deploy Factories.
        moduleFactory = new ModuleFactory();
        proposalFactory =
            new ProposalFactory(address(proposalImpl), address(moduleFactory));

        // Register modules at moduleFactory.
        moduleFactory.registerMetadata(
            fundingManagerMetadata, IBeacon(fundingManagerBeacon)
        );
        moduleFactory.registerMetadata(
            paymentProcessorMetadata, IBeacon(paymentProcessorBeacon)
        );
        moduleFactory.registerMetadata(
            milestoneManagerMetadata, IBeacon(milestoneManagerBeacon)
        );
        moduleFactory.registerMetadata(
            authorizerMetadata, IBeacon(authorizerBeacon)
        );
    }

    function _createNewProposalWithAllModules(
        IProposalFactory.ProposalConfig memory config
    ) internal returns (IProposal) {
        IProposalFactory.ModuleConfig[] memory optionalModules =
            new IProposalFactory.ModuleConfig[](1);
        optionalModules[0] = milestoneManagerFactoryConfig;

        IProposalFactory.ModuleConfig memory fundingManagerFactoryConfig =
        IProposalFactory.ModuleConfig(
            fundingManagerMetadata, abi.encode(address(config.token))
        );

        return proposalFactory.createProposal(
            config,
            fundingManagerFactoryConfig,
            authorizerFactoryConfig,
            paymentProcessorFactoryConfig,
            optionalModules
        );
    }
}
