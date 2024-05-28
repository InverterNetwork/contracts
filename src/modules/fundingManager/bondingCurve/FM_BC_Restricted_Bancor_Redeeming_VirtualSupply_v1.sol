// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Dependencies

import {
    FM_BC_Bancor_Redeeming_VirtualSupply_v1,
    IFM_BC_Bancor_Redeeming_VirtualSupply_v1,
    IFundingManager_v1
} from "@fm/bondingCurve/FM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";

/**
 * @title   Restricted Bancor Virtual Supply Bonding Curve Funding Manager
 *
 * @notice  This contract enables the issuance and redeeming of tokens on a bonding curve, using
 *          a virtual supply for both the issuance and the collateral as input. It integrates
 *          Aragon's Bancor Formula to manage the calculations for token issuance and redemption
 *          rates based on specified reserve ratios.
 *
 * @dev     It overrides several functions of its parent contract to deactivate or otherwise limit
 *          them:
 *              It defines a "Curve Interaction" role that is required to buy and sell on the curve.
 *              It deactivates the transferOrchestratorToken and mintIssuanceTokenTo functions from
 *                  the workflow.
 *          PLEASE NOTE: This means that the workflow itself can only mint tokens through buying
 *          and selling, but NOT that there are no other ways to mint tokens. The Bonding Curve
 *          uses an external token contract, and there is no guarantee that said contract won't
 *          have an additional way to mint tokens (and potentially sell them on the cruve to receive
 *          backing collateral)
 *
 * @author  Inverter Network
 */
contract FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1 is
    FM_BC_Bancor_Redeeming_VirtualSupply_v1
{
    //--------------------------------------------------------------------------
    // Errors

    /// @notice The feature is deactivated in this implementation.
    error Module__FM_BC_Restricted_Bancor_Redeeming_VirtualSupply__FeatureDeactivated(
    );

    //--------------------------------------------------------------------------
    // Storage

    //Minter/Burner Role
    bytes32 public constant CURVE_INTERACTION_ROLE = "CURVE_USER";

    // Storage gap for future upgrades
    uint[50] private __gap;

    //--------------------------------------------------------------------------
    // Public Functions

    /// @inheritdoc FM_BC_Bancor_Redeeming_VirtualSupply_v1
    /// @dev added role check
    function buyFor(address _receiver, uint _depositAmount, uint _minAmountOut)
        external
        override(FM_BC_Bancor_Redeeming_VirtualSupply_v1)
        validReceiver(_receiver)
        buyingIsEnabled
        onlyModuleRole(CURVE_INTERACTION_ROLE)
    {
        _virtualBuyOrder(_receiver, _depositAmount, _minAmountOut);
    }

    /// @inheritdoc FM_BC_Bancor_Redeeming_VirtualSupply_v1
    /// @dev added role check
    function buy(uint _depositAmount, uint _minAmountOut)
        external
        override(FM_BC_Bancor_Redeeming_VirtualSupply_v1)
        buyingIsEnabled
        onlyModuleRole(CURVE_INTERACTION_ROLE)
    {
        _virtualBuyOrder(_msgSender(), _depositAmount, _minAmountOut);
    }

    /// @inheritdoc FM_BC_Bancor_Redeeming_VirtualSupply_v1
    /// @dev added role check
    function sellFor(address _receiver, uint _depositAmount, uint _minAmountOut)
        external
        override(FM_BC_Bancor_Redeeming_VirtualSupply_v1)
        validReceiver(_receiver)
        sellingIsEnabled
        onlyModuleRole(CURVE_INTERACTION_ROLE)
    {
        _virtualSellOrder(_receiver, _depositAmount, _minAmountOut);
    }

    /// @inheritdoc FM_BC_Bancor_Redeeming_VirtualSupply_v1
    /// @dev added role check
    function sell(uint _depositAmount, uint _minAmountOut)
        external
        override(FM_BC_Bancor_Redeeming_VirtualSupply_v1)
        sellingIsEnabled
        onlyModuleRole(CURVE_INTERACTION_ROLE)
    {
        _virtualSellOrder(_msgSender(), _depositAmount, _minAmountOut);
    }

    /// @notice Mints a specified amount of Issuance Tokens to a designated receiver address. Deactivated in this implementation..
    function mintIssuanceTokenTo(address, uint)
        external
        view
        override(FM_BC_Bancor_Redeeming_VirtualSupply_v1)
        onlyOrchestratorOwner
    {
        revert
            Module__FM_BC_Restricted_Bancor_Redeeming_VirtualSupply__FeatureDeactivated(
        );
    }

    //--------------------------------------------------------------------------
    // OnlyOrchestrator Functions

    /// @notice Transfer a specified amount of Tokens to a designated receiver address. Deactivated in this implementation.
    function transferOrchestratorToken(address, uint)
        external
        view
        override
        onlyOrchestrator
    {
        revert
            Module__FM_BC_Restricted_Bancor_Redeeming_VirtualSupply__FeatureDeactivated(
        );
    }
}
