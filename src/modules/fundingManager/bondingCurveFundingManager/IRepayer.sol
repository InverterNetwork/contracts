// SPDX-License-Identifier: LGPL-3.0-only

pragma solidity ^0.8.0;

import {ILiquidityVaultController} from
    "src/modules/logicModule/liquidityVault/ILiquidityVaultController.sol";

interface IRepayer {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Amount passed as parameter is higher than repayable amount
    error Repayer__InsufficientCollateralForRepayerTransfer();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when the liquidity pool address is updated
    event LiquidityVaultControllerChanged(
        ILiquidityVaultController newValue, ILiquidityVaultController oldValue
    );

    /// @notice Event emitted when the repayable amount is updated
    event RepayableAmountChanged(uint newValue, uint oldValue);

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Return the repayable amount in collateral asset
    /// @return uint The repayable amount
    function getRepayableAmount() external view returns (uint);

    // Todo update comment
    /// @notice Sets the repayable amount
    /// @param _amount Max repayable amount
    function setRepayableAmount(uint _amount) external;

    // Todo update comment
    /// @notice Transfers the repayable amount to the liquidity provider
    /// @param _amount the amount to repay
    /// @param _to the address of liquidity provider
    function transferRepayment(address _to, uint _amount) external;
}
