// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

// Internal Dependencies
import {Module} from "src/modules/base/Module.sol";
import {IFundingManager} from "src/modules/fundingManager/IFundingManager.sol";
import {IBondingCurveFundingManagerBase} from
    "src/modules/fundingManager/bondingCurveFundingManager/IBondingCurveFundingManagerBase.sol";

// Internal Interfaces
import {IOrchestrator} from "src/orchestrator/IOrchestrator.sol";
import {ContextUpgradeable} from "@oz-up/utils/ContextUpgradeable.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IERC20MetadataUpgradeable} from
    "@oz-up/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

// External Dependencies
import {ERC20Upgradeable} from "@oz-up/token/ERC20/ERC20Upgradeable.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

/// @title Bonding Curve Funding Manager Base Contract.
/// @author Inverter Network.
/// @notice This contract enables the base functionalities for issuing tokens along a bonding curve.
/// @dev The contract implements functionalties for:
///         - opening and closing the issuance of tokens.
///         - setting and subtracting of fees, expressed in BPS and subtracted from the collateral.
///         - calculating the issuance amount by means of an abstract function to be implemented in
///             the downstream contract.
abstract contract BondingCurveFundingManagerBase is
    IBondingCurveFundingManagerBase,
    IFundingManager,
    ContextUpgradeable,
    ERC20Upgradeable,
    Module
{
    using SafeERC20 for IERC20;

    //--------------------------------------------------------------------------
    // Storage

    /// @dev Stores the number of decimals used by the token.
    uint8 internal tokenDecimals;
    /// @dev Indicates whether the buy functionality is open or not.
    ///      Enabled = true || disabled = false.
    bool public buyIsOpen;
    /// @dev Buy fee expressed in base points, i.e. 0% = 0; 1% = 100; 10% = 1000
    uint public buyFee;
    /// @dev Base Points used for percentage calculation. This value represents 100%
    uint internal constant BPS = 10_000;

    //--------------------------------------------------------------------------
    // Modifiers

    modifier buyingIsEnabled() {
        if (buyIsOpen == false) {
            revert BondingCurveFundingManager__BuyingFunctionaltiesClosed();
        }
        _;
    }

    /// @dev Modifier to guarantee token recipient is valid.
    modifier validReceiver(address _receiver) {
        if (_receiver == address(0) || _receiver == address(this)) {
            revert BondingCurveFundingManagerBase__InvalidRecipient();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Public Functions

    /// @inheritdoc IBondingCurveFundingManagerBase
    function buyFor(address _receiver, uint _depositAmount)
        external
        virtual
        buyingIsEnabled
        validReceiver(_receiver)
    {
        _buyOrder(_receiver, _depositAmount);
    }

    /// @inheritdoc IBondingCurveFundingManagerBase
    function buy(uint _depositAmount) external virtual buyingIsEnabled {
        _buyOrder(_msgSender(), _depositAmount);
    }

    //--------------------------------------------------------------------------
    // Public Mutating Functions

    /// @inheritdoc IERC20MetadataUpgradeable
    function decimals()
        public
        view
        override(ERC20Upgradeable)
        returns (uint8)
    {
        return tokenDecimals;
    }

    //--------------------------------------------------------------------------
    // OnlyOrchestrator Functions

    /// @inheritdoc IBondingCurveFundingManagerBase
    function openBuy() external onlyOrchestratorOwner {
        _openBuy();
    }

    /// @inheritdoc IBondingCurveFundingManagerBase
    function closeBuy() external onlyOrchestratorOwner {
        _closeBuy();
    }

    /// @inheritdoc IBondingCurveFundingManagerBase
    function setBuyFee(uint _fee) external onlyOrchestratorOwner {
        _setBuyFee(_fee);
    }

    //--------------------------------------------------------------------------
    // Internal Functions Implemented in Downstream Contract

    /// @dev Function used for wrapping the call to the external contract responsible for
    /// calculating the issuing amount. This function is an abstract function and must be
    /// implemented in the downstream contract.
    /// @param _depositAmount The amount of collateral token that is deposited
    /// @return uint Return the amount of tokens to be issued
    function _issueTokensFormulaWrapper(uint _depositAmount)
        internal
        view
        virtual
        returns (uint);

    //--------------------------------------------------------------------------
    // Internal Functions

    /// @dev Internal function to handle the buying of tokens.
    /// This function performs the core logic for buying tokens. It transfers the collateral,
    /// deducts any applicable fees, and mints new tokens for the buyer.
    /// @param _receiver The address that will receive the bought tokens.
    /// @param _depositAmount The amount of collateral to deposit for buying tokens.
    function _buyOrder(address _receiver, uint _depositAmount)
        internal
        returns (uint mintAmount)
    {
        if (_depositAmount == 0) {
            revert BondingCurveFundingManager__InvalidDepositAmount();
        }
        // Transfer collateral, confirming that correct amount == allowance
        __Module_orchestrator.token().safeTransferFrom(
            _msgSender(), address(this), _depositAmount
        );
        // Calculate deposit amount minus fee percentage
        if (buyFee > 0) {
            _depositAmount =
                _calculateFeeDeductedDepositAmount(_depositAmount, buyFee);
        }
        // Calculate mint amount based on upstream formula
        mintAmount = _issueTokens(_depositAmount);
        // Mint tokens to address
        _mint(_receiver, mintAmount);
        // Emit event
        emit TokensBought(_receiver, _depositAmount, mintAmount, _msgSender());
    }

    /// @dev Opens the buy functionality by setting the state variable `buyIsOpen` to true.
    function _openBuy() internal {
        if (buyIsOpen == true) {
            revert BondingCurveFundingManager__BuyingAlreadyOpen();
        }
        buyIsOpen = true;
        emit BuyingEnabled();
    }

    /// @dev Closes the buy functionality by setting the state variable `buyIsOpen` to false.
    function _closeBuy() internal {
        if (buyIsOpen == false) {
            revert BondingCurveFundingManager__BuyingAlreadyClosed();
        }
        buyIsOpen = false;
        emit BuyingDisabled();
    }

    /// @dev Sets the buy transaction fee, expressed in BPS.
    /// @param _fee The fee percentage to set for buy transactions.
    function _setBuyFee(uint _fee) internal {
        if (_fee >= BPS) {
            revert BondingCurveFundingManager__InvalidFeePercentage();
        }
        emit BuyFeeUpdated(_fee, buyFee);
        buyFee = _fee;
    }

    /// @dev Calculates the deposit amount after deducting the fee.
    /// The function takes a deposit amount and a fee percentage to calculate
    /// the net deposit amount after fee deduction.
    /// @param _depositAmount The original amount to be deposited.
    /// @param _feePct The fee percentage to be deducted, represented in basis points.
    /// @return depositAmountMinusFee The deposit amount after fee has been deducted.
    function _calculateFeeDeductedDepositAmount(
        uint _depositAmount,
        uint _feePct
    ) internal pure returns (uint depositAmountMinusFee) {
        // Calculate fee amount
        uint feeAmount = (_depositAmount * _feePct) / BPS;
        // Subtract fee amount from deposit amount
        depositAmountMinusFee = _depositAmount - feeAmount;
    }

    /// @dev This function utilizes another internal function, `_issueTokensFormulaWrapper`,
    /// to determine how many tokens should be minted.
    /// @param _depositAmount The amount of funds deposited for which tokens are to be issued.
    /// @return mintAmount The number of tokens that will be minted.
    function _issueTokens(uint _depositAmount)
        internal
        view
        returns (uint mintAmount)
    {
        mintAmount = _issueTokensFormulaWrapper(_depositAmount);
    }

    /// @dev Sets the number of decimals for the token.
    /// This function updates the `tokenDecimals` state variable.
    /// @param _decimals The number of decimals to set for the token.
    function _setTokenDecimals(uint8 _decimals) internal {
        if (_decimals == 0) {
            revert BondingCurveFundingManager__InvalidDecimals();
        }
        tokenDecimals = _decimals;
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
