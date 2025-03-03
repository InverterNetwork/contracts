// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External imports
import {ERC2771Context, Context} from "@oz/metatx/ERC2771Context.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Core interfaces
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IOrchestratorFactory_v1} from
    "src/factories/interfaces/IOrchestratorFactory_v1.sol";
import {IModule_v1} from "src/modules/base/IModule_v1.sol";

// Funding manager interfaces
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";
import {IRedeemingBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IRedeemingBondingCurveBase_v1.sol";
import {IFM_BC_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
import {IFM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1.sol";

// Migration interfaces
import {IMigrating_PIM_Factory_v1} from
    "../interfaces/IMigrating_PIM_Factory_v1.sol";
import {IDexAdapter_v1} from
    "src/external/immutable-migration/interfaces/IDexAdapter_v1.sol";

// Module implementations
import {FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1.sol";
import {LM_PC_PaymentRouter_v1} from
    "src/modules/logicModule/LM_PC_PaymentRouter_v1.sol";
import {LM_PC_Staking_v1} from "src/modules/logicModule/LM_PC_Staking_v1.sol";
import {FeeManager_v1} from "@ex/fees/FeeManager_v1.sol";

// Token implementations
import {ERC20Issuance_v1} from "src/external/token/ERC20Issuance_v1.sol";

/**
 * @title Migrating_PIM_Factory_v1
 * @notice Factory contract for creating and managing PIM workflows
 */
contract Migrating_PIM_Factory_v1 is
    ERC2771Context,
    IMigrating_PIM_Factory_v1
{
    //--------------------------------------------------------------------------
    // State Variables
    //--------------------------------------------------------------------------

    address public orchestratorFactory;
    address public admin;
    address public mainFundingManager;

    uint public issuanceLiquidityDivisor = 14;
    uint public collateralFeeMultiplier = 0;
    uint public issuanceFeeMultiplier = 0;

    mapping(address fundingManager => PIM orchestrator) public pims;
    address[] public fundingManagers;

    //--------------------------------------------------------------------------
    // Modifiers
    //--------------------------------------------------------------------------

    modifier onlyInitiatorAfterGraduation(address fundingManager) {
        PIM memory pim = pims[fundingManager];
        if (msg.sender != pim.initiator || !pim.isGraduated) {
            revert
                IMigrating_PIM_Factory_v1
                .PIM_WorkflowFactory__OnlyInitiatorAfterGraduation();
        }
        _;
    }

    modifier onlyAdmin() {
        if (msg.sender != admin) {
            revert IMigrating_PIM_Factory_v1.PIM_WorkflowFactory__OnlyAdmin();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Constructor
    //--------------------------------------------------------------------------

    constructor(
        address _orchestratorFactory,
        address _trustedForwarder,
        address _admin
    ) ERC2771Context(_trustedForwarder) {
        orchestratorFactory = _orchestratorFactory;
        admin = _admin;
    }

    //--------------------------------------------------------------------------
    // External Functions - PIM Creation
    //--------------------------------------------------------------------------

    /// @inheritdoc IMigrating_PIM_Factory_v1
    function createPIMWorkflow(
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig,
        IOrchestratorFactory_v1.ModuleConfig memory fundingManagerConfig,
        IOrchestratorFactory_v1.ModuleConfig memory authorizerConfig,
        IOrchestratorFactory_v1.ModuleConfig memory paymentProcessorConfig,
        IOrchestratorFactory_v1.ModuleConfig[] memory moduleConfigs,
        IBondingCurveBase_v1.IssuanceToken memory issuanceTokenParams,
        uint initialPurchaseAmount,
        MigrationConfig memory migrationConfig_
    ) external returns (IOrchestrator_v1) {
        // Deploy issuance token
        ERC20Issuance_v1 issuanceToken =
            _deployIssuanceToken(issuanceTokenParams);

        // Deploy orchestrator
        (
            IOrchestrator_v1 orchestrator,
            address initiator,
            address collateralToken
        ) = _deployOrchestrator(
            workflowConfig,
            fundingManagerConfig,
            authorizerConfig,
            paymentProcessorConfig,
            moduleConfigs,
            address(issuanceToken),
            migrationConfig_.isImmutable
        );

        address fundingManager = address(orchestrator.fundingManager());
        address lpTokenRecipient = migrationConfig_.isImmutable
            ? address(this)
            : migrationConfig_.lpTokenRecipient;

        // Store PIM data
        _storePIM(
            fundingManager,
            orchestrator,
            initiator,
            migrationConfig_,
            lpTokenRecipient
        );

        // Configure permissions
        issuanceToken.setMinter(fundingManager, true);
        _handleWorkflowPrivileges(fundingManager);

        // Handle initial purchase if specified
        _handleInitialPurchase(
            fundingManager,
            collateralToken,
            initialPurchaseAmount,
            initiator,
            migrationConfig_.migrationThreshold
        );

        emit IMigrating_PIM_Factory_v1.PIMWorkflowCreated(
            address(orchestrator),
            address(issuanceToken),
            _msgSender(),
            collateralToken,
            initiator,
            migrationConfig_
        );

        return orchestrator;
    }

    //--------------------------------------------------------------------------
    // External Functions - Admin Configuration
    //--------------------------------------------------------------------------

    function setAdmin(address _admin) external onlyAdmin {
        if (_admin == address(0)) {
            revert
                IMigrating_PIM_Factory_v1
                .PIM_WorkflowFactory__CantBeZeroAddress();
        }
        admin = _admin;
    }

    function setMainFundingManager(address _mainFundingManager)
        external
        onlyAdmin
    {
        if (_mainFundingManager == address(0)) {
            revert
                IMigrating_PIM_Factory_v1
                .PIM_WorkflowFactory__CantBeZeroAddress();
        }
        mainFundingManager = _mainFundingManager;
    }

    function setCollateralFeeMultiplier(uint _collateralFeeMultiplier)
        external
        onlyAdmin
    {
        collateralFeeMultiplier = _collateralFeeMultiplier;
    }

    function setIssuanceFeeMultiplier(uint _issuanceFeeMultiplier)
        external
        onlyAdmin
    {
        issuanceFeeMultiplier = _issuanceFeeMultiplier;
    }

    function setIssuanceLiquidityDivisor(uint _issuanceLiquidityDivisor)
        external
        onlyAdmin
    {
        issuanceLiquidityDivisor = _issuanceLiquidityDivisor;
    }

    //--------------------------------------------------------------------------
    // External Functions - PIM Getters
    //--------------------------------------------------------------------------

    /// @inheritdoc IMigrating_PIM_Factory_v1
    function getIsGraduated(address fundingManager)
        external
        view
        returns (bool)
    {
        return pims[fundingManager].isGraduated;
    }

    /// @inheritdoc IMigrating_PIM_Factory_v1
    function getIsImmutable(address fundingManager)
        external
        view
        returns (bool)
    {
        return pims[fundingManager].isImmutable;
    }

    /// @inheritdoc IMigrating_PIM_Factory_v1
    function getMigrationThreshold(address fundingManager)
        external
        view
        returns (uint)
    {
        return pims[fundingManager].migrationThreshold;
    }

    /// @inheritdoc IMigrating_PIM_Factory_v1
    function getLpTokenRecipient(address fundingManager)
        external
        view
        returns (address)
    {
        return pims[fundingManager].lpTokenRecipient;
    }

    //--------------------------------------------------------------------------
    // External Functions - Bonding Curve Operations
    //--------------------------------------------------------------------------

    /// @inheritdoc IMigrating_PIM_Factory_v1
    function buyFor(
        address fundingManager,
        address recipient,
        uint amountIn,
        uint minAmountOut
    ) external {
        PIM memory pim = pims[fundingManager];
        FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1 fm =
            FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(fundingManager);

        IERC20 collateralToken = fm.token();

        // Check if buy would exceed threshold before transferring tokens
        (uint validAmountIn) =
            _checkBuyExceedsThreshold(fundingManager, amountIn);

        if (validAmountIn > 0) {
            collateralToken.transferFrom(
                msg.sender, address(this), validAmountIn
            );
            collateralToken.approve(fundingManager, validAmountIn);

            // Calculate adjusted minAmountOut based on the ratio of valid to total amount
            uint adjustedMinAmountOut =
                (minAmountOut * validAmountIn) / amountIn;

            // Buy from curve
            fm.buyFor(recipient, validAmountIn, adjustedMinAmountOut);

            // Graduate if threshold reached
            if (
                collateralToken.balanceOf(fundingManager)
                    >= pim.migrationThreshold
            ) {
                _graduate(fundingManager);
            }
        }
    }

    /// @inheritdoc IMigrating_PIM_Factory_v1
    function sellTo(
        address fundingManager,
        address recipient,
        uint amountIn,
        uint minAmountOut
    ) external {
        FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1 fm =
            FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(fundingManager);

        ERC20Issuance_v1 issuanceToken = ERC20Issuance_v1(fm.getIssuanceToken());

        // Transfer and approve tokens
        issuanceToken.transferFrom(msg.sender, address(this), amountIn);
        issuanceToken.approve(fundingManager, amountIn);

        // Sell tokens
        fm.sellTo(recipient, amountIn, minAmountOut);
    }

    //--------------------------------------------------------------------------
    // External Functions - Fee Management
    //--------------------------------------------------------------------------

    function withdrawAllProjectCollateralFeesToStaking() external {
        for (uint i = 0; i < fundingManagers.length; i++) {
            address fundingManager = fundingManagers[i];
            PIM memory pim = pims[fundingManager];

            if (!pim.isGraduated) {
                _withdrawCollateralFeeToStaking(pim);
            }
        }
    }

    //--------------------------------------------------------------------------
    // Internal Functions - Threshold Checking
    //--------------------------------------------------------------------------

    /**
     * @notice Checks if buying would exceed the migration threshold
     * @param fundingManager The funding manager to check
     * @param amountIn The amount of collateral tokens to check
     * @return validAmountIn The amount that would not exceed the threshold
     */
    function _checkBuyExceedsThreshold(address fundingManager, uint amountIn)
        internal
        view
        returns (uint validAmountIn)
    {
        PIM memory pim = pims[fundingManager];
        FeeManager_v1 feeManager =
            FeeManager_v1(pim.orchestrator.governor().getFeeManager());
        FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1 fm =
            FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(fundingManager);
        IERC20 collateralToken = fm.token();

        // Get current collateral balance
        uint currentCollateral = collateralToken.balanceOf(fundingManager);

        // Calculate fee-adjusted amount
        uint feeRate = feeManager.getDefaultCollateralFee();
        uint appliedFee = (amountIn * feeRate) / 10_000;
        uint netAmountIn = amountIn - appliedFee;
        uint collateralAfterBuy = currentCollateral + netAmountIn;

        // Check if total would exceed threshold
        if (collateralAfterBuy > pim.migrationThreshold) {
            // Calculate valid amount before hitting threshold
            uint remainingToThreshold = pim.migrationThreshold
                > currentCollateral ? pim.migrationThreshold - currentCollateral : 0;
            validAmountIn = (remainingToThreshold * 10_000) / (10_000 - feeRate);
        } else {
            validAmountIn = amountIn;
        }
    }

    //--------------------------------------------------------------------------
    // Internal Functions - Graduation
    //--------------------------------------------------------------------------

    /**
     * @notice Graduates the PIM when threshold is reached
     * @param fundingManager The funding manager to graduate
     */
    function _graduate(address fundingManager) internal {
        PIM memory pim = pims[fundingManager];
        LM_PC_PaymentRouter_v1 paymentRouter =
            _getPaymentRouter(pim.orchestrator);
        FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1 fm =
            FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(fundingManager);

        IERC20 collateralToken = fm.token();
        ERC20Issuance_v1 issuanceToken = ERC20Issuance_v1(fm.getIssuanceToken());

        // Calculate collateral liquidity and fees
        uint collateralLiquidity = collateralToken.balanceOf(fundingManager)
            - fm.projectCollateralFeeCollected();
        uint collateralFee =
            (collateralLiquidity * collateralFeeMultiplier) / 10_000;

        // Transfer collateral to factory
        paymentRouter.pushPayment(
            address(this),
            address(collateralToken),
            collateralLiquidity,
            0,
            0,
            0
        );

        // Distribute collateral
        collateralLiquidity -= collateralFee;
        collateralToken.transfer(pim.dexAdapter, collateralLiquidity);
        collateralToken.transfer(admin, collateralFee);

        // Calculate issuance liquidity and fees
        uint issuanceLiquidity = (
            fm.getVirtualIssuanceSupply() - pim.initialVirtualIssuanceSupply
        ) / issuanceLiquidityDivisor;
        uint issuanceFee = (issuanceLiquidity * issuanceFeeMultiplier) / 10_000;
        issuanceLiquidity -= issuanceFee;

        // Close bonding curve
        fm.closeBuy();
        fm.closeSell();

        // Mint liquidity tokens
        issuanceToken.mint(pim.dexAdapter, issuanceLiquidity);
        issuanceToken.mint(admin, issuanceFee);

        // Create liquidity on DEX
        address pool = IDexAdapter_v1(pim.dexAdapter).createLiquidity(
            address(collateralToken),
            address(issuanceToken),
            pim.lpTokenRecipient
        );

        // Handle token ownership
        if (pim.isImmutable) {
            issuanceToken.renounceOwnership();
        } else {
            issuanceToken.transferOwnership(pim.initiator);
        }

        // Update graduation status
        pim.isGraduated = true;
        pims[fundingManager] = pim;

        // Handle fees
        _withdrawCollateralFeeToStaking(pim);

        emit Graduation(
            address(pim.orchestrator),
            pool,
            issuanceLiquidity,
            collateralLiquidity
        );
    }

    //--------------------------------------------------------------------------
    // Internal Functions - Deployment Helpers
    //--------------------------------------------------------------------------

    function _deployIssuanceToken(
        IBondingCurveBase_v1.IssuanceToken memory issuanceTokenParams
    ) internal returns (ERC20Issuance_v1) {
        return new ERC20Issuance_v1(
            issuanceTokenParams.name,
            issuanceTokenParams.symbol,
            issuanceTokenParams.decimals,
            issuanceTokenParams.maxSupply,
            address(this)
        );
    }

    function _deployOrchestrator(
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig,
        IOrchestratorFactory_v1.ModuleConfig memory fundingManagerConfig,
        IOrchestratorFactory_v1.ModuleConfig memory authorizerConfig,
        IOrchestratorFactory_v1.ModuleConfig memory paymentProcessorConfig,
        IOrchestratorFactory_v1.ModuleConfig[] memory moduleConfigs,
        address issuanceToken,
        bool isImmutable
    )
        internal
        returns (
            IOrchestrator_v1 orchestrator,
            address initiator,
            address collateralToken
        )
    {
        // Modify authorizer config - set factory as orchestrator admin
        bytes memory authorizerConfigData = authorizerConfig.configData;
        (initiator) = abi.decode(authorizerConfigData, (address));
        authorizerConfig.configData = abi.encode(address(this));

        // Modify funding manager config - set issuance token
        IFM_BC_Bancor_Redeeming_VirtualSupply_v1.BondingCurveProperties memory
            bcProperties;
        bytes memory fundingManagerConfigData = fundingManagerConfig.configData;
        (, bcProperties, collateralToken) = abi.decode(
            fundingManagerConfigData,
            (
                address,
                IFM_BC_Bancor_Redeeming_VirtualSupply_v1.BondingCurveProperties,
                address
            )
        );

        fundingManagerConfig.configData =
            abi.encode(address(issuanceToken), bcProperties, collateralToken);

        // Prepare module configs
        IOrchestratorFactory_v1.ModuleConfig[] memory moduleConfigsMemory = new IOrchestratorFactory_v1
            .ModuleConfig[](
            isImmutable ? moduleConfigs.length : moduleConfigs.length + 1
        );

        // Copy existing module configurations
        for (uint i = 0; i < moduleConfigs.length; i++) {
            moduleConfigsMemory[i] = moduleConfigs[i];
        }

        // Add staking module for non-immutable PIMs
        if (!isImmutable) {
            moduleConfigsMemory[moduleConfigs.length] = IOrchestratorFactory_v1
                .ModuleConfig(
                IModule_v1.Metadata(
                    1,
                    0,
                    0,
                    "https://github.com/InverterNetwork/contracts",
                    "LM_PC_Staking_v1"
                ),
                abi.encode(issuanceToken)
            );
        }

        // Create orchestrator
        orchestrator = IOrchestratorFactory_v1(orchestratorFactory)
            .createOrchestrator(
            workflowConfig,
            fundingManagerConfig,
            authorizerConfig,
            paymentProcessorConfig,
            moduleConfigsMemory
        );

        // Set main funding manager if needed
        if (mainFundingManager == address(0) && !isImmutable) {
            mainFundingManager = address(orchestrator.fundingManager());
        }

        return (orchestrator, initiator, collateralToken);
    }

    //--------------------------------------------------------------------------
    // Internal Functions - Setup and Configuration
    //--------------------------------------------------------------------------

    function _handleWorkflowPrivileges(address fundingManager) internal {
        PIM memory pim = pims[fundingManager];
        LM_PC_PaymentRouter_v1 paymentRouter =
            _getPaymentRouter(pim.orchestrator);
        FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1 fm =
            FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(fundingManager);
        ERC20Issuance_v1 issuanceToken = ERC20Issuance_v1(fm.getIssuanceToken());

        // Grant admin role to initiator for mutable PIMs
        if (!pim.isImmutable) {
            pim.orchestrator.authorizer().grantRole(
                pim.orchestrator.authorizer().getAdminRole(), pim.initiator
            );
        }

        // Set factory as minter for graduation liquidity
        issuanceToken.setMinter(address(this), true);

        // Grant curve interaction role to factory
        fm.grantModuleRole(fm.CURVE_INTERACTION_ROLE(), address(this));

        // Grant payment pusher role to factory
        paymentRouter.grantModuleRole(
            paymentRouter.PAYMENT_PUSHER_ROLE(), address(this)
        );
    }

    function _handleInitialPurchase(
        address fundingManager,
        address collateralToken,
        uint initialPurchaseAmount,
        address recipient,
        uint migrationThreshold
    ) internal {
        if (initialPurchaseAmount > migrationThreshold) {
            revert
                IMigrating_PIM_Factory_v1
                .PIM_WorkflowFactory__InitialPurchaseGraduatesMarket();
        }

        if (initialPurchaseAmount > 0) {
            IERC20(collateralToken).transferFrom(
                _msgSender(), address(this), initialPurchaseAmount
            );
            IERC20(collateralToken).approve(
                fundingManager, initialPurchaseAmount
            );
            IBondingCurveBase_v1(fundingManager).buyFor(
                recipient, initialPurchaseAmount, 1
            );
        }
    }

    function _storePIM(
        address fundingManager,
        IOrchestrator_v1 orchestrator,
        address initiator,
        MigrationConfig memory migrationConfig_,
        address lpTokenRecipient
    ) internal {
        FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1 fm =
            FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(fundingManager);

        pims[fundingManager] = IMigrating_PIM_Factory_v1.PIM({
            isGraduated: false,
            isImmutable: migrationConfig_.isImmutable,
            migrationThreshold: migrationConfig_.migrationThreshold,
            lpTokenRecipient: lpTokenRecipient,
            dexAdapter: migrationConfig_.dexAdapter,
            orchestrator: orchestrator,
            initiator: initiator,
            initialVirtualIssuanceSupply: fm.getVirtualIssuanceSupply(),
            initialVirtualCollateralSupply: fm.getVirtualCollateralSupply()
        });

        fundingManagers.push(fundingManager);
    }

    //--------------------------------------------------------------------------
    // Internal Functions - Module Helpers
    //--------------------------------------------------------------------------

    function _getStaking(IOrchestrator_v1 orchestrator)
        internal
        view
        returns (LM_PC_Staking_v1 staking)
    {
        address[] memory modules = orchestrator.listModules();

        for (uint i = 0; i < modules.length; i++) {
            try LM_PC_Staking_v1(modules[i]).rewardRate() {
                staking = LM_PC_Staking_v1(modules[i]);
                break;
            } catch {}
        }
    }

    function _getPaymentRouter(IOrchestrator_v1 orchestrator)
        internal
        view
        returns (LM_PC_PaymentRouter_v1 paymentRouter)
    {
        address[] memory modules = orchestrator.listModules();

        for (uint i = 0; i < modules.length; i++) {
            try LM_PC_PaymentRouter_v1(modules[i]).PAYMENT_PUSHER_ROLE() {
                paymentRouter = LM_PC_PaymentRouter_v1(modules[i]);
                break;
            } catch {}
        }
    }

    function _withdrawCollateralFeeToStaking(PIM memory pim) internal {
        if (mainFundingManager != address(0)) {
            FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1 fm =
            FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(
                address(pim.orchestrator.fundingManager())
            );

            uint stakingRewards = fm.projectCollateralFeeCollected();
            address mainTokenStaking =
                address(_getStaking(pims[mainFundingManager].orchestrator));

            // Withdraw project collateral fee to staking module
            fm.withdrawProjectCollateralFee(mainTokenStaking, stakingRewards);
        }
    }
}
