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
import {SimplePaymentProcessor} from "src/modules/SimplePaymentProcessor.sol";
import {MilestoneManager} from "src/modules/MilestoneManager.sol";
import {SpecificFundingManager} from
    "src/modules/milestoneSubModules/SpecificFundingManager.sol";

import {AuthorizerMock} from "test/utils/mocks/modules/AuthorizerMock.sol";

// Beacon
import {Beacon, IBeacon} from "src/factories/beacon/Beacon.sol";

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
        abi.encode(100_000_000, 1_000_000, makeAddr("treasury")) //Has to be set live to get proper address
    );

    SpecificFundingManager specificFundingManagerImpl;
    Beacon specificFundingManagerBeacon;
    address specificFundingManagerBeaconOwner = address(0x3BEAC0);
    IModule.Metadata specificFundingManagerMetadata = IModule.Metadata(
        1,
        1,
        "https://github.com/inverter/specific-funding-manager",
        "SpecificFundingManager"
    );
    IProposalFactory.ModuleConfig specificFundingManagerFactoryConfig =
    IProposalFactory.ModuleConfig(
        specificFundingManagerMetadata, abi.encode("")
    );

    AuthorizerMock authorizerImpl;
    Beacon authorizerBeacon;
    address authorizerBeaconOwner = address(0x4BEAC0);
    IModule.Metadata authorizerMetadata = IModule.Metadata(
        1, 1, "https://github.com/inverter/authorizer", "Authorizer"
    );
    // Note that the IAuthorizer's first authorized address is address(this).
    IProposalFactory.ModuleConfig authorizerFactoryConfig = IProposalFactory
        .ModuleConfig(authorizerMetadata, abi.encode(address(this)));

    function setUp() public {
        // Deploy Proposal implementation.
        proposalImpl = new Proposal();

        // Deploy module implementations.
        paymentProcessorImpl = new SimplePaymentProcessor();
        milestoneManagerImpl = new MilestoneManager();
        specificFundingManagerImpl = new SpecificFundingManager();
        authorizerImpl = new AuthorizerMock();

        // Deploy module beacons.
        vm.prank(paymentProcessorBeaconOwner);
        paymentProcessorBeacon = new Beacon();
        vm.prank(milestoneManagerBeaconOwner);
        milestoneManagerBeacon = new Beacon();
        vm.prank(specificFundingManagerBeaconOwner);
        specificFundingManagerBeacon = new Beacon();
        vm.prank(authorizerBeaconOwner);
        authorizerBeacon = new Beacon();

        // Set beacon's implementations.
        vm.prank(paymentProcessorBeaconOwner);
        paymentProcessorBeacon.upgradeTo(address(paymentProcessorImpl));
        vm.prank(milestoneManagerBeaconOwner);
        milestoneManagerBeacon.upgradeTo(address(milestoneManagerImpl));
        vm.prank(specificFundingManagerBeaconOwner);
        specificFundingManagerBeacon.upgradeTo(
            address(specificFundingManagerImpl)
        );
        vm.prank(authorizerBeaconOwner);
        authorizerBeacon.upgradeTo(address(authorizerImpl));

        // Deploy Factories.
        moduleFactory = new ModuleFactory();
        proposalFactory =
            new ProposalFactory(address(proposalImpl), address(moduleFactory));

        // Register modules at moduleFactory.
        moduleFactory.registerMetadata(
            paymentProcessorMetadata, IBeacon(paymentProcessorBeacon)
        );
        moduleFactory.registerMetadata(
            milestoneManagerMetadata, IBeacon(milestoneManagerBeacon)
        );
        moduleFactory.registerMetadata(
            specificFundingManagerMetadata,
            IBeacon(specificFundingManagerBeacon)
        );
        moduleFactory.registerMetadata(
            authorizerMetadata, IBeacon(authorizerBeacon)
        );
    }

    function _createNewProposalWithAllModules(
        IProposalFactory.ProposalConfig memory config
    ) internal returns (IProposal) {
        IProposalFactory.ModuleConfig[] memory optionalModules =
            new IProposalFactory.ModuleConfig[](2);
        optionalModules[0] = milestoneManagerFactoryConfig;
        optionalModules[1] = specificFundingManagerFactoryConfig;

        return proposalFactory.createProposal(
            config,
            authorizerFactoryConfig,
            paymentProcessorFactoryConfig,
            optionalModules
        );
    }
}
