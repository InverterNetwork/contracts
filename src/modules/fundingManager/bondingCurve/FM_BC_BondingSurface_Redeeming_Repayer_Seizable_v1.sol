// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Dependencies
import {Module_v1} from "src/modules/base/Module_v1.sol";
import {FM_BC_BondingSurface_Redeeming_v1} from
    "@fm/bondingCurve/FM_BC_BondingSurface_Redeeming_v1.sol";
import {RedeemingBondingCurveBase_v1} from
    "@fm/bondingCurve/abstracts/RedeemingBondingCurveBase_v1.sol";
import {BondingCurveBase_v1} from
    "@fm/bondingCurve/abstracts/BondingCurveBase_v1.sol";
import {FixedPointMathLib} from "src/modules/lib/FixedPointMathLib.sol";
import {FM_BC_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/FM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";

// Internal Interfaces
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";
import {IRedeemingBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IRedeemingBondingCurveBase_v1.sol";
import {IFM_BC_BondingSurface_Redeeming_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_BondingSurface_Redeeming_v1.sol";
import {IFM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1.sol";
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
contract FM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1 is
    IRepayer_v1,
    IFM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1,
    FM_BC_BondingSurface_Redeeming_v1
{
    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(
        bytes4 interfaceId //@todo adapt tests
    )
        public
        view
        virtual
        override(FM_BC_BondingSurface_Redeeming_v1)
        returns (bool)
    {
        return interfaceId
            == type(IFM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1).interfaceId
            || interfaceId == type(IRepayer_v1).interfaceId
            || super.supportsInterface(interfaceId);
    }

    using SafeERC20 for IERC20;

    //--------------------------------------------------------------------------
    // Constants

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

    /// @notice Repayable amount collateral which can be pulled from the contract by the liquidity vault controller
    uint public repayableAmount;
    /// @dev The current seize percentage expressed in BPS
    uint64 public currentSeize;
    /// @dev Address of the liquidity vault controller who has access to the collateral held by the funding manager
    /// through the Repayer functionality
    ILiquidityVaultController public liquidityVaultController;
    /// @dev Tracks last seize timestamp to determine eligibility for subsequent seizures based on SEIZE_DELAY.
    uint public lastSeizeTimestamp;
    /// @dev the amount of value that is needed to operate the protocol according to market size
    /// and conditions
    /// @notice Address of the reserve pool.
    address public tokenVault; // Todo: might need change from address to interface based on contract. Todo: Add interface type

    /// @notice Restricts buying and selling functionalities to specific role.
    bool public buyAndSellIsRestricted;

    //--------------------------------------------------------------------------
    // Init Function

    /// @inheritdoc Module_v1
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata,
        bytes memory configData
    ) external override(FM_BC_BondingSurface_Redeeming_v1) initializer {
        __Module_init(orchestrator_, metadata);

        address _issuanceToken;
        address _acceptedToken;
        address _tokenVault;
        address _liquidityVaultController;
        BondingCurveProperties memory bondingCurveProperties;
        uint64 _seize;

        (
            _issuanceToken,
            _acceptedToken,
            _tokenVault,
            _liquidityVaultController,
            bondingCurveProperties,
            _seize
        ) = abi.decode(
            configData,
            (address, address, address, address, BondingCurveProperties, uint64)
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

        // Set currentSeize
        _setSeize(_seize);

        emit OrchestratorTokenSet(
            _acceptedToken, IERC20Metadata(address(_token)).decimals()
        );
    }

    //--------------------------------------------------------------------------
    // Modifiers

    modifier isBuyAndSellRestricted() {
        _isBuyAndSellRestrictedModifier();
        _;
    }

    // @todo want
    modifier onlyLiquidityVaultController() {
        if (_msgSender() != address(liquidityVaultController)) {
            revert
                FM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1__InvalidLiquidityVaultController(
                _msgSender()
            );
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Public Functions

    /// @notice Buy tokens on behalf of a specified receiver address.
    /// @dev The buy functionality can be restircted to the CURVE_INTERACTION_ROLE.
    /// @param _receiver The address that will receive the bought tokens.
    /// @param _depositAmount The amount of collateral token depoisited.
    /// @param _minAmountOut The minimum acceptable amount the user expects to receive from the transaction.
    function buyFor(address _receiver, uint _depositAmount, uint _minAmountOut)
        public
        virtual
        override(FM_BC_BondingSurface_Redeeming_v1)
        isBuyAndSellRestricted
    {
        super._buyOrder(_receiver, _depositAmount, _minAmountOut);
    }

    /// @notice Buy tokens for the sender's address.
    /// @dev The buy functionality can be restircted to the CURVE_INTERACTION_ROLE.
    /// @param _depositAmount The amount of collateral token depoisited.
    /// @param _minAmountOut The minimum acceptable amount the user expects to receive from the transaction.
    function buy(uint _depositAmount, uint _minAmountOut)
        public
        virtual
        override(FM_BC_BondingSurface_Redeeming_v1)
        isBuyAndSellRestricted
    {
        super._buyOrder(_msgSender(), _depositAmount, _minAmountOut);
    }

    /// @notice Redeem tokens and directs the proceeds to a specified receiver address.
    /// @dev    The sell functionality can be restircted to the CURVE_INTERACTION_ROLE.
    /// @param  _receiver The address that will receive the redeemed tokens.
    /// @param  _depositAmount The amount of tokens to be sold.
    /// @param  _minAmountOut The minimum acceptable amount of proceeds that the receiver should receive from the sale.
    function sellTo(address _receiver, uint _depositAmount, uint _minAmountOut)
        public
        virtual
        override(FM_BC_BondingSurface_Redeeming_v1)
        isBuyAndSellRestricted
    {
        super._sellOrder(_receiver, _depositAmount, _minAmountOut);
    }

    /// @notice Redeem collateral for the sender's address.
    /// @dev    The sell functionality can be restircted to the CURVE_INTERACTION_ROLE.
    /// @param _depositAmount The amount of issued token depoisited.
    /// @param _minAmountOut The minimum acceptable amount the user expects to receive from the transaction.
    /// @param _minAmountOut The minimum acceptable amount the user expects to receive from the transaction.
    function sell(uint _depositAmount, uint _minAmountOut)
        public
        virtual
        override(FM_BC_BondingSurface_Redeeming_v1)
        isBuyAndSellRestricted
    {
        super._sellOrder(_msgSender(), _depositAmount, _minAmountOut);
    }

    /// @inheritdoc IFM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1
    function burnIssuanceToken(uint _amount) external {
        _burn(_msgSender(), _amount);
    }

    /// @inheritdoc IFM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1
    function burnIssuanceTokenFor(address _owner, uint _amount) external {
        if (_owner != _msgSender()) {
            // Does not update allowance if set to infinite
            _spendAllowance(_owner, _msgSender(), _amount);
        }
        // Will revert if balance < amount
        _burn(_owner, _amount);
    }

    /// @inheritdoc IRepayer_v1
    function getRepayableAmount() external view returns (uint) {
        return _getRepayableAmount();
    }

    /// @inheritdoc IFM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1
    function seizable() public view returns (uint) {
        uint currentBalance = _getCapitalAvailable();

        return (currentBalance * currentSeize) / BPS;
    }

    //--------------------------------------------------------------------------
    // OnlyLiquidityVaultController Functions

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

    /// @inheritdoc IFM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1
    function restrictBuyAndSell() external onlyModuleRole(COVER_MANAGER_ROLE) {
        buyAndSellIsRestricted = true;
        emit BuyAndSellIsRestricted();
    }

    /// @inheritdoc IFM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1
    function unrestrictBuyAndSell()
        external
        onlyModuleRole(COVER_MANAGER_ROLE)
    {
        buyAndSellIsRestricted = false;
        emit BuyAndSellIsUnrestricted();
    }

    /// @inheritdoc IFM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1
    function seize(uint _amount) public onlyModuleRole(COVER_MANAGER_ROLE) {
        uint _seizableAmount = seizable();
        if (_amount > _seizableAmount) {
            revert
                FM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1__InvalidSeizeAmount(
                _seizableAmount
            );
        }
        // solhint-disable-next-line not-rely-on-time
        else if (lastSeizeTimestamp + SEIZE_DELAY > block.timestamp) {
            revert
                FM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1__SeizeTimeout(
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

    /// @inheritdoc IFM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1
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
        //@todo can be removed from test as its already checked in the base contract
        // @note Overridden the internal _validateWorkflowFee function as the max is different than specified for Topos
        _setSellFee(_fee);
    }

    /// @inheritdoc IRepayer_v1
    function setRepayableAmount(uint _amount)
        external
        onlyModuleRole(COVER_MANAGER_ROLE)
    {
        if (_amount > _getSmallerCaCr()) {
            revert
                FM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1__InvalidInputAmount(
            );
        }
        emit RepayableAmountChanged(_amount, repayableAmount);
        repayableAmount = _amount;
    }

    /// @inheritdoc IFM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1
    function setLiquidityVaultControllerContract(ILiquidityVaultController _lvc)
        external
        onlyModuleRole(COVER_MANAGER_ROLE)
    {
        // @note When upgrading to Topos next version, we should add an interface check here.
        if (address(_lvc) == address(0) || address(_lvc) == address(this)) {
            revert
                FM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1__InvalidInputAddress(
            );
        }
        emit LiquidityVaultControllerChanged(
            address(_lvc), address(liquidityVaultController)
        );
        liquidityVaultController = _lvc;
    }

    /// @notice Disabled function for setting the buy fee
    function setBuyFee(uint /*_fee*/ )
        external
        pure
        override(BondingCurveBase_v1)
    {
        revert
            FM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1__InvalidFunctionality(
        );
    }

    //--------------------------------------------------------------------------
    // OnlyRiskManager Functions

    function setCapitalRequired(uint _newCapitalRequired)
        public
        override(FM_BC_BondingSurface_Redeeming_v1)
        onlyModuleRole(RISK_MANAGER_ROLE) //@todo override
    {
        _setCapitalRequired(_newCapitalRequired);
    }

    function setBasePriceMultiplier(uint _newBasePriceMultiplier)
        public
        override(FM_BC_BondingSurface_Redeeming_v1)
        onlyModuleRole(RISK_MANAGER_ROLE) //@todo override
    {
        _setBasePriceMultiplier(_newBasePriceMultiplier);
    }

    //--------------------------------------------------------------------------
    // OnlyOrchestratorAdmin Functions

    //@todo Natspec
    function setTokenVault(
        address _tokenVault //@todo test
    ) external onlyOrchestratorAdmin {
        _setTokenVault(_tokenVault);
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    /// @dev Sets the token vault address.
    /// @param _tokenVault The address of the token vault.
    function _setTokenVault(address _tokenVault)
        internal
        validAddress(_tokenVault)
    {
        tokenVault = _tokenVault;
    }

    /// @dev Set the current seize state, which defines the percentage of seizable amount
    function _setSeize(uint64 _seize) internal {
        if (_seize > MAX_SEIZE) {
            revert
                FM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1__InvalidSeize(
                _seize
            );
        }
        emit SeizeChanged(currentSeize, _seize);
        currentSeize = _seize;
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

    /// @dev    Validates the workflow fee.
    function _validateWorkflowFee(uint _workflowFee)
        internal
        pure
        override(BondingCurveBase_v1)
    {
        if (_workflowFee > MAX_FEE) {
            revert Module__BondingCurveBase__InvalidFeePercentage(); //@todo do we need to output the fee amount?
        }
    }

    ///@dev Validate if buy and sell is restricted, and if so
    ///     check if the caller has the CURVE_INTERACTION_ROLE
    function _isBuyAndSellRestrictedModifier() internal view {
        if (buyAndSellIsRestricted) {
            _checkRoleModifier(CURVE_INTERACTION_ROLE, _msgSender());
        }
    }
}
