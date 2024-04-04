// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Dependencies
import {BondingCurveBase} from
    "src/modules/fundingManager/bondingCurve/abstracts/BondingCurveBase.sol";
import {IRedeemingBondingCurveBase} from
    "src/modules/fundingManager/bondingCurve/interfaces/IRedeemingBondingCurveBase.sol";
// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

/// @title Redeeming Bonding Curve Funding Manager Base Contract.
/// @author Inverter Network.
/// @notice This contract enables the base functionalities for redeeming issued tokens for collateral
/// tokens along a bonding curve.
/// @dev The contract implements functionalties for:
///         - opening and closing the redeeming of collateral tokens.
///         - setting and subtracting of fees, expressed in BPS and subtracted from the collateral.
///         - calculating the redeeming amount by means of an abstract function to be implemented in
///             the downstream contract.
abstract contract RedeemingBondingCurveBase is
    IRedeemingBondingCurveBase,
    BondingCurveBase
{
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(BondingCurveBase)
        returns (bool)
    {
        return interfaceId == type(IRedeemingBondingCurveBase).interfaceId
            || super.supportsInterface(interfaceId);
    }

    using SafeERC20 for IERC20;

    //--------------------------------------------------------------------------
    // Storage

    /// @dev Indicates whether the sell functionality is open or not.
    ///      Enabled = true || disabled = false.
    bool public sellIsOpen;
    /// @dev Sell fee expressed in base points, i.e. 0% = 0; 1% = 100; 10% = 1000
    uint public sellFee;

    //--------------------------------------------------------------------------
    // Modifiers

    modifier sellingIsEnabled() {
        if (sellIsOpen == false) {
            revert RedeemingBondingCurveBase__SellingFunctionaltiesClosed();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Public Functions

    /// @inheritdoc IRedeemingBondingCurveBase
    function sellFor(address _receiver, uint _depositAmount, uint _minAmountOut)
        external
        virtual
        sellingIsEnabled
        validReceiver(_receiver)
    {
        _sellOrder(_receiver, _depositAmount, _minAmountOut);
    }

    /// @inheritdoc IRedeemingBondingCurveBase
    function sell(uint _depositAmount, uint _minAmountOut)
        external
        virtual
        sellingIsEnabled
    {
        _sellOrder(_msgSender(), _depositAmount, _minAmountOut);
    }

    /// @inheritdoc IRedeemingBondingCurveBase
    function calculateSaleReturn(uint _depositAmount)
        external
        view
        virtual
        returns (uint redeemAmount)
    {
        return _calculateSaleReturn(_depositAmount);
    }

    /// @inheritdoc IRedeemingBondingCurveBase
    function getSaleFeeForAmount(uint _amountIn)
        external
        view
        virtual
        returns (uint feeAmount)
    {
        ( /* netAmount */ , feeAmount) =
            _calculateNetAmountAndFee(_amountIn, sellFee);
    }

    //--------------------------------------------------------------------------
    // OnlyOrchestrator Functions

    /// @inheritdoc IRedeemingBondingCurveBase
    function openSell() external virtual onlyOrchestratorOwner {
        _openSell();
    }

    /// @inheritdoc IRedeemingBondingCurveBase
    function closeSell() external virtual onlyOrchestratorOwner {
        _closeSell();
    }

    /// @inheritdoc IRedeemingBondingCurveBase
    function setSellFee(uint _fee) external virtual onlyOrchestratorOwner {
        _setSellFee(_fee);
    }

    //--------------------------------------------------------------------------
    // Public Functions Implemented in Downstream Contract

    /// @inheritdoc IRedeemingBondingCurveBase
    function getStaticPriceForSelling() external virtual returns (uint);

    //--------------------------------------------------------------------------
    // Internal Functions Implemented in Downstream Contract

    /// @dev Function used for wrapping the call to the external contract responsible for
    /// calculating the redeeming amount. This function is an abstract function and must be
    /// implemented in the downstream contract.
    /// @param _depositAmount The amount of issuing token that is deposited
    /// @return uint Return the amount of collateral to be redeemed
    function _redeemTokensFormulaWrapper(uint _depositAmount)
        internal
        view
        virtual
        returns (uint);

    //--------------------------------------------------------------------------
    // Internal Functions

    /// @dev Executes a sell order by transferring tokens from the receiver to the contract,
    /// calculating the redeem amount, and finally transferring the redeem amount back to the receiver.
    /// This function is internal and not intended for end-user interaction.
    /// PLEASE NOTE:
    /// The current implementation only requires that enough collateral token is held for redeeming
    /// to be possible. No further functionality is implemented which would manages the outflow of
    /// collateral, e.g., restricting max redeemable amount per user, or a redeemable amount which
    /// differes from the actual balance.
    /// Throws an exception if `_depositAmount` is zero or if there's insufficient collateral in the
    /// contract for redemption.
    /// @param _receiver The address receiving the redeem amount.
    /// @param _depositAmount The amount of tokens being sold by the receiver.
    /// @param _minAmountOut The minimum acceptable amount the user expects to receive from the transaction.
    /// @return redeemAmount The amount of tokens that are transfered to the receiver in exchange for _depositAmount.
    /// @return feeAmount The amount of collateral token subtracted as fee
    function _sellOrder(
        address _receiver,
        uint _depositAmount,
        uint _minAmountOut
    ) internal virtual returns (uint redeemAmount, uint feeAmount) {
        if (_depositAmount == 0) {
            revert RedeemingBondingCurveBase__InvalidDepositAmount();
        }
        // Calculate redeem amount based on upstream formula
        redeemAmount = _redeemTokensFormulaWrapper(_depositAmount);

        // Burn issued token from user
        _burn(_msgSender(), _depositAmount);

        if (sellFee > 0) {
            // Calculate fee amount and redeem amount subtracted by fee
            (redeemAmount, feeAmount) =
                _calculateNetAmountAndFee(redeemAmount, sellFee);
            // Add fee amount to total collected fee
            totalCollateralTradeFeeCollected += feeAmount;
        }
        // Revert when the redeem amount is lower than minimum amount the user expects
        if (redeemAmount < _minAmountOut) {
            revert RedeemingBondingCurveBase__InsufficientOutputAmount();
        }
        // Require that enough collateral token is held to be redeemable
        if (
            redeemAmount + totalCollateralTradeFeeCollected
                > __Module_orchestrator.fundingManager().token().balanceOf(
                    address(this)
                )
        ) {
            revert
                RedeemingBondingCurveBase__InsufficientCollateralForRedemption();
        }
        // Transfer tokens to receiver
        __Module_orchestrator.fundingManager().token().transfer(
            _receiver, redeemAmount
        );
        // Emit event
        emit TokensSold(_receiver, _depositAmount, redeemAmount, _msgSender());
    }

    /// @dev Opens the sell functionality by setting the state variable `sellIsOpen` to true.
    function _openSell() internal virtual {
        if (sellIsOpen == true) {
            revert RedeemingBondingCurveBase__SellingAlreadyOpen();
        }
        sellIsOpen = true;
        emit SellingEnabled();
    }

    /// @dev Closes the sell functionality by setting the state variable `sellIsOpen` to false.
    function _closeSell() internal virtual {
        if (sellIsOpen == false) {
            revert RedeemingBondingCurveBase__SellingAlreadyClosed();
        }
        sellIsOpen = false;
        emit SellingDisabled();
    }

    /// @dev Sets the sell transaction fee, expressed in BPS.
    /// @param _fee The fee percentage to set for sell transactions.
    function _setSellFee(uint _fee) internal virtual {
        if (_fee > BPS) {
            revert RedeemingBondingCurveBase__InvalidFeePercentage();
        }
        emit SellFeeUpdated(_fee, sellFee);
        sellFee = _fee;
    }

    /// @dev This function takes into account any applicable sell fees before computing the
    /// collateral amount to be redeemed. Revert when depositAmount is zero.
    /// @param _depositAmount The amount of tokens deposited by the user.
    /// @return redeemAmount The amount of collateral that will be redeemed as a result of the deposit.
    function _calculateSaleReturn(uint _depositAmount)
        internal
        view
        virtual
        returns (uint redeemAmount)
    {
        if (_depositAmount == 0) {
            revert RedeemingBondingCurveBase__InvalidDepositAmount();
        }
        redeemAmount = _redeemTokensFormulaWrapper(_depositAmount);
        if (sellFee > 0) {
            (redeemAmount, /* feeAmount */ ) =
                _calculateNetAmountAndFee(redeemAmount, sellFee);
        }
        return redeemAmount;
    }

    /// @dev Redeems collateral based on the deposit amount.
    /// This function utilizes another internal function, `_redeemTokensFormulaWrapper`,
    /// to determine how many collateral tokens should be redeemed.
    /// @param _depositAmount The amount of issued tokens deposited for which collateral are to
    /// be redeemed.
    /// @return redeemAmount The number of collateral tokens to be redeemed.
    function _redeemTokens(uint _depositAmount)
        internal
        view
        returns (uint redeemAmount)
    {
        redeemAmount = _redeemTokensFormulaWrapper(_depositAmount);
    }
}
