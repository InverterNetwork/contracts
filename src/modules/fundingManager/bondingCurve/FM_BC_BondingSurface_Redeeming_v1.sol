// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Dependencies
import {Module_v1} from "src/modules/base/Module_v1.sol";
import {RedeemingBondingCurveBase_v1} from
    "@fm/bondingCurve/abstracts/RedeemingBondingCurveBase_v1.sol";
import {BondingCurveBase_v1} from
    "@fm/bondingCurve/abstracts/BondingCurveBase_v1.sol";
import {FixedPointMathLib} from "src/modules/lib/FixedPointMathLib.sol";

// Internal Interfaces
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

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@oz/token/ERC20/extensions/IERC20Metadata.sol";

// External Dependencies
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

/// @title Bonding Surface Bonding Curve Funding Manager Contract.
/// @author Inverter Network.
/// @notice This contract enables the issuance and redeeming of tokens on a bonding curve
/// @dev This contract inherits functionalties from the contracts:
/// - BondingCurveBase_v1
/// - RedeemingBondingCurveBase_v1
/// - Repayer
/// The contract should be used by the Orchestrator Owner or manager to manage all the configuration for the
/// bonding curve as well as the opening and closing of the issuance and redeeming functionalities.
/// The contract implements the formulaWrapper functions enforced by the upstream contracts,
/// using the Bonding Surface formula to calculate the issuance/redeeming rate.
contract FM_BC_BondingSurface_Redeeming_v1 is
    IFM_BC_BondingSurface_Redeeming_v1,
    IFundingManager_v1,
    RedeemingBondingCurveBase_v1
{
    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(
        bytes4 interfaceId //@todo adapt tests
    )
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
    uint public constant MIN_RESERVE = 1 ether;
    /// @dev Role associated with the managing of the bonding curve values
    bytes32 public constant RISK_MANAGER_ROLE = "RISK_MANAGER"; //@todo what roles do we want here?
    /// @dev Role associated with the managing of setting withdraw addresses and setting the fee
    bytes32 public constant COVER_MANAGER_ROLE = "COVER_MANAGER";
    /// @dev Minter/Burner Role.
    bytes32 public constant CURVE_INTERACTION_ROLE = "CURVE_USER";

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
    /// @notice Restricts buying and selling functionalities to specific role.
    bool public buyAndSellIsRestricted;

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
        address _acceptedToken;
        address _tokenVault;
        BondingCurveProperties memory bondingCurveProperties;
        address _liquidityVaultController;

        (
            _issuanceToken,
            _acceptedToken,
            _tokenVault,
            _liquidityVaultController,
            bondingCurveProperties
        ) = abi.decode(
            configData,
            (address, address, address, address, BondingCurveProperties)
        );

        // Set accepted token
        _token = IERC20(_acceptedToken);

        // Set issuance token. This also caches the decimals
        _setIssuanceToken(address(_issuanceToken));

        // Check for valid Bonding Surface formula contract
        if (
            !ERC165Upgradeable(bondingCurveProperties.formula).supportsInterface(
                type(IBondingSurface).interfaceId
            )
        ) {
            revert
                FM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1__InvalidBondingSurfaceFormula(
            );
        }
        // Set formula contract
        formula = IBondingSurface(bondingCurveProperties.formula);

        // Set Bonding Curve Properties
        // Set capital required
        _setCapitalRequired(bondingCurveProperties.capitalRequired);
        // Set base price multiplier
        _setBasePriceMultiplier(bondingCurveProperties.basePriceMultiplier);
        // Set buy fee
        _setBuyFee(0);
        // Set sell fee
        _setSellFee(bondingCurveProperties.sellFee);
        // Set buying functionality to open if true. By default buying is false
        buyIsOpen = bondingCurveProperties.buyIsOpen;
        // Set selling functionality to open if true. By default selling is false
        sellIsOpen = bondingCurveProperties.sellIsOpen;
        // Set buy and sell restriction to restricted if true. By default buy and sell is unrestricted.
        buyAndSellIsRestricted = bondingCurveProperties.buyAndSellIsRestricted;

        emit OrchestratorTokenSet(
            _acceptedToken, IERC20Metadata(address(_token)).decimals()
        );
    }

    //--------------------------------------------------------------------------
    // Modifiers

    // @todo want
    modifier isBuyAndSellRestricted() {
        _isBuyAndSellRestrictedModifier();
        _;
    }

    //--------------------------------------------------------------------------
    // Public Functions
    // @todo want
    /// @notice Buy tokens on behalf of a specified receiver address.
    /// @dev
    /// @param _receiver The address that will receive the bought tokens.
    /// @param _depositAmount The amount of collateral token depoisited.
    /// @param _minAmountOut The minimum acceptable amount the user expects to receive from the transaction.
    function buyFor(address _receiver, uint _depositAmount, uint _minAmountOut)
        public
        virtual
        override(BondingCurveBase_v1)
        buyingIsEnabled
        isBuyAndSellRestricted
        validReceiver(_receiver)
    {
        _buyOrder(_receiver, _depositAmount, _minAmountOut);
    }
    // @todo want
    /// @notice Buy tokens for the sender's address.
    /// @dev
    /// @param _depositAmount The amount of collateral token depoisited.
    /// @param _minAmountOut The minimum acceptable amount the user expects to receive from the transaction.

    function buy(uint _depositAmount, uint _minAmountOut)
        public
        virtual
        override(BondingCurveBase_v1)
        buyingIsEnabled
        isBuyAndSellRestricted
    {
        _buyOrder(_msgSender(), _depositAmount, _minAmountOut);
    }
    // @todo want
    /// @notice Redeem tokens and directs the proceeds to a specified receiver address.
    /// @dev   This function wraps the `_sellOrder` internal function with specified parameters to handle
    ///         the transaction and direct the proceeds. The function has a mechanism to restrict the sell functionality
    ///         to the CURVE_INTERACTION_ROLE
    /// @param  _receiver The address that will receive the redeemed tokens.
    /// @param  _depositAmount The amount of tokens to be sold.
    /// @param  _minAmountOut The minimum acceptable amount of proceeds that the receiver should receive from the sale.

    function sellTo(address _receiver, uint _depositAmount, uint _minAmountOut)
        public
        virtual
        override(RedeemingBondingCurveBase_v1)
        sellingIsEnabled
        isBuyAndSellRestricted
        validReceiver(_receiver)
    {
        _sellOrder(_receiver, _depositAmount, _minAmountOut);
    }
    // @todo want
    /// @notice Redeem collateral for the sender's address.
    /// @dev    The function has a mechanism to restrict the sell functionality to the CURVE_INTERACTION_ROLE.
    /// @param _depositAmount The amount of issued token depoisited.
    /// @param _minAmountOut The minimum acceptable amount the user expects to receive from the transaction.
    /// @param _minAmountOut The minimum acceptable amount the user expects to receive from the transaction.

    function sell(uint _depositAmount, uint _minAmountOut)
        public
        virtual
        override(RedeemingBondingCurveBase_v1)
        sellingIsEnabled
        isBuyAndSellRestricted
    {
        _sellOrder(_msgSender(), _depositAmount, _minAmountOut);
    }

    // @todo want
    /// @inheritdoc IFM_BC_BondingSurface_Redeeming_v1
    function calculateBasePriceToCapitalRatio(
        uint _capitalRequired,
        uint _basePriceMultiplier
    ) external pure returns (uint) {
        return _calculateBasePriceToCapitalRatio(
            _capitalRequired, _basePriceMultiplier
        );
    }
    // @todo want
    /// @notice Calculates and returns the static price for buying the issuance token.
    /// @return uint The static price for buying the issuance token.

    function getStaticPriceForBuying()
        external
        view
        override(BondingCurveBase_v1)
        returns (uint)
    {
        return _issueTokensFormulaWrapper(1);
    }
    // @todo want
    /// @notice Calculates and returns the static price for selling the issuance token.
    ///         The return value is formatted in PPM.
    /// @return uint The static price for selling the issuance token.

    function getStaticPriceForSelling()
        external
        view
        override(RedeemingBondingCurveBase_v1)
        returns (uint)
    {
        return _redeemTokensFormulaWrapper(1);
    }

    //--------------------------------------------------------------------------
    // Public IFundingManager Functions

    /// @inheritdoc IFundingManager_v1
    function token() public view returns (IERC20) {
        return _token;
    }

    //--------------------------------------------------------------------------
    // OnlyCoverManager Functions

    // @todo want
    /// @inheritdoc IFM_BC_BondingSurface_Redeeming_v1
    function restrictBuyAndSell()
        external
        onlyModuleRole(COVER_MANAGER_ROLE) //@todo use OrchestratorAdmin here
    {
        buyAndSellIsRestricted = true;
        emit BuyAndSellIsRestricted();
    }
    // @todo want
    /// @inheritdoc IFM_BC_BondingSurface_Redeeming_v1

    function unrestrictBuyAndSell()
        external
        onlyModuleRole(COVER_MANAGER_ROLE) //@todo use OrchestratorAdmin here
    {
        buyAndSellIsRestricted = false;
        emit BuyAndSellIsUnrestricted();
    }

    //--------------------------------------------------------------------------
    // OnlyRiskManager Functions
    // @todo want
    /// @inheritdoc IFM_BC_BondingSurface_Redeeming_v1
    function setCapitalRequired(uint _newCapitalRequired)
        public
        onlyModuleRole(RISK_MANAGER_ROLE) //@todo use OrchestratorAdmin here
    {
        _setCapitalRequired(_newCapitalRequired);
    }
    // @todo want
    /// @inheritdoc IFM_BC_BondingSurface_Redeeming_v1

    function setBasePriceMultiplier(uint _newBasePriceMultiplier)
        public
        onlyModuleRole(RISK_MANAGER_ROLE) //@todo use OrchestratorAdmin here
    {
        _setBasePriceMultiplier(_newBasePriceMultiplier);
    }

    //--------------------------------------------------------------------------
    // Upstream Function Implementations
    // @todo want
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
            revert
                FM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1__NoCapitalAvailable(
            );
        }

        mintAmount = formula.tokenOut(
            _depositAmount, capitalAvailable, basePriceToCapitalRatio
        );
    }
    // @todo want
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
            revert
                FM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1__NoCapitalAvailable(
            );
        }
        redeemAmount = formula.tokenIn(
            _depositAmount, capitalAvailable, basePriceToCapitalRatio
        );

        // The asset pool must never be empty.
        if (capitalAvailable - redeemAmount < MIN_RESERVE) {
            redeemAmount = capitalAvailable - MIN_RESERVE;
        }
    }

    //--------------------------------------------------------------------------
    // OnlyOrchestrator Functions
    // @todo want
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

        emit TransferOrchestratorToken(to, amount);
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    // @todo want
    /// @dev Returns the collateral available in this contract, subtracted by the fee collected
    /// @return uint Capital available in contract
    function _getCapitalAvailable() internal view returns (uint) {
        return _token.balanceOf(address(this)) - projectCollateralFeeCollected;
    }
    // @todo want
    /// @dev Set the capital required state used in the bonding curve calculations.
    /// _newCapitalRequired cannot be zero

    function _setCapitalRequired(uint _newCapitalRequired) internal {
        if (_newCapitalRequired == 0) {
            revert
                FM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1__InvalidInputAmount(
            );
        }
        emit CapitalRequiredChanged(capitalRequired, _newCapitalRequired);
        capitalRequired = _newCapitalRequired;
        _updateVariables();
    }
    // @todo want

    function _setBasePriceMultiplier(uint _newBasePriceMultiplier) internal {
        if (_newBasePriceMultiplier == 0) {
            revert
                FM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1__InvalidInputAmount(
            );
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
    // @todo want
    /// @dev Internal function which calculates the price multiplier to capital ratio

    function _calculateBasePriceToCapitalRatio(
        uint _capitalRequired,
        uint _basePriceMultiplier
    ) internal pure returns (uint _basePriceToCapitalRatio) {
        _basePriceToCapitalRatio = FixedPointMathLib.fdiv(
            _basePriceMultiplier, _capitalRequired, FixedPointMathLib.WAD
        );
        if (_basePriceToCapitalRatio > 1e36) {
            revert
                FM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1__InvalidInputAmount(
            );
        }
    }

    function _isBuyAndSellRestrictedModifier() internal view {
        if (buyAndSellIsRestricted) {
            _checkRoleModifier(CURVE_INTERACTION_ROLE, _msgSender());
        }
    }
}
