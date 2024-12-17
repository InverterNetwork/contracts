// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal
import {Module_v1} from "src/modules/base/Module_v1.sol";
import {RedeemingBondingCurveBase_v1} from
    "@fm/bondingCurve/abstracts/RedeemingBondingCurveBase_v1.sol";
import {BondingCurveBase_v1} from
    "@fm/bondingCurve/abstracts/BondingCurveBase_v1.sol";
import {FixedPointMathLib} from "src/modules/lib/FixedPointMathLib.sol";
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";
import {IRedeemingBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IRedeemingBondingCurveBase_v1.sol";
import {
    IFM_BC_BondingSurface_Redeeming_v1,
    IFundingManager_v1
} from "@fm/bondingCurve/interfaces/IFM_BC_BondingSurface_Redeeming_v1.sol";
import {IRepayer_v1} from "@fm/bondingCurve/interfaces/IRepayer_v1.sol";
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IBondingSurface} from "@fm/bondingCurve/interfaces/IBondingSurface.sol";
import {IAuthorizer_v1} from "src/modules/authorizer/IAuthorizer_v1.sol";

// External
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@oz/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

/**
 * @title   Inverter Redeeming Bonding Surface Bonding Curve Funding Manager
 *
 * @notice  This contract enables the issuance and redemption of tokens on a
 *          bonding curve.
 *
 * @dev     This contract inherits functionalties from the contracts:
 *              - BondingCurveBase_v1
 *              - RedeemingBondingCurveBase_v1
 *              - Repayer
 *          The contract should be used by the orchestrator admin or manager
 *          to manage all the configuration for the bonding curve as well as the
 *          opening and closing of the issuance and redeeming functionalities.
 *          The contract implements the formulaWrapper functions enforced by
 *          using the Bonding Surface formula to calculate the issuance/
 *          redemption rate.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to
 *                          our Security Policy at security.inverter.network or
 *                          email us directly!
 *
 * @custom:version  v1.0.0
 *
 * @custom:inverter-standard-version    v0.1.0
 *
 * @author  Inverter Network
 */
contract FM_BC_BondingSurface_Redeeming_v1 is
    RedeemingBondingCurveBase_v1,
    IFM_BC_BondingSurface_Redeeming_v1
{
    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId_)
        public
        view
        virtual
        override(RedeemingBondingCurveBase_v1)
        returns (bool supportsInterface_)
    {
        return interfaceId_
            == type(IFM_BC_BondingSurface_Redeeming_v1).interfaceId
            || interfaceId_ == type(IFundingManager_v1).interfaceId
            || super.supportsInterface(interfaceId_);
    }

    using SafeERC20 for IERC20;

    // ========================================================================
    // Storage

    /// @notice Minimum collateral reserve.
    /// @dev    Should not be changed after initialization.
    uint public MIN_RESERVE;

    /// @notice The interface of the Formula used to calculate the issuance and
    ///         redeeming amount.
    IBondingSurface internal _formula;
    /// @notice Token that is accepted by this funding manager for deposits.
    IERC20 internal _token;
    /// @notice The amount of capital that is needed to operate the protocol
    ///         according to market size and conditions.
    uint internal _capitalRequired;
    /// @notice Base price multiplier in the bonding curve formula.
    uint internal _basePriceMultiplier;
    /// @notice The base price to capital ratio.
    /// @dev    (basePriceMultiplier / capitalRequired).
    uint internal _basePriceToCapitalRatio;

    /// @notice Storage gap for future upgrades.
    uint[50] private __gap;

    // ========================================================================
    // Init Function

    /// @inheritdoc Module_v1
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata_,
        bytes memory configData_
    ) external virtual override(Module_v1) initializer {
        address issuanceToken;
        address acceptedToken;
        BondingCurveProperties memory bondingCurveProperties;

        (issuanceToken, acceptedToken, bondingCurveProperties) =
            abi.decode(configData_, (address, address, BondingCurveProperties));

        __Module_init(orchestrator_, metadata_);
        __FM_BC_BondingSurface_Redeeming_v1_Init(
            issuanceToken, acceptedToken, bondingCurveProperties
        );
    }

    /// @notice Initializes the Redeeming Bonding Surface Contract.
    /// @dev    Only callable during the initialization.
    /// @param  issuanceToken_ The token that is used to issue bonds.
    /// @param  acceptedToken_ The token that is accepted as collateral.
    /// @param  bondingCurveProperties_ The properties of the bonding curve.
    function __FM_BC_BondingSurface_Redeeming_v1_Init(
        address issuanceToken_,
        address acceptedToken_,
        BondingCurveProperties memory bondingCurveProperties_
    ) internal onlyInitializing {
        // Set collateral token.
        _token = IERC20(acceptedToken_);

        // MIN_RESERVE is in relation to the decimals of the
        // workflow's collateral token.
        MIN_RESERVE = 10 ** IERC20Metadata(address(_token)).decimals();

        // Set issuance token. This also caches the decimals.
        _setIssuanceToken(address(issuanceToken_));

        // Check for valid Bonding Surface formula contract.
        if (
            !ERC165Upgradeable(bondingCurveProperties_.formula).supportsInterface(
                type(IBondingSurface).interfaceId
            )
        ) {
            revert
                IFM_BC_BondingSurface_Redeeming_v1
                .FM_BC_BondingSurface_Redeeming_v1__InvalidBondingSurfaceFormula();
        }
        // Set formula contract.
        _formula = IBondingSurface(bondingCurveProperties_.formula);

        // Set Bonding Curve Properties.
        _setCapitalRequired(bondingCurveProperties_.capitalRequired);
        _setBasePriceMultiplier(bondingCurveProperties_.basePriceMultiplier);
        _setBuyFee(bondingCurveProperties_.buyFee);
        _setSellFee(bondingCurveProperties_.sellFee);

        // Set buying functionality to open if true.
        // By default buying is false.
        buyIsOpen = bondingCurveProperties_.buyIsOpen;
        // Set selling functionality to open if true.
        // By default selling is false.
        sellIsOpen = bondingCurveProperties_.sellIsOpen;

        emit OrchestratorTokenSet(
            acceptedToken_, IERC20Metadata(address(_token)).decimals()
        );
    }

    // ========================================================================
    // Public Getter Functions

    /// @inheritdoc IBondingCurveBase_v1
    function getStaticPriceForBuying()
        external
        view
        override(BondingCurveBase_v1, IBondingCurveBase_v1)
        returns (uint staticPriceForBuying_)
    {
        return _formula.spotPrice(
            _getCapitalAvailable(), _capitalRequired, _basePriceMultiplier
        );
    }

    /// @inheritdoc IRedeemingBondingCurveBase_v1
    /// @dev    The return value is formatted in PPM.
    function getStaticPriceForSelling()
        external
        view
        override(RedeemingBondingCurveBase_v1, IRedeemingBondingCurveBase_v1)
        returns (uint staticPriceForSelling_)
    {
        return _formula.spotPrice(
            _getCapitalAvailable(), _capitalRequired, _basePriceMultiplier
        );
    }

    /// @inheritdoc IFM_BC_BondingSurface_Redeeming_v1
    function getBondingSurfaceFormula()
        external
        view
        returns (address formula_)
    {
        return address(_formula);
    }

    /// @inheritdoc IFM_BC_BondingSurface_Redeeming_v1
    function getCapitalRequired()
        external
        view
        returns (uint capitalRequired_)
    {
        return _capitalRequired;
    }

    /// @inheritdoc IFM_BC_BondingSurface_Redeeming_v1
    function getBasePriceMultiplier()
        external
        view
        returns (uint basePriceMultiplier_)
    {
        return _basePriceMultiplier;
    }

    /// @inheritdoc IFM_BC_BondingSurface_Redeeming_v1
    function getBasePriceToCapitalRatio()
        external
        view
        returns (uint basePriceToCapitalRatio_)
    {
        return _basePriceToCapitalRatio;
    }

    /// @inheritdoc IFM_BC_BondingSurface_Redeeming_v1
    function calculateBasePriceToCapitalRatio(
        uint capitalRequired_,
        uint basePriceMultiplier_
    ) external pure returns (uint basePriceTocaptialRatio_) {
        return _calculateBasePriceToCapitalRatio(
            capitalRequired_, basePriceMultiplier_
        );
    }

    // ------------------------------------------------------------------------
    // Getter -  IFundingManager Functions

    /// @inheritdoc IFundingManager_v1
    function token()
        public
        view
        override(IFundingManager_v1)
        returns (IERC20 token_)
    {
        return _token;
    }

    // ========================================================================
    // Mutating Functions

    // ------------------------------------------------------------------------
    // Mutating - OnlyOrchestratorAdmin Functions

    /// @inheritdoc IFM_BC_BondingSurface_Redeeming_v1
    function setCapitalRequired(uint newCapitalRequired_)
        public
        virtual
        onlyOrchestratorAdmin
    {
        _setCapitalRequired(newCapitalRequired_);
    }

    /// @inheritdoc IFM_BC_BondingSurface_Redeeming_v1
    function setBasePriceMultiplier(uint newBasePriceMultiplier_)
        public
        virtual
        onlyOrchestratorAdmin
    {
        _setBasePriceMultiplier(newBasePriceMultiplier_);
    }

    // ------------------------------------------------------------------------
    // Mutating - OnlyPaymentClient Functions

    /// @inheritdoc IFundingManager_v1
    function transferOrchestratorToken(address to_, uint amount_)
        external
        virtual
        override(IFundingManager_v1)
        onlyPaymentClient
    {
        if (
            amount_
                > token().balanceOf(address(this)) - projectCollateralFeeCollected
        ) {
            revert InvalidOrchestratorTokenWithdrawAmount();
        }

        token().safeTransfer(to_, amount_);

        if (MIN_RESERVE > token().balanceOf(address(this))) {
            revert FM_BC_BondingSurface_Redeeming_v1__MinReserveReached();
        }

        emit TransferOrchestratorToken(to_, amount_);
    }

    // ========================================================================
    // Internal Functions

    /// @notice Returns the collateral available in this contract,
    ///         subtracted by the fee collected.
    /// @return capitalAvailable_ Capital available in contract.
    function _getCapitalAvailable()
        internal
        view
        returns (uint capitalAvailable_)
    {
        return _token.balanceOf(address(this)) - projectCollateralFeeCollected;
    }

    /// @notice Set the capital required state used in the bonding curve
    ///         calculations.
    /// @dev    newCapitalRequired_ cannot be zero.
    /// @param  newCapitalRequired_ the new capital that is required.
    function _setCapitalRequired(uint newCapitalRequired_) internal {
        if (newCapitalRequired_ == 0) {
            revert FM_BC_BondingSurface_Redeeming_v1__InvalidInputAmount();
        }
        emit CapitalRequiredChanged(_capitalRequired, newCapitalRequired_);
        _capitalRequired = newCapitalRequired_;
        _updateVariables();
    }

    /// @notice Sets the base price multiplier.
    /// @dev    Reverts if newBasePriceMultiplier_ is zero.
    /// @param  newBasePriceMultiplier_ The new base price multiplier.
    function _setBasePriceMultiplier(uint newBasePriceMultiplier_) internal {
        if (newBasePriceMultiplier_ == 0) {
            revert FM_BC_BondingSurface_Redeeming_v1__InvalidInputAmount();
        }
        emit BasePriceMultiplierChanged(
            _basePriceMultiplier, newBasePriceMultiplier_
        );
        _basePriceMultiplier = newBasePriceMultiplier_;
        _updateVariables();
    }

    /// @notice Precomputes and sets the price multiplier to capital ratio.
    function _updateVariables() internal {
        uint newBasePriceToCapitalRatio = _calculateBasePriceToCapitalRatio(
            _capitalRequired, _basePriceMultiplier
        );
        emit BasePriceToCapitalRatioChanged(
            _basePriceToCapitalRatio, newBasePriceToCapitalRatio
        );
        _basePriceToCapitalRatio = newBasePriceToCapitalRatio;
    }

    /// @notice Internal function which calculates the price multiplier to
    ///         capital ratio.
    /// @dev    Reverts if the ratio is higher than 1e36.
    /// @param  capitalRequired_ The capital required.
    /// @param  basePriceMultiplier_ The base price multiplier.
    /// @return basePriceToCapitalRatio_ The calculated price to capital ratio.
    function _calculateBasePriceToCapitalRatio(
        uint capitalRequired_,
        uint basePriceMultiplier_
    ) internal pure returns (uint basePriceToCapitalRatio_) {
        basePriceToCapitalRatio_ = FixedPointMathLib.fdiv(
            basePriceMultiplier_, capitalRequired_, FixedPointMathLib.WAD
        );
        if (basePriceToCapitalRatio_ > 1e36) {
            revert FM_BC_BondingSurface_Redeeming_v1__InvalidInputAmount();
        }
    }

    // ------------------------------------------------------------------------
    // Internal - Upstream Function Implementations

    /// @notice Calculates the amount of tokens to mint for a given deposit
    ///         amount using the formula contract.
    /// @dev    This internal function is an override of BondingCurveBase_v1's
    ///         virtual function.
    /// @param  depositAmount_ The amount of collateral deposited to
    ///         purchase tokens.
    /// @return mintAmount_ The amount of tokens that will be minted.
    function _issueTokensFormulaWrapper(uint depositAmount_)
        internal
        view
        override(BondingCurveBase_v1)
        returns (uint mintAmount_)
    {
        uint capitalAvailable = _getCapitalAvailable();
        if (capitalAvailable == 0) {
            revert FM_BC_BondingSurface_Redeeming_v1__NoCapitalAvailable();
        }

        mintAmount_ = _formula.tokenOut(
            depositAmount_, capitalAvailable, _basePriceToCapitalRatio
        );
    }

    /// @notice Calculates the amount of collateral to be received when
    ///         redeeming a given amount of tokens.
    /// @dev    This internal function is an override of
    ///         RedeemingBondingCurveBase_v1's virtual function.
    /// @param  depositAmount_ The amount of tokens to be redeemed for
    ///         collateral.
    /// @return redeemAmount_ The amount of collateral that will be received.
    function _redeemTokensFormulaWrapper(uint depositAmount_)
        internal
        view
        override(RedeemingBondingCurveBase_v1)
        returns (uint redeemAmount_)
    {
        // Subtract fee collected from capital held by contract.
        uint capitalAvailable = _getCapitalAvailable();
        if (capitalAvailable == 0) {
            revert FM_BC_BondingSurface_Redeeming_v1__NoCapitalAvailable();
        }
        redeemAmount_ = _formula.tokenIn(
            depositAmount_, capitalAvailable, _basePriceToCapitalRatio
        );

        // The asset pool must never be empty.
        if (capitalAvailable - redeemAmount_ < MIN_RESERVE) {
            revert FM_BC_BondingSurface_Redeeming_v1__MinReserveReached();
        }
    }
}
