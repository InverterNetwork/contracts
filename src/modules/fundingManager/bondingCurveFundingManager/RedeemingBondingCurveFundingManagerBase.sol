// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

// Internal Dependencies
import {BondingCurveFundingManagerBase} from
    "src/modules/fundingManager/bondingCurveFundingManager/BondingCurveFundingManagerBase.sol";
import {IRedeemingBondingCurveFundingManagerBase} from
    "src/modules/fundingManager/bondingCurveFundingManager/IRedeemingBondingCurveFundingManagerBase.sol";
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
abstract contract RedeemingBondingCurveFundingManagerBase is
    IRedeemingBondingCurveFundingManagerBase,
    BondingCurveFundingManagerBase
{
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
                RedeemingBondingCurveFundingManager__SellingFunctionaltiesClosed();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Public Functions

    /// @inheritdoc IRedeemingBondingCurveFundingManagerBase
    function sellOrderFor(address _receiver, uint _depositAmount)
        external
        payable
        virtual
        sellingIsEnabled
        validReceiver(_receiver)
    {
        _sellOrder(_receiver, _depositAmount);
    }

    /// @inheritdoc IRedeemingBondingCurveFundingManagerBase
    function sellOrder(uint _depositAmount)
        external
        payable
        virtual
        sellingIsEnabled
    {
        _sellOrder(_msgSender(), _depositAmount);
    }

    //--------------------------------------------------------------------------
    // OnlyOrchestrator Functions

    /// @inheritdoc IRedeemingBondingCurveFundingManagerBase
    function openSell() external onlyOrchestratorOwner {
        _openSell();
    }

    /// @inheritdoc IRedeemingBondingCurveFundingManagerBase
    function closeSell() external onlyOrchestratorOwner {
        _closeSell();
    }

    /// @inheritdoc IRedeemingBondingCurveFundingManagerBase
    function setSellFee(uint _fee) external onlyOrchestratorOwner {
        _setSellFee(_fee);
    }

    //--------------------------------------------------------------------------
    // Internal Functions Implemented in Downstream Contract

    /// @dev Function used for wrapping the call to the external contract responsible for
    /// calculating the redeeming amount. This function is an abstract function and must be
    /// implemented in the downstream contract.
    /// @param _depositAmount The amount of issuing token that is deposited
    /// @return uint Return the amount of collateral to be redeemed
    function _redeemTokensFormulaWrapper(uint _depositAmount)
        internal
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
    /// @param _receiver The address receiving the redeem amount after the sell order is processed.
    /// @param _depositAmount The amount of tokens being sold by the receiver.
    /// @return redeemAmount The amount of tokens the receiver will get after selling `_depositAmount`.
    /// Throws an exception if `_depositAmount` is zero or if there's insufficient collateral in the
    /// contract for redemption.
    function _sellOrder(address _receiver, uint _depositAmount)
        internal
        returns (uint redeemAmount)
    {
        if (_depositAmount == 0) {
            revert RedeemingBondingCurveFundingManager__InvalidDepositAmount();
        }
        // Transfer issued token to contract, confirming deposit amount == allowance
        IERC20(address(this)).safeTransferFrom(
            _msgSender(),
            address(this),
            _depositAmount // bugfix @review
        );
        // Calculate redeem amount based on upstream formula
        redeemAmount = _redeemTokens(_depositAmount);
        // Subtract fee from redeem amount
        if (sellFee > 0) {
            redeemAmount =
                _calculateFeeDeductedDepositAmount(redeemAmount, sellFee); //bugfix @review (not really, pretty clear cut bug)
        }
        // Require that enough collateral token is held to be redeemable
        if (
            redeemAmount
                > __Module_orchestrator.token().balanceOf(address(this))
        ) {
            revert
                RedeemingBondingCurveFundingManager__InsufficientCollateralForRedemption(
            );
        }
        // Transfer tokens to receiver
        __Module_orchestrator.token().transfer(_receiver, redeemAmount);
    }

    /// @dev Opens the sell functionality by setting the state variable `sellIsOpen` to true.
    function _openSell() internal {
        if (sellIsOpen == true) {
            revert RedeemingBondingCurveFundingManager__SellingAlreadyOpen(); // bugfix @review oversight?
        }
        sellIsOpen = true;
    }

    /// @dev Closes the sell functionality by setting the state variable `sellIsOpen` to false.
    function _closeSell() internal {
        if (sellIsOpen == false) {
            revert RedeemingBondingCurveFundingManager__SellingAlreadyClosed(); // bugfix @review oversight?
        }
        sellIsOpen = false;
    }

    /// @dev Sets the sell transaction fee, expressed in BPS.
    /// @param _fee The fee percentage to set for sell transactions.
    function _setSellFee(uint _fee) internal {
        if (_fee > BPS) {
            revert RedeemingBondingCurveFundingManager__InvalidFeePercentage();
        }
        sellFee = _fee;
    }

    /// @dev Redeems collateral based on the deposit amount.
    /// This function utilizes another internal function, `_redeemTokensFormulaWrapper`,
    /// to determine how many collateral tokens should be redeemed.
    /// @param _depositAmount The amount of issued tokens deposited for which collateral are to
    /// be redeemed.
    /// @return redeemAmount The number of collateral tokens to be redeemed.
    function _redeemTokens(uint _depositAmount)
        internal
        returns (uint redeemAmount)
    {
        redeemAmount = _redeemTokensFormulaWrapper(_depositAmount);
    }
}
