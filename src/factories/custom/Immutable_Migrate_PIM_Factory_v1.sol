// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// OpenZeppelin Imports
import {ERC2771Context, Context} from "@oz/metatx/ERC2771Context.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Core Interfaces
import {IOrchestratorFactory_v1} from
    "src/factories/interfaces/IOrchestratorFactory_v1.sol";
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IImmutable_Migrate_PIM_Factory_v1} from
    "src/factories/interfaces/IImmutable_Migrate_PIM_Factory_v1.sol";
import {IModule_v1} from "src/modules/base/IModule_v1.sol";
import {IAuthorizer_v1} from "@aut/IAuthorizer_v1.sol";

// Bonding Curve Interfaces
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";
import {IRedeemingBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IRedeemingBondingCurveBase_v1.sol";
import {IFM_BC_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
import {IFM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1.sol";

// Migration Interfaces
import {ILM_PC_MigrateLiquidity_UniswapV2_v1} from
    "@lm/LM_PC_MigrateLiquidity_UniswapV2_v1.sol";

// Implementation Contracts
import {FM_BC_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/FM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
import {ERC20Issuance_v1} from "src/external/token/ERC20Issuance_v1.sol";

/**
 * @title   Inverter Immutable Migrate PIM Factory
 *
 * @notice  Used to deploy a PIM workflow with an unrestricted bonding curve and a mechanism to
 *          ensure immutability of the workflow while still enabling the claiming of fees. Also
 *          provides a function to execute the migration of liquidity from the Bonding Curve Uniswap V2.
 *
 * @dev     More user-friendly way to deploy a PIM workflow with an unrestricted bonding curve.
 *          Acts as wrapper for workflow to make it "unruggable" while exposing fee claiming functionality.
 *
 * @custom:security-contact security@inverter.network
 *                          This contract is experimental in nature and has not been audited.
 *                          Please use at your own risk!
 *
 * @author  Inverter Network
 */
contract Immutable_Migrate_PIM_Factory_v1 is
    ERC2771Context,
    IImmutable_Migrate_PIM_Factory_v1
{
    //--------------------------------------------------------------------------
    // State Variables

    /// @dev	Stores address of {Orchestratorfactory_v1}.
    address public orchestratorFactory;

    /// @dev	Mapping of who can claim fees for a given funding manager.
    mapping(address fundingManager => address feeRecipient) private
        _pimFeeRecipients;

    /// @dev    Stores the orchestrator address for this workflow
    address private _orchestrator;

    /// @dev    Stores the issuance token address for this workflow
    address private _issuanceToken;

    /// @dev    Stores the funding manager address for this workflow
    address private _fundingManager;

    /// @dev    Stores the logic module address for this workflow
    address private _logicModule;

    //--------------------------------------------------------------------------
    // Modifiers

    /// @dev	Modifier to guarantee the caller is the fee recipient for the given funding manager.
    modifier onlyPimFeeRecipient(address fundingManager) {
        if (_msgSender() != _pimFeeRecipients[fundingManager]) {
            revert PIM_WorkflowFactory__OnlyPimFeeRecipient();
        }
        _;
    }

    /// @dev    Get address of module with given title.
    function _getModuleAddressByTitle(
        address[] memory modules,
        string memory title
    ) private view returns (address) {
        for (uint i = 0; i < modules.length; i++) {
            if (
                keccak256(bytes(IModule_v1(modules[i]).title()))
                    == keccak256(bytes(title))
            ) {
                return modules[i];
            }
        }
        revert
            IImmutable_Migrate_PIM_Factory_v1
            .PIM_WorkflowFactory__ModuleNotFound();
    }

    //--------------------------------------------------------------------------
    // Constructor

    constructor(address _orchestratorFactory, address _trustedForwarder)
        ERC2771Context(_trustedForwarder)
    {
        orchestratorFactory = _orchestratorFactory;
    }

    //--------------------------------------------------------------------------
    // Public Mutating Functions

    /// @inheritdoc IImmutable_Migrate_PIM_Factory_v1
    function createPIMWorkflow(
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig,
        IOrchestratorFactory_v1.ModuleConfig memory fundingManagerConfig,
        IOrchestratorFactory_v1.ModuleConfig memory authorizerConfig,
        IOrchestratorFactory_v1.ModuleConfig memory paymentProcessorConfig,
        IOrchestratorFactory_v1.ModuleConfig[] memory moduleConfigs,
        IBondingCurveBase_v1.IssuanceToken memory issuanceTokenParams,
        uint initialPurchaseAmount
    ) external returns (IOrchestrator_v1 orchestrator) {
        // deploy issuance token
        ERC20Issuance_v1 issuanceToken = new ERC20Issuance_v1(
            issuanceTokenParams.name,
            issuanceTokenParams.symbol,
            issuanceTokenParams.decimals,
            issuanceTokenParams.maxSupply,
            address(this) // assigns owner role to itself initially to manage minting rights temporarily
        );

        // MODIFY AUTHORIZER CONFIG
        // decode configData of authorizer
        // set (own) factory as orchestrator admin
        // reinterpret the `initialAdmin` field as the `initiator` address
        bytes memory authorizerConfigData = authorizerConfig.configData;
        (address initiator) = abi.decode(authorizerConfigData, (address));
        if (initiator == address(0)) {
            revert
                IImmutable_Migrate_PIM_Factory_v1
                .PIM_WorkflowFactory__InvalidZeroAddress();
        }
        authorizerConfigData = abi.encode(address(this));
        authorizerConfig.configData = authorizerConfigData;

        // MODIFY FUNDING MANAGER CONFIG
        // decode configData of fundingManager
        // set newly deployed token as issuance token
        bytes memory fundingManagerConfigData = fundingManagerConfig.configData;
        (
            ,
            IFM_BC_Bancor_Redeeming_VirtualSupply_v1.BondingCurveProperties
                memory bcProperties,
            address collateralTokenAddress
        ) = abi.decode(
            fundingManagerConfigData,
            (
                address,
                IFM_BC_Bancor_Redeeming_VirtualSupply_v1.BondingCurveProperties,
                address
            )
        );
        fundingManagerConfigData = abi.encode(
            address(issuanceToken), bcProperties, collateralTokenAddress
        );
        fundingManagerConfig.configData = fundingManagerConfigData;

        // deploy workflow
        orchestrator = IOrchestratorFactory_v1(orchestratorFactory)
            .createOrchestrator(
            workflowConfig,
            fundingManagerConfig,
            authorizerConfig,
            paymentProcessorConfig,
            moduleConfigs
        );

        // set orchestrator
        _orchestrator = address(orchestrator);

        // get and set funding manager
        _fundingManager = address(orchestrator.fundingManager());
        FM_BC_Bancor_Redeeming_VirtualSupply_v1 fundingManager =
            FM_BC_Bancor_Redeeming_VirtualSupply_v1(_fundingManager);

        // get and set logic module
        ILM_PC_MigrateLiquidity_UniswapV2_v1 logicModule =
        ILM_PC_MigrateLiquidity_UniswapV2_v1(
            _getModuleAddressByTitle(
                orchestrator.listModules(),
                "LM_PC_MigrateLiquidity_UniswapV2_v1"
            )
        );
        _logicModule = address(logicModule);

        // get the authorizer
        IAuthorizer_v1 authorizer = IAuthorizer_v1(orchestrator.authorizer());

        // grant owner role to logic module
        authorizer.grantRole(bytes32(0), _logicModule);

        // get collateral token
        IERC20 collateralToken = IERC20(collateralTokenAddress);

        // enable bonding curve to mint issuance token and disable minting from factory
        issuanceToken.setMinter(_fundingManager, true);
        issuanceToken.setMinter(_logicModule, true);
        issuanceToken.setMinter(address(this), false);

        // if initial purchase amount is set (> 0) execute first purchase from curve
        // recipient: initiator
        if (initialPurchaseAmount > 0) {
            collateralToken.transferFrom(
                _msgSender(), address(this), initialPurchaseAmount
            );
            collateralToken.approve(_fundingManager, initialPurchaseAmount);
            fundingManager.buyFor(initiator, initialPurchaseAmount, 1);
        }

        // set fee recipient (initiator)
        _pimFeeRecipients[_fundingManager] = initiator;

        // renounce token ownership
        issuanceToken.renounceOwnership();

        emit IImmutable_Migrate_PIM_Factory_v1.PIMWorkflowCreated(
            address(orchestrator), address(issuanceToken), _msgSender()
        );
    }

    //--------------------------------------------------------------------------
    // Permissioned Functions

    /// @inheritdoc IImmutable_Migrate_PIM_Factory_v1
    function withdrawPimFee(address fundingManager, address to)
        external
        onlyPimFeeRecipient(fundingManager)
    {
        // get accumulated fee amount from bonding curve
        uint amount =
            IBondingCurveBase_v1(fundingManager).projectCollateralFeeCollected();
        // withdraw fee from bonding curve and send to `to`
        IBondingCurveBase_v1(fundingManager).withdrawProjectCollateralFee(
            to, amount
        );
        emit IImmutable_Migrate_PIM_Factory_v1.PimFeeClaimed(
            fundingManager, _msgSender(), to, amount
        );
    }

    /// @inheritdoc IImmutable_Migrate_PIM_Factory_v1
    function transferPimFeeEligibility(address fundingManager, address to)
        external
        onlyPimFeeRecipient(fundingManager)
    {
        _pimFeeRecipients[fundingManager] = to;
        emit IImmutable_Migrate_PIM_Factory_v1.PimFeeRecipientUpdated(
            fundingManager, _msgSender(), to
        );
    }

    //--------------------------------------------------------------------------
    // Permissionless Functions
    /// @inheritdoc IImmutable_Migrate_PIM_Factory_v1
    function executeMigration()
        external
        returns (
            ILM_PC_MigrateLiquidity_UniswapV2_v1.LiquidityMigrationResult memory
        )
    {
        // get logic module
        ILM_PC_MigrateLiquidity_UniswapV2_v1 logicModule =
            ILM_PC_MigrateLiquidity_UniswapV2_v1(_logicModule);

        // get funding manager
        FM_BC_Bancor_Redeeming_VirtualSupply_v1 fundingManager =
            FM_BC_Bancor_Redeeming_VirtualSupply_v1(_fundingManager);

        // execute migration
        ILM_PC_MigrateLiquidity_UniswapV2_v1.LiquidityMigrationResult memory
            result = logicModule.executeMigration();

        // close buy and sell of the bonding curve
        fundingManager.closeBuy();
        fundingManager.closeSell();

        return result;
    }
}
