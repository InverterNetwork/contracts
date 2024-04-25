// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

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
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(BondingCurveFundingManagerBase)
        returns (bool)
    {
        return interfaceId
            == type(IRedeemingBondingCurveFundingManagerBase).interfaceId
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
                RedeemingBondingCurveFundingManager__SellingFunctionaltiesClosed();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Public Functions

    /// @inheritdoc IRedeemingBondingCurveFundingManagerBase
    function sellFor(address _receiver, uint _depositAmount, uint _minAmountOut)
        external
        virtual
        sellingIsEnabled
        validReceiver(_receiver)
    {
        _sellOrder(_receiver, _depositAmount, _minAmountOut);
    }

    /// @inheritdoc IRedeemingBondingCurveFundingManagerBase
    function sell(uint _depositAmount, uint _minAmountOut)
        external
        virtual
        sellingIsEnabled
    {
        _sellOrder(_msgSender(), _depositAmount, _minAmountOut);
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
    // Public Functions Implemented in Downstream Contract

    /// @inheritdoc IRedeemingBondingCurveFundingManagerBase
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
    /// @return totalCollateralTokenMovedOut The total amount of collateral tokens that are transfered away from this contract.
    /// @return issuanceFeeAmount The amount of issuance token subtracted as fee
    function _sellOrder(
        address _receiver,
        uint _depositAmount,
        uint _minAmountOut
    )
        internal
        returns (uint totalCollateralTokenMovedOut, uint issuanceFeeAmount)
    {
        if (_depositAmount == 0) {
            revert RedeemingBondingCurveFundingManager__InvalidDepositAmount();
        }
        // Get protocol fee percentages and treasury addresses
        (
            address collateralreasury,
            address issuanceTreasury,
            uint collateralSellFeePercentage,
            uint issuanceSellFeePercentage
        ) = _getSellFeesAndTreasuryAddresses();

        uint protocolFeeAmount;
        uint workflowFeeAmount;
        uint netDeposit;

        // Get net amount, protocol and workflow fee amounts. Currently there is no issuance project
        // fee enabled
        (netDeposit, protocolFeeAmount, /* workflowFee */ ) =
        _calculateNetAndSplitFees(_depositAmount, issuanceSellFeePercentage, 0);
        // Process the protocol fee
        _processProtocolFeeViaMinting(issuanceTreasury, protocolFeeAmount);
        // Calculate redeem amount based on upstream formula
        uint collateralRedeemAmount = _redeemTokensFormulaWrapper(netDeposit);

        totalCollateralTokenMovedOut = collateralRedeemAmount;

        // Burn issued token from user
        _burn(_msgSender(), _depositAmount);

        // Require that enough collateral token is held to be redeemable
        if (
            collateralRedeemAmount
                > __Module_orchestrator.fundingManager().token().balanceOf(
                    address(this)
                )
        ) {
            revert
                RedeemingBondingCurveFundingManager__InsufficientCollateralForRedemption(
            );
        }

        // Get net amount, protocol and workflow fee amounts
        (collateralRedeemAmount, protocolFeeAmount, workflowFeeAmount) =
        _calculateNetAndSplitFees(
            collateralRedeemAmount, collateralSellFeePercentage, sellFee
        );
        // Process the protocol fee
        _processProtocolFeeViaTransfer(
            collateralreasury,
            __Module_orchestrator.fundingManager().token(),
            protocolFeeAmount
        );

        // Add workflow fee if applicable
        if (workflowFeeAmount > 0) tradeFeeCollected += workflowFeeAmount; // Add fee amount to total collected fee

        // Revert when the redeem amount is lower than minimum amount the user expects
        if (collateralRedeemAmount < _minAmountOut) {
            revert RedeemingBondingCurveFundingManager__InsufficientOutputAmount(
            );
        }
        // Transfer tokens to receiver
        __Module_orchestrator.fundingManager().token().transfer(
            _receiver, collateralRedeemAmount
        );
        // Emit event
        emit TokensSold(
            _receiver, _depositAmount, collateralRedeemAmount, _msgSender()
        );
    }

    /// @dev Opens the sell functionality by setting the state variable `sellIsOpen` to true.
    function _openSell() internal {
        if (sellIsOpen == true) {
            revert RedeemingBondingCurveFundingManager__SellingAlreadyOpen();
        }
        sellIsOpen = true;
        emit SellingEnabled();
    }

    /// @dev Closes the sell functionality by setting the state variable `sellIsOpen` to false.
    function _closeSell() internal {
        if (sellIsOpen == false) {
            revert RedeemingBondingCurveFundingManager__SellingAlreadyClosed();
        }
        sellIsOpen = false;
        emit SellingDisabled();
    }

    /// @dev Sets the sell transaction fee, expressed in BPS.
    /// @param _fee The fee percentage to set for sell transactions.
    function _setSellFee(uint _fee) internal {
        if (_fee > BPS) {
            revert RedeemingBondingCurveFundingManager__InvalidFeePercentage();
        }
        emit SellFeeUpdated(_fee, sellFee);
        sellFee = _fee;
    }

    /// @dev Returns the collateral and issuance fee percentage retrieved from the fee manager for
    ///     sell operations
    /// @return collateralTreasury The address the protocol fee in collateral should be sent to
    /// @return issuanceTreasury The address the protocol fee in issuance should be sent to
    /// @return collateralSellFeePercentage The percentage fee to be collected from the collateral
    ///     token being redeemed, expressed in BPS
    /// @return issuanceSellFeePercentage The percentage fee to be collected from the issuance token
    ///     being deposited, expressed in BPS
    function _getSellFeesAndTreasuryAddresses()
        internal
        virtual
        returns (
            address collateralTreasury,
            address issuanceTreasury,
            uint collateralSellFeePercentage,
            uint issuanceSellFeePercentage
        )
    {
        (collateralSellFeePercentage, collateralTreasury) =
        getFeeManagerCollateralFeeData(
            bytes4(keccak256(bytes("_sellOrder(address, uint, uint)")))
        );
        (issuanceSellFeePercentage, issuanceTreasury) =
        getFeeManagerIssuanceFeeData(
            bytes4(keccak256(bytes("_sellOrder(address, uint, uint)")))
        );
    }
}
