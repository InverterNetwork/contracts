// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IFM_BC_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";
import {IERC20Issuance_v1} from "@ex/token/IERC20Issuance_v1.sol";

// Internal Dependencies
import {ERC165Upgradeable, Module_v1} from "src/modules/base/Module_v1.sol";

import {
    IBondingCurveBase_v1,
    BondingCurveBase_v1
} from "@fm/bondingCurve/abstracts/BondingCurveBase_v1.sol";
import {
    IRedeemingBondingCurveBase_v1,
    RedeemingBondingCurveBase_v1
} from "@fm/bondingCurve/abstracts/RedeemingBondingCurveBase_v1.sol";
import {
    IVirtualCollateralSupplyBase_v1,
    VirtualCollateralSupplyBase_v1
} from "@fm/bondingCurve/abstracts/VirtualCollateralSupplyBase_v1.sol";
import {
    IVirtualIssuanceSupplyBase_v1,
    VirtualIssuanceSupplyBase_v1
} from "@fm/bondingCurve/abstracts/VirtualIssuanceSupplyBase_v1.sol";
import {IBancorFormula} from "@fm/bondingCurve/interfaces/IBancorFormula.sol";
import {ERC20Issuance_v1} from "@ex/token/ERC20Issuance_v1.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@oz/token/ERC20/extensions/IERC20Metadata.sol";

// External Dependencies
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

// Libraries
import {FM_BC_Tools} from "@fm/bondingCurve/FM_BC_Tools.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

/**
 * @title   Inverter Bancor Virtual Supply Bonding Curve Funding Manager
 *
 * @notice  This contract enables the issuance and redeeming of tokens on a
 *          bonding curve, using a virtual supply for both the issuance and
 *          the collateral as input. It integrates Aragon's {BancorFormula}
 *          to manage the calculations for token issuance and redemption rates
 *          based on specified reserve ratios.
 *
 * @dev     Inherits {BondingCurveBase_v1}, {RedeemingBondingCurveBase_v1},
 *          {VirtualIssuanceSupplyBase_v1}, and
 *          {VirtualCollateralSupplyBase_v1}. Implements formulaWrapper
 *          functions for bonding curve calculations using the {BancorFormula}.
 *          {Orchestrator_v1} Admin manages configuration such as virtual
 *          supplies and reserve ratios. Ensure interaction adheres to defined
 *          transactional limits and decimal precision requirements to prevent
 *          computational overflows or underflows.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer
 *                          to our Security Policy at security.inverter.network
 *                          or email us directly!
 *
 * @custom:version 1.1.0
 *
 * @author  Inverter Network
 */
contract FM_BC_Bancor_Redeeming_VirtualSupply_v1 is
    IFM_BC_Bancor_Redeeming_VirtualSupply_v1,
    IFundingManager_v1,
    VirtualIssuanceSupplyBase_v1,
    VirtualCollateralSupplyBase_v1,
    RedeemingBondingCurveBase_v1
{
    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(
            VirtualIssuanceSupplyBase_v1,
            VirtualCollateralSupplyBase_v1,
            RedeemingBondingCurveBase_v1
        )
        returns (bool)
    {
        return interfaceId
            == type(IFM_BC_Bancor_Redeeming_VirtualSupply_v1).interfaceId
            || interfaceId == type(IFundingManager_v1).interfaceId
            || super.supportsInterface(interfaceId);
    }

    using SafeERC20 for IERC20;

    //--------------------------------------------------------------------------
    // Storage

    /// @dev    The interface of the Bancor Formula used to calculate the issuance and redeeming amount.
    IBancorFormula public formula;
    /// @dev    Value is used to convert deposit amount to 18 decimals, which is required by the {BancorFormula}.
    ///         which is required by the Bancor formula.
    uint8 private constant eighteenDecimals = 18;
    /// @dev    Parts per million used for calculation the reserve ratio for the Bancor formula.
    uint32 internal constant PPM = 1_000_000;
    /// @dev    The reserve ratio for buying determines the rate of price growth. It is a measure of the fraction
    ///         of the Token's value that is held in reserve. The value is a number between 0 and 100%,
    ///         expressed in PPM. A higher reserve ratio means slower price growth. See Bancor Formula contract
    ///         for reference.
    uint32 internal reserveRatioForBuying;
    /// @dev    The reserve ratio for selling determines the rate of price growth. It is a measure of the fraction
    ///         of the Token's value that is held in reserve. The value is a number between 0 and 100%,
    ///         expressed in PPM. A higher reserve ratio means slower price growth. See Bancor Formula contract
    ///         for reference.
    uint32 internal reserveRatioForSelling;
    /// @dev    Token that is accepted by this funding manager for deposits.
    IERC20 private _token;
    /// @dev    Token decimals of the Orchestrator token, which is used as collateral and stores within
    ///         implementation for gas saving.
    uint8 internal collateralTokenDecimals;
    /// @dev    Token decimals of the issuance token, which is stored within the implementation for gas saving.
    uint8 internal issuanceTokenDecimals;

    /// @dev    Storage gap for future upgrades.
    uint[50] private __gap;

    //--------------------------------------------------------------------------
    // Modifiers

    /// @dev    Modifier to guarantee the buying and selling functionalities are closed.
    modifier onlyWhenCurveInteractionsAreClosed() {
        _checkCurveInteractionClosedModifier();
        _;
    }

    //--------------------------------------------------------------------------
    // Init Function

    /// @inheritdoc Module_v1
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata,
        bytes memory configData
    ) external override(Module_v1) initializer {
        __Module_init(orchestrator_, metadata);

        address _issuanceToken;
        BondingCurveProperties memory bondingCurveProperties;
        address _acceptedToken;

        (_issuanceToken, bondingCurveProperties, _acceptedToken) =
            abi.decode(configData, (address, BondingCurveProperties, address));

        // Set accepted token
        _token = IERC20(_acceptedToken);

        // Cache token decimals for collateral
        collateralTokenDecimals = IERC20Metadata(address(_token)).decimals();

        // Set issuance token. This also caches the decimals
        _setIssuanceToken(address(_issuanceToken));

        // Check for valid Bancor Formula
        if (
            !ERC165Upgradeable(bondingCurveProperties.formula).supportsInterface(
                type(IBancorFormula).interfaceId
            )
        ) {
            revert
                Module__FM_BC_Bancor_Redeeming_VirtualSupply__InvalidBancorFormula();
        }
        // Set formula contract
        formula = IBancorFormula(bondingCurveProperties.formula);
        // Set virtual issuance token supply
        _setVirtualIssuanceSupply(bondingCurveProperties.initialIssuanceSupply);
        // Set virtual collateral supply
        _setVirtualCollateralSupply(
            bondingCurveProperties.initialCollateralSupply
        );
        // Set reserve ratio for buying
        _setReserveRatioForBuying(bondingCurveProperties.reserveRatioForBuying);
        // Set reserve ratio for selling
        _setReserveRatioForSelling(
            bondingCurveProperties.reserveRatioForSelling
        );
        // Set buy fee percentage
        _setBuyFee(bondingCurveProperties.buyFee);
        // Set sell fee percentage
        _setSellFee(bondingCurveProperties.sellFee);
        // Set buying functionality to open if true. By default buying is false
        buyIsOpen = bondingCurveProperties.buyIsOpen;
        // Set selling functionality to open if true. By default selling is false
        sellIsOpen = bondingCurveProperties.sellIsOpen;

        emit OrchestratorTokenSet(_acceptedToken, collateralTokenDecimals);
    }

    //--------------------------------------------------------------------------
    // Public Mutating Functions

    /// @notice Buy tokens on behalf of a specified receiver address. This function is subject
    ///         to a transactional limit, determined by the deposit token's decimal precision and the underlying
    ///         bonding curve algorithm.
    /// @dev    Redirects to the internal function `_buyOrder` by passing the receiver address and deposit amount.
    ///         Important: The {BancorFormula} has an upper computational limit of (10^38). For tokens with
    ///         18 decimal places, this effectively leaves a maximum allowable deposit amount of (10^20).
    ///         While this is substantially large, it is crucial to be aware of this constraint.
    ///         Transactions exceeding this limit will be reverted.
    /// @param  _receiver The address that will receive the bought tokens.
    /// @param  _depositAmount The amount of collateral token depoisited.
    /// @param  _minAmountOut The minimum acceptable amount the user expects to receive from the transaction.
    function buyFor(address _receiver, uint _depositAmount, uint _minAmountOut)
        public
        virtual
        override(BondingCurveBase_v1)
        validReceiver(_receiver)
        buyingIsEnabled
    {
        (uint amountIssued, uint collateralFeeAmount) =
            _buyOrder(_receiver, _depositAmount, _minAmountOut);
        _addVirtualIssuanceAmount(amountIssued);
        _addVirtualCollateralAmount(_depositAmount - collateralFeeAmount);
    }

    /// @notice Buy tokens for the sender's address. This function is subject
    ///         to a transactional limit, determined by the deposit token's decimal precision and the underlying
    ///         bonding curve algorithm.
    /// @dev    Redirects to the internal function `_buyOrder` by passing the sender's address and deposit amount.
    ///         Important: The {BancorFormula} has an upper computational limit of (10^38).
    ///         While this is substantially large, it is crucial to be aware of this constraint.
    ///         Transactions exceeding this limit will be reverted.
    /// @param  _depositAmount The amount of collateral token depoisited.
    /// @param  _minAmountOut The minimum acceptable amount the user expects to receive from the transaction.
    function buy(uint _depositAmount, uint _minAmountOut)
        public
        virtual
        override(BondingCurveBase_v1)
        buyingIsEnabled
    {
        buyFor(_msgSender(), _depositAmount, _minAmountOut);
    }

    /// @notice Redeem tokens and direct the proceeds to a specified receiver address. This function is subject
    ///         to a transactional limit, determined by the issuing token's decimal precision and the underlying
    ///         bonding curve algorithm.
    /// @dev    Redirects to the internal function `_sellOrder` by passing the receiver address and deposit amount.
    ///         Important: The {BancorFormula} has an upper computational limit of (10^26). For tokens with
    ///         18 decimal places, this effectively leaves a maximum allowable deposit amount of (10^8), or
    ///         100,000,000. Transactions exceeding this limit will be reverted.
    /// @param  _receiver The address that will receive the redeemed tokens.
    /// @param  _depositAmount The amount of issued token to deposited.
    /// @param  _minAmountOut The minimum acceptable amount the user expects to receive from the transaction.
    function sellTo(address _receiver, uint _depositAmount, uint _minAmountOut)
        public
        virtual
        override(RedeemingBondingCurveBase_v1)
        validReceiver(_receiver)
        sellingIsEnabled
    {
        (uint redeemAmount, uint issuanceFeeAmount) =
            _sellOrder(_receiver, _depositAmount, _minAmountOut);
        _subVirtualIssuanceAmount(_depositAmount - issuanceFeeAmount);
        _subVirtualCollateralAmount(redeemAmount);
    }

    /// @notice Redeem collateral for the sender's address. This function is subject
    ///         to a transactional limit, determined by the issuing token's decimal precision and the underlying
    ///         bonding curve algorithm.
    /// @dev    Redirects to the internal function `_sellOrder` by passing the sender's address and deposit amount.
    ///         Important: The {BancorFormula} has an upper computational limit of (10^26). For tokens with
    ///         18 decimal places, this effectively leaves a maximum allowable deposit amount of (10^8), or
    ///         100,000,000. Transactions exceeding this limit will be reverted.
    /// @param  _depositAmount The amount of issued token depoisited.
    /// @param  _minAmountOut The minimum acceptable amount the user expects to receive from the transaction.
    function sell(uint _depositAmount, uint _minAmountOut)
        public
        virtual
        override(RedeemingBondingCurveBase_v1)
        sellingIsEnabled
    {
        sellTo(_msgSender(), _depositAmount, _minAmountOut);
    }

    //--------------------------------------------------------------------------
    // Public Data Query Functions

    /// @inheritdoc IFM_BC_Bancor_Redeeming_VirtualSupply_v1
    function getReserveRatioForBuying() external view returns (uint32) {
        return reserveRatioForBuying;
    }

    /// @inheritdoc IFM_BC_Bancor_Redeeming_VirtualSupply_v1
    function getReserveRatioForSelling() external view returns (uint32) {
        return reserveRatioForSelling;
    }

    /// @notice Calculates and returns the static price for buying the issuance token.
    ///         The return value is formatted in PPM.
    /// @dev    Calculates the static price for either selling or buying the issuance token,
    ///         based on the provided issuance token supply, collateral supply, and buy or sell reserve ratio.
    ///         Note: The reserve ratio specifies whether the sell or buy price is returned.
    ///         The formula used is: PPM * PPM * collateralSupply / (issuanceTokenSupply * reserveRatio).
    ///         The formula is based on Aragon's BatchedBancorMarketMaker, which can be found here:
    ///         https://github.com/AragonBlack/fundraising/blob/5ad1332955bab9d36cfad345ae92b7ad7dc0bdbe/apps/batched-bancor-market-maker/contracts/BatchedBancorMarketMaker.sol#L415
    /// @return uint The static price for buying the issuance token.
    function getStaticPriceForBuying()
        external
        view
        override(BondingCurveBase_v1)
        returns (uint)
    {
        return (
            uint(PPM) * uint(PPM)
                * FM_BC_Tools._convertAmountToRequiredDecimal(
                    virtualCollateralSupply,
                    collateralTokenDecimals,
                    eighteenDecimals
                )
        )
            / (
                FM_BC_Tools._convertAmountToRequiredDecimal(
                    virtualIssuanceSupply, issuanceTokenDecimals, eighteenDecimals
                ) * uint(reserveRatioForBuying)
            );
    }

    /// @notice Calculates and returns the static price for selling the issuance token.
    ///         The return value is formatted in PPM.
    /// @return uint The static price for selling the issuance token.
    function getStaticPriceForSelling()
        external
        view
        override(RedeemingBondingCurveBase_v1)
        returns (uint)
    {
        return (
            uint(PPM) * uint(PPM)
                * FM_BC_Tools._convertAmountToRequiredDecimal(
                    virtualCollateralSupply,
                    collateralTokenDecimals,
                    eighteenDecimals
                )
        )
            / (
                FM_BC_Tools._convertAmountToRequiredDecimal(
                    virtualIssuanceSupply, issuanceTokenDecimals, eighteenDecimals
                ) * uint(reserveRatioForSelling)
            );
    }

    /// @inheritdoc IFundingManager_v1
    function token() public view returns (IERC20) {
        return _token;
    }

    //--------------------------------------------------------------------------
    // OnlyOrchestrator Functions

    /// @inheritdoc IFundingManager_v1
    function transferOrchestratorToken(address to, uint amount)
        external
        virtual
        onlyPaymentClient
    {
        if (
            amount
                > token().balanceOf(address(this)) - projectCollateralFeeCollected
        ) {
            revert
                Module__FM_BC_Bancor_Redeeming_VirtualSupply__InvalidOrchestratorTokenWithdrawAmount(
            );
        }
        token().safeTransfer(to, amount);

        emit TransferOrchestratorToken(to, amount);
    }

    /// @inheritdoc IVirtualIssuanceSupplyBase_v1
    function setVirtualIssuanceSupply(uint _virtualSupply)
        external
        virtual
        override(VirtualIssuanceSupplyBase_v1)
        onlyOrchestratorAdmin
        onlyWhenCurveInteractionsAreClosed
    {
        _setVirtualIssuanceSupply(_virtualSupply);
    }

    /// @inheritdoc IVirtualCollateralSupplyBase_v1
    function setVirtualCollateralSupply(uint _virtualSupply)
        external
        virtual
        override(VirtualCollateralSupplyBase_v1)
        onlyOrchestratorAdmin
        onlyWhenCurveInteractionsAreClosed
    {
        _setVirtualCollateralSupply(_virtualSupply);
    }

    /// @inheritdoc IFM_BC_Bancor_Redeeming_VirtualSupply_v1
    function setReserveRatioForBuying(uint32 _reserveRatio)
        external
        virtual
        onlyOrchestratorAdmin
        onlyWhenCurveInteractionsAreClosed
    {
        _setReserveRatioForBuying(_reserveRatio);
    }

    /// @inheritdoc IFM_BC_Bancor_Redeeming_VirtualSupply_v1
    function setReserveRatioForSelling(uint32 _reserveRatio)
        external
        virtual
        onlyOrchestratorAdmin
        onlyWhenCurveInteractionsAreClosed
    {
        _setReserveRatioForSelling(_reserveRatio);
    }

    //--------------------------------------------------------------------------
    // Upstream Function Implementations

    /// @dev    Calculates the amount of tokens to mint for a given deposit amount using the {BancorFormula}.
    ///         This internal function is an override of {BondingCurveBase_v1}'s abstract function.
    ///         It handles decimal conversions and calculations through the bonding curve.
    /// @param  _depositAmount The amount of collateral deposited to purchase tokens.
    /// @return mintAmount The amount of tokens that will be minted.
    function _issueTokensFormulaWrapper(uint _depositAmount)
        internal
        view
        override(BondingCurveBase_v1)
        returns (uint mintAmount)
    {
        // Calculate mint amount through bonding curve
        uint decimalConvertedMintAmount = formula.calculatePurchaseReturn(
            // decimalConvertedVirtualIssuanceSupply
            FM_BC_Tools._convertAmountToRequiredDecimal(
                virtualIssuanceSupply, issuanceTokenDecimals, eighteenDecimals
            ),
            // decimalConvertedVirtualCollateralSupply
            FM_BC_Tools._convertAmountToRequiredDecimal(
                virtualCollateralSupply,
                collateralTokenDecimals,
                eighteenDecimals
            ),
            reserveRatioForBuying,
            // decimalConvertedDepositAmount
            FM_BC_Tools._convertAmountToRequiredDecimal(
                _depositAmount, collateralTokenDecimals, eighteenDecimals
            )
        );
        // Convert mint amount to issuing token decimals
        mintAmount = FM_BC_Tools._convertAmountToRequiredDecimal(
            decimalConvertedMintAmount, eighteenDecimals, issuanceTokenDecimals
        );
    }

    /// @dev    Calculates the amount of collateral to be received when redeeming a given amount of tokens.
    ///         This internal function is an override of {RedeemingBondingCurveBase_v1}'s abstract function.
    ///         It handles decimal conversions and calculations through the bonding curve. Note the {BancorFormula}
    ///         assumes 18 decimals for all tokens.
    /// @param  _depositAmount The amount of tokens to be redeemed for collateral.
    /// @return redeemAmount The amount of collateral that will be received.
    function _redeemTokensFormulaWrapper(uint _depositAmount)
        internal
        view
        override(RedeemingBondingCurveBase_v1)
        returns (uint redeemAmount)
    {
        // Calculate redeem amount through bonding curve
        uint decimalConvertedRedeemAmount = formula.calculateSaleReturn(
            // decimalConvertedVirtualIssuanceSupply
            FM_BC_Tools._convertAmountToRequiredDecimal(
                virtualIssuanceSupply, issuanceTokenDecimals, eighteenDecimals
            ),
            // decimalConvertedVirtualCollateralSupply
            FM_BC_Tools._convertAmountToRequiredDecimal(
                virtualCollateralSupply,
                collateralTokenDecimals,
                eighteenDecimals
            ),
            reserveRatioForSelling,
            // decimalConvertedDepositAmount
            FM_BC_Tools._convertAmountToRequiredDecimal(
                _depositAmount, issuanceTokenDecimals, eighteenDecimals
            )
        );

        // Convert redeem amount to collateral decimals
        redeemAmount = FM_BC_Tools._convertAmountToRequiredDecimal(
            decimalConvertedRedeemAmount,
            eighteenDecimals,
            collateralTokenDecimals
        );
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    /// @dev    Sets the issuance token for the Bonding Curve Funding Manager.
    ///         This function overrides the internal function set in {BondingCurveBase_v1}, adding
    ///         an input validation specific for the {BancorFormula} utilizing implementation, after which
    ///         it updates the `issuanceToken` state variable and caches the decimals as `issuanceTokenDecimals`.
    /// @param  _issuanceToken The token which will be issued by the Bonding Curve.
    function _setIssuanceToken(address _issuanceToken)
        internal
        override(BondingCurveBase_v1)
    {
        uint8 _decimals = IERC20Metadata(_issuanceToken).decimals();
        // An input verification is needed here since the Bancor formula, which determines the
        // issuance price, utilizes PPM for its computations. This leads to a precision loss
        // that's too significant to be acceptable for tokens with fewer than 7 decimals.
        if (_decimals < 7 || _decimals < collateralTokenDecimals) {
            revert
                Module__FM_BC_Bancor_Redeeming_VirtualSupply__InvalidTokenDecimal();
        }
        issuanceToken = IERC20Issuance_v1(_issuanceToken);
        issuanceTokenDecimals = _decimals;
        emit IssuanceTokenSet(_issuanceToken, _decimals);
    }

    /// @dev    Internal function to directly set the virtual collateral supply to a new value.
    /// @param  _virtualSupply The new value to set for the virtual collateral supply.
    function _setVirtualCollateralSupply(uint _virtualSupply)
        internal
        override(VirtualCollateralSupplyBase_v1)
    {
        super._setVirtualCollateralSupply(_virtualSupply);
    }

    /// @dev    Internal function to directly set the virtual issuance supply to a new value.
    ///         Virtual supply cannot be zero, or result in rounded down being zero when conversion
    ///         is done for use in the Bancor Formulat.
    /// @param  _virtualSupply The new value to set for the virtual issuance supply.
    function _setVirtualIssuanceSupply(uint _virtualSupply)
        internal
        override(VirtualIssuanceSupplyBase_v1)
    {
        uint minSupplyScaleFactor;
        uint decimals = issuanceTokenDecimals;

        // If the issuance token has 18 or fewer decimals, we leave the minSupplyScaleFactor at 0,
        // such that 10**0 equals 1.
        // If the issuance token has more than 18 decimals, we calculate the difference and
        // store it in minSupplyScaleFactor.
        if (decimals > 18) {
            minSupplyScaleFactor = decimals - 18;
        }
        // Check if virtual supply is big enough to ensure compatibility with relative issuance
        // token decimal and conversion to 18 decimals done in FM_BC_Tools._convertAmountToRequiredDecimal()
        // so it will not result in a round down 0 value
        if (_virtualSupply < 10 ** minSupplyScaleFactor) {
            revert Module__VirtualIssuanceSupplyBase__VirtualSupplyCannotBeZero(
            );
        }

        super._setVirtualIssuanceSupply(_virtualSupply);
    }

    /// @dev    Sets the reserve ratio for buying tokens.
    ///         The function will revert if the ratio is greater than the constant PPM.
    /// @param  _reserveRatio The reserve ratio to be set for buying tokens. Must be <= PPM.
    function _setReserveRatioForBuying(uint32 _reserveRatio) internal {
        _validateReserveRatio(_reserveRatio);
        emit BuyReserveRatioSet(_reserveRatio, reserveRatioForBuying);
        reserveRatioForBuying = _reserveRatio;
    }

    /// @dev    Sets the reserve ratio for selling tokens.
    ///         Similar to its counterpart for buying, this function sets the reserve ratio for selling tokens.
    ///         The function will revert if the ratio is greater than the constant PPM.
    /// @param  _reserveRatio The reserve ratio to be set for selling tokens. Must be <= PPM.
    function _setReserveRatioForSelling(uint32 _reserveRatio) internal {
        _validateReserveRatio(_reserveRatio);
        emit SellReserveRatioSet(_reserveRatio, reserveRatioForSelling);
        reserveRatioForSelling = _reserveRatio;
    }

    /// @dev    Validates the reserve ratio for buying and selling.
    ///         The function will revert if the ratio is greater than the constant PPM.
    /// @param  _reserveRatio The reserve ratio to be validated. Must be <= PPM.
    function _validateReserveRatio(uint32 _reserveRatio) internal pure {
        if (_reserveRatio == 0 || _reserveRatio > PPM) {
            revert
                Module__FM_BC_Bancor_Redeeming_VirtualSupply__InvalidReserveRatio();
        }
    }

    /// @dev    Checks if the buy and sell functionality is closed.
    function _checkCurveInteractionClosedModifier() internal view {
        if (buyIsOpen == true || sellIsOpen == true) {
            revert
                Module__FM_BC_Bancor_Redeeming_VirtualSupply__CurveInteractionsMustBeClosed(
            );
        }
    }
}
