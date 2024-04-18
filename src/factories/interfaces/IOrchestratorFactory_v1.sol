// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Interfaces
import {IModule_v1, IOrchestrator_v1} from "src/modules/base/IModule_v1.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

interface IOrchestratorFactory_v1 {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Given id is invalid.
    error OrchestratorFactory_v1__InvalidId();

    /// @notice The module's data arrays length mismatch.
    error OrchestratorFactory_v1__ModuleDataLengthMismatch();

    /// @notice The orchestrator owner is address(0)
    error OrchestratorFactory_v1__OrchestratorOwnerIsInvalid();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when a new orchestrator_v1 is created.
    /// @param orchestratorId The id of the orchestrator.
    /// @param orchestratorAddress The address of the orchestrator.
    event OrchestratorCreated(
        uint indexed orchestratorId, address indexed orchestratorAddress
    );

    //--------------------------------------------------------------------------
    // Structs

    struct OrchestratorConfig {
        address owner;
        IERC20 token;
    }

    struct ModuleConfig {
        IModule_v1.Metadata metadata;
        bytes configData;
        bytes dependencyData;
    }

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Creates a new orchestrator_v1 with caller being the orchestrator's owner.
    /// @param orchestratorConfig The orchestrator's config data.
    /// @param authorizerConfig The config data for the orchestrator's {IAuthorizer}
    ///                         instance.
    /// @param paymentProcessorConfig The config data for the orchestrator's
    ///                               {IPaymentProcessor} instance.
    /// @param moduleConfigs Variable length set of optional module's config
    ///                      data.
    function createOrchestrator(
        OrchestratorConfig memory orchestratorConfig,
        ModuleConfig memory fundingManagerConfig,
        ModuleConfig memory authorizerConfig,
        ModuleConfig memory paymentProcessorConfig,
        ModuleConfig[] memory moduleConfigs
    ) external returns (IOrchestrator_v1);

    /// @notice Returns the {IOrchestrator_v1} target implementation address.
    function target() external view returns (address);

    /// @notice Returns the {IModuleFactory_v1} implementation address.
    function moduleFactory() external view returns (address);

    /// @notice Returns the {IOrchestrator_v1} address that corresponds to the given id.
    /// @param id The requested orchestrator's id.
    function getOrchestratorByID(uint id) external view returns (address);

    /// @notice Returns the counter of the current orchestrator id
    function getOrchestratorIDCounter() external view returns (uint);
}
