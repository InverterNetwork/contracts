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
 * @custom:version  v1.0.0
 *
 * @custom:inverter-standard-version    v0.1.0
 *
 * @author  Inverter Network
 */
contract FM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1 is
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

    // ------------------------------------------------------------------------
    // Constants

    /// @notice Max seizable amount is 1% expressed in BPS.
    uint64 public constant MAX_SEIZE = 100;
    /// @notice Max fee for selling is 1% expressed in BPS.
    uint64 public constant MAX_FEE = 100;
    /// @notice Time interval between seizes.
    uint64 public constant SEIZE_DELAY = 7 days;
    /// @notice Role associated with the managing of the bonding curve values.
    bytes32 public constant RISK_MANAGER_ROLE = "RISK_MANAGER";
    /// @notice Role associated with the managing of setting withdraw addresses
    ///         and setting the fee.
    bytes32 public constant COVER_MANAGER_ROLE = "COVER_MANAGER";
    /// @notice Role that can use buy and sell regardless wether these
    ///         functions are restricted or not
    bytes32 public constant CURVE_INTERACTION_ROLE = "CURVE_USER";

    // ------------------------------------------------------------------------
    // Storage

    /// @notice Repayable amount collateral which can be pulled from the
    ///         contract by the liquidity vault controller.
    uint internal _repayableAmount;
    /// @notice The current seize percentage expressed in BPS.
    uint64 internal _currentSeize;
    /// @notice Address of the liquidity vault controller who has access to the
    ///         collateral held by the funding manager through the Repayer
    ///         through the Repayer functionality.
    address internal _liquidityVaultController;
    /// @notice Tracks last seize timestamp to determine eligibility for
    ///         subsequent seizures based on SEIZE_DELAY.
    uint internal _lastSeizeTimestamp;
    /// @notice Address of the reserve pool.
    address internal _tokenVault;
    /// @notice Restricts buying and selling functionalities to specific role.
    bool internal _buyAndSellIsRestricted;

    /// @notice Storage gap for future upgrades.
    uint[50] private __gap;

    // ------------------------------------------------------------------------
    // Modifiers

    /// @notice Modifier to ensure buy and sell restrictions are met.
    modifier onlyIfNotBuyAndSellRestricted() {
        _onlyIfNotBuyAndSellRestrictedModifier();
        _;
    }

    /// @notice Modifier to ensure only the LiquidityVaultController can call
    ///         the function.
    modifier onlyLiquidityVaultController() {
        _ensureOnlyLiquidityVaultController();
        _;
    }

    // ------------------------------------------------------------------------
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

    /// @notice Initializes the  Redeeming Restricted Repayer Seizable Bonding
    /// Surface Contract.
    /// @dev    Only callable during the initialization.
    /// @param  liquidityVaultController_ The address of the
    ///         LiquidityVaultController.
    /// @param  newSeize_ The new seize value.
    /// @param  buyAndSellIsRestricted_ Whether buy and sell is restricted.
    function __FM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1_Init(
        address liquidityVaultController_,
        uint64 newSeize_,
        bool buyAndSellIsRestricted_
    ) internal onlyInitializing {
        _liquidityVaultController = liquidityVaultController_;

        // Set buy and sell restriction to restricted if true. By default buy
        // and sell are unrestricted.
        _buyAndSellIsRestricted = buyAndSellIsRestricted_;

        _setSeize(newSeize_);
    }

    // ------------------------------------------------------------------------
    // Public Getter Functions

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

    // ------------------------------------------------------------------------
    // Public Mutating Functions

    // ------------------------------------------------------------------------
    // Mutating - Token Manipulation Functions

    /// @inheritdoc IBondingCurveBase_v1
    /// @dev    The buy functionality can be restricted to the
    ///         CURVE_INTERACTION_ROLE.
    function buyFor(address receiver_, uint depositAmount_, uint minAmountOut_)
        public
        virtual
        override(BondingCurveBase_v1, IBondingCurveBase_v1)
        onlyIfNotBuyAndSellRestricted
    {
        super.buyFor(receiver_, depositAmount_, minAmountOut_);
    }

    /// @inheritdoc IBondingCurveBase_v1
    /// @dev    The buy functionality can be restricted to the
    ///         CURVE_INTERACTION_ROLE.
    function buy(uint depositAmount_, uint minAmountOut_)
        public
        virtual
        override(BondingCurveBase_v1, IBondingCurveBase_v1)
    {
        buyFor(_msgSender(), depositAmount_, minAmountOut_);
    }

    /// @inheritdoc IRedeemingBondingCurveBase_v1
    /// @dev    The sell functionality can be restricted to the
    ///         CURVE_INTERACTION_ROLE.
    function sellTo(address receiver_, uint depositAmount_, uint minAmountOut_)
        public
        virtual
        override(RedeemingBondingCurveBase_v1, IRedeemingBondingCurveBase_v1)
        onlyIfNotBuyAndSellRestricted
    {
        super.sellTo(receiver_, depositAmount_, minAmountOut_);
    }

    /// @inheritdoc IRedeemingBondingCurveBase_v1
    /// @dev    The sell functionality can be restricted to the
    ///         CURVE_INTERACTION_ROLE.
    function sell(uint depositAmount_, uint minAmountOut_)
        public
        virtual
        override(RedeemingBondingCurveBase_v1, IRedeemingBondingCurveBase_v1)
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
            // Does not update allowance if set to infinite.
            _spendAllowance(owner_, _msgSender(), amount_);
        }
        // Will revert if balance < amount.
        _burn(owner_, amount_);
    }

    // ------------------------------------------------------------------------
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

    // ------------------------------------------------------------------------
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
        uint seizableAmount = getSeizableAmount();
        if (amount_ > seizableAmount) {
            revert
                FM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1__InvalidSeizeAmount(
                seizableAmount
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
    function setLiquidityVaultControllerContract(address lvc_)
        external
        onlyModuleRole(COVER_MANAGER_ROLE)
    {
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

    // ------------------------------------------------------------------------
    // Mutating - RedeemingBondingCurveBase_v1 Overrides

    /// @inheritdoc IRedeemingBondingCurveBase_v1
    function setSellFee(uint fee_)
        external
        virtual
        override(RedeemingBondingCurveBase_v1, IRedeemingBondingCurveBase_v1)
        onlyModuleRole(COVER_MANAGER_ROLE)
    {
        _setSellFee(fee_);
    }

    // ------------------------------------------------------------------------
    // Mutating - OnlyRiskManager Functions

    /// @inheritdoc IFM_BC_BondingSurface_Redeeming_v1
    function setCapitalRequired(uint newCapitalRequired_)
        public
        override(
            FM_BC_BondingSurface_Redeeming_v1, IFM_BC_BondingSurface_Redeeming_v1
        )
        onlyModuleRole(RISK_MANAGER_ROLE)
    {
        _setCapitalRequired(newCapitalRequired_);
    }

    /// @inheritdoc IFM_BC_BondingSurface_Redeeming_v1
    function setBasePriceMultiplier(uint newBasePriceMultiplier_)
        public
        override(
            FM_BC_BondingSurface_Redeeming_v1, IFM_BC_BondingSurface_Redeeming_v1
        )
        onlyModuleRole(RISK_MANAGER_ROLE)
    {
        _setBasePriceMultiplier(newBasePriceMultiplier_);
    }

    // ------------------------------------------------------------------------
    // Mutating - OnlyOrchestratorAdmin Functions

    /// @inheritdoc IFM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1
    function setTokenVault(address tokenVault_)
        external
        onlyOrchestratorAdmin
    {
        _setTokenVault(tokenVault_);
    }

    /// @inheritdoc IBondingCurveBase_v1
    function withdrawProjectCollateralFee(
        address, /* receiver_ */
        uint /* amount_ */
    )
        public
        view
        override(BondingCurveBase_v1, IBondingCurveBase_v1)
        onlyOrchestratorAdmin
    {
        revert
            FM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1__InvalidFunctionality(
        );
    }

    // ------------------------------------------------------------------------
    // Internal Functions

    /// @notice Sets the token vault address.
    /// @param  tokenVault_ The address of the token vault.
    function _setTokenVault(address tokenVault_)
        internal
        validAddress(tokenVault_)
    {
        _tokenVault = tokenVault_;
        emit TokenVaultSet(tokenVault_);
    }

    /// @notice Set the current seize state, which defines the percentage
    ///         of seizable amount.
    /// @dev    Reverts if the seize is greater than the MAX_SEIZE.
    /// @param  seize_ The new seize value.
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

    /// @notice Returns the repayable amount.
    /// @dev    If the repayable amount was not defined, it is automatically set
    ///         to the smaller one between the Ca and the Cr value.
    /// @dev    The repayable amount as maximum is applied when it is greater
    ///         than 0 and is less than the smallest between Cr and Ca.
    /// @return repayableAmount_ The repayable amount.
    function _getRepayableAmount()
        internal
        view
        returns (uint repayableAmount_)
    {
        uint repayable = _getSmallerCaCr();
        return (_repayableAmount == 0 || _repayableAmount > repayable)
            ? repayable
            : _repayableAmount;
    }

    /// @notice Returns the smaller of the Capital Available (Ca) and Capital
    ///         Required (Cr).
    /// @dev    If the balance of the Capital Available (Ca) is larger than
    ///         the Capital Required (Cr), the repayable amount can be less
    ///         than or equal to Cr.
    /// @dev    If the Ca is lt Cr, the max repayable amount is the Ca.
    /// @return smallerCaCr_    The smaller of the Capital Available (Ca)
    ///                         and Capital Required (Cr).
    function _getSmallerCaCr() internal view returns (uint smallerCaCr_) {
        uint ca = _getCapitalAvailable();
        uint cr = _capitalRequired;
        return ca > cr ? cr : ca;
    }

    /// @notice Processes project fee by transfer.
    /// @param  workflowFeeAmount_ The amount of project fee to transfer.
    function _projectFeeCollected(uint workflowFeeAmount_) internal override {
        _token.safeTransfer(_tokenVault, workflowFeeAmount_);
        emit ProjectCollateralFeeWithdrawn(_tokenVault, workflowFeeAmount_);
    }

    // ------------------------------------------------------------------------
    // Internal - Modifier Functions

    /// @notice Ensures that only the Liquidity Vault Controller can call the
    ///         function.
    function _ensureOnlyLiquidityVaultController() internal view {
        if (_msgSender() != address(_liquidityVaultController)) {
            revert
                FM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v1__InvalidLiquidityVaultController(
                _msgSender()
            );
        }
    }

    /// @notice Validate if buy and sell is restricted, and if so
    ///         check if the caller has the CURVE_INTERACTION_ROLE.
    function _onlyIfNotBuyAndSellRestrictedModifier() internal view {
        if (_buyAndSellIsRestricted) {
            _checkRoleModifier(CURVE_INTERACTION_ROLE, _msgSender());
        }
    }

    // ------------------------------------------------------------------------
    // Internal - BondingCurveBase_v1 Overrides

    /// @notice Validates the project fee.
    /// @dev    Reverts if the project fee is greater than the maximum fee.
    /// @param  projectFee_ The project fee.
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
