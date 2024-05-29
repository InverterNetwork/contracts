// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// Internal Dependencies
import {ModuleFactory_v1} from "src/factories/ModuleFactory_v1.sol";

// Internal Libraries
import {LibMetadata} from "src/modules/lib/LibMetadata.sol";

// Internal Interfaces
import {
    IModuleFactory_v1,
    IModule_v1,
    IOrchestrator_v1
} from "src/factories/interfaces/IModuleFactory_v1.sol";

import {IOrchestratorFactory_v1} from
    "src/factories/interfaces/IOrchestratorFactory_v1.sol";

import {IInverterBeacon_v1} from "src/proxies/interfaces/IInverterBeacon_v1.sol";

// Mocks
import {ModuleImplementationV1Mock} from
    "test/utils/mocks/proxies/ModuleImplementationV1Mock.sol";
import {ModuleImplementationV2Mock} from
    "test/utils/mocks/proxies/ModuleImplementationV2Mock.sol";
import {InverterBeaconV1OwnableMock} from
    "test/utils/mocks/proxies/InverterBeaconV1OwnableMock.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

contract ModuleFactoryV1Test is Test {
    // SuT
    ModuleFactory_v1 factory;

    // Mocks
    ModuleImplementationV1Mock module;
    InverterBeaconV1OwnableMock beacon;

    address governanceContract = address(0x010101010101);

    IOrchestratorFactory_v1.WorkflowConfig workflowConfigNoIndependentUpdates =
    IOrchestratorFactory_v1.WorkflowConfig({
        independentUpdates: false,
        independentUpdateAdmin: address(0)
    });

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when new beacon registered for metadata.
    event MetadataRegistered(
        IModule_v1.Metadata indexed metadata, IInverterBeacon_v1 indexed beacon
    );

    /// @notice Event emitted when new module created for a orchestrator.
    event ModuleCreated(
        address indexed orchestrator, address indexed module, bytes32 identifier
    );

    // Constants
    uint constant MAJOR_VERSION = 1;
    uint constant MINOR_VERSION = 0;
    string constant URL = "https://github.com/organization/module";
    string constant TITLE = "Payment Processor";

    IModule_v1.Metadata DATA =
        IModule_v1.Metadata(MAJOR_VERSION, MINOR_VERSION, URL, TITLE);

    function setUp() public {
        module = new ModuleImplementationV1Mock();
        beacon = new InverterBeaconV1OwnableMock(governanceContract);

        factory = new ModuleFactory_v1(address(0));
        factory.init(governanceContract);
    }

    function testDeploymentInvariants() public {
        // Invariants: Ownable2Step
        assertEq(factory.owner(), governanceContract);
        assertEq(factory.pendingOwner(), address(0));
    }

    //--------------------------------------------------------------------------
    // Test: registerMetadata

    function testRegisterMetadataOnlyCallableByOwner(address caller) public {
        vm.assume(caller != governanceContract);
        vm.assume(caller != address(0));
        vm.assume(caller != governanceContract);
        vm.prank(caller);

        vm.expectRevert(
            abi.encodeWithSelector(
                OZErrors.Ownable__UnauthorizedAccount, caller
            )
        );

        factory.registerMetadata(DATA, beacon);
    }

    function testRegisterMetadata(IModule_v1.Metadata memory metadata) public {
        _assumeValidMetadata(metadata);

        beacon.overrideImplementation(address(module));

        vm.expectEmit(true, true, true, true);

        // We emit the event we expect to see.
        emit MetadataRegistered(metadata, beacon);

        vm.prank(governanceContract);
        factory.registerMetadata(metadata, beacon);

        IInverterBeacon_v1 beaconRegistered;
        (beaconRegistered, /*id*/ ) = factory.getBeaconAndId(metadata);

        assertEq(address(beaconRegistered), address(beacon));
    }

    function testRegisterMetadataFailsIfMetadataInvalid() public {
        // Invalid if url empty.
        vm.expectRevert(
            IModuleFactory_v1.ModuleFactory__InvalidMetadata.selector
        );
        vm.prank(governanceContract);
        factory.registerMetadata(
            IModule_v1.Metadata(MAJOR_VERSION, MINOR_VERSION, "", TITLE), beacon
        );

        // Invalid if title empty.
        vm.expectRevert(
            IModuleFactory_v1.ModuleFactory__InvalidMetadata.selector
        );
        vm.prank(governanceContract);
        factory.registerMetadata(
            IModule_v1.Metadata(MAJOR_VERSION, MINOR_VERSION, URL, ""), beacon
        );
    }

    function testRegisterMetadataFailsIfAlreadyRegistered() public {
        beacon.overrideImplementation(address(module));

        InverterBeaconV1OwnableMock additionalBeacon =
            new InverterBeaconV1OwnableMock(governanceContract);
        additionalBeacon.overrideImplementation(address(module));

        vm.prank(governanceContract);
        factory.registerMetadata(DATA, beacon);

        vm.expectRevert(
            IModuleFactory_v1.ModuleFactory__MetadataAlreadyRegistered.selector
        );
        vm.prank(governanceContract);
        factory.registerMetadata(DATA, additionalBeacon);
    }

    function testRegisterMetadataFailsIfBeaconsImplementationIsZero() public {
        beacon.overrideImplementation(address(0));

        vm.expectRevert(
            IModuleFactory_v1.ModuleFactory__InvalidInverterBeacon.selector
        );
        vm.prank(governanceContract);
        factory.registerMetadata(DATA, beacon);
    }

    function testRegisterMetadataFailsIfBeaconIsNotOwnedByGovernor() public {
        InverterBeaconV1OwnableMock notOwnedBeacon =
            new InverterBeaconV1OwnableMock(address(0x1111111));

        notOwnedBeacon.overrideImplementation(address(0x1));

        vm.expectRevert(
            IModuleFactory_v1.ModuleFactory__InvalidInverterBeacon.selector
        );
        vm.prank(governanceContract);
        factory.registerMetadata(DATA, notOwnedBeacon);
    }

    //--------------------------------------------------------------------------
    // Tests: createModule

    error hm();

    function testCreateModule(
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig,
        IModule_v1.Metadata memory metadata,
        address orchestrator,
        bytes memory configData
    ) public {
        _assumeValidMetadata(metadata);
        _assumeValidOrchestrator(orchestrator);
        _assumeValidWorkflowConfig(workflowConfig);

        beacon.overrideImplementation(address(module));

        // Register ModuleV1Mock for given metadata.
        vm.prank(governanceContract);
        factory.registerMetadata(metadata, beacon);

        // Since we don't know the exact address the cloned module will have, we only check that an event of the right type is fired
        vm.expectEmit(true, false, false, false);

        // We emit the event we expect to see.
        emit ModuleCreated(
            orchestrator, address(0), LibMetadata.identifier(metadata)
        );

        // Create new module instance.
        IModule_v1 newModule = IModule_v1(
            factory.createModule(
                metadata,
                IOrchestrator_v1(orchestrator),
                configData,
                workflowConfig
            )
        );

        assertEq(
            factory.getOrchestratorOfProxy(address(newModule)), orchestrator
        );
        assertEq(address(newModule.orchestrator()), address(orchestrator));
        assertEq(newModule.identifier(), LibMetadata.identifier(metadata));

        //Check for proper Proxy setup

        beacon.overrideImplementation(address(new ModuleImplementationV2Mock()));

        //Beacon should point to Version 2
        uint expectedValue = 2;

        //If it is independent then the version should have stayed at 1
        if (workflowConfig.independentUpdates) {
            expectedValue = 1;
        }

        assertEq(
            ModuleImplementationV1Mock(address(newModule)).getMockVersion(),
            expectedValue
        );
    }

    function testCreateModuleFailsIfMetadataUnregistered(
        IModule_v1.Metadata memory metadata,
        address orchestrator,
        bytes memory configData
    ) public {
        _assumeValidMetadata(metadata);
        _assumeValidOrchestrator(orchestrator);

        vm.expectRevert(
            IModuleFactory_v1.ModuleFactory__UnregisteredMetadata.selector
        );
        factory.createModule(
            metadata,
            IOrchestrator_v1(orchestrator),
            configData,
            workflowConfigNoIndependentUpdates
        );
    }

    //--------------------------------------------------------------------------
    // Internal Helper Functions

    function _assumeValidMetadata(IModule_v1.Metadata memory metadata)
        public
        pure
    {
        vm.assume(LibMetadata.isValid(metadata));
    }

    function _assumeValidOrchestrator(address orchestrator) internal pure {
        vm.assume(orchestrator != address(0));
    }

    function _assumeValidWorkflowConfig(
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig
    ) internal view {
        if (workflowConfig.independentUpdates) {
            vm.assume(workflowConfig.independentUpdateAdmin != address(0));
            vm.assume(
                address(workflowConfig.independentUpdateAdmin).code.length == 0
            );
        }
    }
}
