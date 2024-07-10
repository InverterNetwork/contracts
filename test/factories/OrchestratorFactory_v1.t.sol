// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// Internal Dependencies
import {OrchestratorFactory_v1} from "src/factories/OrchestratorFactory_v1.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {Ownable} from "@oz/access/Ownable.sol";

// Internal Interfaces
import {
    IOrchestratorFactory_v1,
    IModule_v1,
    IOrchestrator_v1
} from "src/factories/interfaces/IOrchestratorFactory_v1.sol";

import {Orchestrator_v1} from "src/orchestrator/Orchestrator_v1.sol";

// Mocks
import {ModuleImplementationV1Mock} from
    "test/utils/mocks/proxies/ModuleImplementationV1Mock.sol";
import {ModuleFactoryV1Mock} from
    "test/utils/mocks/factories/ModuleFactoryV1Mock.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

import {InverterBeaconV1OwnableMock} from
    "test/utils/mocks/proxies/InverterBeaconV1OwnableMock.sol";

// External Dependencies
import {Clones} from "@oz/proxy/Clones.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

contract OrchestratorFactoryV1Test is Test {
    // SuT
    OrchestratorFactory_v1 factory;

    Orchestrator_v1 target;

    InverterBeaconV1OwnableMock beacon;

    address governanceContract = makeAddr("GovernorContract");

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when a new orchestrator is created.
    /// @param orchestratorId The id of the orchestrator.
    /// @param orchestratorAddress The address of the orchestrator.
    event OrchestratorCreated(
        uint indexed orchestratorId, address indexed orchestratorAddress
    );

    // Mocks
    ModuleFactoryV1Mock moduleFactory;

    // Metadata
    IOrchestratorFactory_v1.WorkflowConfig workflowConfigNoIndependentUpdates =
    IOrchestratorFactory_v1.WorkflowConfig({
        independentUpdates: false,
        independentUpdateAdmin: address(0)
    });

    IOrchestratorFactory_v1.ModuleConfig fundingManagerConfig =
    IOrchestratorFactory_v1.ModuleConfig(
        IModule_v1.Metadata(
            1, 0, "https://fundingmanager.com", "FundingManager"
        ),
        bytes("data")
    );

    IOrchestratorFactory_v1.ModuleConfig authorizerConfig =
    IOrchestratorFactory_v1.ModuleConfig(
        IModule_v1.Metadata(1, 0, "https://authorizer.com", "Authorizer"),
        abi.encode(address(this), address(this))
    );

    IOrchestratorFactory_v1.ModuleConfig paymentProcessorConfig =
    IOrchestratorFactory_v1.ModuleConfig(
        IModule_v1.Metadata(
            1, 1, "https://paymentprocessor.com", "PP_Simple_v1"
        ),
        bytes("data")
    );

    IOrchestratorFactory_v1.ModuleConfig moduleConfig = IOrchestratorFactory_v1
        .ModuleConfig(
        IModule_v1.Metadata(1, 0, "https://module.com", "Module_v1"), bytes("")
    );

    function setUp() public {
        moduleFactory = new ModuleFactoryV1Mock();

        target = new Orchestrator_v1(address(0));

        beacon = new InverterBeaconV1OwnableMock(governanceContract);
        beacon.overrideImplementation(address(target));

        address impl = address(new OrchestratorFactory_v1(address(0)));
        factory = OrchestratorFactory_v1(Clones.clone(impl));
        factory.init(moduleFactory.governor(), beacon, address(moduleFactory));
    }

    function testValidOrchestratorId(uint getId, uint orchestratorsCreated)
        public
    {
        // Note to stay reasonable
        orchestratorsCreated = bound(orchestratorsCreated, 0, 50);

        for (uint i = 0; i < orchestratorsCreated; ++i) {
            _deployOrchestrator();
        }

        if (getId > orchestratorsCreated) {
            vm.expectRevert(
                IOrchestratorFactory_v1.OrchestratorFactory__InvalidId.selector
            );
        }
        factory.getOrchestratorByID(getId);
    }

    function testDeploymentInvariants() public {
        assertEq(address(factory.beacon()), address(beacon));
        assertEq(factory.moduleFactory(), address(moduleFactory));
    }

    function testCreateOrchestrator(
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig,
        uint modulesLen
    ) public {
        _assumeValidWorkflowConfig(workflowConfig);
        // Note to stay reasonable
        modulesLen = bound(modulesLen, 0, 50);

        // Create optional ModuleConfig instances.
        IOrchestratorFactory_v1.ModuleConfig[] memory moduleConfigs =
            new IOrchestratorFactory_v1.ModuleConfig[](modulesLen);
        for (uint i; i < modulesLen; ++i) {
            moduleConfigs[i] = moduleConfig;
        }

        vm.expectEmit(true, false, false, false);
        emit OrchestratorCreated(1, address(0)); // Since we don't know the address of the orchestrator

        // Deploy Orchestrator_v1 with id=1
        IOrchestrator_v1 orchestrator = factory.createOrchestrator(
            workflowConfig,
            fundingManagerConfig,
            authorizerConfig,
            paymentProcessorConfig,
            moduleConfigs
        );

        // Check that workflowConfig was properly forwarded
        (bool independentUpdates, address independentUpdateProxyAdmin) =
            moduleFactory.givenWorkflowConfig();

        assertEq(workflowConfig.independentUpdates, independentUpdates);
        if (workflowConfig.independentUpdates) {
            address independentUpdateAdmin =
                Ownable(independentUpdateProxyAdmin).owner();
            assertEq(
                workflowConfig.independentUpdateAdmin, independentUpdateAdmin
            );
        }

        // Check that orchestrator's strorage correctly initialized.
        assertEq(orchestrator.orchestratorId(), 1);
        assertTrue(address(orchestrator.authorizer()) != address(0));
        assertTrue(address(orchestrator.paymentProcessor()) != address(0));
        assertTrue(address(orchestrator.governor()) == moduleFactory.governor());

        // Module size should be the 3 enforced contracts + whatever is in the module config
        assertEq(orchestrator.modulesSize(), 3 + moduleConfigs.length);

        vm.expectEmit(true, false, false, false);
        emit OrchestratorCreated(2, address(0)); // since we don't know the address of the orchestrator

        // Deploy Orchestrator_v1 with id=2
        orchestrator = factory.createOrchestrator(
            workflowConfig,
            fundingManagerConfig,
            authorizerConfig,
            paymentProcessorConfig,
            moduleConfigs
        );
        // Only check that orchestrator's id is correct.
        assertEq(orchestrator.orchestratorId(), 2);

        // check that orchestratorFactory idCounter is correct.
        assertEq(factory.getOrchestratorIDCounter(), 2);

        // Check for proper Proxy setup

        beacon.overrideImplementation(address(new ModuleImplementationV1Mock()));

        // If it is independent then the beacon change should not be represented
        if (workflowConfig.independentUpdates) {
            vm.expectRevert();
            ModuleImplementationV1Mock(address(orchestrator)).getMockVersion();

            assertEq(orchestrator.orchestratorId(), 2);
        } else {
            assertEq(
                ModuleImplementationV1Mock(address(orchestrator)).getMockVersion(
                ),
                1
            );
            vm.expectRevert();
            orchestrator.orchestratorId();
        }
    }

    function testOrchestratorMapping(uint orchestratorAmount) public {
        // Note to stay reasonable
        orchestratorAmount = bound(orchestratorAmount, 0, 50);

        for (uint i = 1; i < orchestratorAmount; ++i) {
            address orchestrator = _deployOrchestrator();
            assertEq(orchestrator, factory.getOrchestratorByID(i));
        }
    }

    function _deployOrchestrator() private returns (address) {
        // Create Empty ModuleConfig
        IOrchestratorFactory_v1.ModuleConfig[] memory moduleConfigs =
            new IOrchestratorFactory_v1.ModuleConfig[](0);

        vm.expectEmit(false, false, false, false);
        emit OrchestratorCreated(0, address(0)); // Since we don't know the id/address of the orchestrator

        // Deploy Orchestrator_v1
        IOrchestrator_v1 orchestrator = factory.createOrchestrator(
            workflowConfigNoIndependentUpdates,
            fundingManagerConfig,
            authorizerConfig,
            paymentProcessorConfig,
            moduleConfigs
        );

        return address(orchestrator);
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
