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
import {IFM_BC_BondingSurface_Redeeming_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_BondingSurface_Redeeming_v1.sol";
import {IRepayer_v1} from "@fm/bondingCurve/interfaces/IRepayer_v1.sol";
import {ILiquidityVaultController} from
    "@lm/interfaces/ILiquidityVaultController.sol";
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";
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
 *          The contract implements the formulaWrapper functions enforced by the
 *          using the Bonding Surface formula to calculate the issuance/
 *          redeeming rate.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to
 *                          our Security Policy at security.inverter.network or
 *                          email us directly!
 *
 * @author  Inverter Network
 */
contract FM_BC_BondingSurface_Redeeming_v1 is
    IFM_BC_BondingSurface_Redeeming_v1,
    IFundingManager_v1,
    RedeemingBondingCurveBase_v1
{
    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(RedeemingBondingCurveBase_v1)
        returns (bool)
    {
        return interfaceId
            == type(IFM_BC_BondingSurface_Redeeming_v1).interfaceId
            || interfaceId == type(IFundingManager_v1).interfaceId
            || super.supportsInterface(interfaceId);
    }

    using SafeERC20 for IERC20;

    //--------------------------------------------------------------------------
    // Constants

    /// @dev Minimum collateral reserve
    uint public MIN_RESERVE;

    //--------------------------------------------------------------------------
    // Storage

    /// @dev The interface of the Formula used to calculate the issuance and redeeming amount.
    IBondingSurface public formula;
    /// @dev Token that is accepted by this funding manager for deposits.
    IERC20 internal _token;
    /// @dev the amount of value that is needed to operate the protocol according to market size
    /// and conditions
    uint public capitalRequired;
    /// @dev Base price multiplier in the bonding curve formula
    uint public basePriceMultiplier;
    /// @dev (basePriceMultiplier / capitalRequired)
    uint public basePriceToCapitalRatio;

    /// @dev    Storage gap for future upgrades.
    uint[50] private __gap;

    //--------------------------------------------------------------------------
    // Init Function

    /// @inheritdoc Module_v1
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata,
        bytes memory configData
    ) external virtual override(Module_v1) initializer {
        __Module_init(orchestrator_, metadata);

        address _issuanceToken;
        address _acceptedToken;
        BondingCurveProperties memory bondingCurveProperties;

        (_issuanceToken, _acceptedToken, bondingCurveProperties) =
            abi.decode(configData, (address, address, BondingCurveProperties));

        // Set accepted token
        _token = IERC20(_acceptedToken);

        // MIN_RESERVE is in relational to the decimals of the workflow collateral token
        MIN_RESERVE = 10 ** IERC20Metadata(address(_token)).decimals();

        // Set issuance token. This also caches the decimals
        _setIssuanceToken(address(_issuanceToken));

        // Check for valid Bonding Surface formula contract
        if (
            !ERC165Upgradeable(bondingCurveProperties.formula).supportsInterface(
                type(IBondingSurface).interfaceId
            )
        ) {
            revert
                FM_BC_BondingSurface_Redeeming_v1__InvalidBondingSurfaceFormula();
        }
        // Set formula contract
        formula = IBondingSurface(bondingCurveProperties.formula);

        // Set Bonding Curve Properties
        // Set capital required
        _setCapitalRequired(bondingCurveProperties.capitalRequired);
        // Set base price multiplier
        _setBasePriceMultiplier(bondingCurveProperties.basePriceMultiplier);
        // Set buy fee
        _setBuyFee(bondingCurveProperties.buyFee);
        // Set sell fee
        _setSellFee(bondingCurveProperties.sellFee);
        // Set buying functionality to open if true. By default buying is false
        buyIsOpen = bondingCurveProperties.buyIsOpen;
        // Set selling functionality to open if true. By default selling is false
        sellIsOpen = bondingCurveProperties.sellIsOpen;

        emit OrchestratorTokenSet(
            _acceptedToken, IERC20Metadata(address(_token)).decimals()
        );
    }

    //--------------------------------------------------------------------------
    // Public Functions
    /// @inheritdoc IFM_BC_BondingSurface_Redeeming_v1
    function calculateBasePriceToCapitalRatio(
        uint _capitalRequired,
        uint _basePriceMultiplier
    ) external pure returns (uint) {
        return _calculateBasePriceToCapitalRatio(
            _capitalRequired, _basePriceMultiplier
        );
    }

    /// @notice Calculates and returns the static price for buying the issuance token.
    /// @return uint The static price for buying the issuance token.
    function getStaticPriceForBuying()
        external
        view
        override(BondingCurveBase_v1)
        returns (uint)
    {
        return formula.spotPrice(
            _getCapitalAvailable(), capitalRequired, basePriceMultiplier
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
        return formula.spotPrice(
            _getCapitalAvailable(), capitalRequired, basePriceMultiplier
        );
    }

    //--------------------------------------------------------------------------
    // Public IFundingManager Functions
    /// @inheritdoc IFundingManager_v1
    function token() public view returns (IERC20) {
        return _token;
    }

    //--------------------------------------------------------------------------
    // OnlyOrchestratorAdmin Functions

    /// @inheritdoc IFM_BC_BondingSurface_Redeeming_v1
    function setCapitalRequired(uint _newCapitalRequired)
        public
        virtual
        onlyOrchestratorAdmin
    {
        _setCapitalRequired(_newCapitalRequired);
    }

    /// @inheritdoc IFM_BC_BondingSurface_Redeeming_v1
    function setBasePriceMultiplier(uint _newBasePriceMultiplier)
        public
        virtual
        onlyOrchestratorAdmin
    {
        _setBasePriceMultiplier(_newBasePriceMultiplier);
    }

    //--------------------------------------------------------------------------
    // Upstream Function Implementations

    /// @dev Calculates the amount of tokens to mint for a given deposit amount using the formula contract.
    /// This internal function is an override of BondingCurveBase_v1's abstract function.
    /// @param _depositAmount The amount of collateral deposited to purchase tokens.
    /// @return mintAmount The amount of tokens that will be minted.
    function _issueTokensFormulaWrapper(uint _depositAmount)
        internal
        view
        override(BondingCurveBase_v1)
        returns (uint mintAmount)
    {
        uint capitalAvailable = _getCapitalAvailable();
        if (capitalAvailable == 0) {
            revert FM_BC_BondingSurface_Redeeming_v1__NoCapitalAvailable();
        }

        mintAmount = formula.tokenOut(
            _depositAmount, capitalAvailable, basePriceToCapitalRatio
        );
    }

    /// @dev Calculates the amount of collateral to be received when redeeming a given amount of tokens.
    /// This internal function is an override of RedeemingBondingCurveBase_v1's abstract function.
    /// @param _depositAmount The amount of tokens to be redeemed for collateral.
    /// @return redeemAmount The amount of collateral that will be received.
    function _redeemTokensFormulaWrapper(uint _depositAmount)
        internal
        view
        override(RedeemingBondingCurveBase_v1)
        returns (uint redeemAmount)
    {
        // Subtract fee collected from capital held by contract
        uint capitalAvailable = _getCapitalAvailable();
        if (capitalAvailable == 0) {
            revert FM_BC_BondingSurface_Redeeming_v1__NoCapitalAvailable();
        }
        redeemAmount = formula.tokenIn(
            _depositAmount, capitalAvailable, basePriceToCapitalRatio
        );

        // The asset pool must never be empty.
        if (capitalAvailable - redeemAmount < MIN_RESERVE) {
            revert FM_BC_BondingSurface_Redeeming_v1__MinReserveReached();
        }
    }

    //--------------------------------------------------------------------------
    // OnlyPaymentClient Functions

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
            revert InvalidOrchestratorTokenWithdrawAmount();
        }

        token().safeTransfer(to, amount);

        if (MIN_RESERVE > token().balanceOf(address(this))) {
            revert FM_BC_BondingSurface_Redeeming_v1__MinReserveReached();
        }

        emit TransferOrchestratorToken(to, amount);
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    /// @dev Returns the collateral available in this contract, subtracted by the fee collected
    /// @return uint Capital available in contract
    function _getCapitalAvailable() internal view returns (uint) {
        return _token.balanceOf(address(this)) - projectCollateralFeeCollected;
    }

    /// @dev Set the capital required state used in the bonding curve calculations.
    /// _newCapitalRequired cannot be zero
    function _setCapitalRequired(uint _newCapitalRequired) internal {
        if (_newCapitalRequired == 0) {
            revert FM_BC_BondingSurface_Redeeming_v1__InvalidInputAmount();
        }
        emit CapitalRequiredChanged(capitalRequired, _newCapitalRequired);
        capitalRequired = _newCapitalRequired;
        _updateVariables();
    }

    /// @dev    Sets the base price multiplier and emits an event. Reverts if the input is zero.
    /// @param  _newBasePriceMultiplier The new base price multiplier.
    function _setBasePriceMultiplier(uint _newBasePriceMultiplier) internal {
        if (_newBasePriceMultiplier == 0) {
            revert FM_BC_BondingSurface_Redeeming_v1__InvalidInputAmount();
        }
        emit BasePriceMultiplierChanged(
            basePriceMultiplier, _newBasePriceMultiplier
        );
        basePriceMultiplier = _newBasePriceMultiplier;
        _updateVariables();
    }

    /// @dev Precomputes and sets the price multiplier to capital ratio
    function _updateVariables() internal {
        uint newBasePriceToCapitalRatio = _calculateBasePriceToCapitalRatio(
            capitalRequired, basePriceMultiplier
        );
        emit BasePriceToCapitalRatioChanged(
            basePriceToCapitalRatio, newBasePriceToCapitalRatio
        );
        basePriceToCapitalRatio = newBasePriceToCapitalRatio;
    }

    /// @dev Internal function which calculates the price multiplier to capital ratio
    function _calculateBasePriceToCapitalRatio(
        uint _capitalRequired,
        uint _basePriceMultiplier
    ) internal pure returns (uint _basePriceToCapitalRatio) {
        _basePriceToCapitalRatio = FixedPointMathLib.fdiv(
            _basePriceMultiplier, _capitalRequired, FixedPointMathLib.WAD
        );
        if (_basePriceToCapitalRatio > 1e36) {
            revert FM_BC_BondingSurface_Redeeming_v1__InvalidInputAmount();
        }
    }
}
