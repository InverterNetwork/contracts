// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
//Internal Dependencies
import {
    E2ETest,
    IOrchestratorFactory,
    IOrchestrator,
    ModuleFactory
} from "test/e2e/E2ETest.sol";
import {IModuleFactory, IModule} from "src/factories/IModuleFactory.sol";

import {InverterBeacon} from "src/factories/beacon/InverterBeacon.sol";

// Internal Libraries
import {LibMetadata} from "src/modules/lib/LibMetadata.sol";

// Mocks
import {ModuleMock} from "test/utils/mocks/modules/base/ModuleMock.sol";

import {
    IModuleImplementationMock,
    ModuleImplementationV1Mock
} from "test/utils/mocks/factories/beacon/ModuleImplementationV1Mock.sol";
import {
    IModuleImplementationMock,
    ModuleImplementationV2Mock
} from "test/utils/mocks/factories/beacon/ModuleImplementationV2Mock.sol";

contract InverterBeaconE2E is E2ETest {
    // Mocks
    ModuleImplementationV1Mock moduleImpl1;
    ModuleImplementationV2Mock moduleImpl2;
    InverterBeacon beacon;

    // Mock Metadata
    uint constant MAJOR_VERSION = 1;
    uint constant MINOR_VERSION = 1;
    string constant URL = "https://github.com/organization/module";
    string constant TITLE = "Module";

    IModule.Metadata DATA =
        IModule.Metadata(MAJOR_VERSION, MINOR_VERSION, URL, TITLE);

    // Module Configurations for the current E2E test. Should be filled during setUp() call.
    IOrchestratorFactory.ModuleConfig[] moduleConfigurations;

    // E2E Test Variables

    function setUp() public override {
        // Setup common E2E framework
        super.setUp();

        // Set Up individual Modules the E2E test is going to use and store their configurations:
        // NOTE: It's important to store the module configurations in order, since _create_E2E_Orchestrator() will copy from the array.
        // The order should be:
        //      moduleConfigurations[0]  => FundingManager
        //      moduleConfigurations[1]  => Authorizer
        //      moduleConfigurations[2]  => PaymentProcessor
        //      moduleConfigurations[3:] => Additional Logic Modules

        // FundingManager
        setUpRebasingFundingManager();
        moduleConfigurations.push(
            IOrchestratorFactory.ModuleConfig(
                rebasingFundingManagerMetadata,
                abi.encode(address(token)),
                abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
            )
        );

        // Authorizer
        setUpTokenGatedRoleAuthorizer();
        moduleConfigurations.push(
            IOrchestratorFactory.ModuleConfig(
                tokenRoleAuthorizerMetadata,
                abi.encode(address(this), address(this)),
                abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
            )
        );

        // PaymentProcessor
        setUpSimplePaymentProcessor();
        moduleConfigurations.push(
            IOrchestratorFactory.ModuleConfig(
                simplePaymentProcessorMetadata,
                bytes(""),
                abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
            )
        );
        console2.log("1");
        //--------------------------------------------------------------------------
        // Beacon added to factory

        // Deploy module implementations.
        moduleImpl1 = new ModuleImplementationV1Mock();
        moduleImpl2 = new ModuleImplementationV2Mock();

        console2.log("2");

        // Deploy module beacons.
        vm.prank(address(this)); //this will be the owner of the beacon
        beacon = new InverterBeacon(MAJOR_VERSION);

        // Set beacon's implementations.
        vm.prank(address(this));
        beacon.upgradeTo(address(moduleImpl1), MINOR_VERSION, false);

        console2.log("3");

        // Register modules at moduleFactory.
        moduleFactory.registerMetadata(DATA, InverterBeacon(beacon));

        console2.log("4");

        //Add new Beacon to this moduleConfiguration
        moduleConfigurations.push(
            IOrchestratorFactory.ModuleConfig(
                DATA,
                bytes(""),
                abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
            )
        );

        console2.log("11");
    }

    //--------------------------------------------------------------------------
    // Tests: InverterBeacon Upgrades

    function test_e2e_InverterBeaconUpgrade() public {
        //--------------------------------------------------------------------------------
        // Orchestrator Initialization
        //--------------------------------------------------------------------------------

        IOrchestratorFactory.OrchestratorConfig memory orchestratorConfig =
        IOrchestratorFactory.OrchestratorConfig({
            owner: address(this),
            token: token
        });

        IOrchestrator orchestrator =
            _create_E2E_Orchestrator(orchestratorConfig, moduleConfigurations);

        //--------------------------------------------------------------------------------
        // Module E2E Test
        //--------------------------------------------------------------------------------

        // Find Implementation
        IModuleImplementationMock moduleMock;

        //Get all Modules
        address[] memory modulesList = orchestrator.listModules();
        for (uint i; i < modulesList.length; ++i) {
            //Find the one that can fulfill the IMetadataFunction
            try IModuleImplementationMock(modulesList[i]).getMockVersion()
            returns (uint) {
                moduleMock = IModuleImplementationMock(modulesList[i]);
                break;
            } catch {
                continue;
            }
        }

        //Check that the version is 1 as implemented in the ModuleImplementationV1Mock
        assertEq(moduleMock.getMockVersion(), 1);

        // Upgrade beacon to point to the Version 2 implementation.
        vm.prank(address(this));
        beacon.upgradeTo(address(moduleImpl2), MINOR_VERSION + 1, false);

        //Check that after the update
        assertEq(moduleMock.getMockVersion(), 2);
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
