// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Internal Interfaces
import {IModule, IOrchestrator} from "src/modules/base/IModule.sol";

interface IOrchestratorFactory {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Given id is invalid.
    error OrchestratorFactory__InvalidId();

    /// @notice The module's data arrays length mismatch.
    error OrchestratorFactory__ModuleDataLengthMismatch();

    /// @notice The orchestrator owner is address(0)
    error OrchestratorFactory__OrchestratorOwnerIsInvalid();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when a new orchestrator is created.
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
        IModule.Metadata metadata;
        bytes configData;
        bytes dependencyData;
    }

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Creates a new orchestrator with caller being the orchestrator's owner.
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
    ) external returns (IOrchestrator);

    /// @notice Returns the {IOrchestrator} target implementation address.
    function target() external view returns (address);

    /// @notice Returns the {IModuleFactory} implementation address.
    function moduleFactory() external view returns (address);

    /// @notice Returns the {IOrchestrator} address that corresponds to the given id.
    /// @param id The requested orchestrator's id.
    function getOrchestratorByID(uint id) external view returns (address);

    /// @notice Returns the counter of the current orchestrator id
    function getOrchestratorIDCounter() external view returns (uint);
}
