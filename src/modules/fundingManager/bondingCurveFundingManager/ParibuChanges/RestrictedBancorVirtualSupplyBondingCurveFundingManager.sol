// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Dependencies

import {
    BancorVirtualSupplyBondingCurveFundingManager,
    IBancorVirtualSupplyBondingCurveFundingManager,
    IFundingManager
} from
    "src/modules/fundingManager/bondingCurveFundingManager/BancorVirtualSupplyBondingCurveFundingManager.sol";

/// @title Restricted Bancor Virtual Supply Bonding Curve Funding Manager Contract.
/// @author Inverter Network.
/// @notice This contract enables the issuance and redeeming of tokens on a bonding curve, using
/// a virtual supply for both the token and the collateral as input. The contract makes use of the
/// Aragon's Bancor Formula contract to calculate the issuance and redeeming rates. The mint and burn functions are gated through a Role in the Inverter Workflow
/// @dev This contract inherits functionalties from the contracts:
/// - BancorVirtualSupplyBondingCurveFundingManager
/// It overrides several functions of its parent contract to deactivate or otherwise limit them:
/// - It defines a "Curve Interaction" role that is required to buy and sell on the curve.
/// - It deactivates the transferOrchestratorToken and mintIssuanceTokenTo functions from the workflow.
/// PLEASE NOTICE: This means that the workflow itself can only mint tokens through buying and selling, but NOT that there are no other ways to mint tokens. The Bonding Curve uses an external token contract, and there is no guarantee that said contract won't have an additional way to mint tokens (and potentially sell them on the cruve to receive backing collateral)
contract RestrictedBancorVirtualSupplyBondingCurveFundingManager is
    BancorVirtualSupplyBondingCurveFundingManager
{
    //--------------------------------------------------------------------------
    // Errors

    /// @notice The feature is deactivated in this implementation.
    error RestrictedBancorVirtualSupplyBondingCurveFundingManager__FeatureDeactivated(
    );

    //--------------------------------------------------------------------------
    // Storage

    //Minter/Burner Role
    bytes32 public constant CURVE_INTERACTION_ROLE = "CURVE_USER";

    //--------------------------------------------------------------------------
    // Public Functions

    /// @inheritdoc BancorVirtualSupplyBondingCurveFundingManager
    /// @dev added role check
    function buyFor(address _receiver, uint _depositAmount, uint _minAmountOut)
        external
        override(BancorVirtualSupplyBondingCurveFundingManager)
        validReceiver(_receiver)
        buyingIsEnabled
        onlyModuleRole(CURVE_INTERACTION_ROLE)
    {
        _virtualBuyOrder(_receiver, _depositAmount, _minAmountOut);
    }

    /// @inheritdoc BancorVirtualSupplyBondingCurveFundingManager
    /// @dev added role check
    function buy(uint _depositAmount, uint _minAmountOut)
        external
        override(BancorVirtualSupplyBondingCurveFundingManager)
        buyingIsEnabled
        onlyModuleRole(CURVE_INTERACTION_ROLE)
    {
        _virtualBuyOrder(_msgSender(), _depositAmount, _minAmountOut);
    }

    /// @inheritdoc BancorVirtualSupplyBondingCurveFundingManager
    /// @dev added role check
    function sellFor(address _receiver, uint _depositAmount, uint _minAmountOut)
        external
        override(BancorVirtualSupplyBondingCurveFundingManager)
        validReceiver(_receiver)
        sellingIsEnabled
        onlyModuleRole(CURVE_INTERACTION_ROLE)
    {
        _virtualSellOrder(_receiver, _depositAmount, _minAmountOut);
    }

    /// @inheritdoc BancorVirtualSupplyBondingCurveFundingManager
    /// @dev added role check
    function sell(uint _depositAmount, uint _minAmountOut)
        external
        override(BancorVirtualSupplyBondingCurveFundingManager)
        sellingIsEnabled
        onlyModuleRole(CURVE_INTERACTION_ROLE)
    {
        _virtualSellOrder(_msgSender(), _depositAmount, _minAmountOut);
    }

    /// @notice Mints a specified amount of Issuance Tokens to a designated receiver address. Deactivated in this implementation..
    function mintIssuanceTokenTo(address, uint)
        external
        view
        override(BancorVirtualSupplyBondingCurveFundingManager)
        onlyOrchestratorOwner
    {
        revert
            RestrictedBancorVirtualSupplyBondingCurveFundingManager__FeatureDeactivated(
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
            RestrictedBancorVirtualSupplyBondingCurveFundingManager__FeatureDeactivated(
        );
    }
}
