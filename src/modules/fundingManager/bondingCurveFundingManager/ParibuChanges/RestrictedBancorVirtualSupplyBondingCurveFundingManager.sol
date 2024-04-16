// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Dependencies

import {
    BancorVirtualSupplyBondingCurveFundingManager,
    IFundingManager,
    IBancorVirtualSupplyBondingCurveFundingManager
} from
    "src/modules/fundingManager/bondingCurveFundingManager/BancorVirtualSupplyBondingCurveFundingManager.sol";

// TODO: correct this
/// @title Bancor Virtual Supply Bonding Curve Funding Manager Contract.
/// @author Inverter Network.
/// @notice This contract enables the issuance and redeeming of tokens on a bonding curve, using
/// a virtual supply for both the token and the collateral as input. The contract makes use of the
/// Aragon's Bancor Formula contract to calculate the issuance and redeeming rates.
/// @dev This contract inherits functionalties from the contracts:
/// - BondingCurveFundingManagerBase
/// - RedeemingBondingCurveFundingManagerBase
/// - VirtualTokenSupplyBase
/// - VirtualCollateralSupplyBase
/// The contract should be used by the Orchestrator Owner to manage all the configuration fo the
/// bonding curve, e.g., the virtual supplies and reserve ratios, as well as the opening and closing
/// of the issuance and redeeming functionalities. The contract implements the formulaWrapper
/// functions enforced by the upstream contracts, using the Bancor formula to calculate the
/// issuance/redeeming rate. It also implements a function which enables direct minting of the issuance token
contract RestrictedBancorVirtualSupplyBondingCurveFundingManager is
    BancorVirtualSupplyBondingCurveFundingManager
{
    //Minter/Burner Role
    bytes32 public constant CURVE_INTERACTION_ROLE = "CURVE_USER";

    // Errors
    error RestrictedBancorVirtualSupplyBondingCurveFundingManager__FeatureDeactivated(
    );

    //--------------------------------------------------------------------------
    // Public Functions

    /// @notice Buy tokens on behalf of a specified receiver address. This function is subject
    /// to a transactional limit, determined by the deposit token's decimal precision and the underlying
    /// bonding curve algorithm.
    /// @dev Redirects to the internal function `_buyOrder` by passing the receiver address and deposit amount.
    /// Important: The Bancor Formula has an upper computational limit of (10^38). For tokens with
    /// 18 decimal places, this effectively leaves a maximum allowable deposit amount of (10^20).
    /// While this is substantially large, it is crucial to be aware of this constraint.
    /// Transactions exceeding this limit will be reverted.
    /// @param _receiver The address that will receive the bought tokens.
    /// @param _depositAmount The amount of collateral token depoisited.
    /// @param _minAmountOut The minimum acceptable amount the user expects to receive from the transaction.
    function buyFor(address _receiver, uint _depositAmount, uint _minAmountOut)
        external
        override(BancorVirtualSupplyBondingCurveFundingManager)
        validReceiver(_receiver)
        buyingIsEnabled
        onlyModuleRole(CURVE_INTERACTION_ROLE)
    {
        _virtualBuyOrder(_receiver, _depositAmount, _minAmountOut);
    }

    /// @notice Buy tokens for the sender's address. This function is subject
    /// to a transactional limit, determined by the deposit token's decimal precision and the underlying
    /// bonding curve algorithm.
    /// @dev Redirects to the internal function `_buyOrder` by passing the sender's address and deposit amount.
    /// Important: The Bancor Formula has an upper computational limit of (10^38). For tokens with
    /// 18 decimal places, this effectively leaves a maximum allowable deposit amount of (10^20).
    /// While this is substantially large, it is crucial to be aware of this constraint.
    /// Transactions exceeding this limit will be reverted.
    /// @param _depositAmount The amount of collateral token depoisited.
    /// @param _minAmountOut The minimum acceptable amount the user expects to receive from the transaction.
    function buy(uint _depositAmount, uint _minAmountOut)
        external
        override(BancorVirtualSupplyBondingCurveFundingManager)
        buyingIsEnabled
        onlyModuleRole(CURVE_INTERACTION_ROLE)
    {
        _virtualBuyOrder(_msgSender(), _depositAmount, _minAmountOut);
    }

    /// @notice Redeem tokens on behalf of a specified receiver address. This function is subject
    /// to a transactional limit, determined by the issuing token's decimal precision and the underlying
    /// bonding curve algorithm.
    /// @dev Redirects to the internal function `_sellOrder` by passing the receiver address and deposit amount.
    /// Important: The Bancor Formula has an upper computational limit of (10^26). For tokens with
    /// 18 decimal places, this effectively leaves a maximum allowable deposit amount of (10^8), or
    /// 100,000,000. Transactions exceeding this limit will be reverted.
    /// @param _receiver The address that will receive the redeemed tokens.
    /// @param _depositAmount The amount of issued token to deposited.
    /// @param _minAmountOut The minimum acceptable amount the user expects to receive from the transaction.
    function sellFor(address _receiver, uint _depositAmount, uint _minAmountOut)
        external
        override(BancorVirtualSupplyBondingCurveFundingManager)
        validReceiver(_receiver)
        sellingIsEnabled
        onlyModuleRole(CURVE_INTERACTION_ROLE)
    {
        _virtualSellOrder(_receiver, _depositAmount, _minAmountOut);
    }

    /// @notice Sell collateral for the sender's address. This function is subject
    /// to a transactional limit, determined by the issuing token's decimal precision and the underlying
    /// bonding curve algorithm.
    /// @dev Redirects to the internal function `_sellOrder` by passing the sender's address and deposit amount.
    /// Important: The Bancor Formula has an upper computational limit of (10^26). For tokens with
    /// 18 decimal places, this effectively leaves a maximum allowable deposit amount of (10^8), or
    /// 100,000,000. Transactions exceeding this limit will be reverted.
    /// @param _depositAmount The amount of issued token depoisited.
    /// @param _minAmountOut The minimum acceptable amount the user expects to receive from the transaction.
    /// @param _minAmountOut The minimum acceptable amount the user expects to receive from the transaction.
    function sell(uint _depositAmount, uint _minAmountOut)
        external
        override(BancorVirtualSupplyBondingCurveFundingManager)
        sellingIsEnabled
        onlyModuleRole(CURVE_INTERACTION_ROLE)
    {
        _virtualSellOrder(_msgSender(), _depositAmount, _minAmountOut);
    }

    /// @inheritdoc IBancorVirtualSupplyBondingCurveFundingManager
    function mintIssuanceTokenTo(address _receiver, uint _amount)
        external
        override(BancorVirtualSupplyBondingCurveFundingManager)
        onlyOrchestratorOwner
        validReceiver(_receiver)
    {
        // @question : check if we need to disable this one too or if it can stay non-overridden
        _mint(_receiver, _amount);
    }

    //--------------------------------------------------------------------------
    // OnlyOrchestrator Functions

    /// @inheritdoc IFundingManager
    function transferOrchestratorToken(address to, uint amount)
        external
        override
        onlyOrchestrator
    {
        revert
            RestrictedBancorVirtualSupplyBondingCurveFundingManager__FeatureDeactivated(
        );
    }
}
