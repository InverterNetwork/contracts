// SPDX-License-Identifier: LGPL-3.0-only

pragma solidity ^0.8.0;

/**
 * @title   Inverter Repayer Interface
 *
 * @notice  This interface enables Repayer functionality. @note This enough? Do we have Documentation where we can get this?
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to
 *                          our Security Policy at security.inverter.network or
 *                          email us directly!
 *
 * @custom:version v1.0.0
 *
 * @custom:inverter-standard-version 0.1.0
 *
 * @author  Inverter Network
 */
interface IRepayer_v1 {
    // -------------------------------------------------------------------------
    // Errors

    /// @notice Amount passed as parameter is higher than repayable amount
    error Repayer__InsufficientCollateralForRepayerTransfer();

    // -------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when the liquidity pool address is updated
    event LiquidityPoolChanged(address newValue, address oldValue);

    /// @notice Event emitted when the repayable amount is updated
    event RepayableAmountChanged(uint newValue, uint oldValue);

    /// @notice Event emitted when a repayment has been transferred
    event RepaymentTransfer(address receiver, uint amount);

    // -------------------------------------------------------------------------
    // Functions

    /// @notice Returns the max repayable amount set in the contract
    /// @return repayableAmount The max repayable amount
    function getRepayableAmount() external returns (uint repayableAmount);

    /// @notice Sets the repayable amount
    /// @param amount_ Max repayable amount
    function setRepayableAmount(uint amount_) external;

    /// @notice Transfers the repayable amount to the liquidity provider
    /// @param amount_ the amount to repay
    /// @param to_ the address of liquidity provider
    function transferRepayment(address to_, uint amount_) external;
}
