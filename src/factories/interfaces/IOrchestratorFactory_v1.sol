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

    /// @notice The provided beacon address doesnt support the interface {IInverterBeacon_v1}
    error OrchestratorFactory__InvalidBeacon();

    /// @notice Given id is invalid.
    error OrchestratorFactory__InvalidId();

    /// @notice The module's data arrays length mismatch.
    error OrchestratorFactory__ModuleDataLengthMismatch();

    /// @notice The orchestrator admin is address(0)
    error OrchestratorFactory__OrchestratorAdminIsInvalid();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when a new orchestrator_v1 is created.
    /// @param orchestratorId The id of the orchestrator.
    /// @param orchestratorAddress The address of the orchestrator.
    event OrchestratorCreated(
        uint indexed orchestratorId, address indexed orchestratorAddress
    );

    /// @notice Event emitted when a new orchestrator factory is initialized.
    /// @param beacon The address of the beacon associated with the factory.
    /// @param moduleFactory The address of the module factory.
    event OrchestratorFactoryInitialized(
        address indexed beacon, address indexed moduleFactory
    );

    //--------------------------------------------------------------------------
    // Structs

    struct WorkflowConfig {
        /// @dev bool wether the workflow should use the independent proxy structure
        /// In case of true it will not use the standard beacon proxy structure
        bool independentUpdates;
        /// @dev The address that will be assigned the admin role of the independent update proxy
        /// Will be disregarded in case independentUpdates is false
        address independentUpdateAdmin;
    }

    struct ModuleConfig {
        IModule_v1.Metadata metadata;
        bytes configData;
    }

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Creates a new orchestrator_v1.
    /// @param workflowConfig The workflow's config data.
    /// @param fundingManagerConfig The config data for the orchestrator's {IFundingManager_v1}
    ///                         instance.
    /// @param authorizerConfig The config data for the orchestrator's {IAuthorizer_v1}
    ///                         instance.
    /// @param paymentProcessorConfig The config data for the orchestrator's
    ///                               {IPaymentProcessor_v1} instance.
    /// @param moduleConfigs Variable length set of optional module's config
    ///                      data.
    /// @return CreatedOrchestrator Returns the created orchestrator instance
    function createOrchestrator(
        WorkflowConfig memory workflowConfig,
        ModuleConfig memory fundingManagerConfig,
        ModuleConfig memory authorizerConfig,
        ModuleConfig memory paymentProcessorConfig,
        ModuleConfig[] memory moduleConfigs
    ) external returns (IOrchestrator_v1);

    /// @notice Returns the {IOrchestrator_v1} beacon address.
    /// @return OrchestratorImplementationBeacon The Beacon of the Orchestrator Implementation
    function beacon() external view returns (IInverterBeacon_v1);

    /// @notice Returns the {IModuleFactory_v1} implementation address.
    /// @return ModuleFactoryAddress The address of the linked Module Factory
    function moduleFactory() external view returns (address);

    /// @notice Returns the {IOrchestrator_v1} address that corresponds to the given id.
    /// @param id The requested orchestrator's id.
    /// @return orchestratorAddress The address of the corresponding orchestrator
    function getOrchestratorByID(uint id) external view returns (address);

    /// @notice Returns the counter of the current orchestrator id
    /// @return id The id of the next created orchestrator
    function getOrchestratorIDCounter() external view returns (uint);
}
