// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal
import {IModule_v2} from "src/modules/base/IModule_v2.sol";
import {Module_v2} from "src/modules/base/Module_v2.sol";
import {FM_BC_QuadraticPrice_Redeeming_v2} from
    "@fm/bondingCurve/FM_BC_QuadraticPrice_Redeeming_v2.sol";
import {RedeemingIssuanceBase_v2} from
    "@fm/bondingCurve/abstracts/RedeemingIssuanceBase_v2.sol";
import {IssuanceBase_v2} from "@fm/bondingCurve/abstracts/IssuanceBase_v2.sol";
import {FixedPointMathLib} from "@modLib/FixedPointMathLib.sol";
import {FM_BC_Bancor_Redeeming_VirtualSupply_v2} from
    "@fm/bondingCurve/FM_BC_Bancor_Redeeming_VirtualSupply_v2.sol";
import {IIssuanceBase_v2} from
    "@fm/bondingCurve/interfaces/IIssuanceBase_v2.sol";
import {IRedeemingIssuanceBase_v2} from
    "@fm/bondingCurve/interfaces/IRedeemingIssuanceBase_v2.sol";
import {IFM_BC_QuadraticPrice_Redeeming_v2} from
    "@fm/bondingCurve/interfaces/IFM_BC_QuadraticPrice_Redeeming_v2.sol";
import {IFM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2} from
    "@fm/bondingCurve/interfaces/IFM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2.sol";
import {IRepayer_v1} from "@fm/bondingCurve/interfaces/IRepayer_v1.sol";
import {IOrchestrator_v2} from
    "src/orchestrator/interfaces/IOrchestrator_v2.sol";
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";
import {IQuadraticPriceFormula} from
    "@fm/bondingCurve/interfaces/IQuadraticPriceFormula.sol";
import {IAuthorizer_v2} from "@aut/IAuthorizer_v2.sol";

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
 *              - IssuanceBase_v2
 *              - RedeemingIssuanceBase_v2
 *              - Repayer
 *          The contract should be used by the orchestrator admin to manage all
 *          the configuration for the bonding curve as well as the opening and
 *          closing of the issuance and redemption functionalities.
 *          The contract implements the formulaWrapper functions enforced by
 *          using the Quadratic Price Formula to calculate the issuance/
 *          redemption rate.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to
 *                          our Security Policy at security.inverter.network or
 *                          email us directly!
 *
 * @custom:version  v2.0.0
 *
 * @custom:former-name FM_BC_BondingSurface_Redeeming_Restricted_Repayer_Seizable_v2
 *
 * @custom:inverter-standard-version    v0.1.0
 *
 * @author  Inverter Network
 */
contract FM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2 is
    IFM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2,
    FM_BC_QuadraticPrice_Redeeming_v2
{
    using SafeERC20 for IERC20;

    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId_)
        public
        view
        virtual
        override(FM_BC_QuadraticPrice_Redeeming_v2)
        returns (bool supportsInterface_)
    {
        return interfaceId_
            == type(IFM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2)
                .interfaceId || interfaceId_ == type(IRepayer_v1).interfaceId
            || super.supportsInterface(interfaceId_);
    }

    // ========================================================================
    // Constants

    /// @notice Max seizable amount is 1% expressed in BPS.
    uint64 public constant MAX_SEIZE = 100;
    /// @notice Max fee for selling is 1% expressed in BPS.
    uint64 public constant MAX_FEE = 100;
    /// @notice Time interval between seizes.
    uint64 public constant SEIZE_DELAY = 7 days;

    // ========================================================================
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

    /// @notice Storage gap for future upgrades.
    uint[50] private __gap;

    // ========================================================================
    // Modifiers

    /// @notice Modifier to ensure only the LiquidityVaultController can call
    ///         the function.
    modifier onlyLiquidityVaultController() {
        _ensureOnlyLiquidityVaultController();
        _;
    }

    // ========================================================================
    // Init Function

    /// @inheritdoc Module_v2
    function init(
        IOrchestrator_v2 orchestrator_,
        Metadata memory metadata_,
        bytes memory configData_
    ) external override(FM_BC_QuadraticPrice_Redeeming_v2) initializer {
        __Module_init(orchestrator_, metadata_);

        address issuanceToken;
        address acceptedToken;
        BondingCurveProperties memory bondingCurveProperties;
        address liquidityVaultController;
        uint64 newSeize;

        (
            issuanceToken,
            acceptedToken,
            bondingCurveProperties,
            liquidityVaultController,
            newSeize
        ) = abi.decode(
            configData_,
            (address, address, BondingCurveProperties, address, uint64)
        );
        __Module_init(orchestrator_, metadata_);
        __FM_BC_QuadraticPrice_Redeeming_v2_Init(
            issuanceToken, acceptedToken, bondingCurveProperties
        );
        __FM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2_Init(
            liquidityVaultController, newSeize
        );
    }

    /// @notice Initializes the  Redeeming Restricted Repayer Seizable Bonding
    /// Surface Contract.
    /// @dev    Only callable during the initialization.
    /// @param  liquidityVaultController_ The address of the
    ///         LiquidityVaultController.
    /// @param  newSeize_ The new seize value.
    function __FM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2_Init(
        address liquidityVaultController_,
        uint64 newSeize_
    ) internal onlyInitializing {
        _liquidityVaultController = liquidityVaultController_;

        _setSeize(newSeize_);
    }

    // ========================================================================
    // Public Getter Functions

    /// @inheritdoc IFM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2
    function getSeizableAmount() public view returns (uint amount_) {
        uint currentBalance = _getCapitalAvailable();

        return (currentBalance * _currentSeize) / BPS;
    }

    /// @inheritdoc IFM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2
    function getCurrentSeize() public view returns (uint64 currentSeize_) {
        return _currentSeize;
    }

    /// @inheritdoc IFM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2
    function getLiquidityVaultController()
        public
        view
        returns (address liquidityVaultController_)
    {
        return address(_liquidityVaultController);
    }

    /// @inheritdoc IFM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2
    function getLastSeizeTimestamp()
        public
        view
        returns (uint lastSeizeTimestamp_)
    {
        return _lastSeizeTimestamp;
    }

    /// @inheritdoc IFM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2
    function getTokenVault() public view returns (address tokenVault_) {
        return address(_tokenVault);
    }

    /// @inheritdoc IRepayer_v1
    function getRepayableAmount()
        external
        view
        returns (uint repayableAmount_)
    {
        return _getRepayableAmount();
    }

    // ========================================================================
    // Public Mutating Functions

    // ------------------------------------------------------------------------
    // Mutating - Permissioned Functions

    /// @inheritdoc IFM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2
    function burnIssuanceToken(uint amount_) external permissioned {
        _burn(_msgSender(), amount_);
    }

    /// @inheritdoc IFM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2
    function burnIssuanceTokenFor(address owner_, uint amount_)
        external
        permissioned
    {
        if (owner_ != _msgSender()) {
            // Does not update allowance if set to infinite.
            _spendAllowance(owner_, _msgSender(), amount_);
        }
        // Will revert if balance < amount.
        _burn(owner_, amount_);
    }

    /// @inheritdoc IFM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2
    function seize(uint amount_) public permissioned {
        uint seizableAmount = getSeizableAmount();
        if (amount_ > seizableAmount) {
            revert
                FM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2__InvalidSeizeAmount(
                seizableAmount
            );
        }
        // solhint-disable-next-line not-rely-on-time
        else if (_lastSeizeTimestamp + SEIZE_DELAY > block.timestamp) {
            revert
                FM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2__SeizeTimeout(
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

    /// @inheritdoc IFM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2
    function adjustSeize(uint64 seize_) public permissioned {
        _setSeize(seize_);
    }

    /// @inheritdoc IFM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2
    function setLiquidityVaultControllerContract(address lvc_)
        external
        permissioned
    {
        if (address(lvc_) == address(0) || address(lvc_) == address(this)) {
            revert
                FM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2__InvalidInputAddress(
            );
        }
        emit LiquidityVaultControllerChanged(
            address(lvc_), address(_liquidityVaultController)
        );
        _liquidityVaultController = lvc_;
    }

    /// @inheritdoc IRepayer_v1
    function setRepayableAmount(uint amount_) external permissioned {
        if (amount_ > _getSmallerCaCr()) {
            revert
                IFM_BC_QuadraticPrice_Redeeming_v2
                .FM_BC_QuadraticPrice_Redeeming_v2__InvalidInputAmount();
        }
        emit RepayableAmountChanged(amount_, _repayableAmount);
        _repayableAmount = amount_;
    }

    /// @inheritdoc IFM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2
    function setTokenVault(address tokenVault_) external permissioned {
        _setTokenVault(tokenVault_);
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
            revert FM_BC_QuadraticPrice_Redeeming_v2__MinReserveReached();
        }

        emit RepaymentTransfer(to_, amount_);
    }

    // ------------------------------------------------------------------------
    // Mutating - Out of Order

    /// @inheritdoc IIssuanceBase_v2
    function withdrawProjectCollateralFee(
        address, /* receiver_ */
        uint /* amount_ */
    ) public view override(IssuanceBase_v2, IIssuanceBase_v2) {
        revert
            FM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2__InvalidFunctionality(
        );
    }

    // ========================================================================
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
                FM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2__InvalidSeize(
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
                FM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2__InvalidLiquidityVaultController(
                _msgSender()
            );
        }
    }

    // ------------------------------------------------------------------------
    // Internal - IssuanceBase_v2 Overrides

    /// @notice Validates the project fee.
    /// @dev    Reverts if the project fee is greater than the maximum fee.
    /// @param  projectFee_ The project fee.
    function _validateProjectFee(uint projectFee_)
        internal
        pure
        override(IssuanceBase_v2)
    {
        if (projectFee_ > MAX_FEE) {
            revert Module__BondingCurveBase__InvalidFeePercentage();
        }
    }
}
