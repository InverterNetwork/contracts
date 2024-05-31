// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

interface IBondingCurveBase_v1 {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Function is only callable if buying is not already enabled.
    error Module__BondingCurveBase__BuyingAlreadyOpen();

    /// @notice Function is only callable if buying is not already closed.
    error Module__BondingCurveBase__BuyingAlreadyClosed();

    /// @notice Percentage amount is bigger than 100%, i.e. 10_000
    error Module__BondingCurveBase__InvalidFeePercentage();

    /// @notice Deposit amount has to be larger than zero
    error Module__BondingCurveBase__InvalidDepositAmount();

    /// @notice Buying functionalities are set to closed
    error Module__BondingCurveBase__BuyingFunctionaltiesClosed();

    /// @notice Receiver address can not be zero address or
    /// Bonding Curve Funding Manager itself
    error Module__BondingCurveBase__InvalidRecipient();

    /// @notice Actual buy amount is lower than the minimum acceptable amount
    error Module__BondingCurveBase__InsufficientOutputAmount();

    /// @notice The combination of protocol fee and workflow fee cant be higher than 100%
    error Module__BondingCurveBase__FeeAmountToHigh();

    /// @notice Withdrawl amount is bigger than project fee collected
    error Module__BondingCurveBase__InvalidWithdrawAmount();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when buying is opened
    event BuyingEnabled();

    /// @notice Event emitted when buying is closed
    event BuyingDisabled();

    /// @notice Event emitted when buy fee is updated
    event BuyFeeUpdated(uint newBuyFee, uint oldBuyFee);

    /// @notice Event emitted when the issuance token is updated
    event IssuanceTokenUpdated(
        address indexed oldToken, address indexed issuanceToken
    );

    /// @notice Event emitted when project collateral fee is withdrawn
    event ProjectCollateralFeeWithdrawn(address receiver, uint amount);

    /// @notice Event emitted when tokens have been succesfully issued
    /// @param receiver The address that will receive the issued tokens.
    /// @param depositAmount The amount of collateral token deposited.
    /// @param receivedAmount The amount of issued token received.
    /// @param buyer The address that initiated the buy order.
    event TokensBought(
        address indexed receiver,
        uint depositAmount,
        uint receivedAmount,
        address buyer
    );

    /// @notice Event emitted when the decimals of the issuance token are updated
    /// @param oldDecimals The old decimals of the issuance token
    /// @param newDecimals The new decimals of the issuance token
    event TokenDecimalsUpdated(
        uint8 indexed oldDecimals, uint8 indexed newDecimals
    );

    /// @notice Event emitted when protocol fee has been minted to the treasury
    /// @param token The token minted as protocol fee
    /// @param treasury The protocol treasury address receiving the token fee amount
    /// @param feeAmount The fee amount minted to the treasury
    event ProtocolFeeMinted(
        address indexed token, address indexed treasury, uint feeAmount
    );

    /// @notice Event emitted when protocol fee has been transferred to the treasury
    /// @param token The token received as protocol fee
    /// @param treasury The protocol treasury address receiving the token fee amount
    /// @param feeAmount The fee amount transferred to the treasury
    event ProtocolFeeTransferred(
        address indexed token, address indexed treasury, uint feeAmount
    );

    //--------------------------------------------------------------------------
    // Structs
    struct IssuanceToken {
        string name; // The name of the issuance token
        string symbol; // The symbol of the issuance token
        uint8 decimals; // The decimals used within the issuance token
        uint maxSupply; // The maximum supply of the issuance token
    }

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
    /// @dev Only callable by the Orchestrator_v1 owner.
    ///      Reverts if buying is already open.
    function openBuy() external;

    /// @notice Closes the buying functionality for the token.
    /// @dev Only callable by the Orchestrator_v1 owner.
    ///      Reverts if buying is already closed.
    function closeBuy() external;

    /// @notice Sets the fee percentage for buying tokens, payed in collateral
    /// @dev Only callable by the Orchestrator_v1 owner.
    ///      The fee cannot exceed 10000 basis points. Reverts if an invalid fee is provided.
    /// @param _fee The fee in basis points.
    function setBuyFee(uint _fee) external;

    /// @notice Calculates and returns the static price for buying the issuance token.
    /// @return uint The static price for buying the issuance token.
    function getStaticPriceForBuying() external view returns (uint);

    /// @notice Calculates the amount of tokens to be minted based on a given deposit amount.
    /// @dev This function takes into account any applicable buy fees before computing the
    /// token amount to be minted. Revert when depositAmount is zero.
    /// @param _depositAmount The amount of tokens deposited by the user.
    /// @return mintAmount The amount of new tokens that will be minted as a result of the deposit.
    function calculatePurchaseReturn(uint _depositAmount)
        external
        returns (uint mintAmount);

    /// @notice Withdraw project collateral fee to the receiver address
    function withdrawProjectCollateralFee(address _receiver, uint _amount)
        external;
}
