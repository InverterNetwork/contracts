// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

//Internal Dependencies
import {
    E2ETest,
    IOrchestratorFactory,
    IOrchestrator,
    ModuleFactory
} from "test/e2e/E2ETest.sol";
import {IModuleFactory, IModule} from "src/factories/IModuleFactory.sol";

// Internal Libraries
import {LibMetadata} from "src/modules/lib/LibMetadata.sol";

// Mocks
import {ModuleMock} from "test/utils/mocks/modules/base/ModuleMock.sol";
import {InverterBeaconMock} from
    "test/utils/mocks/factories/beacon/InverterBeaconMock.sol";
import {ModuleImplementationV1Mock} from
    "test/utils/mocks/factories/beacon/ModuleImplementationV1Mock.sol";
import {ModuleImplementationV2Mock} from
    "test/utils/mocks/factories/beacon/ModuleImplementationV2Mock.sol";

contract BInvertereacon_ModuleUpdateTest is E2ETest {
    // Mocks
    ModuleMock module;
    InverterBeaconMock beacon;

    // Mock Metadata
    uint constant MAJOR_VERSION = 1;
    uint constant MINOR_VERSION = 1;
    string constant URL = "https://github.com/organization/module";
    string constant TITLE = "Module";

    IModule.Metadata DATA =
        IModule.Metadata(MAJOR_VERSION, MINOR_VERSION, URL, TITLE);

    function setUp() public override {
        super.setUp();

        module = new ModuleMock();
        beacon = new InverterBeaconMock();
    }

    function testDeploymentInvariants() public {
        // Invariants: Ownable2Step
        assertEq(moduleFactory.owner(), address(this));
        assertEq(moduleFactory.pendingOwner(), address(0));
    }

    //--------------------------------------------------------------------------
    // Tests: InverterBeacon Upgrades

    function test_e2e_InverterBeaconUpgrade(
        IModule.Metadata memory metadata,
        address orchestrator,
        bytes memory configData
    ) public {
        _assumeValidMetadata(metadata);
        _assumeValidOrchestrator(orchestrator);

        // Create implementation V1 and upgrade beacon to it.
        ModuleImplementationV1Mock implementationV1 =
            new ModuleImplementationV1Mock();
        beacon.overrideImplementation(address(implementationV1));

        // Register beacon as Module.
        moduleFactory.registerMetadata(metadata, beacon);

        //Create Module Proxy in Factory
        address proxyImplementationAddress1 = moduleFactory.createModule(
            metadata, IOrchestrator(orchestrator), configData
        );

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

    function _assumeValidMetadata(IModule.Metadata memory metadata)
        public
        pure
    {
        vm.assume(LibMetadata.isValid(metadata));
    }

    function _assumeValidOrchestrator(address orchestrator) internal pure {
        vm.assume(orchestrator != address(0));
    }
}
