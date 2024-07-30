// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Interfaces
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IModule_v1} from "src/modules/base/IModule_v1.sol";
import {IInverterBeacon_v1} from "src/proxies/interfaces/IInverterBeacon_v1.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {
    IOrchestratorFactory_v1,
    IOrchestrator_v1,
    IModule_v1
} from "src/factories/interfaces/IOrchestratorFactory_v1.sol";
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IModule_v1} from "src/modules/base/IModule_v1.sol";
import {IFM_BC_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
import {IPIM_WorkflowFactory} from
    "src/factories/interfaces/IPIM_WorkflowFactory.sol";
import {ERC20Issuance_v1} from "src/external/token/ERC20Issuance_v1.sol";

interface IPIM_WorkflowFactory {
    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when a new PIM workflow is created.
    // TODO
    event PIMWorkflowCreated(
        address indexed bondingCurve,
        address indexed issuanceToken,
        address indexed deployer,
        address recipient,
        bool isRenouncedIssuanceToken,
        bool isRenouncedWorkflow
    );

    /// @notice Event emitted factory owner sets new fee..
    /// @param fee The fee in basis points.
    event FeeSet(uint fee);

    //--------------------------------------------------------------------------
    // Structs

    /// @notice Struct for the issuance token parameters.
    /// @param name The name of the issuance token.
    /// @param symbol The symbol of the issuance token.
    /// @param decimals The decimals of the issuance token.
    /// @param maxSupply The maximum supply of the issuance token.
    /// @param initialAdmin The owner and initial minter of the issuance token.
    struct IssuanceTokenParams {
        string name;
        string symbol;
        uint8 decimals;
        uint maxSupply;
        address initialAdmin;
    }

    /// @notice Struct for the issuance token parameters.
    /// @param metadata The module's metadata.
    /// @param bcProperties The bonding curve's properties.
    /// @param issuanceTokenParams The issuance token's parameters.
    /// @param recipient The recipient of the initial issuance token supply.
    /// @param collateralToken The collateral token.
    /// @param isRenouncedIssuanceToken If ownership over the issuance token should be renounced.
    /// @param isRenouncedWorkflow If admin rights over the workflow should be renounced.
    struct PIMConfig {
        IModule_v1.Metadata metadata;
        IFM_BC_Bancor_Redeeming_VirtualSupply_v1.BondingCurveProperties
            bcProperties;
        IssuanceTokenParams issuanceTokenParams;
        address recipient;
        address collateralToken;
        bool isRenouncedIssuanceToken;
        bool isRenouncedWorkflow;
    }

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Deploys a workflow with a bonding curve and an issuance token
    /// @param workflowConfig The workflow's config data.
    /// @param authorizerConfig The config data for the orchestrator's {IAuthorizer_v1} instance.
    /// @param paymentProcessorConfig The config data for the orchestrator's {IPaymentProcessor_v1} instance.
    /// @param moduleConfigs Variable length set of optional module's config data.
    /// @param PIMConfig The configuration for the issuance token and the bonding curve.
    /// @return Returns the address of orchestrator and the address of the issuance token.
    function createPIMWorkflow(
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig,
        IOrchestratorFactory_v1.ModuleConfig memory authorizerConfig,
        IOrchestratorFactory_v1.ModuleConfig memory paymentProcessorConfig,
        IOrchestratorFactory_v1.ModuleConfig[] memory moduleConfigs,
        IPIM_WorkflowFactory.PIMConfig memory PIMConfig
    ) external returns (IOrchestrator_v1, ERC20Issuance_v1);

    /// @notice Ownable. Sets a fee in basis points that is added to the initial collateral supply and sent to the factory.
    /// @param newFee Fee in basis points.
    function setFee(uint newFee) external;

    /// @notice Ownable. Withdraws the complete balance of the specified token to the specified address.
    /// @param token The token to withdraw.
    /// @param to The recipient of the withdrawn tokens.
    function withdrawFee(IERC20 token, address to) external;
}
