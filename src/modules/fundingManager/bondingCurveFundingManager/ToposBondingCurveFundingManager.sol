// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Dependencies
import {Module} from "src/modules/base/Module.sol";
import {RedeemingBondingCurveFundingManagerBase} from
    "src/modules/fundingManager/bondingCurveFundingManager/RedeemingBondingCurveFundingManagerBase.sol";
import {BondingCurveFundingManagerBase} from
    "src/modules/fundingManager/bondingCurveFundingManager/BondingCurveFundingManagerBase.sol";

// Internal Interfaces
import {IBondingCurveFundingManagerBase} from
    "src/modules/fundingManager/bondingCurveFundingManager/IBondingCurveFundingManagerBase.sol";
import {IRedeemingBondingCurveFundingManagerBase} from
    "src/modules/fundingManager/bondingCurveFundingManager/IRedeemingBondingCurveFundingManagerBase.sol";
import {IToposBondingCurveFundingManager} from
    "src/modules/fundingManager/bondingCurveFundingManager/IToposBondingCurveFundingManager.sol";
import {IRepayer} from
    "src/modules/fundingManager/bondingCurveFundingManager/IRepayer.sol";
import {ILiquidityPool} from
    "src/modules/logicModule/liquidityPool/ILiquidityPool.sol";
import {IOrchestrator} from "src/orchestrator/IOrchestrator.sol";
import {IFundingManager} from "src/modules/fundingManager/IFundingManager.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@oz/token/ERC20/extensions/IERC20Metadata.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

/// @title Topos Bonding Curve Funding Manager Contract.
/// @author Inverter Network.
/// @notice This contract enables the issuance and redeeming of tokens on a bonding curve
/// @dev This contract inherits functionalties from the contracts:
/// - BondingCurveFundingManagerBase
/// - RedeemingBondingCurveFundingManagerBase
/// The contract should be used by the Orchestrator Owner or manager to manage all the configuration for the
/// bonding curve as well as the opening and closing of the issuance and redeeming functionalities.
/// The contract implements the formulaWrapper functions enforced by the upstream contracts,
/// using the Topos formula to calculate the issuance/redeeming rate.
contract ToposBondingCurveFundingManager is
    IRepayer,
    IToposBondingCurveFundingManager,
    RedeemingBondingCurveFundingManagerBase
{
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(RedeemingBondingCurveFundingManagerBase)
        returns (bool)
    {
        return interfaceId == type(IToposBondingCurveFundingManager).interfaceId
            || super.supportsInterface(interfaceId);
    }

    using SafeERC20 for IERC20;

    //--------------------------------------------------------------------------
    // Storage

    /// @dev The interface of the Formula used to calculate the issuance and redeeming amount.
    // address public formula; // TODO: Add interface
    /// @notice Repayable amount collateral which can be pulled from the contract by the liquidity pool
    uint public repayableAmount;

    /// @dev Address of the liquidity pool who has access to the collateral held by the funding manager
    /// through the Repayer functionality
    ILiquidityPool public liquidityPool;
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
        address _liquidityPool;

        (issuanceToken, bondingCurveProperties, _acceptedToken, _liquidityPool)
        = abi.decode(
            configData,
            (IssuanceToken, BondingCurveProperties, address, address)
        );

        __ERC20_init(
            string(abi.encodePacked(issuanceToken.name)),
            string(abi.encodePacked(issuanceToken.symbol))
        );

        // Set collateral token
        _token = IERC20(_acceptedToken);
        // Set liquidity pool address
        liquidityPool = ILiquidityPool(_liquidityPool);

        // TODO:
        // - Add reserve address to init
        // - Set Liquidity Pool address to init
        // - Sort out if we need issuance token decimal and collateral decimal for calculations
        // - Set formula contract in init
        // - Set bonding curve properties
        // - Do we need to set decimal like in Bancor
    }

    //--------------------------------------------------------------------------
    // Modifiers

    modifier onlyLiquidityPool() {
        if (_msgSender() != address(liquidityPool)) {
            revert ToposBondingCurveFundingManager__InvalidLiquidityPool(
                _msgSender()
            );
        }
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
        external
        override(BondingCurveFundingManagerBase)
        validReceiver(_receiver)
        buyingIsEnabled
    {
        // Implement buy logic
    }

    /// @notice Buy tokens for the sender's address.
    /// @dev
    /// @param _depositAmount The amount of collateral token depoisited.
    /// @param _minAmountOut The minimum acceptable amount the user expects to receive from the transaction.
    function buy(uint _depositAmount, uint _minAmountOut)
        external
        override(BondingCurveFundingManagerBase)
        buyingIsEnabled
    {
        // Implement buy logic
    }

    /// @notice Redeem tokens on behalf of a specified receiver address.
    /// @dev
    /// @param _receiver The address that will receive the redeemed tokens.
    /// @param _depositAmount The amount of issued token to deposited.
    /// @param _minAmountOut The minimum acceptable amount the user expects to receive from the transaction.
    function sellFor(address _receiver, uint _depositAmount, uint _minAmountOut)
        external
        override(RedeemingBondingCurveFundingManagerBase)
        validReceiver(_receiver)
        sellingIsEnabled
    {
        // Implement sell logic
    }

    /// @notice Sell collateral for the sender's address.
    /// @dev
    /// @param _depositAmount The amount of issued token depoisited.
    /// @param _minAmountOut The minimum acceptable amount the user expects to receive from the transaction.
    /// @param _minAmountOut The minimum acceptable amount the user expects to receive from the transaction.
    function sell(uint _depositAmount, uint _minAmountOut)
        external
        override(RedeemingBondingCurveFundingManagerBase)
        sellingIsEnabled
    {
        // Implement sell logic
    }
    /// @notice Calculates and returns the static price for buying the issuance token.
    /// @return uint The static price for buying the issuance token
    function getStaticPriceForBuying()
        external
        view
        override(BondingCurveFundingManagerBase)
        returns (uint)
    {
        // Implement static price logic
    }

    /// @notice Calculates and returns the static price for selling the issuance token.
    /// @return uint The static price for selling the issuance token
    function getStaticPriceForSelling()
        external
        view
        override(RedeemingBondingCurveFundingManagerBase)
        returns (uint)
    {
        // Implement static price logic
    }

    /// @inheritdoc IRepayer
    function getRepayableAmount() external view returns (uint) {
        return _getRepayableAmount();
    }

    //--------------------------------------------------------------------------
    // Public Mutating Functions

    /// @inheritdoc IFundingManager
    function token() public view returns (IERC20) {
        return _token;
    }

    //--------------------------------------------------------------------------
    // Only Liquidty Pool Functions

    /// @inheritdoc IRepayer
    function transferRepayment(address _to, uint _amount)
        external
        validReceiver(_to)
        onlyLiquidityPool
    {
        if (_amount > _getRepayableAmount()) {
            revert Repayer__InsufficientCollateralForRepayerTransfer();
        }
        __Module_orchestrator.fundingManager().token().safeTransfer(
            _to, _amount
        );
    }

    //--------------------------------------------------------------------------
    // OnlyOrchestrator Functions

    /// @inheritdoc IRepayer
    function setRepayableAmount(uint _amount)
        external
        onlyOrchestratorOwnerOrManager
    {
        if (_amount > _getSmallerCaCr()) {
            revert ToposBondingCurveFundingManager__InvalidInputAmount();
        }
        emit RepayableChanged(_amount, repayableAmount);
        repayableAmount = _amount;
    }

    /// @inheritdoc IToposBondingCurveFundingManager
    function setLiquidityPoolContract(ILiquidityPool _lp)
        external
        onlyOrchestratorOwnerOrManager
    {
        if (address(_lp) == address(0)) {
            revert ToposBondingCurveFundingManager__InvalidInputAddress();
        }
        emit LiquidityPoolChanged(_lp, liquidityPool);
        liquidityPool = _lp;
    }

    //--------------------------------------------------------------------------
    // Upstream Function Implementations

    /// @dev Calculates the amount of tokens to mint for a given deposit amount using the formula contract.
    /// This internal function is an override of BondingCurveFundingManagerBase's abstract function.
    /// @param _depositAmount The amount of collateral deposited to purchase tokens.
    /// @return mintAmount The amount of tokens that will be minted.
    function _issueTokensFormulaWrapper(uint _depositAmount)
        internal
        view
        override(BondingCurveFundingManagerBase)
        returns (uint mintAmount)
    {
        // Implement call to formula contract
    }

    /// @dev Calculates the amount of collateral to be received when redeeming a given amount of tokens.
    /// This internal function is an override of RedeemingBondingCurveFundingManagerBase's abstract function.
    /// @param _depositAmount The amount of tokens to be redeemed for collateral.
    /// @return redeemAmount The amount of collateral that will be received.
    function _redeemTokensFormulaWrapper(uint _depositAmount)
        internal
        view
        override(RedeemingBondingCurveFundingManagerBase)
        returns (uint redeemAmount)
    {
        // Implement call to formula contract
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    /// @notice If the repayable amount was not defined, it is automatically set to the smaller between the Ca and the Cr value
    /// @notice The repayable amount as maximum is applied when is gt 0 and is lt the smallest between Cr and Ca
    function _getRepayableAmount() internal view returns (uint) {
        uint _repayable = _getSmallerCaCr();
        return (repayableAmount == 0 || repayableAmount > _repayable)
            ? _repayable
            : repayableAmount;
    }

    /// @notice If the balance of the Capital Available (Ca) is larger than the Capital Requested (Cr), the repayable amount can be lte Cr
    /// @notice If the Ca is lt Cr, the max repayable amount is the Ca
    function _getSmallerCaCr() internal view returns (uint) {
        /// TODO: update after formula contract is added
        // uint256 _ca = asset.balanceOf(address(this));
        // uint256 _cr = surface.capitalRequired();
        // return _ca > _cr ? _cr : _ca;
    }
}
