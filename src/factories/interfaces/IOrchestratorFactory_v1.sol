// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Interfaces
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IModule_v1} from "src/modules/base/IModule_v1.sol";

import {IInverterBeacon_v1} from "src/proxies/interfaces/IInverterBeacon_v1.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

interface IOrchestratorFactory_v1 {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice The provided beacon address doesnt support the interface {IInverterBeacon_v1}.
    error OrchestratorFactory__InvalidBeacon();

    /// @notice Given id is invalid.
    error OrchestratorFactory__InvalidId();

    /// @notice The module's data arrays length mismatch.
    error OrchestratorFactory__ModuleDataLengthMismatch();

    /// @notice The orchestrator admin is address(0).
    error OrchestratorFactory__OrchestratorAdminIsInvalid();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when a new {Orchestrator_v1} is created.
    /// @param  orchestratorId The id of the {Orchestrator_v1}.
    /// @param  orchestratorAddress The address of the {Orchestrator.
    event OrchestratorCreated(
        uint indexed orchestratorId, address indexed orchestratorAddress
    );

    /// @notice Event emitted when a new {OrchestratorFactory_v1} is initialized.
    /// @param  beacon The address of the {IInverterBeacon_v1} associated with the factory.
    /// @param  moduleFactory The address of the {ModuleFactory_v1}.
    event OrchestratorFactoryInitialized(
        address indexed beacon, address indexed moduleFactory
    );

    //--------------------------------------------------------------------------
    // Structs

    /// @notice Struct used to store information about a workflow configuration.
    /// @dev	When the `independentUpdates` is true, the `independentUpdateAdmin` will be disregarded.
    /// @param  independentUpdates bool wether the workflow should use the independent proxy structure.
    ///                           In case of true it will not use the standard beacon proxy structure.
    /// @param  independentUpdateAdmin The address that will be assigned the admin role of the independent update proxy.
    ///                               Will be disregarded in case `independentUpdates` is false.
    struct WorkflowConfig {
        bool independentUpdates;
        address independentUpdateAdmin;
    }

    /// @notice Struct used to store information about a module configuration.
    /// @param  metadata The module's metadata.
    /// @param  configData Variable config data for specific module implementations.
    struct ModuleConfig {
        IModule_v1.Metadata metadata;
        bytes configData;
    }

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Creates a new {Orchestrator_v1}.
    /// @param  workflowConfig The workflow's config data.
    /// @param  fundingManagerConfig The config data for the orchestrator's {IFundingManager_v1}
    ///                             instance.
    /// @param  authorizerConfig The config data for the {Orchestrator_v1}'s {IAuthorizer_v1}
    ///                         instance.
    /// @param  paymentProcessorConfig The config data for the orchestrator's
    ///                               {IPaymentProcessor_v1} instance.
    /// @param  moduleConfigs Variable length set of optional module's config
    ///                      data.
    /// @return CreatedOrchestrator Returns the created orchestrator instance
    function createOrchestrator(
        WorkflowConfig memory workflowConfig,
        ModuleConfig memory fundingManagerConfig,
        ModuleConfig memory authorizerConfig,
        ModuleConfig memory paymentProcessorConfig,
        ModuleConfig[] memory moduleConfigs
    ) external returns (IOrchestrator_v1);

    /// @notice Returns the {IOrchestrator_v1} {IInverterBeacon_v1} address.
    /// @return OrchestratorImplementationBeacon The {IInverterBeacon_v1} of the {Orchestrator_v1} Implementation.
    function beacon() external view returns (IInverterBeacon_v1);

    /// @notice Returns the {IModuleFactory_v1} implementation address.
    /// @return ModuleFactoryAddress The address of the linked {ModuleFactory_v1}.
    function moduleFactory() external view returns (address);

    /// @notice Returns the {IOrchestrator_v1} address that corresponds to the given id.
    /// @param  id The requested orchestrator's id.
    /// @return orchestratorAddress The address of the corresponding {Orchestrator_v1}.
    function getOrchestratorByID(uint id) external view returns (address);

    /// @notice Returns the counter of the current {Orchestrator_v1} id.
    /// @return id The id of the next created {Orchestrator_v1}.
    function getOrchestratorIDCounter() external view returns (uint);
}
