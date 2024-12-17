// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Dependencies

import {
    FM_BC_Bancor_Redeeming_VirtualSupply_v1,
    IFM_BC_Bancor_Redeeming_VirtualSupply_v1,
    IFundingManager_v1
} from "@fm/bondingCurve/FM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";

/**
 * @title   Inverter Restricted Bancor Virtual Supply Bonding Curve Funding Manager
 *
 * @notice  This contract enables the issuance and redeeming of tokens on a
 *          bonding curve, using a virtual supply for both the issuance and
 *          the collateral as input. It integrates Aragon's Bancor Formula to
 *          manage the calculations for token issuance and redemption rates
 *          based on specified reserve ratios.
 *
 * @dev     It overrides the `buyFor()` and `sellTo()` functions of its parent
 *          contract to limit them to callers holding a "Curve Interaction"
 *          role. Since the upstream functions `buy()` and `sell()` call these
 *          functions internally, they also become gated.
 *
 *          PLEASE NOTE: This means that the workflow itself can only mint
 *          tokens through buying and selling by somebody with the
 *          `CURVE_INTERACTION_ROLE`, but NOT that there are no other ways to
 *          mint tokens. The Bonding Curve uses an external token contract, and
 *          there is no guarantee that said uses an external token contract, and
 *          there is no guarantee that said contract won't have an additional
 *          way to mint tokens (and potentially sell them on the cruve to
 *          receive backing collateral)
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer
 *                          to our Security Policy at security.inverter.network
 *                          or email us directly!
 *
 * @custom:version 1.1.2
 *
 * @author  Inverter Network
 */
contract FM_BC_Restricted_Bancor_Redeeming_VirtualSupply_v1 is
    FM_BC_Bancor_Redeeming_VirtualSupply_v1
{
    // -------------------------------------------------------------------------
    // Errors

    /// @notice The feature is deactivated in this implementation.
    error Module__FM_BC_Restricted_Bancor_Redeeming_VirtualSupply__FeatureDeactivated(
    );

    // -------------------------------------------------------------------------
    // Storage

    /// @dev    Minter/Burner Role.
    bytes32 public constant CURVE_INTERACTION_ROLE = "CURVE_USER";

    /// @dev    Storage gap for future upgrades.
    uint[50] private __gap;

    // -------------------------------------------------------------------------
    // Public Functions

    /// @inheritdoc FM_BC_Bancor_Redeeming_VirtualSupply_v1
    /// @dev    Adds additional role check to the buyFor function.
    function buyFor(address _receiver, uint _depositAmount, uint _minAmountOut)
        public
        override
        onlyModuleRole(CURVE_INTERACTION_ROLE)
    {
        super.buyFor(_receiver, _depositAmount, _minAmountOut);
    }

    /// @inheritdoc FM_BC_Bancor_Redeeming_VirtualSupply_v1
    /// @dev    Adds addtional role check to the sellTo function.
    function sellTo(address _receiver, uint _depositAmount, uint _minAmountOut)
        public
        override
        onlyModuleRole(CURVE_INTERACTION_ROLE)
    {
        super.sellTo(_receiver, _depositAmount, _minAmountOut);
    }
}
