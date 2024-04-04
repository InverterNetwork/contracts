// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

// Internal Dependencies:
import {E2EModuleRegistry} from "test/e2e/E2EModuleRegistry.sol";

// Factories
import {ModuleFactory, IModuleFactory} from "src/factories/ModuleFactory.sol";
import {
    OrchestratorFactory,
    IOrchestratorFactory
} from "src/factories/OrchestratorFactory.sol";

// Orchestrator
import {Orchestrator, IOrchestrator} from "src/orchestrator/Orchestrator.sol";

import {IFM_BC_Bancor_Redeeming_VirtualIssuance_VirtualCollateral_v1} from
    "src/modules/fundingManager/bondingCurve/interfaces/IFM_BC_Bancor_Redeeming_VirtualIssuance_VirtualCollateral_v1.sol";
import {BancorFormula} from
    "src/modules/fundingManager/bondingCurve/formulas/BancorFormula.sol";

// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

/**
 * @dev Base contract for e2e tests.
 */
contract E2ETest is E2EModuleRegistry {
    // Factory instances.
    OrchestratorFactory orchestratorFactory;

    // Orchestrator implementation.
    Orchestrator orchestratorImpl;

    // Mock token for funding.
    ERC20Mock token;

    function setUp() public virtual {
        // Basic Setup function. This function es overriden and expanded by child E2E tests

        // Deploy a Mock funding token for testing.
        token = new ERC20Mock("Mock", "MOCK");

        // Deploy Orchestrator implementation.
        orchestratorImpl = new Orchestrator();

        // Deploy Factories.
        moduleFactory = new ModuleFactory();

        orchestratorFactory = new OrchestratorFactory(
            address(orchestratorImpl), address(moduleFactory)
        );
    }

    // Creates an orchestrator with the supplied config and the stored module config.
    // Can be overriden, shouldn't need to
    // NOTE: It's important to send the module configurations in order, since it will copy from the array.
    // The order should be:
    //      moduleConfigurations[0]  => FundingManager
    //      moduleConfigurations[1]  => Authorizer
    //      moduleConfigurations[2]  => PaymentProcessor
    //      moduleConfigurations[3:] => Additional Logic Modules
    function _create_E2E_Orchestrator(
        IOrchestratorFactory.OrchestratorConfig memory _config,
        IOrchestratorFactory.ModuleConfig[] memory _moduleConfigurations
    ) internal virtual returns (IOrchestrator) {
        // Prepare array of optional modules (hopefully can be made more succinct in the future)
        uint amtOfOptionalModules = _moduleConfigurations.length - 3;

        IOrchestratorFactory.ModuleConfig[] memory optionalModules =
            new IOrchestratorFactory.ModuleConfig[](amtOfOptionalModules);

        for (uint i = 0; i < amtOfOptionalModules; i++) {
            optionalModules[i] = _moduleConfigurations[i + 3];
        }

        // Create orchestrator

        return orchestratorFactory.createOrchestrator(
            _config,
            _moduleConfigurations[0],
            _moduleConfigurations[1],
            _moduleConfigurations[2],
            optionalModules
        );
    }
}
