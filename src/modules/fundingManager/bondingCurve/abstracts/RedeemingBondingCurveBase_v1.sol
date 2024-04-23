// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IRedeemingBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IRedeemingBondingCurveBase_v1.sol";

// Internal Dependencies
import {BondingCurveBase_v1} from
    "@fm/bondingCurve/abstracts/BondingCurveBase_v1.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

/**
 * @title   Redeeming Bonding Curve Funding Manager Base
 *
 * @notice  Manages the redemption of issuance for collateral along a bonding curve in the
 *          Inverter Network, including fee handling and sell functionality control.
 *
 * @dev     Inherits from {BondingCurveBase_v1}. Extends by providing core functionalities for
 *          redeem operations, fee adjustments, and redemption calculations.
 *          Fee calculations utilize BPS for precision. Redeem-specific calculations should be
 *          implemented in derived contracts.
 *
 * @author  Inverter Network
 */
abstract contract RedeemingBondingCurveBase_v1 is
    IRedeemingBondingCurveBase_v1,
    BondingCurveBase_v1
{
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(BondingCurveBase_v1)
        returns (bool)
    {
        return interfaceId == type(IRedeemingBondingCurveBase_v1).interfaceId
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
            revert
                Module__RedeemingBondingCurveBase__SellingFunctionaltiesClosed();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Public Functions

    /// @inheritdoc IRedeemingBondingCurveBase_v1
    function sellFor(address _receiver, uint _depositAmount, uint _minAmountOut)
        external
        virtual
        sellingIsEnabled
        validReceiver(_receiver)
    {
        _sellOrder(_receiver, _depositAmount, _minAmountOut);
    }

    /// @inheritdoc IRedeemingBondingCurveBase_v1
    function sell(uint _depositAmount, uint _minAmountOut)
        external
        virtual
        sellingIsEnabled
    {
        _sellOrder(_msgSender(), _depositAmount, _minAmountOut);
    }

    //--------------------------------------------------------------------------
    // OnlyOrchestrator Functions

    /// @inheritdoc IRedeemingBondingCurveBase_v1
    function openSell() external onlyOrchestratorOwner {
        _openSell();
    }

    /// @inheritdoc IRedeemingBondingCurveBase_v1
    function closeSell() external onlyOrchestratorOwner {
        _closeSell();
    }

    /// @inheritdoc IRedeemingBondingCurveBase_v1
    function setSellFee(uint _fee) external onlyOrchestratorOwner {
        _setSellFee(_fee);
    }

    //--------------------------------------------------------------------------
    // Public Functions Implemented in Downstream Contract

    /// @inheritdoc IRedeemingBondingCurveBase_v1
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
    ) internal returns (uint redeemAmount, uint feeAmount) {
        if (_depositAmount == 0) {
            revert Module__RedeemingBondingCurveBase__InvalidDepositAmount();
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
            tradeFeeCollected += feeAmount;
        }
        // Revert when the redeem amount is lower than minimum amount the user expects
        if (redeemAmount < _minAmountOut) {
            revert Module__RedeemingBondingCurveBase__InsufficientOutputAmount();
        }
        // Require that enough collateral token is held to be redeemable
        if (
            redeemAmount
                > __Module_orchestrator.fundingManager().token().balanceOf(
                    address(this)
                )
        ) {
            revert
                Module__RedeemingBondingCurveBase__InsufficientCollateralForRedemption(
            );
        }
        // Transfer tokens to receiver
        __Module_orchestrator.fundingManager().token().transfer(
            _receiver, redeemAmount
        );
        // Emit event
        emit TokensSold(_receiver, _depositAmount, redeemAmount, _msgSender());
    }

    /// @dev Opens the sell functionality by setting the state variable `sellIsOpen` to true.
    function _openSell() internal {
        if (sellIsOpen == true) {
            revert Module__RedeemingBondingCurveBase__SellingAlreadyOpen();
        }
        sellIsOpen = true;
        emit SellingEnabled();
    }

    /// @dev Closes the sell functionality by setting the state variable `sellIsOpen` to false.
    function _closeSell() internal {
        if (sellIsOpen == false) {
            revert Module__RedeemingBondingCurveBase__SellingAlreadyClosed();
        }
        sellIsOpen = false;
        emit SellingDisabled();
    }

    /// @dev Sets the sell transaction fee, expressed in BPS.
    /// @param _fee The fee percentage to set for sell transactions.
    function _setSellFee(uint _fee) internal {
        if (_fee > BPS) {
            revert Module__RedeemingBondingCurveBase__InvalidFeePercentage();
        }
        emit SellFeeUpdated(_fee, sellFee);
        sellFee = _fee;
    }
}
