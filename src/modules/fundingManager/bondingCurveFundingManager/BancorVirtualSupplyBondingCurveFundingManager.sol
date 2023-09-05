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
    RedeemingBondingCurveFundingManagerBase,
    IFundingManager
{
    using SafeERC20 for IERC20;

    //--------------------------------------------------------------------------
    // Storage

    /// @dev The interface of the Bancor Formula used to calculate the issuance and redeeming amount.
    IBancorFormula public formula; // bugfix @review why not public?
    /// @dev Value is used to convert deposit amount to 18 decimals,
    /// which is required by the Bancor formula
    uint8 private constant eighteenDecimals = 18;
    /// @dev The reserve ratio for buying determines the rate of price growth. It is a measure of the fraction
    /// of the Token's value that is held in reserve. The value is a number between 0 and 100%,
    /// expressed in PPM. A higher reserve ratio means slower price growth. See Bancor Formula contract
    /// for reference.
    uint32 internal reserveRatioForBuying; //@note @review why no getters?
    /// @dev The reserve ratio for selling determines the rate of price growth. It is a measure of the fraction
    /// of the Token's value that is held in reserve. The value is a number between 0 and 100%,
    /// expressed in PPM. A higher reserve ratio means slower price growth. See Bancor Formula contract
    /// for reference.
    uint32 internal reserveRatioForSelling; //@note @review why no getters?
    /// @dev Parts per million used for calculation the reserve ratio for the Bancor formula.
    uint32 internal constant PPM = 1_000_000; //@bugfix @review changed type since it will be compared with uint32

    //--------------------------------------------------------------------------
    // Init Function

    /// @inheritdoc Module
    // @todo This function crosses stack-too-deep threshold when we uncomment the decimals. It needs a refactor
    function init(
        IOrchestrator orchestrator_,
        Metadata memory metadata,
        bytes memory configData
    ) external override(Module) initializer {
        __Module_init(orchestrator_, metadata);

        (
            bytes32 _name, // The name of the issuance token
            bytes32 _symbol, // The symbol of the issuance token
            //uint8 _decimals, // The decimals used within the issuance token
            address _formula, // The formula contract used to calculate the issucance and redemption rate
            uint _initalTokenSupply, // The initial virtual issuance token supply
            uint _initialCollateralSupply, // The initial virtual collateral token supply
            uint32 _reserveRatioForBuying, // The reserve ratio, expressed in PPM, used for issuance on the bonding curve
            uint32 _reserveRatioForSelling, // The reserve ratio, expressed in PPM, used for redeeming on the bonding curve
            uint _buyFee, // The buy fee expressed in base points
            uint _sellFee, // The sell fee expressed in base points
            bool _buyIsOpen, // The indicator used for enabling/disabling the buying functionalities on deployment
            bool _sellIsOpen // The indicator used for enabling/disabling the selling functionalties on deployment
        ) = abi.decode(
            configData,
            (
                bytes32,
                bytes32,
                //uint8,
                address,
                uint,
                uint,
                uint32,
                uint32,
                uint,
                uint,
                bool,
                bool
            )
        );

        __ERC20_init(
            string(abi.encodePacked(_name)), string(abi.encodePacked(_symbol))
        );
        // Set token decimals for issuance token
        //_setTokenDecimals(_decimals);
        _setTokenDecimals(18);
        // Set formula contract
        formula = IBancorFormula(_formula);
        // Set virtual issuance token supply
        _setVirtualTokenSupply(_initalTokenSupply);
        // Set virtual collateral supply
        _setVirtualCollateralSupply(_initialCollateralSupply);
        // Set reserve ratio for buying
        _setReserveRatioForBuying(_reserveRatioForBuying);
        // Set reserve ratio for selling
        _setReserveRatioForSelling(_reserveRatioForSelling);
        // Set buy fee percentage
        _setBuyFee(_buyFee);
        // Set sell fee percentage
        _setSellFee(_sellFee);
        // Set buying functionality to open if true. By default buying is false
        if (_buyIsOpen == true) _openBuy();
        // Set selling functionality to open if true. By default selling is false
        if (_sellIsOpen == true) _openSell();
    }

    //--------------------------------------------------------------------------
    // Public Functions

    /// @inheritdoc IBondingCurveFundingManagerBase
    function buyOrderFor(address _receiver, uint _depositAmount)
        external
        payable
        override(BondingCurveFundingManagerBase)
        validReceiver(_receiver)
        buyingIsEnabled
    {
        _virtualSupplyBuyOrder(_receiver, _depositAmount);
    }

    /// @inheritdoc IBondingCurveFundingManagerBase
    function buyOrder(uint _depositAmount)
        external
        payable
        override(BondingCurveFundingManagerBase)
        buyingIsEnabled
    {
        _virtualSupplyBuyOrder(_msgSender(), _depositAmount);
    }

    /// @inheritdoc IRedeemingBondingCurveFundingManagerBase
    function sellOrderFor(address _receiver, uint _depositAmount)
        external
        payable
        override(RedeemingBondingCurveFundingManagerBase)
        validReceiver(_receiver)
        sellingIsEnabled
    {
        _virtualSupplySellOrder(_receiver, _depositAmount);
    }

    /// @inheritdoc IRedeemingBondingCurveFundingManagerBase
    function sellOrder(uint _depositAmount)
        external
        payable
        override(RedeemingBondingCurveFundingManagerBase)
        sellingIsEnabled
    {
        _virtualSupplySellOrder(_msgSender(), _depositAmount);
    }

    //--------------------------------------------------------------------------
    // Public Mutating Functions

    /// @inheritdoc IFundingManager
    function token() public view returns (IERC20) {
        return __Module_orchestrator.token();
    }

    /// @inheritdoc IFundingManager
    function deposit(uint amount) external {}

    /// @inheritdoc IFundingManager
    function depositFor(address to, uint amount) external {}

    /// @inheritdoc IFundingManager
    function withdraw(uint amount) external {}

    /// @inheritdoc IFundingManager
    function withdrawTo(address to, uint amount) external {}

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
    function _virtualSupplyBuyOrder(address _receiver, uint _depositAmount)
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
    function _virtualSupplySellOrder(address _receiver, uint _depositAmount)
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
        // TODO: Qs - TEST: What happens when set to 0? -> Reserve ratio of 0 is not allowed
        //              - Do we want to enforce a max/min value other than absolutes base on test result, i.e. 0 - 100%?
        if (_reserveRatio == 0) {
            // @bugfix @review
            revert
                BancorVirtualSupplyBondingCurveFundingManager__InvalidReserveRatio();
        }
        if (_reserveRatio > PPM) {
            revert
                BancorVirtualSupplyBondingCurveFundingManager__InvalidReserveRatio();
        }
        reserveRatioForBuying = _reserveRatio;
    }

    /// @dev Sets the reserve ratio for selling tokens.
    /// Similar to its counterpart for buying, this function sets the reserve ratio for selling tokens.
    /// The function will revert if the ratio is greater than the constant PPM.
    ///
    /// @param _reserveRatio The reserve ratio to be set for selling tokens. Must be <= PPM.
    function _setReserveRatioForSelling(uint32 _reserveRatio) internal {
        // TODO: Qs - TEST: What happens when set to 0? -> Reserve ratio of 0 is not allowed
        //           - Do we want to enforce a max/min value other than absolutes base on test result, i.e. 0 - 100%?
        if (_reserveRatio == 0) {
            // @bugfix @review
            revert
                BancorVirtualSupplyBondingCurveFundingManager__InvalidReserveRatio();
        }
        if (_reserveRatio > PPM) {
            revert
                BancorVirtualSupplyBondingCurveFundingManager__InvalidReserveRatio();
        }
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
    // @note @review I think the implementation for (_tokenDecimals > _requiredDecimals) is wrong? If the difference in decimals is bigger than BPS it just starts returning zero
    // In general, I'm not sure I understand the use of BPS here. The alternative version leaving it out seems to accomplish the same goal, or am I missing something?
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
/*             uint conversionFactor =
                BPS / (10 ** (_tokenDecimals - _requiredDecimals));
            return (_amount * conversionFactor) / BPS; */
            uint conversionFactor =
                (10 ** (_tokenDecimals - _requiredDecimals));
            return (_amount / conversionFactor) ;

        } else {
            // If the decimal of token is < required decimal, calculate conversion rate and
            // return amount converted to required decimals
/*             uint conversionFactor =
                BPS * (10 ** (_requiredDecimals - _tokenDecimals));
            return (_amount * conversionFactor) / BPS; */
            uint conversionFactor =
             (10 ** (_requiredDecimals - _tokenDecimals));
            return (_amount * conversionFactor) ;
        }
    }

    //--------------------------------------------------------------------------
    // OnlyOrchestrator Mutating Functions

    /// @inheritdoc IFundingManager
    function transferOrchestratorToken(address to, uint amount)
        external
        onlyOrchestrator
    {
        __Module_orchestrator.token().safeTransfer(to, amount);

        emit TransferOrchestratorToken(to, amount);
    }
}
