// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Dependencies

import {
    BancorVirtualSupplyBondingCurveFundingManager,
    IBancorVirtualSupplyBondingCurveFundingManager
} from
    "src/modules/fundingManager/bondingCurveFundingManager/BancorVirtualSupplyBondingCurveFundingManager.sol";

contract RestrictedBancorVirtualSupplyBondingCurveFundingManager is
    BancorVirtualSupplyBondingCurveFundingManager
{
    //Minter/Burner Role
    bytes32 public constant CURVE_INTERACTION_ROLE = "CURVE_USER";

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
        onlyModuleRole(CURVE_INTERACTION_ROLE)
        validReceiver(_receiver)
    {
        _mint(_receiver, _amount);
    }
}
