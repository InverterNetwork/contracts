// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Test.sol";

// External Interfaces
import {IBeacon} from "@oz/proxy/beacon/IBeacon.sol";

// Internal Dependencies
import {ModuleFactory} from "src/factories/ModuleFactory.sol";

// Internal Libraries
import {LibMetadata} from "src/modules/lib/LibMetadata.sol";

// Internal Interfaces
import {
    IModuleFactory,
    IModule,
    IProposal
} from "src/factories/IModuleFactory.sol";

// Mocks
import {ModuleMock} from "test/utils/mocks/modules/base/ModuleMock.sol";
import {BeaconMock} from "test/utils/mocks/factories/beacon/BeaconMock.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

contract ModuleFactoryTest is Test {
    // SuT
    ModuleFactory factory;

    // Mocks
    ModuleMock module;
    BeaconMock beacon;

    // Constants
    uint constant MAJOR_VERSION = 1;
    uint constant MINOR_VERSION = 1;
    string constant URL = "https://github.com/organization/module";
    string constant TITLE = "Payment Processor";

    IModule.Metadata DATA =
        IModule.Metadata(MAJOR_VERSION, MINOR_VERSION, URL, TITLE);

    function setUp() public {
        module = new ModuleMock();
        beacon = new BeaconMock();

        factory = new ModuleFactory();
    }

    function testDeploymentInvariants() public {
        // Invariants: Ownable2Step
        assertEq(factory.owner(), address(this));
        assertEq(factory.pendingOwner(), address(0));
    }

    //--------------------------------------------------------------------------
    // Test: registerMetadata

    function testRegisterMetadataOnlyCallableByOwner(address caller) public {
        vm.assume(caller != address(this));
        vm.prank(caller);

        vm.expectRevert(OZErrors.Ownable2Step__CallerNotOwner);
        factory.registerMetadata(DATA, beacon);
    }

    function testRegisterMetadata(IModule.Metadata memory metadata) public {
        _assumeValidMetadata(metadata);

        beacon.overrideImplementation(address(module));

        factory.registerMetadata(metadata, beacon);

        IBeacon beaconRegistered;
        (beaconRegistered, /*id*/ ) = factory.getBeaconAndId(metadata);

        assertEq(address(beaconRegistered), address(beacon));
    }

    function testRegisterMetadataFailsIfMetadataInvalid() public {
        // Invalid if url empty.
        vm.expectRevert(IModuleFactory.ModuleFactory__InvalidMetadata.selector);
        factory.registerMetadata(
            IModule.Metadata(MAJOR_VERSION, MINOR_VERSION, "", TITLE), beacon
        );

        // Invalid if title empty.
        vm.expectRevert(IModuleFactory.ModuleFactory__InvalidMetadata.selector);
        factory.registerMetadata(
            IModule.Metadata(MAJOR_VERSION, MINOR_VERSION, URL, ""), beacon
        );
    }

    function testRegisterMetadataFailsIfAlreadyRegistered() public {
        beacon.overrideImplementation(address(module));

        BeaconMock additionalBeacon = new BeaconMock();
        additionalBeacon.overrideImplementation(address(module));

        factory.registerMetadata(DATA, beacon);

        vm.expectRevert(
            IModuleFactory.ModuleFactory__MetadataAlreadyRegistered.selector
        );
        factory.registerMetadata(DATA, additionalBeacon);
    }

    function testRegisterMetadataFailsIfBeaconsImplementationIsZero() public {
        beacon.overrideImplementation(address(0));

        vm.expectRevert(IModuleFactory.ModuleFactory__InvalidBeacon.selector);
        factory.registerMetadata(DATA, beacon);
    }

    //--------------------------------------------------------------------------
    // Tests: createModule

    function testCreateModule(
        IModule.Metadata memory metadata,
        address proposal,
        bytes memory configdata
    ) public {
        _assumeValidMetadata(metadata);
        _assumeValidProposal(proposal);

        beacon.overrideImplementation(address(module));

        // Register ModuleMock for given metadata.
        factory.registerMetadata(metadata, beacon);

        // Create new module instance.
        IModule newModule = IModule(
            factory.createModule(metadata, IProposal(proposal), configdata)
        );

        assertEq(address(newModule.proposal()), address(proposal));
        assertEq(newModule.identifier(), LibMetadata.identifier(metadata));
    }

    function testCreateModuleFailsIfMetadataUnregistered(
        IModule.Metadata memory metadata,
        address proposal,
        bytes memory configdata
    ) public {
        _assumeValidMetadata(metadata);
        _assumeValidProposal(proposal);

        vm.expectRevert(
            IModuleFactory.ModuleFactory__UnregisteredMetadata.selector
        );
        factory.createModule(metadata, IProposal(proposal), configdata);
    }

    function testCreateModuleFailsIfBeaconsImplementationIsZero(
        IModule.Metadata memory metadata,
        address proposal,
        bytes memory configdata
    ) public {
        _assumeValidMetadata(metadata);
        _assumeValidProposal(proposal);

        // Setup and register beacon.
        beacon.overrideImplementation(address(new ModuleMock()));
        factory.registerMetadata(metadata, beacon);

        // Change beacon's implementation to zero address.
        beacon.overrideImplementation(address(0));

        // Note that an `assert()` statement fails.
        vm.expectRevert();
        factory.createModule(metadata, IProposal(proposal), configdata);
    }

    //--------------------------------------------------------------------------
    // Internal Helper Functions

    function _assumeValidMetadata(IModule.Metadata memory metadata)
        public
        pure
    {
        vm.assume(LibMetadata.isValid(metadata));
    }

    function _assumeValidProposal(address proposal) internal pure {
        vm.assume(proposal != address(0));
    }
}
