// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// Internal Dependencies
import {ModuleFactory} from "src/factories/ModuleFactory.sol";

// Internal Libraries
import {LibMetadata} from "src/modules/lib/LibMetadata.sol";

// Internal Interfaces
import {IModuleFactory} from "src/interfaces/IModuleFactory.sol";
import {IModule} from "src/interfaces/IModule.sol";
import {IProposal} from "src/interfaces/IProposal.sol";

// Mocks
import {ModuleMock} from "test/utils/mocks/modules/base/ModuleMock.sol";
import {BeaconMock} from "test/utils/mocks/factories/beacon-fundamentals/BeaconMock.sol";
import {ImplementationV1Mock} from "test/utils/mocks/factories/beacon-fundamentals/ImplementationV1Mock.sol"; //Is also a Module
import {ImplementationV2Mock} from "test/utils/mocks/factories/beacon-fundamentals/ImplementationV2Mock.sol"; //Is also a Module

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

contract ModuleFactoryTest is Test {
    ModuleFactory factory;

    // Mocks
    ModuleMock module;
    BeaconMock beacon;

    // Constants
    // @todo mp: Move to some common contract. See todo in Milestone.t.sol too.
    uint256 constant MAJOR_VERSION = 1;
    string constant GIT_URL = "https://github.com/organization/module";

    IModule.Metadata DATA = IModule.Metadata(MAJOR_VERSION, GIT_URL);

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
        factory.registerMetadata(DATA, address(1));
    }

    function testRegisterMetadata(IModule.Metadata memory metadata) public {
        _assumeValidMetadata(metadata);

        beacon.overrideImplementation(address(module));

        factory.registerMetadata(metadata, address(beacon));

        assertEq(factory.target(metadata), address(beacon));
    }

    function testRegisterMetadataFailsIfMetadataInvalid() public {
        // Invalid if gitURL empty.
        IModule.Metadata memory data = IModule.Metadata(1, "");

        vm.expectRevert(IModuleFactory.ModuleFactory__InvalidMetadata.selector);
        factory.registerMetadata(data, address(beacon));
    }

    function testRegisterMetadataFailsIfTargetInvalid() public {
        // Invalid if address(0).
        vm.expectRevert(IModuleFactory.ModuleFactory__InvalidTarget.selector);
        factory.registerMetadata(DATA, address(0));

        // Invalid if address(factory).
        vm.expectRevert(IModuleFactory.ModuleFactory__InvalidTarget.selector);
        factory.registerMetadata(DATA, address(factory));
    }

    function testRegisterMetadataFailsIfAlreadyRegistered() public {
        beacon.overrideImplementation(address(module));

        BeaconMock additionalBeacon = new BeaconMock();
        additionalBeacon.overrideImplementation(address(module));

        factory.registerMetadata(DATA, address(beacon));

        vm.expectRevert(IModuleFactory.ModuleFactory__MetadataAlreadyRegistered.selector);
        factory.registerMetadata(DATA, address(additionalBeacon));
    }

    function testRegisterMetadataFailsIfBeaconHasNoValidImplementation(address burner) public {
        _assumeValidTarget(burner);
        vm.assume(burner.code.length==0);

        //Should fail because 0 Address has no code
        vm.expectRevert(IModuleFactory.ModuleFactory__BeaconNoValidImplementation.selector);
        factory.registerMetadata(DATA, burner);

        //Should fail because factory has no implementation() function//@note is there a better way to generalize this?
        vm.expectRevert(IModuleFactory.ModuleFactory__BeaconNoValidImplementation.selector);
        factory.registerMetadata(DATA, address(this));

        //Should fail because beacon address is 0
        vm.expectRevert(IModuleFactory.ModuleFactory__BeaconNoValidImplementation.selector);
        factory.registerMetadata(DATA, address(beacon));
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
        factory.registerMetadata(metadata, address(beacon));

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

        vm.expectRevert(IModuleFactory.ModuleFactory__UnregisteredMetadata.selector);
        factory.createModule(metadata, IProposal(proposal), configdata);
    }

    function testBeaconUpgrade(
        IModule.Metadata memory metadata,
        address proposal,
        bytes memory configdata
    ) public {
        _assumeValidMetadata(metadata);
        _assumeValidProposal(proposal);

        //Create implementation V1 and upgrade beacon to it
        ImplementationV1Mock implementationV1 = new ImplementationV1Mock();
        beacon.overrideImplementation(address(implementationV1));

        //register beacon as Module
        factory.registerMetadata(metadata, address(beacon));

        address proxyImplementationAddress1 = factory.createModule(
            metadata,
            IProposal(proposal),
            configdata
        );

        assertTrue(
            ImplementationV1Mock(proxyImplementationAddress1).getVersion() == 1
        );

        //Create implementation V2 and upgrade beacon to it
        ImplementationV2Mock implementationV2 = new ImplementationV2Mock();
        beacon.overrideImplementation(address(implementationV2));

        assertTrue(
            ImplementationV2Mock(proxyImplementationAddress1).getVersion() == 2
        );

        //Out of curiosity test if V1 Still works
        assertTrue(
            ImplementationV1Mock(proxyImplementationAddress1).getVersion() == 2
        );
    }

    function testBeaconNotFunctional(
        IModule.Metadata memory metadata,
        address proposal,
        bytes memory configdata
    ) public {
        _assumeValidMetadata(metadata);
        _assumeValidProposal(proposal);

        beacon.overrideImplementation(address(new ModuleMock()));

        //register beacon as Module
        factory.registerMetadata(metadata, address(beacon));

        beacon.overrideImplementation(address(0));

        vm.expectRevert(
            IModuleFactory.ModuleFactory__BeaconNoValidImplementation.selector
        );
        factory.createModule(
            metadata,
            IProposal(proposal),
            configdata
        );
    }

    //--------------------------------------------------------------------------
    // Internal Helper Functions

    function _assumeValidMetadata(IModule.Metadata memory metadata) public {
        vm.assume(LibMetadata.isValid(metadata));
    }

    function _assumeValidTarget(address target) internal {
        vm.assume(target != address(factory));
        vm.assume(target != address(0));
    }

    function _assumeValidProposal(address proposal) internal {
        vm.assume(proposal != address(0));
    }
}
