// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal
import {Module_v1} from "src/modules/base/Module_v1.sol";
import {FM_BC_BondingSurface_Redeeming_v1} from
    "@fm/bondingCurve/FM_BC_BondingSurface_Redeeming_v1.sol";
import {RedeemingBondingCurveBase_v1} from
    "@fm/bondingCurve/abstracts/RedeemingBondingCurveBase_v1.sol";
import {BondingCurveBase_v1} from
    "@fm/bondingCurve/abstracts/BondingCurveBase_v1.sol";
import {FixedPointMathLib} from "@modLib/FixedPointMathLib.sol";
import {FM_BC_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/FM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";
import {IRedeemingBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IRedeemingBondingCurveBase_v1.sol";
import {IFM_BC_BondingSurface_Redeeming_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_BondingSurface_Redeeming_v1.sol";
import {IFM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1.sol";
import {IRepayer_v1} from "@fm/bondingCurve/interfaces/IRepayer_v1.sol";
import {ILiquidityVaultController_v1} from
    "@lm/interfaces/ILiquidityVaultController_v1.sol";
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";
import {IBondingSurface} from "@fm/bondingCurve/interfaces/IBondingSurface.sol";
import {IAuthorizer_v1} from "@aut/IAuthorizer_v1.sol";

// External
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@oz/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

/**
 * @title   Inverter Redeeming Restricted Repayer Seizable Bonding
 *          Surface Bonding Curve Funding Manager
 *
 * @notice  This contract enables the issuance and redeeming of tokens on a
 *          bonding curve.
 *
 * @dev     This contract inherits functionalties from the contracts:
 *              - BondingCurveBase_v1
 *              - RedeemingBondingCurveBase_v1
 *              - Repayer
 *          The contract should be used by the orchestrator admin to manage all
 *          the configuration for the bonding curve as well as the opening and
 *          closing of the issuance and redemption functionalities.
 *          The contract implements the formulaWrapper functions enforced by
 *          using the Bonding Surface formula to calculate the issuance/
 *          redemption rate.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to
 *                          our Security Policy at security.inverter.network or
 *                          email us directly!
 *
 * @custom:version v1.0.0
 *
 * @custom:inverter-standard-version 0.1.0
 *
 * @author  Inverter Network
 */
contract FM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1 is
    IRepayer_v1,
    IFM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1,
    FM_BC_BondingSurface_Redeeming_v1
{
    using SafeERC20 for IERC20;

    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId_)
        public
        view
        virtual
        override(FM_BC_BondingSurface_Redeeming_v1)
        returns (bool supportsInterface_)
    {
        return interfaceId_
            == type(IFM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1)
                .interfaceId || interfaceId_ == type(IRepayer_v1).interfaceId
            || super.supportsInterface(interfaceId_);
    }

    // -------------------------------------------------------------------------
    // Constants

    /// @dev Max seizable amount is 1% expressed in BPS
    uint64 public constant MAX_SEIZE = 100;
    /// @dev Max fee for selling is 1% expressed in BPS
    uint64 public constant MAX_FEE = 100;
    /// @dev Time interval between seizes
    uint64 public constant SEIZE_DELAY = 7 days;
    /// @dev Role associated with the managing of the bonding curve values
    bytes32 public constant RISK_MANAGER_ROLE = "RISK_MANAGER";
    /// @dev Role associated with the managing of setting withdraw addresses
    ///      and setting the fee
    bytes32 public constant COVER_MANAGER_ROLE = "COVER_MANAGER";
    /// @dev Minter/Burner Role.
    bytes32 public constant CURVE_INTERACTION_ROLE = "CURVE_USER";

    // -------------------------------------------------------------------------
    // Storage

    /// @dev Repayable amount collateral which can be pulled from the
    ///         contract by the liquidity vault controller
    uint internal _repayableAmount;
    /// @dev The current seize percentage expressed in BPS
    uint64 internal _currentSeize;
    /// @dev Address of the liquidity vault controller who has access to the
    ///      collateral held by the funding manager through the Repayer
    /// through the Repayer functionality
    ILiquidityVaultController_v1 internal _liquidityVaultController;
    /// @dev Tracks last seize timestamp to determine eligibility for
    ///      subsequent seizures based on SEIZE_DELAY
    uint internal _lastSeizeTimestamp;
    /// @dev Address of the reserve pool.
    address internal _tokenVault;
    /// @dev Restricts buying and selling functionalities to specific role.
    bool internal _buyAndSellIsRestricted;

    /// @dev    Storage gap for future upgrades.
    uint[50] private __gap;

    // -------------------------------------------------------------------------
    // Modifiers

    modifier checkBuyAndSellRestrictions() {
        //@note Naming? Naming Functions Contracts Modifier General
        _checkBuyAndSellRestrictionsModifier();
        _;
    }

    modifier onlyLiquidityVaultController() {
        //@note Naming?
        _ensureOnlyLiquidityVaultController();
        _;
    }

    // -------------------------------------------------------------------------
    // Init Function

    /// @inheritdoc Module_v1
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata_,
        bytes memory configData_
    ) external override(FM_BC_BondingSurface_Redeeming_v1) initializer {
        __Module_init(orchestrator_, metadata_);

        address issuanceToken;
        address acceptedToken;
        BondingCurveProperties memory bondingCurveProperties;
        address liquidityVaultController;
        uint64 newSeize;
        // Indicates whether buying and selling is restricted to the
        // CURVE_INTERACTION_ROLE or open to anyone.
        bool buyAndSellIsRestricted;

        (
            issuanceToken,
            acceptedToken,
            bondingCurveProperties,
            liquidityVaultController,
            newSeize,
            buyAndSellIsRestricted
        ) = abi.decode(
            configData_,
            (address, address, BondingCurveProperties, address, uint64, bool)
        );
        __Module_init(orchestrator_, metadata_);
        __FM_BC_BondingSurface_Redeeming_v1_Init(
            issuanceToken, acceptedToken, bondingCurveProperties
        );
        __FM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1_Init(
            liquidityVaultController, newSeize, buyAndSellIsRestricted
        );
    }

    function __FM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1_Init(
        address liquidityVaultController,
        uint64 newSeize,
        bool buyAndSellIsRestricted
    ) internal onlyInitializing {
        _liquidityVaultController =
            ILiquidityVaultController_v1(liquidityVaultController);

        // Set buy and sell restriction to restricted if true. By default buy and
        // sell is unrestricted
        _buyAndSellIsRestricted = buyAndSellIsRestricted;

        _setSeize(newSeize);
    }

    // =========================================================================
    // Public Functions

    // -------------------------------------------------------------------------
    // Getter Functions

    /// @inheritdoc IFM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1
    function getSeizableAmount() public view returns (uint amount_) {
        uint currentBalance = _getCapitalAvailable();

        return (currentBalance * _currentSeize) / BPS;
    }

    /// @inheritdoc IFM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1
    function getCurrentSeize() public view returns (uint64 currentSeize_) {
        return _currentSeize;
    }

    /// @inheritdoc IFM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1
    function getLiquidityVaultController()
        public
        view
        returns (address liquidityVaultController_)
    {
        return address(_liquidityVaultController);
    }

    /// @inheritdoc IFM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1
    function getLastSeizeTimestamp()
        public
        view
        returns (uint lastSeizeTimestamp_)
    {
        return _lastSeizeTimestamp;
    }

    /// @inheritdoc IFM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1
    function getTokenVault() public view returns (address tokenVault_) {
        return address(_tokenVault);
    }

    /// @inheritdoc IFM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1
    function isBuyAndSellRestricted()
        public
        view
        returns (bool buyAndSellIsRestricted_)
    {
        return _buyAndSellIsRestricted;
    }

    /// @inheritdoc IRepayer_v1
    function getRepayableAmount()
        external
        view
        returns (uint repayableAmount_)
    {
        return _getRepayableAmount();
    }

    // =========================================================================
    // Mutating Functions

    // -------------------------------------------------------------------------
    // Mutating - Token Manipulation Functions

    /// @notice Buy tokens on behalf of a specified receiver address.
    /// @dev    The buy functionality can be restircted to the CURVE_INTERACTION_ROLE.
    /// @param  receiver_ The address that will receive the bought tokens.
    /// @param  depositAmount_ The amount of collateral token depoisited.
    /// @param  minAmountOut_ The minimum acceptable amount the user expects to
    ///         receive from the transaction.
    function buyFor(address receiver_, uint depositAmount_, uint minAmountOut_)
        public
        virtual
        override(BondingCurveBase_v1)
        checkBuyAndSellRestrictions
    {
        super.buyFor(receiver_, depositAmount_, minAmountOut_);
    }

    /// @notice Buy tokens for the sender's address.
    /// @dev    The buy functionality can be restircted to the CURVE_INTERACTION_ROLE.
    /// @param  depositAmount_ The amount of collateral token depoisited.
    /// @param  minAmountOut_ The minimum acceptable amount the user expects to receive
    ///         from the transaction.
    function buy(uint depositAmount_, uint minAmountOut_)
        public
        virtual
        override(BondingCurveBase_v1)
    {
        buyFor(_msgSender(), depositAmount_, minAmountOut_);
    }

    /// @notice Redeem tokens and directs the proceeds to a specified receiver address.
    /// @dev    The sell functionality can be restircted to the CURVE_INTERACTION_ROLE.
    /// @param  receiver_ The address that will receive the redeemed tokens.
    /// @param  depositAmount_ The amount of tokens to be sold.
    /// @param  minAmountOut_ The minimum acceptable amount of proceeds that the receiver
    ///         should receive from the sale.
    function sellTo(address receiver_, uint depositAmount_, uint minAmountOut_)
        public
        virtual
        override(RedeemingBondingCurveBase_v1)
        checkBuyAndSellRestrictions
    {
        super.sellTo(receiver_, depositAmount_, minAmountOut_);
    }

    /// @notice Redeem collateral for the sender's address.
    /// @dev    The sell functionality can be restircted to the CURVE_INTERACTION_ROLE.
    /// @param  depositAmount_ The amount of issued token depoisited.
    /// @param  minAmountOut_ The minimum acceptable amount the user expects to receive
    ///         from the transaction.
    function sell(uint depositAmount_, uint minAmountOut_)
        public
        virtual
        override(RedeemingBondingCurveBase_v1)
    {
        sellTo(_msgSender(), depositAmount_, minAmountOut_);
    }

    /// @inheritdoc IFM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1
    function burnIssuanceToken(uint amount_) external {
        _burn(_msgSender(), amount_);
    }

    /// @inheritdoc IFM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1
    function burnIssuanceTokenFor(address owner_, uint amount_) external {
        if (owner_ != _msgSender()) {
            // Does not update allowance if set to infinite
            _spendAllowance(owner_, _msgSender(), amount_);
        }
        // Will revert if balance < amount
        _burn(owner_, amount_);
    }

    // -------------------------------------------------------------------------
    // Mutating - OnlyLiquidityVaultController Functions

    /// @inheritdoc IRepayer_v1
    function transferRepayment(address to_, uint amount_)
        external
        validReceiver(to_)
        onlyLiquidityVaultController
    {
        if (amount_ > _getRepayableAmount()) {
            revert Repayer__InsufficientCollateralForRepayerTransfer();
        }
        __Module_orchestrator.fundingManager().token().safeTransfer(
            to_, amount_
        );
        if (MIN_RESERVE > token().balanceOf(address(this))) {
            revert FM_BC_BondingSurface_Redeeming_v1__MinReserveReached();
        }

        emit RepaymentTransfer(to_, amount_);
    }

    // -------------------------------------------------------------------------
    // Mutating - OnlyCoverManager Functions

    /// @inheritdoc IFM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1
    function restrictBuyAndSell() external onlyModuleRole(COVER_MANAGER_ROLE) {
        _buyAndSellIsRestricted = true;
        emit BuyAndSellIsRestricted();
    }

    /// @inheritdoc IFM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1
    function unrestrictBuyAndSell()
        external
        onlyModuleRole(COVER_MANAGER_ROLE)
    {
        _buyAndSellIsRestricted = false;
        emit BuyAndSellIsUnrestricted();
    }

    /// @inheritdoc IFM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1
    function seize(uint amount_) public onlyModuleRole(COVER_MANAGER_ROLE) {
        uint _seizableAmount = getSeizableAmount();
        if (amount_ > _seizableAmount) {
            revert
                FM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1__InvalidSeizeAmount(
                _seizableAmount
            );
        }
        // solhint-disable-next-line not-rely-on-time
        else if (_lastSeizeTimestamp + SEIZE_DELAY > block.timestamp) {
            revert
                FM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1__SeizeTimeout(
                _lastSeizeTimestamp + SEIZE_DELAY
            );
        }

        uint capitalAvailable = _getCapitalAvailable();
        // The asset pool must never be empty.
        if (capitalAvailable - amount_ < MIN_RESERVE) {
            amount_ = capitalAvailable - MIN_RESERVE;
        }

        // solhint-disable-next-line not-rely-on-time
        _lastSeizeTimestamp = block.timestamp;
        _token.transfer(_msgSender(), amount_);
        emit CollateralSeized(amount_);
    }

    /// @inheritdoc IFM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1
    function adjustSeize(uint64 seize_)
        public
        onlyModuleRole(COVER_MANAGER_ROLE)
    {
        _setSeize(seize_);
    }

    /// @inheritdoc IFM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1
    function setLiquidityVaultControllerContract(
        ILiquidityVaultController_v1 lvc_
    ) external onlyModuleRole(COVER_MANAGER_ROLE) {
        // @update-info When upgrading to Topos next version, we need to add an
        //              interface check here.
        if (address(lvc_) == address(0) || address(lvc_) == address(this)) {
            revert
                FM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1__InvalidInputAddress(
            );
        }
        emit LiquidityVaultControllerChanged(
            address(lvc_), address(_liquidityVaultController)
        );
        _liquidityVaultController = lvc_;
    }

    /// @inheritdoc IRepayer_v1
    function setRepayableAmount(uint amount_)
        external
        onlyModuleRole(COVER_MANAGER_ROLE)
    {
        if (amount_ > _getSmallerCaCr()) {
            revert
                IFM_BC_BondingSurface_Redeeming_v1
                .FM_BC_BondingSurface_Redeeming_v1__InvalidInputAmount();
        }
        emit RepayableAmountChanged(amount_, _repayableAmount);
        _repayableAmount = amount_;
    }

    // -------------------------------------------------------------------------
    // Mutating - RedeemingBondingCurveBase_v1 Overrides

    /// @inheritdoc IRedeemingBondingCurveBase_v1
    function setSellFee(uint fee_)
        external
        virtual
        override(RedeemingBondingCurveBase_v1)
        onlyModuleRole(COVER_MANAGER_ROLE)
    {
        _setSellFee(fee_);
    }

    // -------------------------------------------------------------------------
    // Mutating - OnlyRiskManager Functions

    /// @inheritdoc IFM_BC_BondingSurface_Redeeming_v1
    function setCapitalRequired(uint newCapitalRequired_)
        public
        override(FM_BC_BondingSurface_Redeeming_v1)
        onlyModuleRole(RISK_MANAGER_ROLE)
    {
        _setCapitalRequired(newCapitalRequired_);
    }

    /// @inheritdoc IFM_BC_BondingSurface_Redeeming_v1
    function setBasePriceMultiplier(uint newBasePriceMultiplier_)
        public
        override(FM_BC_BondingSurface_Redeeming_v1)
        onlyModuleRole(RISK_MANAGER_ROLE)
    {
        _setBasePriceMultiplier(newBasePriceMultiplier_);
    }

    // -------------------------------------------------------------------------
    // Mutating - OnlyOrchestratorAdmin Functions

    /// @inheritdoc IFM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1
    function setTokenVault(address tokenVault_)
        external
        onlyOrchestratorAdmin
    {
        _setTokenVault(tokenVault_);
    }

    function withdrawProjectCollateralFee(
        address, /* _receiver */
        uint /* amount_ */
    ) public view override onlyOrchestratorAdmin {
        revert
            FM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1__InvalidFunctionality(
        );
    }

    // =========================================================================
    // Internal Functions

    /// @dev Sets the token vault address.
    /// @param tokenVault_ The address of the token vault.
    function _setTokenVault(address tokenVault_)
        internal
        validAddress(tokenVault_)
    {
        _tokenVault = tokenVault_;
        emit TokenVaultSet(tokenVault_);
    }

    /// @dev Set the current seize state, which defines the percentage of seizable amount
    function _setSeize(uint64 seize_) internal {
        if (seize_ > MAX_SEIZE) {
            revert
                FM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1__InvalidSeize(
                seize_
            );
        }
        emit SeizeChanged(_currentSeize, seize_);
        _currentSeize = seize_;
    }

    /// @notice If the repayable amount was not defined, it is automatically set to the smaller between the Ca and the Cr value
    /// @notice The repayable amount as maximum is applied when is gt 0 and is lt the smallest between Cr and Ca
    /// @return repayableAmount_ The repayable amount
    function _getRepayableAmount()
        internal
        view
        returns (uint repayableAmount_)
    {
        uint _repayable = _getSmallerCaCr();
        return (_repayableAmount == 0 || _repayableAmount > _repayable)
            ? _repayable
            : _repayableAmount;
    }

    /// @notice If the balance of the Capital Available (Ca) is larger than the Capital Required (Cr), the repayable amount can be lte Cr
    /// @notice If the Ca is lt Cr, the max repayable amount is the Ca
    /// @return smallerCaCr_ The smaller of the Capital Available (Ca) and Capital Required (Cr)
    function _getSmallerCaCr() internal view returns (uint smallerCaCr_) {
        uint _ca = _getCapitalAvailable();
        uint _cr = _capitalRequired;
        return _ca > _cr ? _cr : _ca;
    }

    /// @dev    Processes project fee by transfer
    /// @param workflowFeeAmount_ The amount of project fee to transfer
    function _projectFeeCollected(uint workflowFeeAmount_) internal override {
        _token.safeTransfer(_tokenVault, workflowFeeAmount_);
        emit ProjectCollateralFeeWithdrawn(_tokenVault, workflowFeeAmount_);
    }

    // -------------------------------------------------------------------------
    // Internal - Modifier Functions

    function _ensureOnlyLiquidityVaultController() internal view {
        if (_msgSender() != address(_liquidityVaultController)) {
            revert
                FM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1__InvalidLiquidityVaultController(
                _msgSender()
            );
        }
    }

    /// @dev    Validate if buy and sell is restricted, and if so
    ///         check if the caller has the CURVE_INTERACTION_ROLE
    function _checkBuyAndSellRestrictionsModifier() internal view {
        //@note Naming? Naming Functions Contracts Modifier Internal functions
        if (_buyAndSellIsRestricted) {
            _checkRoleModifier(CURVE_INTERACTION_ROLE, _msgSender());
        }
    }

    // -------------------------------------------------------------------------
    // Internal - BondingCurveBase_v1 Overrides

    /// @dev    Validates the workflow fee.
    function _validateProjectFee(uint projectFee_)
        internal
        pure
        override(BondingCurveBase_v1)
    {
        if (projectFee_ > MAX_FEE) {
            revert Module__BondingCurveBase__InvalidFeePercentage();
        }
    }
}
