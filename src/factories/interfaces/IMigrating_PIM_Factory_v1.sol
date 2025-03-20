// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Interfaces
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IOrchestratorFactory_v1} from
    "src/factories/interfaces/IOrchestratorFactory_v1.sol";
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";
import {LM_PC_Staking_v1} from "src/modules/logicModule/LM_PC_Staking_v1.sol";
import {LM_PC_PaymentRouter_v1} from
    "src/modules/logicModule/LM_PC_PaymentRouter_v1.sol";
import {IModule_v1} from "src/modules/base/IModule_v1.sol";

// Internal Dependencies
import {ERC20Issuance_v1} from "src/external/token/ERC20Issuance_v1.sol";

interface IMigrating_PIM_Factory_v1 {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Error emitted when the caller is not the initiator after graduation.
    error PIM_WorkflowFactory__OnlyInitiatorAfterGraduation();

    /// @notice Error emitted when the caller is not the admin.
    error PIM_WorkflowFactory__OnlyAdmin();

    /// @notice Error emitted when the address is zero.
    error PIM_WorkflowFactory__CantBeZeroAddress();

    /// @notice Error emitted when the initial purchase graduates the market.
    error PIM_WorkflowFactory__InitialPurchaseGraduatesMarket();

    /// @notice Error emitted when a secondary token is tried to be deployed when mainFundingManager is not set.
    error PIM_WorkflowFactory__MainFundingManagerNotSet();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when a new PIM workflow is created.
    /// @param orchestrator The address of the funding manager.
    /// @param issuanceToken The address of the issuance token.
    /// @param deployer The address of the deployer.
    /// @param collateralToken The address of the collateral token.
    /// @param initiator The address of the initiator.
    /// @param migrationConfig_ The migration config.
    event PIMWorkflowCreated(
        address indexed orchestrator,
        address indexed issuanceToken,
        address indexed deployer,
        address collateralToken,
        address initiator,
        MigrationConfig migrationConfig_
    );

    /// @notice Event emitted when collateral liquidity is migrated to the dex.
    /// @param orchestrator The address of the orchestrator.
    /// @param pool The address of the pool.
    /// @param issuanceTokenAmount The amount of issuance tokens added as liquidity.
    /// @param collateralTokenAmount The amount of collateral tokens added as liquidity.
    event Graduation(
        address indexed orchestrator,
        address indexed pool,
        uint issuanceTokenAmount,
        uint collateralTokenAmount
    );

    /// @notice Event emitted when admin is changed
    /// @param oldAdmin The old admin address
    /// @param newAdmin The new admin address
    event AdminChanged(address indexed oldAdmin, address indexed newAdmin);

    /// @notice Event emitted when main funding manager is changed
    /// @param oldMainFundingManager The old main funding manager address
    /// @param newMainFundingManager The new main funding manager address
    event MainFundingManagerChanged(
        address indexed oldMainFundingManager,
        address indexed newMainFundingManager
    );

    /// @notice Event emitted when collateral fee multiplier is changed
    /// @param oldMultiplier The old collateral fee multiplier
    /// @param newMultiplier The new collateral fee multiplier
    event CollateralFeeMultiplierChanged(
        uint oldMultiplier, uint newMultiplier
    );

    /// @notice Event emitted when issuance fee multiplier is changed
    /// @param oldMultiplier The old issuance fee multiplier
    /// @param newMultiplier The new issuance fee multiplier
    event IssuanceFeeMultiplierChanged(uint oldMultiplier, uint newMultiplier);

    /// @notice Event emitted when mutable initial mint amount is changed
    /// @param oldAmount The old mutable initial mint amount
    /// @param newAmount The new mutable initial mint amount
    event MutableInitialMintAmountChanged(uint oldAmount, uint newAmount);

    /// @notice Event emitted when staking module metadata is changed
    /// @param oldMetadata The old staking module metadata
    /// @param newMetadata The new staking module metadata
    event StakingModuleMetadataChanged(
        IModule_v1.Metadata oldMetadata, IModule_v1.Metadata newMetadata
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
        address stakingModule;
        address paymentRouter;
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

    /**
     * @notice Buys tokens from the bonding curve funding manager for a recipient
     * @param fundingManager The funding manager to buy from
     * @param recipient The address to receive the purchased tokens
     * @param amountIn The maximum amount of collateral tokens to spend
     * @param minAmountOut The minimum amount of issuance tokens to receive
     */
    function buyFor(
        address fundingManager,
        address recipient,
        uint amountIn,
        uint minAmountOut
    ) external;

    /**
     * @notice Sells tokens to the funding manager for a recipient
     * @param fundingManager The funding manager to sell to
     * @param recipient The address to receive the purchased tokens
     * @param amountIn The amount of issuance tokens to sell
     * @param minAmountOut The minimum amount of collateral tokens to receive
     */
    function sellTo(
        address fundingManager,
        address recipient,
        uint amountIn,
        uint minAmountOut
    ) external;

    /**
     * @notice Returns the LP token recipient
     * @param fundingManager The funding manager to check
     * @return lpTokenRecipient The LP token recipient
     */
    function getLpTokenRecipient(address fundingManager)
        external
        view
        returns (address lpTokenRecipient);

    /**
     * @notice Returns the migration threshold
     * @param fundingManager The funding manager to check
     * @return migrationThreshold The migration threshold
     */
    function getMigrationThreshold(address fundingManager)
        external
        view
        returns (uint migrationThreshold);

    /**
     * @notice Returns whether the issuance token is immutable
     * @param fundingManager The funding manager to check
     * @return isImmutable Whether the issuance token is immutable
     */
    function getIsImmutable(address fundingManager)
        external
        view
        returns (bool isImmutable);

    /**
     * @notice Returns whether the issuance token has been graduated
     * @param fundingManager The funding manager to check
     * @return isGraduated Whether the issuance token has been graduated
     */
    function getIsGraduated(address fundingManager)
        external
        view
        returns (bool isGraduated);
}
