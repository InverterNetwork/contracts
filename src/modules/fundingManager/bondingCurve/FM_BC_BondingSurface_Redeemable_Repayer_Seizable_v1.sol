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
import {IFM_BC_BondingSurface_Redeemable_Repayer_Seizable_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_BondingSurface_Redeemable_Repayer_Seizable_v1.sol";
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
contract FM_BC_BondingSurface_Redeemable_Repayer_Seizable_v1 is
    IRepayer_v1,
    IFM_BC_BondingSurface_Redeemable_Repayer_Seizable_v1,
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
        return interfaceId == type(IRedeemingBondingCurveBase_v1).interfaceId
            || super.supportsInterface(interfaceId);
    }

    using SafeERC20 for IERC20;

    //--------------------------------------------------------------------------
    // Constants

    /// @dev Minimum collateral reserve
    uint public constant MIN_RESERVE = 1 ether;
    /// @dev Max seizable amount is 1% expressed in BPS
    uint64 public constant MAX_SEIZE = 100;
    /// @dev Max fee for selling is 1% expressed in BPS
    uint64 public constant MAX_FEE = 100;
    /// @dev Time interval between seizes
    uint64 public constant SEIZE_DELAY = 7 days;
    /// @dev Role associated with the managing of the bonding curve values
    bytes32 public constant RISK_MANAGER_ROLE = "RISK_MANAGER";
    /// @dev Role associated with the managing of setting withdraw addresses and setting the fee
    bytes32 public constant COVER_MANAGER_ROLE = "COVER_MANAGER";
    /// @dev Minter/Burner Role.
    bytes32 public constant CURVE_INTERACTION_ROLE = "CURVE_USER";

    //--------------------------------------------------------------------------
    // Storage

    /// @dev The interface of the Formula used to calculate the issuance and redeeming amount.
    IBondingSurface public formula;
    /// @notice Repayable amount collateral which can be pulled from the contract by the liquidity vault controller
    uint public repayableAmount;
    /// @dev The current seize percentage expressed in BPS
    uint64 public currentSeize;
    /// @dev Address of the liquidity vault controller who has access to the collateral held by the funding manager
    /// through the Repayer functionality
    ILiquidityVaultController public liquidityVaultController;
    /// @dev Token that is accepted by this funding manager for deposits.
    IERC20 private _token;
    /// @dev Tracks last seize timestamp to determine eligibility for subsequent seizures based on SEIZE_DELAY.
    uint public lastSeizeTimestamp;
    /// @dev the amount of value that is needed to operate the protocol according to market size
    /// and conditions
    uint public capitalRequired;
    /// @dev Base price multiplier in the bonding curve formula
    uint public basePriceMultiplier;
    /// @dev (basePriceMultiplier / capitalRequired)
    uint public basePriceToCapitalRatio;
    /// @notice Restricts buying and selling functionalities to specific role.
    bool public buyAndSellIsRestricted;
    /// @notice Address of the reserve pool.
    address public tokenVault; // Todo: might need change from address to interface based on contract. Todo: Add interface type

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

        // Set liquidity vault controller address
        liquidityVaultController =
            ILiquidityVaultController(_liquidityVaultController);

        // Check for valid Bonding Surface formula contract
        if (
            !ERC165Upgradeable(bondingCurveProperties.formula).supportsInterface(
                type(IBondingSurface).interfaceId
            )
        ) {
            revert
                FM_BC_BondingSurface_Redeemable_Repayer_Seizable_v1__InvalidBondingSurfaceFormula(
            );
        }
        // Set formula contract
        formula = IBondingSurface(bondingCurveProperties.formula);
        // Set token Vault
        _setTokenVault(_tokenVault);

        // Set Bonding Curve Properties
        // Set capital required
        _setCapitalRequired(bondingCurveProperties.capitalRequired);
        // Set currentSeize
        _setSeize(bondingCurveProperties.seize);
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

    // Todo
    modifier onlyLiquidityVaultController() {
        if (_msgSender() != address(liquidityVaultController)) {
            revert
                FM_BC_BondingSurface_Redeemable_Repayer_Seizable_v1__InvalidLiquidityVaultController(
                _msgSender()
            );
        }
        _;
    }

    // Todo
    modifier isBuyAndSellRestricted() {
        _isBuyAndSellRestrictedModifier();
        _;
    }

    //--------------------------------------------------------------------------
    // Public Functions

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

    /// @inheritdoc IFM_BC_BondingSurface_Redeemable_Repayer_Seizable_v1
    function burnIssuanceToken(uint _amount) external {
        _burn(_msgSender(), _amount);
    }

    /// @inheritdoc IFM_BC_BondingSurface_Redeemable_Repayer_Seizable_v1
    function burnIssuanceTokenFor(address _owner, uint _amount) external {
        if (_owner != _msgSender()) {
            // Does not update allowance if set to infinite
            _spendAllowance(_owner, _msgSender(), _amount);
        }
        // Will revert if balance < amount
        _burn(_owner, _amount);
    }

    /// @inheritdoc IFM_BC_BondingSurface_Redeemable_Repayer_Seizable_v1
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
        return _issueTokensFormulaWrapper(1);
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
        return _redeemTokensFormulaWrapper(1);
    }

    //--------------------------------------------------------------------------
    // Implementation Specific Public Functions

    /// @inheritdoc IRepayer_v1
    function getRepayableAmount() external view returns (uint) {
        return _getRepayableAmount();
    }

    /// @inheritdoc IFM_BC_BondingSurface_Redeemable_Repayer_Seizable_v1
    function seizable() public view returns (uint) {
        uint currentBalance = _getCapitalAvailable();

        return (currentBalance * currentSeize) / BPS;
    }

    //--------------------------------------------------------------------------
    // Public Mutating Functions

    /// @inheritdoc IFundingManager_v1
    function token() public view returns (IERC20) {
        return _token;
    }

    //--------------------------------------------------------------------------
    // OnlyLiquidtyPool Functions

    /// @inheritdoc IRepayer_v1
    function transferRepayment(address _to, uint _amount)
        external
        validReceiver(_to)
        onlyLiquidityVaultController
    {
        if (_amount > _getRepayableAmount()) {
            revert Repayer__InsufficientCollateralForRepayerTransfer();
        }
        __Module_orchestrator.fundingManager().token().safeTransfer(
            _to, _amount
        );
        emit RepaymentTransfer(_to, _amount);
    }

    //--------------------------------------------------------------------------
    // OnlyCoverManager Functions

    /// @inheritdoc IFM_BC_BondingSurface_Redeemable_Repayer_Seizable_v1
    function seize(uint _amount) public onlyModuleRole(COVER_MANAGER_ROLE) {
        uint _seizableAmount = seizable();
        if (_amount > _seizableAmount) {
            revert
                FM_BC_BondingSurface_Redeemable_Repayer_Seizable_v1__InvalidSeizeAmount(
                _seizableAmount
            );
        }
        // solhint-disable-next-line not-rely-on-time
        else if (lastSeizeTimestamp + SEIZE_DELAY > block.timestamp) {
            revert
                FM_BC_BondingSurface_Redeemable_Repayer_Seizable_v1__SeizeTimeout(
                lastSeizeTimestamp + SEIZE_DELAY
            );
        }

        uint capitalAvailable = _getCapitalAvailable();
        // The asset pool must never be empty.
        if (capitalAvailable - _amount < MIN_RESERVE) {
            _amount = capitalAvailable - MIN_RESERVE;
        }

        // solhint-disable-next-line not-rely-on-time
        lastSeizeTimestamp = uint64(block.timestamp);
        _token.transfer(_msgSender(), _amount);
        emit CollateralSeized(_amount);
    }

    /// @inheritdoc IFM_BC_BondingSurface_Redeemable_Repayer_Seizable_v1
    function adjustSeize(uint64 _seize)
        public
        onlyModuleRole(COVER_MANAGER_ROLE)
    {
        _setSeize(_seize);
    }

    /// @inheritdoc IRedeemingBondingCurveBase_v1
    function setSellFee(uint _fee)
        external
        virtual
        override(RedeemingBondingCurveBase_v1)
        onlyModuleRole(COVER_MANAGER_ROLE)
    {
        if (_fee > MAX_FEE) {
            revert
                FM_BC_BondingSurface_Redeemable_Repayer_Seizable_v1__InvalidFeePercentage(
                _fee
            );
        }
        _setSellFee(_fee);
    }

    /// @inheritdoc IFM_BC_BondingSurface_Redeemable_Repayer_Seizable_v1
    function restrictBuyAndSell() external onlyModuleRole(COVER_MANAGER_ROLE) {
        buyAndSellIsRestricted = true;
        emit BuyAndSellIsRestricted();
    }

    /// @inheritdoc IFM_BC_BondingSurface_Redeemable_Repayer_Seizable_v1
    function unrestrictBuyAndSell()
        external
        onlyModuleRole(COVER_MANAGER_ROLE)
    {
        buyAndSellIsRestricted = false;
        emit BuyAndSellIsUnrestricted();
    }

    /// @inheritdoc IRepayer_v1
    function setRepayableAmount(uint _amount)
        external
        onlyModuleRole(COVER_MANAGER_ROLE)
    {
        if (_amount > _getSmallerCaCr()) {
            revert
                FM_BC_BondingSurface_Redeemable_Repayer_Seizable_v1__InvalidInputAmount(
            );
        }
        emit RepayableAmountChanged(_amount, repayableAmount);
        repayableAmount = _amount;
    }

    /// @inheritdoc IFM_BC_BondingSurface_Redeemable_Repayer_Seizable_v1
    function setLiquidityVaultControllerContract(ILiquidityVaultController _lvc)
        external
        onlyModuleRole(COVER_MANAGER_ROLE)
    {
        // @note When upgrading to Topos next version, we should add an interface check here.
        if (address(_lvc) == address(0) || address(_lvc) == address(this)) {
            revert
                FM_BC_BondingSurface_Redeemable_Repayer_Seizable_v1__InvalidInputAddress(
            );
        }
        emit LiquidityVaultControllerChanged(
            address(_lvc), address(liquidityVaultController)
        );
        liquidityVaultController = _lvc;
    }

    function setBuyFee(uint /*_fee*/ )
        external
        pure
        override(BondingCurveBase_v1)
    {
        revert
            FM_BC_BondingSurface_Redeemable_Repayer_Seizable_v1__InvalidFunctionality(
        );
    }

    //--------------------------------------------------------------------------
    // OnlyRiskManager Functions

    /// @inheritdoc IFM_BC_BondingSurface_Redeemable_Repayer_Seizable_v1
    function setCapitalRequired(uint _newCapitalRequired)
        public
        onlyModuleRole(RISK_MANAGER_ROLE)
    {
        _setCapitalRequired(_newCapitalRequired);
    }

    /// @inheritdoc IFM_BC_BondingSurface_Redeemable_Repayer_Seizable_v1
    function setBasePriceMultiplier(uint _newBasePriceMultiplier)
        public
        onlyModuleRole(RISK_MANAGER_ROLE)
    {
        _setBasePriceMultiplier(_newBasePriceMultiplier);
    }

    //--------------------------------------------------------------------------
    // OnlyOrchestratorAdmin Functions

    function setTokenVault(
        address _tokenVault //@todo test
    ) external onlyOrchestratorAdmin {
        _setTokenVault(_tokenVault);
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
            revert
                FM_BC_BondingSurface_Redeemable_Repayer_Seizable_v1__NoCapitalAvailable(
            );
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
            revert
                FM_BC_BondingSurface_Redeemable_Repayer_Seizable_v1__NoCapitalAvailable(
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

    /// @dev Sets the token vault address.
    /// @param _tokenVault The address of the token vault.
    function _setTokenVault(
        address _tokenVault //@todo test
    ) internal validAddress(_tokenVault) {
        tokenVault = _tokenVault;
    }

    /// @dev Set the current seize state, which defines the percentage of seizable amount
    function _setSeize(uint64 _seize) internal {
        if (_seize > MAX_SEIZE) {
            revert
                FM_BC_BondingSurface_Redeemable_Repayer_Seizable_v1__InvalidSeize(
                _seize
            );
        }
        emit SeizeChanged(currentSeize, _seize);
        currentSeize = _seize;
    }

    /// @dev Returns the collateral available in this contract, subtracted by the fee collected
    /// @return uint Capital available in contract
    function _getCapitalAvailable() internal view returns (uint) {
        return _token.balanceOf(address(this)) - projectCollateralFeeCollected;
    }

    /// @dev Set the capital required state used in the bonding curve calculations.
    /// _newCapitalRequired cannot be zero
    function _setCapitalRequired(uint _newCapitalRequired) internal {
        if (_newCapitalRequired == 0) {
            revert
                FM_BC_BondingSurface_Redeemable_Repayer_Seizable_v1__InvalidInputAmount(
            );
        }
        emit CapitalRequiredChanged(capitalRequired, _newCapitalRequired);
        capitalRequired = _newCapitalRequired;
        _updateVariables();
    }

    function _setBasePriceMultiplier(uint _newBasePriceMultiplier) internal {
        if (_newBasePriceMultiplier == 0) {
            revert
                FM_BC_BondingSurface_Redeemable_Repayer_Seizable_v1__InvalidInputAmount(
            );
        }
        emit BasePriceMultiplierChanged(
            basePriceMultiplier, _newBasePriceMultiplier
        );
        basePriceMultiplier = _newBasePriceMultiplier;
        _updateVariables();
    }

    /// @notice If the repayable amount was not defined, it is automatically set to the smaller between the Ca and the Cr value
    /// @notice The repayable amount as maximum is applied when is gt 0 and is lt the smallest between Cr and Ca
    function _getRepayableAmount() internal view returns (uint) {
        uint _repayable = _getSmallerCaCr();
        return (repayableAmount == 0 || repayableAmount > _repayable)
            ? _repayable
            : repayableAmount;
    }

    /// @notice If the balance of the Capital Available (Ca) is larger than the Capital Required (Cr), the repayable amount can be lte Cr
    /// @notice If the Ca is lt Cr, the max repayable amount is the Ca
    function _getSmallerCaCr() internal view returns (uint) {
        uint _ca = _getCapitalAvailable();
        uint _cr = capitalRequired;
        return _ca > _cr ? _cr : _ca;
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
            revert
                FM_BC_BondingSurface_Redeemable_Repayer_Seizable_v1__InvalidInputAmount(
            );
        }
    }

    function _isBuyAndSellRestrictedModifier() internal view {
        if (buyAndSellIsRestricted) {
            _checkRoleModifier(CURVE_INTERACTION_ROLE, _msgSender());
        }
    }
}
