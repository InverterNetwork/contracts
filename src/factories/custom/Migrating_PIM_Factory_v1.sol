// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External imports
import {ERC2771Context, Context} from "@oz/metatx/ERC2771Context.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

// Core interfaces
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IOrchestratorFactory_v1} from
    "src/factories/interfaces/IOrchestratorFactory_v1.sol";
import {IModule_v1} from "src/modules/base/IModule_v1.sol";
import {IERC20Issuance_v1} from "src/external/token/IERC20Issuance_v1.sol";

// Funding manager interfaces
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";
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
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20Issuance_v1;

    //--------------------------------------------------------------------------
    // Constants
    //--------------------------------------------------------------------------

    uint private constant FEE_DENOMINATOR = 1e4;
    uint private constant DEFAULT_MUTABLE_INITIAL_MINT_AMOUNT = 200_000_000e18;
    uint private constant DEFAULT_COLLATERAL_FEE_MULTIPLIER = 0;
    uint private constant DEFAULT_ISSUANCE_FEE_MULTIPLIER = 0;

    //--------------------------------------------------------------------------
    // State Variables
    //--------------------------------------------------------------------------

    address public immutable orchestratorFactory;
    address public admin;
    address public mainFundingManager;
    // Staking module metadata
    // @notice This is the metadata for the staking module that will be used to create the staking module for the PIM
    // @dev This is give so we can update the metadata relative to the beacon, it basically solves a dependency issue during initialization
    LM_PC_Staking_v1_Metadata public stakingModuleMetadata;

    uint public mutableInitialMintAmount;
    uint public collateralFeeMultiplier;
    uint public issuanceFeeMultiplier;

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

    modifier onlyAfterMainFundingManagerSet(bool isImmutable) {
        if (isImmutable && mainFundingManager == address(0)) {
            revert
                IMigrating_PIM_Factory_v1
                .PIM_WorkflowFactory__MainFundingManagerNotSet();
        }
        _;
    }

    modifier onlyAdminCanDeployMutable(bool isImmutable) {
        if (!isImmutable && msg.sender != admin) {
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
        if (_orchestratorFactory == address(0)) {
            revert
                IMigrating_PIM_Factory_v1
                .PIM_WorkflowFactory__CantBeZeroAddress();
        }
        if (_admin == address(0)) {
            revert
                IMigrating_PIM_Factory_v1
                .PIM_WorkflowFactory__CantBeZeroAddress();
        }
        orchestratorFactory = _orchestratorFactory;
        admin = _admin;

        stakingModuleMetadata = LM_PC_Staking_v1_Metadata(
            1, 0, 0, "https://github.com/InverterNetwork/contracts"
        );

        mutableInitialMintAmount = DEFAULT_MUTABLE_INITIAL_MINT_AMOUNT;
        collateralFeeMultiplier = DEFAULT_COLLATERAL_FEE_MULTIPLIER;
        issuanceFeeMultiplier = DEFAULT_ISSUANCE_FEE_MULTIPLIER;
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
    )
        external
        onlyAfterMainFundingManagerSet(migrationConfig_.isImmutable)
        onlyAdminCanDeployMutable(migrationConfig_.isImmutable)
        returns (IOrchestrator_v1)
    {
        // Deploy issuance token
        IERC20Issuance_v1 issuanceToken = _deployIssuanceToken(
            issuanceTokenParams, migrationConfig_.isImmutable
        );

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
            ? address(0)
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
        address oldAdmin = admin;
        admin = _admin;
        emit IMigrating_PIM_Factory_v1.AdminChanged(oldAdmin, _admin);
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
        address oldMainFundingManager = mainFundingManager;
        mainFundingManager = _mainFundingManager;
        emit IMigrating_PIM_Factory_v1.MainFundingManagerChanged(
            oldMainFundingManager, _mainFundingManager
        );
    }

    function setCollateralFeeMultiplier(uint _collateralFeeMultiplier)
        external
        onlyAdmin
    {
        uint oldMultiplier = collateralFeeMultiplier;
        collateralFeeMultiplier = _collateralFeeMultiplier;
        emit IMigrating_PIM_Factory_v1.CollateralFeeMultiplierChanged(
            oldMultiplier, _collateralFeeMultiplier
        );
    }

    function setIssuanceFeeMultiplier(uint _issuanceFeeMultiplier)
        external
        onlyAdmin
    {
        uint oldMultiplier = issuanceFeeMultiplier;
        issuanceFeeMultiplier = _issuanceFeeMultiplier;
        emit IMigrating_PIM_Factory_v1.IssuanceFeeMultiplierChanged(
            oldMultiplier, _issuanceFeeMultiplier
        );
    }

    function setMutableInitialMintAmount(uint _mutableInitialMintAmount)
        external
        onlyAdmin
    {
        uint oldAmount = mutableInitialMintAmount;
        mutableInitialMintAmount = _mutableInitialMintAmount;
        emit IMigrating_PIM_Factory_v1.MutableInitialMintAmountChanged(
            oldAmount, _mutableInitialMintAmount
        );
    }

    function setStakingModuleMetadata(
        LM_PC_Staking_v1_Metadata memory _stakingModuleMetadata
    ) external onlyAdmin {
        LM_PC_Staking_v1_Metadata memory oldMetadata = stakingModuleMetadata;
        stakingModuleMetadata = _stakingModuleMetadata;
        emit IMigrating_PIM_Factory_v1.StakingModuleMetadataChanged(
            oldMetadata, _stakingModuleMetadata
        );
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
        uint validAmountIn = _checkBuyExceedsThreshold(fundingManager, amountIn);

        if (validAmountIn > 0) {
            collateralToken.safeTransferFrom(
                msg.sender, address(this), validAmountIn
            );
            collateralToken.safeIncreaseAllowance(fundingManager, validAmountIn);

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

        IERC20Issuance_v1 issuanceToken =
            IERC20Issuance_v1(fm.getIssuanceToken());

        // Transfer and approve tokens
        issuanceToken.safeTransferFrom(msg.sender, address(this), amountIn);
        issuanceToken.safeIncreaseAllowance(fundingManager, amountIn);

        // Sell tokens
        fm.sellTo(recipient, amountIn, minAmountOut);
    }

    //--------------------------------------------------------------------------
    // External Functions - Fee Management
    //--------------------------------------------------------------------------

    function withdrawAllProjectCollateralFeesToStaking() external {
        uint length = fundingManagers.length;
        for (uint i = 0; i < length; i++) {
            address fundingManager = fundingManagers[i];

            _withdrawCollateralFeeToStaking(fundingManager);
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
        uint protocolFeeRate = feeManager.getDefaultCollateralFee();

        if (amountIn + currentCollateral > pim.migrationThreshold) {
            uint excess = amountIn + currentCollateral - pim.migrationThreshold;
            validAmountIn = amountIn - excess;
            validAmountIn =
                validAmountIn + (validAmountIn * protocolFeeRate) / 9900;
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
            LM_PC_PaymentRouter_v1(pim.paymentRouter);
        FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1 fm =
            FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(fundingManager);

        IERC20 collateralToken = fm.token();
        ERC20Issuance_v1 issuanceToken = ERC20Issuance_v1(fm.getIssuanceToken());

        // Calculate collateral liquidity and fees
        uint collateralLiquidity = collateralToken.balanceOf(fundingManager)
            - fm.projectCollateralFeeCollected();
        uint adminCollateralFee =
            (collateralLiquidity * collateralFeeMultiplier) / FEE_DENOMINATOR;

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
        collateralLiquidity -= adminCollateralFee;
        collateralToken.safeTransfer(pim.dexAdapter, collateralLiquidity);
        collateralToken.safeTransfer(admin, adminCollateralFee);
        _withdrawCollateralFeeToStaking(fundingManager);

        // Calculate issuance liquidity and fees
        uint issuanceCap = issuanceToken.cap();
        uint issuanceTotalSupply = issuanceToken.totalSupply();
        uint issuanceLiquidity = (issuanceCap - issuanceTotalSupply);
        uint adminIssuanceFee =
            (issuanceLiquidity * issuanceFeeMultiplier) / FEE_DENOMINATOR;
        issuanceLiquidity -= adminIssuanceFee;

        // Mint & transfer liquidity tokens
        issuanceToken.mint(address(this), issuanceLiquidity + adminIssuanceFee);
        IERC20Issuance_v1(address(issuanceToken)).safeTransfer(
            pim.dexAdapter, issuanceLiquidity
        );
        IERC20Issuance_v1(address(issuanceToken)).safeTransfer(
            admin, adminIssuanceFee
        );

        // Close bonding curve
        fm.closeBuy();
        fm.closeSell();

        // Create liquidity on DEX
        address pool = IDexAdapter_v1(pim.dexAdapter).createLiquidity(
            address(collateralToken),
            address(issuanceToken),
            pim.lpTokenRecipient
        );

        // Handle token ownership
        issuanceToken.renounceOwnership();

        // Update graduation status
        pim.isGraduated = true;
        pims[fundingManager] = pim;

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
        IBondingCurveBase_v1.IssuanceToken memory issuanceTokenParams,
        bool isImmutable
    ) internal returns (IERC20Issuance_v1) {
        ERC20Issuance_v1 issuanceToken = new ERC20Issuance_v1(
            issuanceTokenParams.name,
            issuanceTokenParams.symbol,
            issuanceTokenParams.decimals,
            issuanceTokenParams.maxSupply,
            address(this)
        );

        // If mutable and mintTo is set, mint mutableInitialMintAmount to mintTo
        if (!isImmutable && admin != address(0) && mutableInitialMintAmount > 0)
        {
            issuanceToken.mint(admin, mutableInitialMintAmount);
        }

        return issuanceToken;
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
                    stakingModuleMetadata.majorVersion,
                    stakingModuleMetadata.minorVersion,
                    stakingModuleMetadata.patchVersion,
                    stakingModuleMetadata.url,
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
            LM_PC_PaymentRouter_v1(pim.paymentRouter);
        FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1 fm =
            FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(fundingManager);
        IERC20Issuance_v1 issuanceToken =
            IERC20Issuance_v1(fm.getIssuanceToken());

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
            IERC20(collateralToken).safeTransferFrom(
                _msgSender(), address(this), initialPurchaseAmount
            );
            IERC20(collateralToken).safeIncreaseAllowance(
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

        address[] memory modules = orchestrator.listModules();

        address paymentRouter;
        for (uint i = 0; i < modules.length; i++) {
            try LM_PC_PaymentRouter_v1(modules[i]).PAYMENT_PUSHER_ROLE() {
                paymentRouter = modules[i];
                break;
            } catch {}
        }

        address stakingModule;
        if (!migrationConfig_.isImmutable) {
            for (uint i = 0; i < modules.length; i++) {
                try LM_PC_Staking_v1(modules[i]).rewardRate() {
                    stakingModule = modules[i];
                    break;
                } catch {}
            }
        }

        pims[fundingManager] = IMigrating_PIM_Factory_v1.PIM({
            isGraduated: false,
            isImmutable: migrationConfig_.isImmutable,
            migrationThreshold: migrationConfig_.migrationThreshold,
            lpTokenRecipient: lpTokenRecipient,
            dexAdapter: migrationConfig_.dexAdapter,
            orchestrator: orchestrator,
            initiator: initiator,
            initialVirtualIssuanceSupply: fm.getVirtualIssuanceSupply(),
            initialVirtualCollateralSupply: fm.getVirtualCollateralSupply(),
            stakingModule: stakingModule,
            paymentRouter: paymentRouter
        });

        fundingManagers.push(fundingManager);
    }

    //--------------------------------------------------------------------------
    // Internal Functions - Module Helpers
    //--------------------------------------------------------------------------

    function _withdrawCollateralFeeToStaking(address fundingManager) internal {
        if (mainFundingManager == address(0)) return;

        if (pims[fundingManager].isGraduated) return;

        IBondingCurveBase_v1 fm = IBondingCurveBase_v1(fundingManager);

        uint feeAmount = fm.projectCollateralFeeCollected();
        if (feeAmount == 0) return;

        address mainTokenStaking = pims[mainFundingManager].stakingModule;

        if (mainTokenStaking == address(0)) return;

        // transfer fee
        fm.withdrawProjectCollateralFee(mainTokenStaking, feeAmount);
    }
}
