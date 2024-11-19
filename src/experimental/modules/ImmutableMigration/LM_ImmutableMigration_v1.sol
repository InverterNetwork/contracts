// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/abstracts/BondingCurveBase_v1.sol";
import {IRedeemingBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IRedeemingBondingCurveBase_v1.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";
import {FM_BC_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/FM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
import {IDexAdapter_v1} from
    "src/experimental/modules/ImmutableMigration/interfaces/IDexAdapter_v1.sol";
import {IERC20Issuance_v1} from "@ex/token/IERC20Issuance_v1.sol";
import {IERC20PaymentClientBase_v1} from
    "@lm/abstracts/ERC20PaymentClientBase_v1.sol";
import {ILM_ImmutableMigration_v1} from
    "./interfaces/ILM_ImmutableMigration_v1.sol";

// Internal Dependencies
import {
    ERC20PaymentClientBase_v1,
    Module_v1
} from "@lm/abstracts/ERC20PaymentClientBase_v1.sol";

// External Dependencies
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

// Uniswap

// import {UniswapV2Factory} from "@univ2core/contracts/UniswapV2Factory.sol";
// import {UniswapV2Router02} from "@univ2peri/contracts/UniswapV2Router02.sol";

/**
 * @title   Immutable Migration Logic Module
 *
 * @notice  Provides functionality for handling immutable migrations
 *
 * @dev     Extends {Module_v1} to integrate with the Orchestrator system
 *
 * @custom:security-contact security@inverter.network
 *
 * @author  Inverter Network
 */
contract LM_ImmutableMigration_v1 is
    ILM_ImmutableMigration_v1,
    ERC20PaymentClientBase_v1
{
    /// @notice The initial virtual issuance supply of the funding manager
    uint public initialVirtualIssuanceSupply;
    uint public initialVirtualCollateralSupply;
    /// @notice The threshold for the migration to be triggered
    uint public migrationThreshold;
    /// @notice Address of the DEX adapter.
    IDexAdapter_v1 public dexAdapter;

    /// @inheritdoc Module_v1
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata,
        bytes memory configData
    ) external override(Module_v1) initializer {
        __Module_init(orchestrator_, metadata);
        (uint threshold, address dexAdapterAddress) =
            abi.decode(configData, (uint, address));
        FM_BC_Bancor_Redeeming_VirtualSupply_v1 fundingManager =
        FM_BC_Bancor_Redeeming_VirtualSupply_v1(
            address(__Module_orchestrator.fundingManager())
        );
        initialVirtualIssuanceSupply = fundingManager.getVirtualIssuanceSupply();
        initialVirtualCollateralSupply =
            fundingManager.getVirtualCollateralSupply();
        migrationThreshold =
            threshold + fundingManager.getVirtualCollateralSupply();
        dexAdapter = IDexAdapter_v1(dexAdapterAddress);
    }

    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC20PaymentClientBase_v1)
        returns (bool)
    {
        return interfaceId == type(ILM_ImmutableMigration_v1).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /// @dev Storage gap for future upgrades
    uint[50] private __gap;

    /**
     * @notice Buys tokens from the bonding curve funding manager for a recipient
     * @param amountIn The maximum amount of collateral tokens to spend
     * @param recipient The address to receive the purchased tokens
     */
    function buyForUpTo(address recipient, uint amountIn, uint minAmountOut)
        external
    {
        address fundingManager = address(__Module_orchestrator.fundingManager());
        IERC20 collateralToken = __Module_orchestrator.fundingManager().token();

        // Transfer collateral tokens from sender to this contract
        collateralToken.transferFrom(msg.sender, address(this), amountIn);

        // Approve funding manager to spend collateral tokens
        collateralToken.approve(fundingManager, amountIn);

        // Check if buy would exceed threshold by calculating how much of amountIn
        // is valid (can be used for buying) and how much is excess (is reimbursed)
        (uint excessAmountIn, uint validAmountIn) =
            _checkBuyExceedsThreshold(amountIn);

        // Use valid amount to buy from curve
        if (validAmountIn > 0) {
            IBondingCurveBase_v1(fundingManager).buyFor(
                recipient, validAmountIn, minAmountOut
            );
        }

        // Reimburse potential
        if (excessAmountIn > 0) {
            collateralToken.transfer(_msgSender(), excessAmountIn);
        }

        // If threshold has been reached, close curve and initiate graduation
        if (
            collateralToken.balanceOf(fundingManager)
                == migrationThreshold - initialVirtualCollateralSupply
        ) {
            // Close buying & selling on the funding manager
            IBondingCurveBase_v1(fundingManager).closeBuy();
            IRedeemingBondingCurveBase_v1(fundingManager).closeSell();

            // Initiate graduation
            _graduate();
        }
    }

    function sellFor(address recipient, uint amountIn, uint minAmountOut)
        external
    {
        FM_BC_Bancor_Redeeming_VirtualSupply_v1 fundingManager =
        FM_BC_Bancor_Redeeming_VirtualSupply_v1(
            address(__Module_orchestrator.fundingManager())
        );
        IERC20Issuance_v1 issuanceToken =
            IERC20Issuance_v1(fundingManager.getIssuanceToken());

        // Transfer issuance tokens from sender to this contract
        issuanceToken.transferFrom(msg.sender, address(this), amountIn);

        // Approve funding manager to spend issuance token
        issuanceToken.approve(address(fundingManager), amountIn);

        // Make sell order
        fundingManager.sellTo(recipient, amountIn, minAmountOut);
    }

    function _checkBuyExceedsThreshold(uint amountIn)
        internal
        view
        returns (uint excessAmountIn, uint validAmountIn)
    {
        // Get funding manager and collateral token
        FM_BC_Bancor_Redeeming_VirtualSupply_v1 fundingManager =
        FM_BC_Bancor_Redeeming_VirtualSupply_v1(
            address(__Module_orchestrator.fundingManager())
        );

        // Get virtual collateral supply before and after buy
        uint currentCollateral = fundingManager.getVirtualCollateralSupply();
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

    function _graduate() internal {
        FM_BC_Bancor_Redeeming_VirtualSupply_v1 fundingManager =
        FM_BC_Bancor_Redeeming_VirtualSupply_v1(
            address(__Module_orchestrator.fundingManager())
        );
        IERC20 collateralToken = fundingManager.token();
        IERC20Issuance_v1 issuanceToken =
            IERC20Issuance_v1(fundingManager.getIssuanceToken());

        // Transfer collateral reserve into adapter
        fundingManager.transferOrchestratorToken(
            address(dexAdapter),
            collateralToken.balanceOf(address(fundingManager))
        );

        // Mint initial liquidity to dex adapter
        issuanceToken.mint(
            address(dexAdapter),
            fundingManager.getVirtualIssuanceSupply()
                - initialVirtualIssuanceSupply
        );

        // Call migration on adapter
        dexAdapter.createLiquidity(
            address(collateralToken), address(issuanceToken), address(this)
        );
    }
}
