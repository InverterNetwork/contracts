// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

interface IBondingCurveBase {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Function is only callable if buying is not already enabled.
    error BondingCurveBase__BuyingAlreadyOpen();

    /// @notice Function is only callable if buying is not already closed.
    error BondingCurveBase__BuyingAlreadyClosed();

    /// @notice Percentage amount is bigger than 100%, i.e. 10_000
    error BondingCurveBase__InvalidFeePercentage();

    /// @notice Deposit amount has to be larger than zero
    error BondingCurveBase__InvalidDepositAmount();

    /// @notice Buying functionalities are set to closed
    error BondingCurveBase__BuyingFunctionaltiesClosed();

    /// @notice Receiver address can not be zero address or
    /// Bonding Curve Funding Manager itself
    error BondingCurveBase__InvalidRecipient();

    /// @notice Actual buy amount is lower than the minimum acceptable amount
    error BondingCurveBase__InsufficientOutputAmount();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when buying is opened
    event BuyingEnabled();

    /// @notice Event emitted when buying is closed
    event BuyingDisabled();

    /// @notice Event emitted when buy fee is updated
    event BuyFeeUpdated(uint indexed newBuyFee, uint indexed oldBuyFee);

    /// @notice Event emitted when tokens have been succesfully issued
    /// @param receiver The address that will receive the issued tokens.
    /// @param depositAmount The amount of collateral token deposited.
    /// @param receivedAmount The amount of issued token received.
    /// @param buyer The address that initiated the buy order.
    event TokensBought(
        address indexed receiver,
        uint indexed depositAmount,
        uint indexed receivedAmount,
        address buyer
    );

    /// @notice Event emitted when the decimals of the issuance token are updated
    /// @param oldDecimals The old decimals of the issuance token
    /// @param newDecimals The new decimals of the issuance token
    event TokenDecimalsUpdated(
        uint8 indexed oldDecimals, uint8 indexed newDecimals
    );

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Buy tokens on behalf of a specified receiver address.
    /// @dev Redirects to the internal function `_buyOrder` by passing the receiver address and deposit amount.
    /// @param _receiver The address that will receive the bought tokens.
    /// @param _depositAmount The amount of collateral token deposited.
    /// @param _minAmountOut The minimum acceptable amount the user expects to receive from the transaction.
    function buyFor(address _receiver, uint _depositAmount, uint _minAmountOut)
        external;

    /// @notice Buy tokens for the sender's address.
    /// @dev Redirects to the internal function `_buyOrder` by passing the sender's address and deposit amount.
    /// @param _depositAmount The amount of collateral token depoisited.
    /// @param _minAmountOut The minimum acceptable amount the user expects to receive from the transaction.
    function buy(uint _depositAmount, uint _minAmountOut) external;

    /// @notice Opens the buying functionality for the token.
    /// @dev Only callable by the Orchestrator owner, or Manager.
    ///      Reverts if buying is already open.
    function openBuy() external;

    /// @notice Closes the buying functionality for the token.
    /// @dev Only callable by the Orchestrator owner, or Manager.
    ///      Reverts if buying is already closed.
    function closeBuy() external;

    /// @notice Sets the fee percentage for buying tokens, payed in collateral
    /// @dev Only callable by the Orchestrator owner, or Manager.
    ///      The fee cannot exceed 10000 basis points. Reverts if an invalid fee is provided.
    /// @param _fee The fee in basis points.
    function setBuyFee(uint _fee) external;

    /// @notice Calculates and returns the static price for buying the issuance token.
    /// @return uint The static price for buying the issuance token.
    function getStaticPriceForBuying() external returns (uint);

    /// @notice Calculates the amount of tokens to be minted based on a given deposit amount.
    /// @dev This function takes into account any applicable buy fees before computing the
    /// token amount to be minted. Revert when depositAmount is zero.
    /// @param _depositAmount The amount of tokens deposited by the user.
    /// @return mintAmount The amount of new tokens that will be minted as a result of the deposit.
    function calculatePurchaseReturn(uint _depositAmount)
        external
        returns (uint mintAmount);

    /// @notice Returns the fee amount for a purchase transaction, based on the buy fee and amount in
    /// @param _amountIn The amount over which the fee is calculated
    /// @return feeAmount Total amount of fee to be paid
    function getPurchaseFeeForAmount(uint _amountIn)
        external
        view
        returns (uint feeAmount);
}
