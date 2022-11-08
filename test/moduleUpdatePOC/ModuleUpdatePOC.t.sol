// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

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
import {ModuleImplementationV1Mock} from
    "test/utils/mocks/factories/beacon/ModuleImplementationV1Mock.sol";
import {ModuleImplementationV2Mock} from
    "test/utils/mocks/factories/beacon/ModuleImplementationV2Mock.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

contract ModuleUpdatePOCTest is Test {
    // SuT
    ModuleFactory factory;

    // Mocks
    ModuleMock module;
    BeaconMock beacon;

    // Constants
    // @todo mp: Move to some common contract. See todo in Milestone.t.sol too.
    uint constant MAJOR_VERSION = 1;
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
    // Tests: Beacon Upgrades

    function testBeaconUpgrade(
        IModule.Metadata memory metadata,
        address proposal,
        bytes memory configdata
    ) public {
        _assumeValidMetadata(metadata);
        _assumeValidProposal(proposal);

        // Create implementation V1 and upgrade beacon to it.
        ModuleImplementationV1Mock implementationV1 =
            new ModuleImplementationV1Mock();
        beacon.overrideImplementation(address(implementationV1));

        // Register beacon as Module.
        factory.registerMetadata(metadata, beacon);

        //Create Module Proxy in Factory
        address proxyImplementationAddress1 =
            factory.createModule(metadata, IProposal(proposal), configdata);

        assertEq(
            ModuleImplementationV1Mock(proxyImplementationAddress1).getVersion(),
            1
        );

        // Create implementation V2 and upgrade beacon to it.
        ModuleImplementationV2Mock implementationV2 =
            new ModuleImplementationV2Mock();
        beacon.overrideImplementation(address(implementationV2));

        assertEq(
            ModuleImplementationV2Mock(proxyImplementationAddress1).getVersion(),
            2
        );
    }

    //--------------------------------------------------------------------------
    // Internal Helper Functions

    function _assumeValidMetadata(IModule.Metadata memory metadata) public {
        vm.assume(LibMetadata.isValid(metadata));
    }

    function _assumeValidProposal(address proposal) internal {
        vm.assume(proposal != address(0));
    }
}
