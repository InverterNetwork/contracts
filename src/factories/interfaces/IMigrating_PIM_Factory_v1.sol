// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Interfaces
import {IOrchestrator_v1} from "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IOrchestratorFactory_v1} from "src/factories/interfaces/IOrchestratorFactory_v1.sol";
import {IBondingCurveBase_v1} from "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";

// Internal Dependencies
import {ERC20Issuance_v1} from "src/external/token/ERC20Issuance_v1.sol";

interface IMigrating_PIM_Factory_v1 {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Error thrown when an unpermissioned address tries to claim fees or to transfer role.
    error PIM_WorkflowFactory__OnlyPimFeeRecipient();

    /// @notice Error thrown when an unpermissioned address tries to set rewards.
    error PIM_WorkflowFactory__OnlyInitiator();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when a new PIM workflow is created.
    /// @param orchestrator The address of the funding manager.
    /// @param issuanceToken The address of the issuance token.
    /// @param deployer The address of the deployer.
    /// @param initiator The address of the initiator.
    /// @param migrationThreshold The migration threshold.
    event PIMWorkflowCreated(
        address indexed orchestrator,
        address indexed issuanceToken,
        address indexed deployer,
        address initiator,
        uint migrationThreshold
    );

    /// @notice Event emitted when factory owner sets new fee.
    /// @param fundingManager The address of the funding manager.
    /// @param oldRecipient The previous pim fee recipient.
    /// @param  newRecipient The new pim fee recipient.
    event PimFeeRecipientUpdated(
        address indexed fundingManager,
        address indexed oldRecipient,
        address indexed newRecipient
    );

    /// @notice Event emitted when PIM fee (buy/sell fees) is claimed.
    /// @param fundingManager The address of the funding manager.
    /// @param  claimer The address of the one that is claiming.
    /// @param  to The address of that is receiving the fee.
    /// @param  amount The amount claimed.
    event PimFeeClaimed(
        address indexed fundingManager,
        address indexed claimer,
        address indexed to,
        uint amount
    );

    /// @notice Event emitted when collateral liquidity is migrated to the dex.
    /// @param fundingManager The address of the funding manager.
    /// @param issuanceToken The address of the issuance token.
    /// @param collateralToken The address of the collateral token.
    /// @param pool The address of the pool.
    /// @param issuanceTokenAmount The amount of issuance tokens added as liquidity.
    /// @param collateralTokenAmount The amount of collateral tokens added as liquidity.
    event Graduation(
        address indexed fundingManager,
        address indexed issuanceToken,
        address collateralToken,
        address indexed pool,
        uint issuanceTokenAmount,
        uint collateralTokenAmount
    );

    //--------------------------------------------------------------------------
    // Structs

    struct PIM {
        bool isGraduated;
        bool isImmutable;
        uint migrationThreshold;
        address initiator;
        address dexAdapter;
        address lpTokenRecipient;
        IOrchestrator_v1 orchestrator;
        uint initialVirtualIssuanceSupply;
        uint initialVirtualCollateralSupply;
    }

    struct MigrationConfig {
        bool isImmutable;
        uint migrationThreshold;
        address dexAdapter;
        address lpTokenRecipient;
    }

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Deploys a new issuance token and uses that to deploy a workflow with restricted bonding curve.
    /// @param workflowConfig The workflow's config data.
    /// @param fundingManagerConfig The config data for the orchestrator's {IFundingManager_v1} instance.
    /// @param authorizerConfig The config data for the orchestrator's {IAuthorizer_v1} instance.
    /// @param paymentProcessorConfig The config data for the orchestrator's {IPaymentProcessor_v1} instance.
    /// @param moduleConfigs Variable length set of optional module's config data.
    /// @param issuanceTokenParams The issuance token's parameters (name, symbol, decimals, maxSupply).
    /// @param initialPurchaseAmount The initial purchase amount.
    /// @param migrationConfig_ The config data for the migration.
    /// @return CreatedOrchestrator Returns the created orchestrator instance.
    function createPIMWorkflow(
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig,
        IOrchestratorFactory_v1.ModuleConfig memory fundingManagerConfig,
        IOrchestratorFactory_v1.ModuleConfig memory authorizerConfig,
        IOrchestratorFactory_v1.ModuleConfig memory paymentProcessorConfig,
        IOrchestratorFactory_v1.ModuleConfig[] memory moduleConfigs,
        IBondingCurveBase_v1.IssuanceToken memory issuanceTokenParams,
        uint initialPurchaseAmount,
        MigrationConfig memory migrationConfig_
    ) external returns (IOrchestrator_v1);
}
