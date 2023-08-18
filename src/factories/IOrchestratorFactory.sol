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
    // Structs

    struct OrchestratorConfig {
        address owner;
        IERC20 token;
    }

    // *bytes dependencyData* is the data (in the form of bytes) that must be passed as part of ModuleConfig to provide information
    //                        about any dependencies that this particular module might have on other modules (cross-dependency of modules)
    // *Expected format of dependencyData*: abi.encode(bool hasDependency, string[] dependenciesURLs)
    // *bool hasDependency*: This boolean indicates whether this module is dependent on other modules for initialization or not
    //                       True if this module has other modules as dependencies, false otherwise
    // *string[] dependenciesURLs*: In the case, where *hasDependency* had been set to true, this array of strings will contain the URL of the 
    //                              required modules. These URL can be used with the `findModuleAddressInOrchestrator` function to find relevant addresses
    //                              In case of no dependencies, this can be left as an empty array of strings.
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
