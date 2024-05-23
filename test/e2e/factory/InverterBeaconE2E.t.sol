// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
//Internal Dependencies
import {
    E2ETest,
    IOrchestratorFactory_v1,
    IOrchestrator_v1,
    ModuleFactory_v1
} from "test/e2e/E2ETest.sol";
import {
    IModuleFactory_v1,
    IModule_v1
} from "src/factories/interfaces/IModuleFactory_v1.sol";

import {InverterBeacon_v1} from "src/proxies/InverterBeacon_v1.sol";

// Internal Libraries
import {LibMetadata} from "src/modules/lib/LibMetadata.sol";

// Mocks
import {
    IModuleImplementationMock,
    ModuleImplementationV1Mock
} from "test/utils/mocks/proxies/ModuleImplementationV1Mock.sol";
import {
    IModuleImplementationMock,
    ModuleImplementationV2Mock
} from "test/utils/mocks/proxies/ModuleImplementationV2Mock.sol";

contract InverterBeaconE2E is E2ETest {
    // Mocks
    ModuleImplementationV1Mock moduleImpl1;
    ModuleImplementationV2Mock moduleImpl2;
    InverterBeacon_v1 beacon;

    // Mock Metadata
    uint constant MAJOR_VERSION = 1;
    uint constant MINOR_VERSION = 0;
    string constant URL = "https://github.com/organization/module";
    string constant TITLE = "Module";

    IModule_v1.Metadata DATA =
        IModule_v1.Metadata(MAJOR_VERSION, MINOR_VERSION, URL, TITLE);

    // Module Configurations for the current E2E test. Should be filled during setUp() call.
    IOrchestratorFactory_v1.ModuleConfig[] moduleConfigurations;

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
            IOrchestratorFactory_v1.ModuleConfig(
                rebasingFundingManagerMetadata,
                abi.encode(address(token)),
                abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
            )
        );

        // Authorizer
        setUpTokenGatedRoleAuthorizer();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                tokenRoleAuthorizerMetadata,
                abi.encode(address(this), address(this)),
                abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
            )
        );

        // PaymentProcessor
        setUpSimplePaymentProcessor();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                simplePaymentProcessorMetadata,
                bytes(""),
                abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
            )
        );
        //--------------------------------------------------------------------------
        // Beacon added to factory

        // Deploy module implementations.
        moduleImpl1 = new ModuleImplementationV1Mock();
        moduleImpl2 = new ModuleImplementationV2Mock();

        // Deploy module beacons.

        beacon = new InverterBeacon_v1(
            address(gov), //The governor contract will be the owner of the beacon
            MAJOR_VERSION,
            address(moduleImpl1),
            MINOR_VERSION
        );

        // Register modules at moduleFactory.
        vm.prank(teamMultisig);
        gov.registerMetadata(moduleFactory, DATA, InverterBeacon_v1(beacon));

        //Add new Beacon to this moduleConfiguration
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                DATA,
                bytes(""),
                abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
            )
        );
    }

    //--------------------------------------------------------------------------
    // Tests: InverterBeacon_v1 Upgrades

    function test_e2e_InverterBeaconUpgrade() public {
        //--------------------------------------------------------------------------------
        // Orchestrator_v1 Initialization
        //--------------------------------------------------------------------------------

        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig =
        IOrchestratorFactory_v1.WorkflowConfig({
            independentUpdates: false,
            independentUpdateAdmin: address(0)
        });

        IOrchestrator_v1 orchestrator =
            _create_E2E_Orchestrator(workflowConfig, moduleConfigurations);

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
        vm.prank(address(gov));
        beacon.upgradeTo(address(moduleImpl2), MINOR_VERSION + 1, false);

        //Check that after the update
        assertEq(moduleMock.getMockVersion(), 2);
    }

    function test_e2e_InverterBeaconShutdown() public {
        //--------------------------------------------------------------------------------
        // Orchestrator_v1 Initialization
        //--------------------------------------------------------------------------------

        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig =
        IOrchestratorFactory_v1.WorkflowConfig({
            independentUpdates: false,
            independentUpdateAdmin: address(0)
        });

        IOrchestrator_v1 orchestrator =
            _create_E2E_Orchestrator(workflowConfig, moduleConfigurations);
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

        //Check that the Call of the implementation still works
        assertEq(moduleMock.getMockVersion(), 1);

        //Simulate Emergency by implementing shut-down
        vm.prank(address(gov));
        beacon.shutDownImplementation();

        //The call to the implementation should fail
        //As a note: apparently a try catch still throws an EVM Error when the call doesnt find the correct function in the target address,
        //because the target doesnt create a proper Revert when its called
        //Thats why im wrapping it in a call to demonstrate
        //Funnily enough the call doesnt return as a failure for some reason
        //Because of the failure of the direct call we know that it actually fails if called
        //I assume its a weird interaction between the delegatecall of the proxy and the call we are just doing here
        //So just to make sure that we can actually check if the call fails
        //We check if the returndata is 0, which it is not supposed to be with the getMockVersion function

        bytes memory data =
            abi.encodeCall(IModuleImplementationMock.getMockVersion, ());
        (, bytes memory returnData) = address(moduleMock).call(data);
        //Make sure returndata is 0 which means call didnt go through
        assertEq(returnData.length, 0);

        //Reverse shut-down
        vm.prank(address(gov));
        beacon.restartImplementation();

        //Check that the Call of the implementation works again
        assertEq(moduleMock.getMockVersion(), 1);

        //Lets do a upgrade that overrides the shutdown
        //First shut-down
        vm.prank(address(gov));
        beacon.shutDownImplementation();

        // Upgrade beacon to point to the Version 2 implementation.
        vm.prank(address(gov));
        beacon.upgradeTo(
            address(moduleImpl2),
            MINOR_VERSION + 1,
            true //Set override shutdown to true, which should result in reversing the shutdown
        );

        //Check that the Call of the implementation works again and is properly upgraded
        assertEq(moduleMock.getMockVersion(), 2);
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
}
