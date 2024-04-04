// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

interface IRedeemingBondingCurveBase {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Function is only callable if selling is not already enabled.
    error RedeemingBondingCurveBase__SellingAlreadyOpen();

    /// @notice Function is only callable if selling is not already closed.
    error RedeemingBondingCurveBase__SellingAlreadyClosed();

    /// @notice Percentage amount is bigger than 100%, i.e. 10_000
    error RedeemingBondingCurveBase__InvalidFeePercentage();

    /// @notice Deposit amount has to be larger than zero
    error RedeemingBondingCurveBase__InvalidDepositAmount();

    /// @notice Selling functionalities are set to closed
    error RedeemingBondingCurveBase__SellingFunctionaltiesClosed();

    /// @notice Not enough collateral in contract for redemption
    error RedeemingBondingCurveBase__InsufficientCollateralForRedemption();

    /// @notice Actual redeem amount is lower than the minimum acceptable amount
    error RedeemingBondingCurveBase__InsufficientOutputAmount();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when selling is opened
    event SellingEnabled();

    /// @notice Event emitted when selling is closed
    event SellingDisabled();

    /// @notice Event emitted when sell fee is updated
    /// @param newSellFee The new sell fee
    /// @param oldSellFee The old sell fee
    event SellFeeUpdated(uint indexed newSellFee, uint indexed oldSellFee);

    /// @notice Event emitted when tokens have been succesfully redeemed
    /// @param receiver The address that will receive the redeemed tokens.
    /// @param depositAmount The amount of issued token deposited.
    /// @param receivedAmount The amount of collateral token received.
    /// @param seller The address that initiated the sell order.
    event TokensSold(
        address indexed receiver,
        uint indexed depositAmount,
        uint indexed receivedAmount,
        address seller
    );

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Redeem tokens on behalf of a specified receiver address.
    /// @dev Redirects to the internal function `_sellOrder` by passing the receiver address and deposit amount.
    /// @param _receiver The address that will receive the redeemed tokens.
    /// @param _depositAmount The amount of issued token to deposited.
    /// @param _minAmountOut The minimum acceptable amount the user expects to receive from the transaction.
    function sellFor(address _receiver, uint _depositAmount, uint _minAmountOut)
        external;

    /// @notice Sell collateral for the sender's address.
    /// @dev Redirects to the internal function `_sellOrder` by passing the sender's address and deposit amount.
    /// @param _depositAmount The amount of issued token deposited.
    /// @param _minAmountOut The minimum acceptable amount the user expects to receive from the transaction.
    function sell(uint _depositAmount, uint _minAmountOut) external;

    /// @notice Opens the selling functionality for the collateral.
    /// @dev Only callable by the Orchestrator owner, or Manager.
    ///      Reverts if selling is already open.
    function openSell() external;

    /// @notice Closes the selling functionality for the collateral.
    /// @dev Only callable by the Orchestrator owner, or Manager.
    ///      Reverts if selling is already closed.
    function closeSell() external;

    /// @notice Sets the fee percentage for selling collateral, payed in collateral
    /// @dev Only callable by the Orchestrator owner, or Manager.
    ///      The fee cannot exceed 10000 basis points. Reverts if an invalid fee is provided.
    /// @param _fee The fee in basis points.
    function setSellFee(uint _fee) external;

    /// @notice Calculates and returns the static price for selling the issuance token.
    /// @return uint The static price for selling the issuance token.
    function getStaticPriceForSelling() external returns (uint);

    /// @notice Calculates the amount of tokens to be redeemed based on a given deposit amount.
    /// @dev This function takes into account any applicable sell fees before computing the
    /// collateral amount to be redeemed. Revert when depositAmount is zero.
    /// @param _depositAmount The amount of tokens deposited by the user.
    /// @return redeemAmount The amount of collateral that will be redeemed as a result of the deposit.
    function calculateSaleReturn(uint _depositAmount)
        external
        returns (uint redeemAmount);

    /// @notice Returns the fee amount for a sale transaction, based on the sell fee and amount in
    /// @param _amountIn The amount over which the fee is calculated
    /// @return feeAmount Total amount of fee to be paid
    function getSaleFeeForAmount(uint _amountIn)
        external
        view
        returns (uint feeAmount);
}
