// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

/**
 * @title   Inverter Redeeming Bonding Curve Funding Manager Base Interface
 *
 * @notice  Interface that enables the management of the the redemption of
 *          issuance for collateral along a bonding curve in the
 *          Inverter Network, including fee handling and sell functionality control.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer
 *                          to our Security Policy at security.inverter.network
 *                          or email us directly!
 *
 * @custom:version 1.1.3
 *
 * @author  Inverter Network
 */
interface IRedeemingBondingCurveBase_v1 {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Selling functionalities are set to closed.
    error Module__RedeemingBondingCurveBase__SellingFunctionaltiesClosed();

    /// @notice Insufficient collateral tokens are held to cover the project collateral fee.
    error Module__RedeemingBondingCurveBase__InsufficientCollateralForProjectFee(
    );

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when selling is opened.
    event SellingEnabled();

    /// @notice Event emitted when selling is closed.
    event SellingDisabled();

    /// @notice Event emitted when sell fee is updated.
    /// @param  newSellFee The new sell fee.
    /// @param  oldSellFee The old sell fee.
    event SellFeeUpdated(uint newSellFee, uint oldSellFee);

    /// @notice Event emitted when tokens have been succesfully redeemed.
    /// @param  receiver The address that will receive the redeemed tokens.
    /// @param  depositAmount The amount of issued token deposited.
    /// @param  receivedAmount The amount of collateral token received.
    /// @param  seller The address that initiated the sell order.
    event TokensSold(
        address indexed receiver,
        uint depositAmount,
        uint receivedAmount,
        address seller
    );

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Redeem tokens and directs the proceeds to a specified receiver address.
    /// @dev    Executes a sell order, with the proceeds being sent directly to the _receiver's address.
    ///         This function wraps the `_sellOrder` internal function with specified parameters to handle
    ///         the transaction and direct the proceeds.
    /// @param  _receiver The address that will receive the redeemed tokens.
    /// @param  _depositAmount The amount of tokens to be sold.
    /// @param  _minAmountOut The minimum acceptable amount of proceeds that the receiver should receive from the sale.
    function sellTo(address _receiver, uint _depositAmount, uint _minAmountOut)
        external;

    /// @notice Redeem collateral for the sender's address.
    /// @dev	Redirects to the internal function `_sellOrder` by passing the sender's address and deposit amount.
    /// @param  _depositAmount The amount of issued token deposited.
    /// @param  _minAmountOut The minimum acceptable amount the user expects to receive from the transaction.
    function sell(uint _depositAmount, uint _minAmountOut) external;

    /// @notice Opens the selling functionality for the collateral.
    /// @dev    Only callable by the {Orchestrator_v1} admin.
    ///         Reverts if selling is already open.
    function openSell() external;

    /// @notice Closes the selling functionality for the collateral.
    /// @dev    Only callable by the {Orchestrator_v1} admin.
    ///         Reverts if selling is already closed.
    function closeSell() external;

    /// @notice Sets the fee percentage for selling collateral, payed in collateral.
    /// @dev    Only callable by the {Orchestrator_v1} admin.
    ///         The fee cannot exceed 10000 basis points. Reverts if an invalid fee is provided.
    /// @param  _fee The fee in basis points.
    function setSellFee(uint _fee) external;

    /// @notice Calculates and returns the static price for selling the issuance token.
    /// @return uint The static price for selling the issuance token.
    function getStaticPriceForSelling() external view returns (uint);

    /// @notice Calculates the amount of tokens to be redeemed based on a given deposit amount.
    /// @dev    This function takes into account any applicable sell fees before computing the
    ///         collateral amount to be redeemed. Revert when `_depositAmount` is zero.
    /// @param  _depositAmount The amount of tokens deposited by the user.
    /// @return redeemAmount The amount of collateral that will be redeemed as a result of the deposit.
    function calculateSaleReturn(uint _depositAmount)
        external
        returns (uint redeemAmount);
}
