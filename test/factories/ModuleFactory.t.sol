// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// Internal Dependencies
import {ModuleFactory} from "src/factories/ModuleFactory.sol";

import {IInverterBeacon} from "src/factories/beacon/IInverterBeacon.sol";

// Internal Libraries
import {LibMetadata} from "src/modules/lib/LibMetadata.sol";

// Internal Interfaces
import {
    IModuleFactory,
    IModule,
    IOrchestrator
} from "src/factories/IModuleFactory.sol";

// Mocks
import {ModuleMock} from "test/utils/mocks/modules/base/ModuleMock.sol";
import {InverterBeaconMock} from
    "test/utils/mocks/factories/beacon/InverterBeaconMock.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

contract ModuleFactoryTest is Test {
    // SuT
    ModuleFactory factory;

    // Mocks
    ModuleMock module;
    InverterBeaconMock beacon;

    address governaceContract = address(0x010101010101);

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when new beacon registered for metadata.
    event MetadataRegistered(
        IModule.Metadata indexed metadata, IInverterBeacon indexed beacon
    );

    /// @notice Event emitted when new module created for a orchestrator.
    event ModuleCreated(
        address indexed orchestrator, address indexed module, bytes32 identifier
    );

    // Constants
    uint constant MAJOR_VERSION = 1;
    uint constant MINOR_VERSION = 1;
    string constant URL = "https://github.com/organization/module";
    string constant TITLE = "Payment Processor";

    IModule.Metadata DATA =
        IModule.Metadata(MAJOR_VERSION, MINOR_VERSION, URL, TITLE);

    function setUp() public {
        module = new ModuleMock();
        beacon = new InverterBeaconMock();

        factory = new ModuleFactory(address(0), governaceContract);
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
        vm.assume(caller != address(0));
        vm.prank(caller);

        vm.expectRevert(
            abi.encodeWithSelector(
                OZErrors.Ownable__UnauthorizedAccount, caller
            )
        );
        factory.registerMetadata(DATA, beacon);
    }

    function testRegisterMetadata(IModule.Metadata memory metadata) public {
        _assumeValidMetadata(metadata);

        beacon.overrideImplementation(address(module));

        vm.expectEmit(true, true, true, true);

        // We emit the event we expect to see.
        emit MetadataRegistered(metadata, beacon);

        factory.registerMetadata(metadata, beacon);

        IInverterBeacon beaconRegistered;
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

        InverterBeaconMock additionalBeacon = new InverterBeaconMock();
        additionalBeacon.overrideImplementation(address(module));

        factory.registerMetadata(DATA, beacon);

        vm.expectRevert(
            IModuleFactory.ModuleFactory__MetadataAlreadyRegistered.selector
        );
        factory.registerMetadata(DATA, additionalBeacon);
    }

    function testRegisterMetadataFailsIfBeaconsImplementationIsZero() public {
        beacon.overrideImplementation(address(0));

        vm.expectRevert(
            IModuleFactory.ModuleFactory__InvalidInverterBeacon.selector
        );
        factory.registerMetadata(DATA, beacon);
    }

    //--------------------------------------------------------------------------
    // Tests: createModule

    function testCreateModule(
        IModule.Metadata memory metadata,
        address orchestrator,
        bytes memory configData
    ) public {
        _assumeValidMetadata(metadata);
        _assumeValidOrchestrator(orchestrator);

        beacon.overrideImplementation(address(module));

        // Register ModuleMock for given metadata.
        factory.registerMetadata(metadata, beacon);

        // Since we don't know the exact address the cloned module will have, we only check that an event of the right type is fired
        vm.expectEmit(true, false, false, false);

        // We emit the event we expect to see.
        emit ModuleCreated(
            orchestrator, address(0), LibMetadata.identifier(metadata)
        );

        // Create new module instance.
        IModule newModule = IModule(
            factory.createModule(
                metadata, IOrchestrator(orchestrator), configData
            )
        );

        assertEq(address(newModule.orchestrator()), address(orchestrator));
        assertEq(newModule.identifier(), LibMetadata.identifier(metadata));
    }

    function testCreateModuleFailsIfMetadataUnregistered(
        IModule.Metadata memory metadata,
        address orchestrator,
        bytes memory configData
    ) public {
        _assumeValidMetadata(metadata);
        _assumeValidOrchestrator(orchestrator);

        vm.expectRevert(
            IModuleFactory.ModuleFactory__UnregisteredMetadata.selector
        );
        factory.createModule(metadata, IOrchestrator(orchestrator), configData);
    }

    function testCreateModuleFailsIfBeaconsImplementationIsZero(
        IModule.Metadata memory metadata,
        address orchestrator,
        bytes memory configData
    ) public {
        _assumeValidMetadata(metadata);
        _assumeValidOrchestrator(orchestrator);

        // Setup and register beacon.
        beacon.overrideImplementation(address(new ModuleMock()));
        factory.registerMetadata(metadata, beacon);

        // Change beacon's implementation to zero address.
        beacon.overrideImplementation(address(0));

        // Note that an `assert()` statement fails.
        vm.expectRevert();
        factory.createModule(metadata, IOrchestrator(orchestrator), configData);
    }

    //--------------------------------------------------------------------------
    // Internal Helper Functions

    function _assumeValidMetadata(IModule.Metadata memory metadata)
        public
        pure
    {
        vm.assume(LibMetadata.isValid(metadata));
    }

    function _assumeValidOrchestrator(address orchestrator) internal pure {
        vm.assume(orchestrator != address(0));
    }

    //@todo check for beacon Ownable(address(beacon)).owner() != governanceContract
}
