// SPDX-License-Identifier: LGPL-3.0-only

pragma solidity ^0.8.0;

import {ILiquidityPool} from
    "src/modules/logicModule/liquidityPool/ILiquidityPool.sol";

interface IRepayer {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Amount passed as parameter is higher than repayable amount
    error Repayer__InsufficientCollateralForRepayerTransfer();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when the liquidity pool address is updated
    event LiquidityPoolChanged(
        ILiquidityPool newValue, ILiquidityPool oldValue
    );

    /// @notice Event emitted when the repayable amount is updated
    event RepayableAmountChanged(uint newValue, uint oldValue);

    /// @notice Event emitted when a repayment has been transferred
    event RepaymentTransfer(address receiver, uint amount);

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Returns the max repayable amount set in the contract
    function getRepayableAmount() external view returns (uint);

    /// @notice Sets the repayable amount
    /// @param _amount Max repayable amount
    function setRepayableAmount(uint _amount) external;

    /// @notice Transfers the repayable amount to the liquidity provider
    /// @param _amount the amount to repay
    /// @param _to the address of liquidity provider
    function transferRepayment(address _to, uint _amount) external;
}
