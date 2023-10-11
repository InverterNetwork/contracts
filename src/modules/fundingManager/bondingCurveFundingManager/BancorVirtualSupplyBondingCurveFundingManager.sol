// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

// Internal Dependencies
import {Module} from "src/modules/base/Module.sol";
import {RedeemingBondingCurveFundingManagerBase} from
    "src/modules/fundingManager/bondingCurveFundingManager/RedeemingBondingCurveFundingManagerBase.sol";
import {BondingCurveFundingManagerBase} from
    "src/modules/fundingManager/bondingCurveFundingManager/BondingCurveFundingManagerBase.sol";
import {VirtualCollateralSupplyBase} from
    "src/modules/fundingManager/bondingCurveFundingManager/marketMaker/VirtualCollateralSupplyBase.sol";
import {VirtualTokenSupplyBase} from
    "src/modules/fundingManager/bondingCurveFundingManager/marketMaker/VirtualTokenSupplyBase.sol";
import {IBancorFormula} from
    "src/modules/fundingManager/bondingCurveFundingManager/formula/IBancorFormula.sol";

// Internal Interfaces
import {IBondingCurveFundingManagerBase} from
    "src/modules/fundingManager/bondingCurveFundingManager/IBondingCurveFundingManagerBase.sol";
import {IRedeemingBondingCurveFundingManagerBase} from
    "src/modules/fundingManager/bondingCurveFundingManager/IRedeemingBondingCurveFundingManagerBase.sol";
import {IBancorVirtualSupplyBondingCurveFundingManager} from
    "src/modules/fundingManager/bondingCurveFundingManager/IBancorVirtualSupplyBondingCurveFundingManager.sol";
import {IVirtualTokenSupply} from
    "src/modules/fundingManager/bondingCurveFundingManager/marketMaker/IVirtualTokenSupply.sol";
import {IVirtualCollateralSupply} from
    "src/modules/fundingManager/bondingCurveFundingManager/marketMaker/IVirtualCollateralSupply.sol";
import {IOrchestrator} from "src/orchestrator/IOrchestrator.sol";
import {IFundingManager} from "src/modules/fundingManager/IFundingManager.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IERC20MetadataUpgradeable} from
    "@oz-up/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

/// @title Bancor Virtual Supply Bonding Curve Funding Manager Contract.
/// @author Inverter Network.
/// @notice This contract enables the issuance and redeeming of tokens on a bonding curve, using
/// a virtual supply for both the token and the collateral as input. The contract makes use of the
/// Aragon's Bancor Formula contract to calculate the issuance and redeeming rates.
/// @dev This contract inherits functionalties from the contracts:
/// - BondingCurveFundingManagerBase
/// - RedeemingBondingCurveFundingManagerBase
/// - VirtualTokenSupplyBase
/// - VirtualCollateralSupplyBase
/// The contract should be used by the Orchestrator Owner to manage all the configuration fo the
/// bonding curve, e.g., the virtual supplies and reserve ratios, as well as the opening and closing
/// of the issuance and redeeming functionalities. The contract implements the formulaWrapper
/// functions enforced by the upstream contracts, using the Bancor formula to calculate the
/// issuance/redeeming rate. It also implements a function which enables direct minting of the issuance token
contract BancorVirtualSupplyBondingCurveFundingManager is
    IBancorVirtualSupplyBondingCurveFundingManager,
    VirtualTokenSupplyBase,
    VirtualCollateralSupplyBase,
    RedeemingBondingCurveFundingManagerBase
{
    using SafeERC20 for IERC20;

    //--------------------------------------------------------------------------
    // Storage

    /// @dev The interface of the Bancor Formula used to calculate the issuance and redeeming amount.
    IBancorFormula public formula;
    /// @dev Value is used to convert deposit amount to 18 decimals,
    /// which is required by the Bancor formula
    uint8 private constant eighteenDecimals = 18;
    /// @dev The reserve ratio for buying determines the rate of price growth. It is a measure of the fraction
    /// of the Token's value that is held in reserve. The value is a number between 0 and 100%,
    /// expressed in PPM. A higher reserve ratio means slower price growth. See Bancor Formula contract
    /// for reference.
    uint32 internal reserveRatioForBuying;
    /// @dev The reserve ratio for selling determines the rate of price growth. It is a measure of the fraction
    /// of the Token's value that is held in reserve. The value is a number between 0 and 100%,
    /// expressed in PPM. A higher reserve ratio means slower price growth. See Bancor Formula contract
    /// for reference.
    uint32 internal reserveRatioForSelling;
    /// @dev Parts per million used for calculation the reserve ratio for the Bancor formula.
    uint32 internal constant PPM = 1_000_000;
    /// @dev Token that is accepted by this funding manager for deposits.
    IERC20 private _token;

    //--------------------------------------------------------------------------
    // Init Function

    /// @inheritdoc Module
    function init(
        IOrchestrator orchestrator_,
        Metadata memory metadata,
        bytes memory configData
    ) external override(Module) initializer {
        __Module_init(orchestrator_, metadata);

        address _acceptedToken;
        IssuanceToken memory issuanceToken;
        BondingCurveProperties memory bondingCurveProperties;

        (issuanceToken, bondingCurveProperties, _acceptedToken) = abi.decode(
            configData, (IssuanceToken, BondingCurveProperties, address)
        );

        __ERC20_init(
            string(abi.encodePacked(issuanceToken.name)),
            string(abi.encodePacked(issuanceToken.symbol))
        );

        _token = IERC20(_acceptedToken);
        // Set token decimals for issuance token
        _setTokenDecimals(issuanceToken.decimals);
        // Set formula contract
        formula = IBancorFormula(bondingCurveProperties.formula);
        // Set virtual issuance token supply
        _setVirtualTokenSupply(issuanceToken.initalTokenSupply);
        // Set virtual collateral supply
        _setVirtualCollateralSupply(issuanceToken.initialCollateralSupply);
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
        if (bondingCurveProperties.buyIsOpen == true) _openBuy();
        // Set selling functionality to open if true. By default selling is false
        if (bondingCurveProperties.sellIsOpen == true) _openSell();
    }

    //--------------------------------------------------------------------------
    // Public Functions

    /// @notice Buy tokens on behalf of a specified receiver address. This function is subject
    /// to a transactional limit, determined by the deposit token's decimal precision and the underlying
    /// bonding curve algorithm.
    /// @dev Redirects to the internal function `_buyOrder` by passing the receiver address and deposit amount.
    /// Important: The Bancor Formula has an upper computational limit of (10^38). For tokens with
    /// 18 decimal places, this effectively leaves a maximum allowable deposit amount of (10^20).
    /// While this is substantially large, it is crucial to be aware of this constraint.
    /// Transactions exceeding this limit will be reverted.
    /// @param _receiver The address that will receive the bought tokens.
    /// @param _depositAmount The amount of collateral token depoisited.
    function buyOrderFor(address _receiver, uint _depositAmount)
        external
        payable
        override(BondingCurveFundingManagerBase)
        validReceiver(_receiver)
        buyingIsEnabled
    {
        _virtualBuyOrder(_receiver, _depositAmount);
    }

    /// @notice Buy tokens for the sender's address. This function is subject
    /// to a transactional limit, determined by the deposit token's decimal precision and the underlying
    /// bonding curve algorithm.
    /// @dev Redirects to the internal function `_buyOrder` by passing the sender's address and deposit amount.
    /// Important: The Bancor Formula has an upper computational limit of (10^38). For tokens with
    /// 18 decimal places, this effectively leaves a maximum allowable deposit amount of (10^20).
    /// While this is substantially large, it is crucial to be aware of this constraint.
    /// Transactions exceeding this limit will be reverted.
    /// @param _depositAmount The amount of collateral token depoisited.
    function buyOrder(uint _depositAmount)
        external
        payable
        override(BondingCurveFundingManagerBase)
        buyingIsEnabled
    {
        _virtualBuyOrder(_msgSender(), _depositAmount);
    }

    /// @notice Redeem tokens on behalf of a specified receiver address. This function is subject
    /// to a transactional limit, determined by the issuing token's decimal precision and the underlying
    /// bonding curve algorithm.
    /// @dev Redirects to the internal function `_sellOrder` by passing the receiver address and deposit amount.
    /// Important: The Bancor Formula has an upper computational limit of (10^26). For tokens with
    /// 18 decimal places, this effectively leaves a maximum allowable deposit amount of (10^8), or
    /// 100,000,000. Transactions exceeding this limit will be reverted.
    /// @param _receiver The address that will receive the redeemed tokens.
    /// @param _depositAmount The amount of issued token to deposited.
    function sellOrderFor(address _receiver, uint _depositAmount)
        external
        payable
        override(RedeemingBondingCurveFundingManagerBase)
        validReceiver(_receiver)
        sellingIsEnabled
    {
        _virtualSellOrder(_receiver, _depositAmount);
    }

    /// @notice Sell collateral for the sender's address. This function is subject
    /// to a transactional limit, determined by the issuing token's decimal precision and the underlying
    /// bonding curve algorithm.
    /// @dev Redirects to the internal function `_sellOrder` by passing the sender's address and deposit amount.
    /// Important: The Bancor Formula has an upper computational limit of (10^26). For tokens with
    /// 18 decimal places, this effectively leaves a maximum allowable deposit amount of (10^8), or
    /// 100,000,000. Transactions exceeding this limit will be reverted.
    /// @param _depositAmount The amount of issued token depoisited.
    function sellOrder(uint _depositAmount)
        external
        payable
        override(RedeemingBondingCurveFundingManagerBase)
        sellingIsEnabled
    {
        _virtualSellOrder(_msgSender(), _depositAmount);
    }

    /// @inheritdoc IBancorVirtualSupplyBondingCurveFundingManager
    function getReserveRatioForBuying() external view returns (uint32) {
        return reserveRatioForBuying;
    }

    /// @inheritdoc IBancorVirtualSupplyBondingCurveFundingManager
    function getReserveRatioForSelling() external view returns (uint32) {
        return reserveRatioForBuying;
    }

    //--------------------------------------------------------------------------
    // Public Mutating Functions

    /// @inheritdoc IFundingManager
    function token() public view returns (IERC20) {
        return _token;
    }

    //--------------------------------------------------------------------------
    // OnlyOrchestrator Functions

    /// @inheritdoc IBancorVirtualSupplyBondingCurveFundingManager
    function mintIssuanceTokenTo(address _receiver, uint _amount)
        external
        onlyOrchestratorOwner
        validReceiver(_receiver)
    {
        _mint(_receiver, _amount);
    }

    /// @inheritdoc IVirtualTokenSupply
    function setVirtualTokenSupply(uint _virtualSupply)
        external
        override(VirtualTokenSupplyBase)
        onlyOrchestratorOwner
    {
        _setVirtualTokenSupply(_virtualSupply);
    }

    /// @inheritdoc IVirtualCollateralSupply
    function setVirtualCollateralSupply(uint _virtualSupply)
        external
        override(VirtualCollateralSupplyBase)
        onlyOrchestratorOwner
    {
        _setVirtualCollateralSupply(_virtualSupply);
    }

    /// @inheritdoc IBancorVirtualSupplyBondingCurveFundingManager
    function setReserveRatioForBuying(uint32 _reserveRatio)
        external
        onlyOrchestratorOwner
    {
        _setReserveRatioForBuying(_reserveRatio);
    }

    /// @inheritdoc IBancorVirtualSupplyBondingCurveFundingManager
    function setReserveRatioForSelling(uint32 _reserveRatio)
        external
        onlyOrchestratorOwner
    {
        _setReserveRatioForSelling(_reserveRatio);
    }

    //--------------------------------------------------------------------------
    // Upstream Function Implementations

    /// @dev Calculates the amount of tokens to mint for a given deposit amount using the Bancor formula.
    /// This internal function is an override of BondingCurveFundingManagerBase's abstract function.
    /// It handles decimal conversions and calculations through the bonding curve.
    /// @param _depositAmount The amount of collateral deposited to purchase tokens.
    /// @return mintAmount The amount of tokens that will be minted.
    function _issueTokensFormulaWrapper(uint _depositAmount)
        internal
        view
        override(BondingCurveFundingManagerBase)
        returns (uint mintAmount)
    {
        // Convert depositAmount to 18 decimals, which is required by Bancor formula
        uint decimalConvertedDepositAmount = _convertAmountToRequiredDecimal(
            _depositAmount,
            IERC20MetadataUpgradeable(address(token())).decimals(),
            eighteenDecimals
        );
        // Calculate mint amount through bonding curve
        mintAmount = formula.calculatePurchaseReturn(
            virtualTokenSupply,
            virtualCollateralSupply,
            reserveRatioForBuying,
            decimalConvertedDepositAmount
        );
        // Convert mint amount to issuing token decimals
        mintAmount = _convertAmountToRequiredDecimal(
            mintAmount, eighteenDecimals, decimals()
        );
    }

    /// @dev Calculates the amount of collateral to be received when redeeming a given amount of tokens.
    /// This internal function is an override of RedeemingBondingCurveFundingManagerBase's abstract function.
    /// It handles decimal conversions and calculations through the bonding curve.
    /// @param _depositAmount The amount of tokens to be redeemed for collateral.
    /// @return redeemAmount The amount of collateral that will be received.
    function _redeemTokensFormulaWrapper(uint _depositAmount)
        internal
        view
        override(RedeemingBondingCurveFundingManagerBase)
        returns (uint redeemAmount)
    {
        // Convert depositAmount to 18 decimals, which is required by Bancor formula
        uint decimalConvertedDepositAmount = _convertAmountToRequiredDecimal(
            _depositAmount, decimals(), eighteenDecimals
        );
        // Calculate redeem amount through bonding curve
        redeemAmount = formula.calculateSaleReturn(
            virtualTokenSupply,
            virtualCollateralSupply,
            reserveRatioForSelling,
            decimalConvertedDepositAmount
        );

        // Convert redeem amount to collateral decimals
        redeemAmount = _convertAmountToRequiredDecimal(
            redeemAmount,
            eighteenDecimals,
            IERC20MetadataUpgradeable(address(token())).decimals()
        );
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    /// @dev Executes a buy order and updates the virtual supply of tokens and collateral.
    /// This function internally calls `_buyOrder` to get the issuing amount and updates the
    /// virtual balances accordingly.
    /// @param _receiver The address of the recipient of the issued tokens.
    /// @param _depositAmount The amount of collateral deposited for the buy order.
    function _virtualBuyOrder(address _receiver, uint _depositAmount)
        internal
    {
        uint amountIssued = _buyOrder(_receiver, _depositAmount);
        _addVirtualTokenAmount(amountIssued);
        _addVirtualCollateralAmount(_depositAmount);
    }

    /// @dev Executes a sell order and updates the virtual supply of tokens and collateral.
    /// This function internally calls `_sellOrder` to get the redeem amount and updates the
    /// virtual balances accordingly.
    /// @param _receiver The address that will receive the redeem amount.
    /// @param _depositAmount The amount of tokens that are being sold.
    function _virtualSellOrder(address _receiver, uint _depositAmount)
        internal
    {
        uint redeemAmount = _sellOrder(_receiver, _depositAmount);
        _subVirtualTokenAmount(_depositAmount);
        _subVirtualCollateralAmount(redeemAmount);
    }

    /// @dev Sets the reserve ratio for buying tokens.
    /// The function will revert if the ratio is greater than the constant PPM.
    ///
    /// @param _reserveRatio The reserve ratio to be set for buying tokens. Must be <= PPM.
    function _setReserveRatioForBuying(uint32 _reserveRatio) internal {
        if (_reserveRatio == 0) {
            revert
                BancorVirtualSupplyBondingCurveFundingManager__InvalidReserveRatio();
        }
        if (_reserveRatio > PPM) {
            revert
                BancorVirtualSupplyBondingCurveFundingManager__InvalidReserveRatio();
        }
        emit BuyReserveRatioSet(_reserveRatio, reserveRatioForBuying);
        reserveRatioForBuying = _reserveRatio;
    }

    /// @dev Sets the reserve ratio for selling tokens.
    /// Similar to its counterpart for buying, this function sets the reserve ratio for selling tokens.
    /// The function will revert if the ratio is greater than the constant PPM.
    ///
    /// @param _reserveRatio The reserve ratio to be set for selling tokens. Must be <= PPM.
    function _setReserveRatioForSelling(uint32 _reserveRatio) internal {
        if (_reserveRatio == 0) {
            revert
                BancorVirtualSupplyBondingCurveFundingManager__InvalidReserveRatio();
        }
        if (_reserveRatio > PPM) {
            revert
                BancorVirtualSupplyBondingCurveFundingManager__InvalidReserveRatio();
        }
        emit SellReserveRatioSet(_reserveRatio, reserveRatioForSelling);
        reserveRatioForSelling = _reserveRatio;
    }

    /// @dev Converts an amount to a required decimal representation.
    /// This function is useful for handling tokens with different decimal places.
    /// It takes care of both upscaling and downscaling the decimals based on the required decimals.
    ///
    /// @param _amount The amount to be converted.
    /// @param _tokenDecimals The current decimal places of the token.
    /// @param _requiredDecimals The required decimal places for the token.
    ///
    /// @return The converted amount with required decimal places.
    function _convertAmountToRequiredDecimal(
        uint _amount,
        uint8 _tokenDecimals,
        uint8 _requiredDecimals
    ) internal pure returns (uint) {
        // If the token decimal is the same as required decimal, return amount
        if (_tokenDecimals == _requiredDecimals) {
            return _amount;
        }
        // If the decimal of token is > required decimal, calculate conversion rate and
        // return amount converted to required decimal
        if (_tokenDecimals > _requiredDecimals) {
            uint conversionFactor = (10 ** (_tokenDecimals - _requiredDecimals));
            return (_amount / conversionFactor);
        } else {
            // If the decimal of token is < required decimal, calculate conversion rate and
            // return amount converted to required decimals
            uint conversionFactor = (10 ** (_requiredDecimals - _tokenDecimals));
            return (_amount * conversionFactor);
        }
    }
}
