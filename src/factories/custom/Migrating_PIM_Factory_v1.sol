// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// OpenZeppelin
import {ERC2771Context, Context} from "@oz/metatx/ERC2771Context.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Core Interfaces
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IOrchestratorFactory_v1} from
    "src/factories/interfaces/IOrchestratorFactory_v1.sol";
import {IModule_v1} from "src/modules/base/IModule_v1.sol";

// Funding Manager Interfaces
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";
import {IRedeemingBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IRedeemingBondingCurveBase_v1.sol";
import {IFM_BC_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
import {IFM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1.sol";

// Migration Interfaces
import {IMigrating_PIM_Factory_v1} from
    "../interfaces/IMigrating_PIM_Factory_v1.sol";
import {IDexAdapter_v1} from
    "src/external/immutable-migration/interfaces/IDexAdapter_v1.sol";

// Module Implementations
import {FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1.sol";
import {LM_PC_PaymentRouter_v1} from
    "src/modules/logicModule/LM_PC_PaymentRouter_v1.sol";
import {LM_PC_Staking_v1} from "src/modules/logicModule/LM_PC_Staking_v1.sol";
import {FeeManager_v1} from "@ex/fees/FeeManager_v1.sol";

// Token Implementations
import {ERC20Issuance_v1} from "src/external/token/ERC20Issuance_v1.sol";

contract Migrating_PIM_Factory_v1 is
    ERC2771Context,
    IMigrating_PIM_Factory_v1
{
    //--------------------------------------------------------------------------
    // State Variables

    /// @dev	store address of {Orchestratorfactory_v1}.
    address public orchestratorFactory;

    mapping(address fundingManager => PIM orchestrator) public pims;

    //--------------------------------------------------------------------------
    // Modifiers

    /// @dev	Modifier to guarantee the caller is the deployer for the given funding manager.
    modifier onlyInitiatorAfterGraduation(address fundingManager) {
        PIM memory pim = pims[fundingManager];
        if (msg.sender != pim.initiator || !pim.isGraduated) {
            revert
                IMigrating_PIM_Factory_v1
                .PIM_WorkflowFactory__OnlyInitiatorAfterGraduation();
        }
        _;
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
        // deploy issuance token
        ERC20Issuance_v1 issuanceToken = new ERC20Issuance_v1(
            issuanceTokenParams.name,
            issuanceTokenParams.symbol,
            issuanceTokenParams.decimals,
            issuanceTokenParams.maxSupply,
            address(this) // assigns owner role to itself initially to manage minting rights temporarily
        );

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
            address(issuanceToken)
        );

        address fundingManager = address(orchestrator.fundingManager());

        address lpTokenRecipient = migrationConfig_.isImmutable
            ? address(this)
            : migrationConfig_.lpTokenRecipient;

        // get bonding curve / funding manager
        // store orchestrator for issuance token
        pims[address(fundingManager)] = IMigrating_PIM_Factory_v1.PIM({
            isGraduated: false,
            isImmutable: migrationConfig_.isImmutable,
            migrationThreshold: migrationConfig_.migrationThreshold,
            lpTokenRecipient: lpTokenRecipient,
            dexAdapter: migrationConfig_.dexAdapter,
            orchestrator: orchestrator,
            initiator: initiator,
            initialVirtualIssuanceSupply: FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(
                fundingManager
            ).getVirtualIssuanceSupply(),
            initialVirtualCollateralSupply: FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(
                fundingManager
            ).getVirtualCollateralSupply(),
            initialRewardDuration: migrationConfig_.initialRewardDuration
        });

        // enable bonding curve to mint issuance token
        issuanceToken.setMinter(fundingManager, true);

        _handleWorkflowPrivileges(fundingManager);

        _handleInitialPurchase(
            fundingManager, collateralToken, initialPurchaseAmount, initiator
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

    /**
     * @notice Returns whether the issuance token has been graduated
     * @param fundingManager The funding manager to check
     * @return isGraduated Whether the issuance token has been graduated
     */
    function getIsGraduated(address fundingManager)
        external
        view
        returns (bool)
    {
        return pims[fundingManager].isGraduated;
    }

    /**
     * @notice Returns whether the issuance token is immutable
     * @param fundingManager The funding manager to check
     * @return isImmutable Whether the issuance token is immutable
     */
    function getIsImmutable(address fundingManager)
        external
        view
        returns (bool)
    {
        return pims[fundingManager].isImmutable;
    }

    /**
     * @notice Returns the migration threshold
     * @param fundingManager The funding manager to check
     * @return migrationThreshold The migration threshold
     */
    function getMigrationThreshold(address fundingManager)
        external
        view
        returns (uint)
    {
        return pims[fundingManager].migrationThreshold;
    }

    /**
     * @notice Returns the LP token recipient
     * @param fundingManager The funding manager to check
     * @return lpTokenRecipient The LP token recipient
     */
    function getLpTokenRecipient(address fundingManager)
        external
        view
        returns (address)
    {
        return pims[fundingManager].lpTokenRecipient;
    }

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
    ) external {
        PIM memory pim = pims[fundingManager];
        FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1 fm =
            FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(fundingManager);

        IERC20 collateralToken = fm.token();

        // Check if buy would exceed threshold BEFORE transferring tokens
        (uint excessAmountIn, uint validAmountIn) =
            _checkBuyExceedsThreshold(fundingManager, amountIn);

        // Transfer only the valid amount
        if (validAmountIn > 0) {
            collateralToken.transferFrom(
                msg.sender, address(this), validAmountIn
            );

            // Approve funding manager to spend collateral tokens
            collateralToken.approve(fundingManager, validAmountIn);

            // Calculate adjusted minAmountOut based on the ratio of valid to total amount
            uint adjustedMinAmountOut =
                (minAmountOut * validAmountIn) / amountIn;

            // Use valid amount to buy from curve
            fm.buyFor(recipient, validAmountIn, adjustedMinAmountOut);

            // If threshold has been reached, close curve and initiate graduation
            if (
                collateralToken.balanceOf(fundingManager)
                    >= pim.migrationThreshold
            ) {
                // Initiate graduation
                _graduate(fundingManager);
            }
        }
    }

    /**
     * @notice Checks if buying from the funding manager would exceed the migration threshold
     * @param fundingManager The funding manager to check
     * @param amountIn The amount of collateral tokens to check
     * @return excessAmountIn The amount of collateral tokens that would exceed the threshold
     * @return validAmountIn The amount of collateral tokens that would not exceed the threshold
     */
    function _checkBuyExceedsThreshold(address fundingManager, uint amountIn)
        internal
        view
        returns (uint excessAmountIn, uint validAmountIn)
    {
        PIM memory pim = pims[fundingManager];

        // Get fee manager
        FeeManager_v1 feeManager =
            FeeManager_v1(pim.orchestrator.governor().getFeeManager());

        // Get funding manager and collateral token
        FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1 fm =
            FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(fundingManager);

        IERC20 collateralToken = fm.token();

        // Get actual collateral supply before and after buy
        uint currentCollateral = collateralToken.balanceOf(fundingManager);

        // Calculate fee-adjusted amount that would actually go to the funding manager
        uint feeRate = feeManager.getDefaultCollateralFee();
        uint appliedFee = (amountIn * feeRate) / 10_000;
        uint netAmountIn = amountIn - appliedFee;
        uint collateralAfterBuy = currentCollateral + netAmountIn;

        // Check if total would exceed threshold
        if (collateralAfterBuy > pim.migrationThreshold) {
            // Calculate how much can be validly bought before hitting threshold
            uint remainingToThreshold = pim.migrationThreshold
                > currentCollateral ? pim.migrationThreshold - currentCollateral : 0;

            // Account for fees when calculating valid amount
            // validAmountIn = remainingToThreshold * 10000 / (10000 - feeRate);
            validAmountIn = (remainingToThreshold * 10_000) / (10_000 - feeRate);
            excessAmountIn =
                amountIn > validAmountIn ? amountIn - validAmountIn : 0;
        } else {
            // Entire amount is valid if under threshold
            validAmountIn = amountIn;
            excessAmountIn = 0;
        }
    }

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
    ) external {
        // Get funding manager
        FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1 fm =
            FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(fundingManager);

        // Get issuance token
        ERC20Issuance_v1 issuanceToken = ERC20Issuance_v1(fm.getIssuanceToken());

        // Transfer issuance tokens from sender to this contract
        issuanceToken.transferFrom(msg.sender, address(this), amountIn);

        // Approve funding manager to spend issuance token
        issuanceToken.approve(fundingManager, amountIn);

        // Make sell order
        fm.sellTo(recipient, amountIn, minAmountOut);
    }

    /**
     * @notice Graduates the issuance token
     * @param fundingManager The funding manager to graduate
     */
    function _graduate(address fundingManager) internal {
        PIM memory pim = pims[fundingManager];

        // Get funding manager
        FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1 fm =
            FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(fundingManager);

        // Get collateral token
        IERC20 collateralToken = fm.token();
        ERC20Issuance_v1 issuanceToken = ERC20Issuance_v1(fm.getIssuanceToken());

        // Get modules
        address[] memory modules = pim.orchestrator.listModules();

        uint collateralLiquidity = collateralToken.balanceOf(fundingManager);

        uint issuanceLiquidity =
            fm.getVirtualIssuanceSupply() - pim.initialVirtualIssuanceSupply;

        for (uint i = 0; i < modules.length; i++) {
            try LM_PC_PaymentRouter_v1(modules[i]).PAYMENT_PUSHER_ROLE() {
                LM_PC_PaymentRouter_v1(modules[i]).pushPayment(
                    pim.dexAdapter,
                    address(collateralToken),
                    collateralLiquidity - fm.projectCollateralFeeCollected(),
                    0,
                    0,
                    0
                );
                break;
            } catch {}
        }

        fm.closeBuy();
        fm.closeSell();

        // Mint initial liquidity to dex adapter
        issuanceToken.mint(pim.dexAdapter, issuanceLiquidity);

        // Call migration on adapter
        address pool = IDexAdapter_v1(pim.dexAdapter).createLiquidity(
            address(collateralToken),
            address(issuanceToken),
            pim.lpTokenRecipient
        );

        if (pim.isImmutable) {
            issuanceToken.renounceOwnership();
        } else {
            issuanceToken.transferOwnership(pim.initiator);
        }

        if (!pim.isImmutable) {
            pim.orchestrator.authorizer().grantRole(
                pim.orchestrator.authorizer().getAdminRole(), pim.initiator
            );
        }

        pim.isGraduated = true;

        // Update the mapping with the modified PIM struct
        pims[fundingManager] = pim;

        uint stakingRewards = fm.projectCollateralFeeCollected();

        for (uint i = 0; i < modules.length; i++) {
            try LM_PC_Staking_v1(modules[i]).rewardRate() {
                LM_PC_Staking_v1(modules[i]).setRewards(
                    stakingRewards, pim.initialRewardDuration
                );
                break;
            } catch {}
        }

        emit Graduation(
            address(pim.orchestrator),
            pool,
            issuanceLiquidity,
            collateralLiquidity,
            stakingRewards
        );
    }

    function _handleWorkflowPrivileges(address fundingManager) internal {
        PIM memory pim = pims[fundingManager];

        // Get funding manager
        FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1 fm =
            FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(fundingManager);

        // Set issuance token
        ERC20Issuance_v1 issuanceToken = ERC20Issuance_v1(fm.getIssuanceToken());

        // grant admin role to factory (immutable) or to deployer address (mutable)
        if (!pim.isImmutable) {
            pim.orchestrator.authorizer().grantRole(
                pim.orchestrator.authorizer().getAdminRole(), pim.initiator
            );
        }

        // set factory as minter to be able to mint initial liquidity upon graduation
        issuanceToken.setMinter(address(this), true);

        // grant curve interaction role to factory to be able to buy and sell
        fm.grantModuleRole(fm.CURVE_INTERACTION_ROLE(), address(this));
        // grant payment pusher role to factory to be able to transfer collateral to dex
        address[] memory modules = pim.orchestrator.listModules();
        for (uint i = 0; i < modules.length; i++) {
            try LM_PC_PaymentRouter_v1(modules[i]).PAYMENT_PUSHER_ROLE() {
                LM_PC_PaymentRouter_v1(modules[i]).grantModuleRole(
                    LM_PC_PaymentRouter_v1(modules[i]).PAYMENT_PUSHER_ROLE(),
                    address(this)
                );
                break;
            } catch {}
        }
    }

    function _handleInitialPurchase(
        address fundingManager,
        address collateralToken,
        uint initialPurchaseAmount,
        address recipient
    ) internal {
        // if initial purchase amount set execute first purchase from curve
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

    function _deployOrchestrator(
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig,
        IOrchestratorFactory_v1.ModuleConfig memory fundingManagerConfig,
        IOrchestratorFactory_v1.ModuleConfig memory authorizerConfig,
        IOrchestratorFactory_v1.ModuleConfig memory paymentProcessorConfig,
        IOrchestratorFactory_v1.ModuleConfig[] memory moduleConfigs,
        address issuanceToken
    )
        internal
        returns (
            IOrchestrator_v1 orchestrator,
            address initiator,
            address collateralToken
        )
    {
        // MODIFY AUTHORIZER CONFIG
        // decode configData of authorizer
        // set (own) factory as orchestrator admin
        bytes memory authorizerConfigData = authorizerConfig.configData;
        (initiator) = abi.decode(authorizerConfigData, (address));
        authorizerConfigData = abi.encode(address(this));
        authorizerConfig.configData = authorizerConfigData;
        // MODIFY FUNDING MANAGER CONFIG
        // decode configData of fundingManager
        // set newly deployed token as issuance token
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

        bcProperties.buyFee = 100;
        bcProperties.sellFee = 100;

        fundingManagerConfigData =
            abi.encode(address(issuanceToken), bcProperties, collateralToken);

        fundingManagerConfig.configData = fundingManagerConfigData;

        // Create a new memory array to hold the module configurations
        IOrchestratorFactory_v1.ModuleConfig[] memory moduleConfigsMemory =
            new IOrchestratorFactory_v1.ModuleConfig[](moduleConfigs.length + 1);

        // Copy existing module configurations from memory to the new memory array
        for (uint i = 0; i < moduleConfigs.length; i++) {
            moduleConfigsMemory[i] = moduleConfigs[i];
        }

        // Add the new module configuration
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

        orchestrator = IOrchestratorFactory_v1(orchestratorFactory)
            .createOrchestrator(
            workflowConfig,
            fundingManagerConfig,
            authorizerConfig,
            paymentProcessorConfig,
            moduleConfigsMemory
        );

        return (orchestrator, initiator, collateralToken);
    }
}
