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
    IDexAdapter_v1 public dexAdapter;
    bool public isImmutable;
    bool public isGraduated;
    uint public migrationThreshold;
    address public lpTokenRecipient;

    mapping(address issuanceToken => PIM orchestrator) public pims;

    //--------------------------------------------------------------------------
    // Constructor

    constructor(address _orchestratorFactory, address _trustedForwarder)
        ERC2771Context(_trustedForwarder)
    {
        isGraduated = false;

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
        isImmutable = migrationConfig_.isImmutable;
        migrationThreshold = migrationConfig_.migrationThreshold;
        dexAdapter = IDexAdapter_v1(migrationConfig_.dexAdapter);

        // set lp token recipient (mutable) or to factory (immutable)
        if (isImmutable) {
            lpTokenRecipient = address(this);
        } else {
            lpTokenRecipient = migrationConfig_.lpTokenRecipient;
        }

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

        // get bonding curve / funding manager
        address fundingManager = address(orchestrator.fundingManager());
        // store orchestrator for issuance token
        pims[address(issuanceToken)] = PIM(
            orchestrator,
            FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(fundingManager)
                .getVirtualIssuanceSupply(),
            FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(fundingManager)
                .getVirtualCollateralSupply()
        );

        // enable bonding curve to mint issuance token
        issuanceToken.setMinter(fundingManager, true);

        _handleWorkflowPrivileges(address(issuanceToken));

        _handleInitialPurchase(
            fundingManager, collateralToken, initialPurchaseAmount, initiator
        );

        // renounce token ownership
        issuanceToken.renounceOwnership();

        emit IMigrating_PIM_Factory_v1.PIMWorkflowCreated(
            address(orchestrator),
            address(issuanceToken),
            _msgSender(),
            isImmutable,
            migrationThreshold,
            lpTokenRecipient
        );

        return orchestrator;
    }

    /**
     * @notice Buys tokens from the bonding curve funding manager for a recipient
     * @param issuanceToken The issuance token to buy
     * @param amountIn The maximum amount of collateral tokens to spend
     * @param recipient The address to receive the purchased tokens
     */
    function buyForUpTo(
        address issuanceToken,
        address recipient,
        uint amountIn,
        uint minAmountOut
    ) external {
        PIM memory pim = pims[issuanceToken];
        address fundingManager = address(pim.orchestrator.fundingManager());
        IERC20 collateralToken = pim.orchestrator.fundingManager().token();

        // Check if buy would exceed threshold BEFORE transferring tokens
        (uint excessAmountIn, uint validAmountIn) =
            _checkBuyExceedsThreshold(issuanceToken, amountIn);

        // Transfer the full amount first
        collateralToken.transferFrom(msg.sender, address(this), amountIn);

        if (validAmountIn > 0) {
            // Approve funding manager to spend collateral tokens
            collateralToken.approve(fundingManager, validAmountIn);

            // Calculate adjusted minAmountOut based on the ratio of valid to total amount
            uint adjustedMinAmountOut = validAmountIn == 0
                ? 0
                : (minAmountOut * validAmountIn) / amountIn;

            // Use valid amount to buy from curve
            IBondingCurveBase_v1(fundingManager).buyFor(
                recipient, validAmountIn, adjustedMinAmountOut
            );

            // If threshold has been reached, close curve and initiate graduation
            if (collateralToken.balanceOf(fundingManager) >= migrationThreshold)
            {
                // Close buying & selling on the funding manager
                FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(
                    fundingManager
                ).closeBuy();
                FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(
                    fundingManager
                ).closeSell();

                // Initiate graduation
                _graduate(issuanceToken);
            }
        }

        // If there was excess amount, transfer it back to sender
        if (excessAmountIn > 0) {
            collateralToken.transfer(msg.sender, excessAmountIn);
        }
    }

    function sellTo(
        address issuanceToken,
        address recipient,
        uint amountIn,
        uint minAmountOut
    ) external {
        PIM memory pim = pims[issuanceToken];
        IRedeemingBondingCurveBase_v1 fundingManager =
        IRedeemingBondingCurveBase_v1(
            address(pim.orchestrator.fundingManager())
        );

        // Transfer issuance tokens from sender to this contract
        ERC20Issuance_v1(issuanceToken).transferFrom(
            msg.sender, address(this), amountIn
        );

        // Approve funding manager to spend issuance token
        ERC20Issuance_v1(issuanceToken).approve(
            address(fundingManager), amountIn
        );

        // Make sell order
        fundingManager.sellTo(recipient, amountIn, minAmountOut);
    }

    function _checkBuyExceedsThreshold(address token, uint amountIn)
        internal
        view
        returns (uint excessAmountIn, uint validAmountIn)
    {
        PIM memory pim = pims[token];

        // Get funding manager and collateral token
        FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1 fundingManager =
        FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(
            address(pim.orchestrator.fundingManager())
        );

        IERC20 collateralToken = pim.orchestrator.fundingManager().token();

        // Get actual collateral supply before and after buy
        uint currentCollateral =
            collateralToken.balanceOf(address(fundingManager));
        uint collateralAfterBuy = currentCollateral + amountIn;

        // Check if total would exceed threshold
        if (collateralAfterBuy > migrationThreshold) {
            // Calculate how much can be validly bought before hitting threshold
            validAmountIn = migrationThreshold > currentCollateral
                ? migrationThreshold - currentCollateral
                : 0;

            // Remaining amount is excess
            excessAmountIn = amountIn - validAmountIn;
        } else {
            // Entire amount is valid if under threshold
            validAmountIn = amountIn;
            excessAmountIn = 0;
        }
    }

    function _graduate(address issuanceToken) internal {
        PIM memory pim = pims[issuanceToken];
        FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1 fundingManager =
        FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(
            address(pim.orchestrator.fundingManager())
        );
        IERC20 collateralToken = fundingManager.token();

        uint collateralLiquidity =
            collateralToken.balanceOf(address(fundingManager));
        uint issuanceLiquidity = fundingManager.getVirtualIssuanceSupply()
            - pim.initialVirtualIssuanceSupply;

        address[] memory modules = pim.orchestrator.listModules();
        for (uint i = 0; i < modules.length; i++) {
            try LM_PC_PaymentRouter_v1(modules[i]).PAYMENT_PUSHER_ROLE() {
                LM_PC_PaymentRouter_v1(modules[i]).pushPayment(
                    address(dexAdapter),
                    address(collateralToken),
                    collateralLiquidity,
                    0,
                    0,
                    0
                );
                break;
            } catch {}
        }

        fundingManager.closeBuy();
        fundingManager.closeSell();

        // Mint initial liquidity to dex adapter
        ERC20Issuance_v1(issuanceToken).mint(
            address(dexAdapter), issuanceLiquidity
        );

        // Call migration on adapter
        address pool = dexAdapter.createLiquidity(
            address(collateralToken), address(issuanceToken), lpTokenRecipient
        );

        isGraduated = true;

        emit Graduation(
            issuanceToken,
            address(collateralToken),
            pool,
            issuanceLiquidity,
            collateralLiquidity
        );
    }

    function _handleWorkflowPrivileges(address issuanceToken) internal {
        PIM memory pim = pims[issuanceToken];
        FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1 fundingManager =
        FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1(
            address(pim.orchestrator.fundingManager())
        );

        // grant admin role to factory (immutable) or to deployer address (mutable)
        pim.orchestrator.authorizer().grantRole(
            pim.orchestrator.authorizer().getAdminRole(),
            isImmutable ? address(this) : _msgSender()
        );
        // set factory as minter to be able to mint initial liquidity upon graduation
        ERC20Issuance_v1(issuanceToken).setMinter(address(this), true);
        // grant curve interaction role to factory to be able to buy and sell
        fundingManager.grantModuleRole(
            fundingManager.CURVE_INTERACTION_ROLE(), address(this)
        );
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
        fundingManagerConfigData =
            abi.encode(address(issuanceToken), bcProperties, collateralToken);
        fundingManagerConfig.configData = fundingManagerConfigData;
        orchestrator = IOrchestratorFactory_v1(orchestratorFactory)
            .createOrchestrator(
            workflowConfig,
            fundingManagerConfig,
            authorizerConfig,
            paymentProcessorConfig,
            moduleConfigs
        );

        return (orchestrator, initiator, collateralToken);
    }
}
