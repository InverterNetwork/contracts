// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

interface IBondingCurveFundingManagerBase {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Function is only callable if buying is not already enabled.
    error BondingCurveFundingManager__BuyingAlreadyOpen();

    /// @notice Function is only callable if buying is not already closed.
    error BondingCurveFundingManager__BuyingAlreadyClosed();

    /// @notice Percentage amount is bigger than 100%, i.e. 10_000
    error BondingCurveFundingManager__InvalidFeePercentage();

    /// @notice Deposit amount has to be larger than zero
    error BondingCurveFundingManager__InvalidDepositAmount();

    /// @notice Buying functionalities are set to closed
    error BondingCurveFundingManager__BuyingFunctionaltiesClosed();

    /// @notice Receiver address can not be zero address or
    /// Bonding Curve Funding Manager itself
    error BondingCurveFundingManagerBase__InvalidRecipient();

    /// @notice Actual buy amount is lower than the minimum acceptable amount
    error BondingCurveFundingManagerBase__InsufficientOutputAmount();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when buying is opened
    event BuyingEnabled();

    /// @notice Event emitted when buying is closed
    event BuyingDisabled();

    /// @notice Event emitted when buy fee is updated
    event BuyFeeUpdated(uint indexed newBuyFee, uint indexed oldBuyFee);

    /// @notice Event emitted when tokens have been succesfully issued
    event TokensBought(
        address indexed receiver,
        uint indexed depositAmount,
        uint indexed receivedAmount,
        address buyer
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
}
