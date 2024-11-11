// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

import "forge-std/console.sol";

// Internal Interfaces
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/abstracts/BondingCurveBase_v1.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";
import {FM_BC_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/FM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";

// Internal Dependencies
import {Module_v1} from "../base/Module_v1.sol";

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
contract LM_ImmutableMigration_v1 is Module_v1 {
    /// @notice The threshold for the migration to be triggered
    uint public migrationThreshold;

    /// @inheritdoc Module_v1
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata,
        bytes memory configData
    ) external override(Module_v1) initializer {
        __Module_init(orchestrator_, metadata);
        migrationThreshold = abi.decode(configData, (uint));
    }

    /// @inheritdoc Module_v1
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(Module_v1)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /// @dev Storage gap for future upgrades
    uint[50] private __gap;

    /**
     * @notice Buys tokens from the bonding curve funding manager for a recipient
     * @param amountIn The maximum amount of collateral tokens to spend
     * @param recipient The address to receive the purchased tokens
     */
    function buyForUpTo(uint amountIn, address recipient) external {
        address fundingManager = address(__Module_orchestrator.fundingManager());
        IERC20 collateralToken = __Module_orchestrator.fundingManager().token();

        // Transfer collateral tokens from sender to this contract
        collateralToken.transferFrom(msg.sender, address(this), amountIn);

        // Approve funding manager to spend collateral tokens
        collateralToken.approve(fundingManager, amountIn);

        // Check if buy would exceed threshold
        (uint excessAmountIn, uint validAmountIn) =
            _checkBuyExceedsThreshold(amountIn);

        if (validAmountIn > 0) {
            console.log("Buying valid amount");
            // Buy valid amount for recipient
            IBondingCurveBase_v1(fundingManager).buyFor(
                recipient, validAmountIn, 1
            );
        }

        if (excessAmountIn > 0) {
            console.log("Returning excess amount");
            collateralToken.transfer(_msgSender(), excessAmountIn);
            // Close buying on the funding manager
            IBondingCurveBase_v1(fundingManager).closeBuy();
        }
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
        IERC20 collateralToken = fundingManager.token();

        // Get current virtual collateral supply
        uint currentCollateral = fundingManager.getVirtualCollateralSupply();

        console.log("currentCollateral", currentCollateral);

        uint totalCollateralAfterBuy = currentCollateral + amountIn;

        // Check if total would exceed threshold
        if (totalCollateralAfterBuy > migrationThreshold) {
            // Calculate how much can be validly bought before hitting threshold
            validAmountIn = migrationThreshold > currentCollateral ? 
                migrationThreshold - currentCollateral : 
                0;
            
            // Remaining amount is excess
            excessAmountIn = amountIn - validAmountIn;
        } else {
            // Entire amount is valid if under threshold
            validAmountIn = amountIn;
            excessAmountIn = 0;
        }
    }
}
