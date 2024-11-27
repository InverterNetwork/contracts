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

// External Dependencies
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

/**
 * @title   Inverter Redeeming Bonding Curve Funding Manager Base
 *
 * @notice  Manages the redemption of issuance for collateral along a bonding curve in the
 *          Inverter Network, including fee handling and sell functionality control.
 *
 * @dev     Inherits from {BondingCurveBase_v1}. Extends by providing core functionalities for
 *          redeem operations, fee adjustments, and redemption calculations.
 *          Fee calculations utilize BPS for precision. Redeem-specific calculations should be
 *          implemented in derived contracts.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer
 *                          to our Security Policy at security.inverter.network
 *                          or email us directly!
 *
 * @custom:version 1.1.1
 *
 * @author  Inverter Network
 */
abstract contract RedeemingBondingCurveBase_v1 is
    IRedeemingBondingCurveBase_v1,
    BondingCurveBase_v1
{
    /// @inheritdoc ERC165Upgradeable
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

    // -------------------------------------------------------------------------
    // Storage

    /// @dev	Indicates whether the sell functionality is open or not.
    ///         Enabled = true || disabled = false.
    bool public sellIsOpen;
    /// @dev	Sell fee expressed in base points, i.e. 0% = 0; 1% = 100; 10% = 1000.
    uint public sellFee;

    /// @dev    Storage gap for future upgrades.
    uint[50] private __gap;

    // -------------------------------------------------------------------------
    // Modifiers

    /// @dev	Modifier to guarantee the selling functionality is enabled.
    modifier sellingIsEnabled() {
        _sellingIsEnabledModifier();
        _;
    }

    // -------------------------------------------------------------------------
    // Public Functions

    /// @inheritdoc IRedeemingBondingCurveBase_v1
    function sellTo(address _receiver, uint _depositAmount, uint _minAmountOut)
        public
        virtual
        sellingIsEnabled
        validReceiver(_receiver)
    {
        _sellOrder(_receiver, _depositAmount, _minAmountOut);
    }

    /// @inheritdoc IRedeemingBondingCurveBase_v1
    function sell(uint _depositAmount, uint _minAmountOut) public virtual {
        sellTo(_msgSender(), _depositAmount, _minAmountOut);
    }

    // -------------------------------------------------------------------------
    // OnlyOrchestrator Functions

    /// @inheritdoc IRedeemingBondingCurveBase_v1
    function openSell() external virtual onlyOrchestratorAdmin {
        sellIsOpen = true;
        emit SellingEnabled();
    }

    /// @inheritdoc IRedeemingBondingCurveBase_v1
    function closeSell() external virtual onlyOrchestratorAdmin {
        sellIsOpen = false;
        emit SellingDisabled();
    }

    /// @inheritdoc IRedeemingBondingCurveBase_v1
    function setSellFee(uint _fee) external virtual onlyOrchestratorAdmin {
        _setSellFee(_fee);
    }

    /// @inheritdoc IRedeemingBondingCurveBase_v1
    function calculateSaleReturn(uint _depositAmount)
        public
        view
        virtual
        returns (uint redeemAmount)
    {
        // Set min amount out to 1 for price calculation
        _ensureNonZeroTradeParameters(_depositAmount, 1);

        // Get protocol fee percentages
        (
            /* collateralTreasury */
            ,
            /* issuanceTreasury */
            ,
            uint collateralSellFeePercentage,
            uint issuanceSellFeePercentage
        ) = _getFunctionFeesAndTreasuryAddresses(
            bytes4(keccak256(bytes("_sellOrder(address,uint,uint)")))
        );

        // Deduct protocol sell fee from issuance, if applicable
        (_depositAmount, /* protocolFeeAmount */, /* projectFeeAmount */ ) =
        _calculateNetAndSplitFees(_depositAmount, issuanceSellFeePercentage, 0);

        // Calculate redeem amount from formula
        redeemAmount = _redeemTokensFormulaWrapper(_depositAmount);

        // Deduct protocol and project sell fee from collateral, if applicable
        (redeemAmount, /* protocolFeeAmount */, /* projectFeeAmount */ ) =
        _calculateNetAndSplitFees(
            redeemAmount, collateralSellFeePercentage, sellFee
        );

        // Return redeem amount
        // return redeemAmount;
    }

    // -------------------------------------------------------------------------
    // Public Functions Implemented in Downstream Contract

    /// @inheritdoc IRedeemingBondingCurveBase_v1
    function getStaticPriceForSelling() external view virtual returns (uint);

    // -------------------------------------------------------------------------
    // Internal Functions Implemented in Downstream Contract

    /// @dev    Function used for wrapping the call to the external contract responsible for
    ///         calculating the redeeming amount. This function is an abstract function and must be
    ///         implemented in the downstream contract.
    /// @param  _depositAmount The amount of issuing token that is deposited.
    /// @return uint Return the amount of collateral to be redeemed.
    function _redeemTokensFormulaWrapper(uint _depositAmount)
        internal
        view
        virtual
        returns (uint);

    // -------------------------------------------------------------------------
    // Internal Functions

    /// @dev    Executes a sell order by transferring tokens from the receiver to the contract,.
    ///         calculating the redeem amount, and finally transferring the redeem amount back to the receiver.
    ///         This function is internal and not intended for end-user interaction.
    ///         PLEASE NOTE:
    ///         The current implementation only requires that enough collateral token is held for redeeming
    ///         to be possible. No further functionality is implemented which would manages the outflow of
    ///         collateral, e.g., restricting max redeemable amount per user, or a redeemable amount which
    ///         differes from the actual balance.
    ///         Throws an exception if `_depositAmount` is zero or if there's insufficient collateral in the
    ///         contract for redemption.
    /// @param  _receiver The address receiving the redeem amount.
    /// @param  _depositAmount The amount of tokens being sold by the receiver.
    /// @param  _minAmountOut The minimum acceptable amount the user expects to receive from the transaction.
    /// @return totalCollateralTokenMovedOut The total amount of collateral tokens that are transfered away from
    ///         the collateral token amount of this contract.
    /// @return issuanceFeeAmount The amount of issuance token subtracted as fee.
    function _sellOrder(
        address _receiver,
        uint _depositAmount,
        uint _minAmountOut
    )
        internal
        returns (uint totalCollateralTokenMovedOut, uint issuanceFeeAmount)
    {
        _ensureNonZeroTradeParameters(_depositAmount, _minAmountOut);
        // Get protocol fee percentages and treasury addresses
        (
            address collateralTreasury,
            address issuanceTreasury,
            uint collateralSellFeePercentage,
            uint issuanceSellFeePercentage
        ) = _getFunctionFeesAndTreasuryAddresses(
            bytes4(keccak256(bytes("_sellOrder(address,uint,uint)")))
        );

        uint protocolFeeAmount;
        uint projectFeeAmount;
        uint netDeposit;

        // Get net amount, protocol and project fee amounts. Currently there is no issuance project
        // fee enabled
        (netDeposit, protocolFeeAmount, /* projectFee */ ) =
        _calculateNetAndSplitFees(_depositAmount, issuanceSellFeePercentage, 0);

        issuanceFeeAmount = protocolFeeAmount;

        // Calculate redeem amount based on upstream formula
        uint collateralRedeemAmount = _redeemTokensFormulaWrapper(netDeposit);

        totalCollateralTokenMovedOut = collateralRedeemAmount;

        // Burn issued token from user
        _burn(_msgSender(), _depositAmount);

        // Process the protocol fee. We can re-mint some of the burned tokens, since we aren't paying out
        // the backing collateral
        _processProtocolFeeViaMinting(issuanceTreasury, protocolFeeAmount);

        // Cache Collateral Token
        IERC20 collateralToken = __Module_orchestrator.fundingManager().token();

        // Require that enough collateral token is held to be redeemable
        if (
            (collateralRedeemAmount + projectCollateralFeeCollected)
                > collateralToken.balanceOf(address(this))
        ) {
            revert
                Module__RedeemingBondingCurveBase__InsufficientCollateralForRedemption(
            );
        }

        // Get net amount, protocol and project fee amounts
        (collateralRedeemAmount, protocolFeeAmount, projectFeeAmount) =
        _calculateNetAndSplitFees(
            collateralRedeemAmount, collateralSellFeePercentage, sellFee
        );
        // Process the protocol fee
        _processProtocolFeeViaTransfer(
            collateralTreasury, collateralToken, protocolFeeAmount
        );

        // Add project fee if applicable
        if (projectFeeAmount > 0) {
            projectCollateralFeeCollected += projectFeeAmount;
            emit ProjectCollateralFeeAdded(projectFeeAmount);
        } // Add fee amount to total collected fee

        // Revert when the redeem amount is lower than minimum amount the user expects
        if (collateralRedeemAmount < _minAmountOut) {
            revert Module__BondingCurveBase__InsufficientOutputAmount();
        }

        // Use virtual function to handle collateral tokens
        _handleCollateralTokensAfterSell(_receiver, collateralRedeemAmount);

        // Emit event
        emit TokensSold(
            _receiver, _depositAmount, collateralRedeemAmount, _msgSender()
        );
    }

    /// @notice Virtual function to handle collateral tokens after a successful sell.
    /// @param  _receiver  The address for which the collateral tokens will be handled.
    /// @param  _collateralTokenAmount The amount of collateral tokens to handle.
    function _handleCollateralTokensAfterSell(
        address _receiver,
        uint _collateralTokenAmount
    ) internal virtual;

    ///  @dev    Checks if the sell functionality is enabled.
    function _sellingIsEnabledModifier() internal view {
        if (!sellIsOpen) {
            revert
                Module__RedeemingBondingCurveBase__SellingFunctionaltiesClosed();
        }
    }

    /// @dev	Sets the sell transaction fee, expressed in BPS.
    /// @param  _fee The fee percentage to set for sell transactions.
    function _setSellFee(uint _fee) internal virtual {
        _validateProjectFee(_fee);
        emit SellFeeUpdated(_fee, sellFee);
        sellFee = _fee;
    }
}
