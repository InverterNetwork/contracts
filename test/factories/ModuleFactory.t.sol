// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// Internal Dependencies
import {ModuleFactory} from "src/factories/ModuleFactory.sol";

// Internal Libraries
import {MetadataLib} from "src/modules/lib/MetadataLib.sol";

// Internal Interfaces
import {IModule} from "src/interfaces/IModule.sol";
import {IProposal} from "src/interfaces/IProposal.sol";

// Mocks
import {ModuleMock} from "test/utils/mocks/modules/base/ModuleMock.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

/**
 * Errors library for ModuleFactory's custom errors.
 * Enables checking for errors with vm.expectRevert(Errors.<Error>).
 */
library Errors {
    bytes internal constant ModuleFactory__InvalidMetadata =
        abi.encodeWithSignature("ModuleFactory__InvalidMetadata()");

    bytes internal constant ModuleFactory__InvalidTarget =
        abi.encodeWithSignature("ModuleFactory__InvalidTarget()");

    bytes internal constant ModuleFactory__UnregisteredMetadata =
        abi.encodeWithSignature("ModuleFactory__UnregisteredMetadata()");

    bytes internal constant ModuleFactory__MetadataAlreadyRegistered =
        abi.encodeWithSignature("ModuleFactory__MetadataAlreadyRegistered()");
}

contract ModuleFactoryTest is Test {
    ModuleFactory factory;

    // Mocks
    ModuleMock module;

    // Constants
    // @todo mp: Move to some common contract. See todo in Milestone.t.sol too.
    uint constant MAJOR_VERSION = 1;
    string constant GIT_URL = "https://github.com/organization/module";

    IModule.Metadata DATA = IModule.Metadata(MAJOR_VERSION, GIT_URL);

    function setUp() public {
        module = new ModuleMock();

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

    function testRegisterMetadata(
        IModule.Metadata memory metadata,
        address target
    ) public {
        _assumeValidMetadata(metadata);
        _assumeValidTarget(target);

        factory.registerMetadata(metadata, target);

        assertEq(factory.target(metadata), target);
    }

    function testRegisterMetadataFailsIfMetadataInvalid(address target)
        public
    {
        _assumeValidTarget(target);

        // Invalid if gitURL empty.
        IModule.Metadata memory data = IModule.Metadata(1, "");

        vm.expectRevert(Errors.ModuleFactory__InvalidMetadata);
        factory.registerMetadata(data, target);
    }

    function testRegisterMetadataFailsIfTargetInvalid() public {
        // Invalid if address(0).
        vm.expectRevert(Errors.ModuleFactory__InvalidTarget);
        factory.registerMetadata(DATA, address(0));

        // Invalid if address(factory).
        vm.expectRevert(Errors.ModuleFactory__InvalidTarget);
        factory.registerMetadata(DATA, address(factory));
    }

    function testRegisterMetadataFailsIfAlreadyRegistered(
        address target1,
        address target2
    ) public {
        _assumeValidTarget(target1);
        _assumeValidTarget(target2);

        factory.registerMetadata(DATA, target1);

        vm.expectRevert(Errors.ModuleFactory__MetadataAlreadyRegistered);
        factory.registerMetadata(DATA, target2);
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

        // Register ModuleMock for given metadata.
        factory.registerMetadata(metadata, address(module));

        // Create new module instance.
        IModule newModule = IModule(
            factory.createModule(metadata, IProposal(proposal), configdata)
        );

        assertEq(address(newModule.proposal()), address(proposal));
        assertEq(newModule.identifier(), MetadataLib.identifier(metadata));
    }

    function testCreateModuleFailsIfMetadataUnregistered(
        IModule.Metadata memory metadata,
        address proposal,
        bytes memory configdata
    ) public {
        _assumeValidMetadata(metadata);
        _assumeValidProposal(proposal);

        vm.expectRevert(Errors.ModuleFactory__UnregisteredMetadata);
        factory.createModule(metadata, IProposal(proposal), configdata);
    }

    //--------------------------------------------------------------------------
    // Internal Helper Functions

    function _assumeValidMetadata(IModule.Metadata memory metadata) public {
        vm.assume(MetadataLib.isValid(metadata));
    }

    function _assumeValidTarget(address target) internal {
        vm.assume(target != address(factory));
        vm.assume(target != address(0));
    }

    function _assumeValidProposal(address proposal) internal {
        vm.assume(proposal != address(0));
    }
}
