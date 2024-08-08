// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Interfaces
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IModule_v1} from "src/modules/base/IModule_v1.sol";
import {IInverterBeacon_v1} from "src/proxies/interfaces/IInverterBeacon_v1.sol";
import {IOrchestratorFactory_v1} from
    "src/factories/interfaces/IOrchestratorFactory_v1.sol";
import {IFM_BC_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
import {IRestricted_PIM_Factory_v1} from
    "src/factories/interfaces/IRestricted_PIM_Factory_v1.sol";
import {IERC20Issuance_v1} from "src/external/token/IERC20Issuance_v1.sol";
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";

// Internal Dependencies
import {ERC20Issuance_v1} from "src/external/token/ERC20Issuance_v1.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

interface IRestricted_PIM_Factory_v1 {
    //--------------------------------------------------------------------------
    // Errors
    /// @notice Error thrown when an unpermissioned address tries to claim fees or to transfer role.
    error PIM_WorkflowFactory__OnlyPimFeeRecipient();
    /// @notice Error thrown when the curve is deployed with an invalid configuration.
    error PIM_WorkflowFactory__InvalidConfiguration();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when a new PIM workflow is created.
    /// @param orchestrator The address of the orchestrator.
    /// @param issuanceToken The address of the issuance token.
    /// @param deployer The address of the deployer.
    event PIMWorkflowCreated(
        address indexed orchestrator,
        address indexed issuanceToken,
        address indexed deployer
    );

    /// @notice Event emitted when factory owner sets new fee.
    /// @param oldRecipient The previous pim fee recipient.
    /// @param newRecipient The new pim fee recipient.
    event PimFeeRecipientUpdated(
        address indexed oldRecipient, address indexed newRecipient
    );

    /// @notice Event emitted when PIM fee (buy/sell fees) is claimed.
    /// @param fundingManager The address of the bonding curve from which to withdraw fees.
    /// @param claimant The address of the claimer.
    /// @param recipient The address to which the fees are sent.
    /// @param amount The amount claimed.
    event PimFeeClaimed(
        address indexed fundingManager,
        address indexed claimant,
        address indexed recipient,
        uint amount
    );

    //--------------------------------------------------------------------------
    // Structs

    /// @notice Struct for the issuance token parameters.
    /// @param name The name of the issuance token.
    /// @param symbol The symbol of the issuance token.
    /// @param decimals The decimals of the issuance token.
    /// @param maxSupply The maximum supply of the issuance token.
    struct IssuanceTokenParams {
        string name;
        string symbol;
        uint8 decimals;
        uint maxSupply;
    }

    /// @notice Struct for the issuance token parameters.
    /// @param fundingManagerMetadata The funding manager's metadata.
    /// @param authorizerMetadata The authorizer's metadata.
    /// @param bcProperties The bonding curve's properties.
    /// @param issuanceTokenParams The issuance token's parameters.
    /// @param recipient The recipient of the initial issuance token supply.
    /// @param admin Is set as token owner and workflow admin unless renounced.
    /// @param collateralToken The collateral token.
    /// @param firstCollateralIn Amount of collateral that is used for the first purchase from the bonding curve.
    /// @param isRenouncedIssuanceToken If ownership over the issuance token should be renounced.
    /// @param isRenouncedWorkflow If admin rights over the workflow should be renounced.
    /// @param withInitialLiquidity If true initial liquidity will be added to the bonding curve.
    /// In this case the recipient will receive the initial issuance token supply.
    /// If false initial liquidity will not be added to the bonding curve and initial token
    struct PIMConfig {
        IModule_v1.Metadata fundingManagerMetadata;
        IModule_v1.Metadata authorizerMetadata;
        IFM_BC_Bancor_Redeeming_VirtualSupply_v1.BondingCurveProperties
            bcProperties;
        IssuanceTokenParams issuanceTokenParams;
        address admin;
        address recipient;
        address collateralToken;
        uint firstCollateralIn;
        bool isRenouncedIssuanceToken;
        bool isRenouncedWorkflow;
        bool withInitialLiquidity;
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
    /// @param issuanceTokenParams The issuance token's parameters (name, symbol, decimals, maxSupply).
    /// @return CreatedOrchestrator Returns the created orchestrator instance
    function createPIMWorkflow(
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig,
        IOrchestratorFactory_v1.ModuleConfig memory fundingManagerConfig,
        IOrchestratorFactory_v1.ModuleConfig memory authorizerConfig,
        IOrchestratorFactory_v1.ModuleConfig memory paymentProcessorConfig,
        IOrchestratorFactory_v1.ModuleConfig[] memory moduleConfigs,
        IBondingCurveBase_v1.IssuanceToken memory issuanceTokenParams
    ) external returns (IOrchestrator_v1, ERC20Issuance_v1);
}
