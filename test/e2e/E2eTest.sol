// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

// Factories
import {ModuleFactory} from "src/factories/ModuleFactory.sol";
import {ProposalFactory} from "src/factories/ProposalFactory.sol";

// Proposal
import {Proposal} from "src/proposal/Proposal.sol";

// Modules
import {IModule} from "src/modules/base/IModule.sol";
import {PaymentProcessor} from "src/modules/PaymentProcessor.sol";
import {MilestoneManager} from "src/modules/MilestoneManager.sol";

import {AuthorizerMock} from "test/utils/mocks/AuthorizerMock.sol";

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
    Proposal proposal;

    // Module implementations, beacons and Metadata.
    PaymentProcessor paymentProcessorModule;
    Beacon paymentProcessorBeacon;
    address paymentProcessorBeaconOwner = address(0x1BEAC0);
    IModule.Metadata paymentProcessorModuleMetadata = IModule.Metadata(
        1,
        1,
        "https://github.com/inverter/payment-processor",
        "PaymentProcessor"
    );

    MilestoneManager milestoneManagerModule;
    Beacon milestoneManagerBeacon;
    address milestoneManagerBeaconOwner = address(0x2BEAC0);
    IModule.Metadata milestoneManagerModuleMetadata = IModule.Metadata(
        1,
        1,
        "https://github.com/inverter/milestone-manager",
        "MilestoneManager"
    );

    AuthorizerMock authorizerModule;
    Beacon authorizerBeacon;
    address authorizerBeaconOwner = address(0x3BEAC0);
    IModule.Metadata authorizerModuleMetadata = IModule.Metadata(
        1, 1, "https://github.com/inverter/authorizer", "Authorizer"
    );

    function setUp() public {
        // Deploy Proposal implementation.
        proposal = new Proposal();

        // Deploy module implementations.
        paymentProcessorModule = new PaymentProcessor();
        milestoneManagerModule = new MilestoneManager();
        authorizerModule = new AuthorizerMock();

        // Deploy module beacons.
        vm.prank(paymentProcessorBeaconOwner);
        paymentProcessorBeacon = new Beacon();
        vm.prank(milestoneManagerBeaconOwner);
        milestoneManagerBeacon = new Beacon();
        vm.prank(authorizerBeaconOwner);
        authorizerBeacon = new Beacon();

        // Set beacon's implementations.
        vm.prank(paymentProcessorBeaconOwner);
        paymentProcessorBeacon.upgradeTo(address(paymentProcessorModule));
        vm.prank(milestoneManagerBeaconOwner);
        milestoneManagerBeacon.upgradeTo(address(milestoneManagerModule));
        vm.prank(authorizerBeaconOwner);
        authorizerBeacon.upgradeTo(address(authorizerModule));

        // Deploy Factories.
        moduleFactory = new ModuleFactory();
        proposalFactory =
            new ProposalFactory(address(proposal), address(moduleFactory));

        // Register modules at moduleFactory.
        moduleFactory.registerMetadata(
            paymentProcessorModuleMetadata, IBeacon(paymentProcessorBeacon)
        );
        moduleFactory.registerMetadata(
            milestoneManagerModuleMetadata, IBeacon(milestoneManagerBeacon)
        );
        moduleFactory.registerMetadata(
            authorizerModuleMetadata, IBeacon(authorizerBeacon)
        );
    }
}
