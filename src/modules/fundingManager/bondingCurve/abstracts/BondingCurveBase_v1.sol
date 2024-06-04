// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Dependencies
import {Module_v1} from "src/modules/base/Module_v1.sol";
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";

// External Interfaces
import {IERC20Issuance_v1} from
    "@fm/bondingCurve/interfaces/IERC20Issuance_v1.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

/**
 * @title   Bonding Curve Funding Manager Base
 *
 * @notice  Manages the issuance of token for collateral along a bonding curve in the
 *          Inverter Network, including fee handling and sell functionality control.
 *
 * @dev     Provides core functionalities for issuance operations, fee adjustments,
 *          and issuance calculations.
 *          Fee calculations utilize BPS for precision. Issuance-specific calculations should be
 *          implemented in derived contracts.
 *
 * @author  Inverter Network
 */
abstract contract BondingCurveBase_v1 is IBondingCurveBase_v1, Module_v1 {
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(Module_v1)
        returns (bool)
    {
        return interfaceId == type(IBondingCurveBase_v1).interfaceId
            || super.supportsInterface(interfaceId);
    }

    using SafeERC20 for IERC20Issuance_v1;
    using SafeERC20 for IERC20;

    //--------------------------------------------------------------------------
    // Storage

    /// @dev The token the Curve will mint and burn from
    IERC20Issuance_v1 internal issuanceToken;

    /// @dev Indicates whether the buy functionality is open or not.
    ///      Enabled = true || disabled = false.
    bool public buyIsOpen;
    /// @dev Buy fee expressed in base points, i.e. 0% = 0; 1% = 100; 10% = 1000
    uint public buyFee;
    /// @dev Base Points used for percentage calculation. This value represents 100%
    uint internal constant BPS = 10_000;
    /// @notice Accumulated project trading fees collected from deposits made by users
    /// when engaging with the bonding curve-based funding manager. Collected in collateral
    uint public projectCollateralFeeCollected;

    // Storage gap for future upgrades
    uint[50] private __gap;

    //--------------------------------------------------------------------------
    // Modifiers

    modifier buyingIsEnabled() {
        if (!buyIsOpen) {
            revert Module__BondingCurveBase__BuyingFunctionaltiesClosed();
        }
        _;
    }

    /// @dev Modifier to guarantee token recipient is valid.
    modifier validReceiver(address _receiver) {
        if (_receiver == address(0) || _receiver == address(this)) {
            revert Module__BondingCurveBase__InvalidRecipient();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Public Functions

    /// @inheritdoc IBondingCurveBase_v1
    function buyFor(address _receiver, uint _depositAmount, uint _minAmountOut)
        external
        virtual
        buyingIsEnabled
        validReceiver(_receiver)
    {
        _buyOrder(_receiver, _depositAmount, _minAmountOut);
    }

    /// @inheritdoc IBondingCurveBase_v1
    function buy(uint _depositAmount, uint _minAmountOut)
        external
        virtual
        buyingIsEnabled
    {
        _buyOrder(_msgSender(), _depositAmount, _minAmountOut);
    }

    //--------------------------------------------------------------------------
    // OnlyOrchestrator Functions

    /// @inheritdoc IBondingCurveBase_v1
    function openBuy() external virtual onlyOrchestratorOwner {
        _openBuy();
    }

    /// @inheritdoc IBondingCurveBase_v1
    function closeBuy() external virtual onlyOrchestratorOwner {
        _closeBuy();
    }

    /// @inheritdoc IBondingCurveBase_v1
    function setBuyFee(uint _fee) external virtual onlyOrchestratorOwner {
        _setBuyFee(_fee);
    }

    /// @inheritdoc IBondingCurveBase_v1
    function calculatePurchaseReturn(uint _depositAmount)
        external
        virtual
        returns (uint mintAmount)
    {
        return _calculatePurchaseReturn(_depositAmount);
    }

    /// @inheritdoc IBondingCurveBase_v1
    function withdrawProjectCollateralFee(address _receiver, uint _amount)
        external
        virtual
        validReceiver(_receiver)
        onlyOrchestratorOwner
    {
        _withdrawProjectCollateralFee(_receiver, _amount);
    }

    //--------------------------------------------------------------------------
    // Public Functions

    /// @notice Returns the address of the issuance token
    function getIssuanceToken() public view virtual returns (address) {
        return address(issuanceToken);
    }

    //--------------------------------------------------------------------------
    // Public Functions Implemented in Downstream Contract

    /// @inheritdoc IBondingCurveBase_v1
    function getStaticPriceForBuying() external view virtual returns (uint);

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
    /// @param _minAmountOut The minimum acceptable amount the user expects to receive from the transaction.
    /// @return totalIssuanceTokenMinted The total amount of issuance token minted during this function call
    /// @return collateralFeeAmount The amount of collateral token subtracted as fee
    function _buyOrder(
        address _receiver,
        uint _depositAmount,
        uint _minAmountOut
    )
        internal
        returns (uint totalIssuanceTokenMinted, uint collateralFeeAmount)
    {
        if (_depositAmount == 0) {
            revert Module__BondingCurveBase__InvalidDepositAmount();
        }

        // Cache Collateral Token
        IERC20 collateralToken = __Module_orchestrator.fundingManager().token();

        // Transfer collateral, confirming that correct amount == allowance
        collateralToken.safeTransferFrom(
            _msgSender(), address(this), _depositAmount
        );
        // Get protocol fee percentages and treasury addresses
        (
            address collateralTreasury,
            address issuanceTreasury,
            uint collateralBuyFeePercentage,
            uint issuanceBuyFeePercentage
        ) = _getBuyFeesAndTreasuryAddresses();

        uint protocolFeeAmount;
        uint workflowFeeAmount;
        uint netDeposit;
        // Get net amount, protocol and workflow fee amounts
        (netDeposit, protocolFeeAmount, workflowFeeAmount) =
        _calculateNetAndSplitFees(
            _depositAmount, collateralBuyFeePercentage, buyFee
        );

        //collateral Fee Amount is the combination of protocolFeeAmount plus the workflowFeeAmount
        collateralFeeAmount = protocolFeeAmount + workflowFeeAmount;

        // Process the protocol fee
        _processProtocolFeeViaTransfer(
            collateralTreasury, collateralToken, protocolFeeAmount
        );
        // Add workflow fee if applicable
        if (workflowFeeAmount > 0) {
            projectCollateralFeeCollected += workflowFeeAmount;
        }

        // Calculate mint amount based on upstream formula
        uint issuanceMintAmount = _issueTokensFormulaWrapper(netDeposit);
        totalIssuanceTokenMinted = issuanceMintAmount;

        // Get net amount, protocol and workflow fee amounts. Currently there is no issuance project
        // fee enabled
        (issuanceMintAmount, protocolFeeAmount, /* workflowFeeAmount */ ) =
        _calculateNetAndSplitFees(
            issuanceMintAmount, issuanceBuyFeePercentage, 0
        );
        // collect protocol fee on outgoing issuance token
        _processProtocolFeeViaMinting(issuanceTreasury, protocolFeeAmount);

        // Revert when the mint amount is lower than minimum amount the user expects
        if (issuanceMintAmount < _minAmountOut) {
            revert Module__BondingCurveBase__InsufficientOutputAmount();
        }
        // Mint tokens to address
        _mint(_receiver, issuanceMintAmount);
        // Emit event
        emit TokensBought(
            _receiver, _depositAmount, issuanceMintAmount, _msgSender()
        );
    }

    /// @dev Opens the buy functionality by setting the state variable `buyIsOpen` to true.
    function _openBuy() internal virtual {
        if (buyIsOpen) {
            revert Module__BondingCurveBase__BuyingAlreadyOpen();
        }
        buyIsOpen = true;
        emit BuyingEnabled();
    }

    /// @dev Closes the buy functionality by setting the state variable `buyIsOpen` to false.
    function _closeBuy() internal virtual {
        if (!buyIsOpen) {
            revert Module__BondingCurveBase__BuyingAlreadyClosed();
        }
        buyIsOpen = false;
        emit BuyingDisabled();
    }

    /// @dev Sets the buy transaction fee, expressed in BPS.
    /// @param _fee The fee percentage to set for buy transactions.
    function _setBuyFee(uint _fee) internal virtual {
        if (_fee >= BPS) {
            revert Module__BondingCurveBase__InvalidFeePercentage();
        }
        emit BuyFeeUpdated(_fee, buyFee);
        buyFee = _fee;
    }

    /// @dev Calculates the net amount after fee deduction and the fee amount based on
    /// a transaction amount and a specified fee percentage.
    /// @param _transactionAmount The amount involved in the transaction before fee deduction.
    /// @param _feePct The fee percentage to be deducted, represented in basis points (BPS).
    /// @return netAmount The transaction amount after fee deduction.
    /// @return feeAmount The amount of fee deducted from the transaction amount.
    function _calculateNetAmountAndFee(uint _transactionAmount, uint _feePct)
        internal
        pure
        virtual
        returns (uint netAmount, uint feeAmount)
    {
        // Return transaction amount as net amount if fee percentage is zero
        if (_feePct == 0) return (_transactionAmount, feeAmount);
        // Calculate fee amount
        feeAmount = (_transactionAmount * _feePct) / BPS;
        // Calculate net amount after fee deduction
        netAmount = _transactionAmount - feeAmount;
    }

    /// @dev Returns the collateral and issuance fee percentage retrieved from the fee manager for
    ///     buy operations
    /// @return collateralTreasury The address the protocol fee in collateral should be sent to
    /// @return issuanceTreasury The address the protocol fee in issuance should be sent to
    /// @return collateralBuyFeePercentage The percentage fee to be collected from the collateral
    ///     token being deposited for minting issuance, expressed in BPS
    /// @return issuanceBuyFeePercentage The percentage fee to be collected from the issuance token
    ///     being minted, expressed in BPS
    function _getBuyFeesAndTreasuryAddresses()
        internal
        view
        virtual
        returns (
            address collateralTreasury,
            address issuanceTreasury,
            uint collateralBuyFeePercentage,
            uint issuanceBuyFeePercentage
        )
    {
        (collateralBuyFeePercentage, collateralTreasury) =
        _getFeeManagerCollateralFeeData(
            bytes4(keccak256(bytes("_buyOrder(address, uint, uint)")))
        );
        (issuanceBuyFeePercentage, issuanceTreasury) =
        _getFeeManagerIssuanceFeeData(
            bytes4(keccak256(bytes("_buyOrder(address, uint, uint)")))
        );
    }

    //@note missing description
    function _calculateNetAndSplitFees(
        uint _totalAmount,
        uint _protocolFee,
        uint _workflowFee
    )
        public
        pure
        returns (uint netAmount, uint protocolFeeAmount, uint workflowFeeAmount)
    {
        if ((_protocolFee + _workflowFee) > BPS) {
            revert Module__BondingCurveBase__FeeAmountToHigh();
        }
        protocolFeeAmount = _totalAmount * _protocolFee / BPS;
        workflowFeeAmount = _totalAmount * _workflowFee / BPS;
        netAmount = _totalAmount - protocolFeeAmount - workflowFeeAmount;
    }

    function _processProtocolFeeViaTransfer(
        address _treasury,
        IERC20 _token,
        uint _feeAmount
    ) internal {
        // skip protocol fee collection if fee percentage set to zero
        if (_feeAmount == 0) return;
        if (_treasury == address(0)) {
            revert Module__BondingCurveBase__InvalidRecipient();
        }

        // transfer fee amount
        _token.safeTransfer(_treasury, _feeAmount);
        emit ProtocolFeeTransferred(address(_token), _treasury, _feeAmount);
    }

    function _processProtocolFeeViaMinting(address _treasury, uint _feeAmount)
        internal
    {
        // skip protocol fee collection if fee percentage set to zero
        if (_feeAmount == 0) return;
        if (_treasury == address(0)) {
            revert Module__BondingCurveBase__InvalidRecipient();
        }

        // mint fee amount
        _mint(_treasury, _feeAmount);
        emit ProtocolFeeMinted(address(this), _treasury, _feeAmount);
    }

    /// @dev This function takes into account any applicable buy fees before computing the
    /// token amount to be minted. Revert when depositAmount is zero.
    /// @param _depositAmount The amount of tokens deposited by the user.
    /// @return mintAmount The amount of new tokens that will be minted as a result of the deposit.
    function _calculatePurchaseReturn(uint _depositAmount)
        internal
        view
        virtual
        returns (uint mintAmount)
    {
        if (_depositAmount == 0) {
            revert Module__BondingCurveBase__InvalidDepositAmount();
        }
        // Get protocol fee percentages
        (
            /* collateralreasury */
            ,
            /* issuanceTreasury */
            ,
            uint collateralBuyFeePercentage,
            uint issuanceBuyFeePercentage
        ) = _getBuyFeesAndTreasuryAddresses();

        // Deduct protocol and project buy fee from collateral, if applicable
        (_depositAmount, /* protocolFeeAmount */, /* workflowFeeAmount */ ) =
        _calculateNetAndSplitFees(
            _depositAmount, collateralBuyFeePercentage, buyFee
        );

        // Calculate issuance token return from formula
        mintAmount = _issueTokensFormulaWrapper(_depositAmount);

        // Deduct protocol buy fee from issuance, if applicable
        (mintAmount, /* protocolFeeAmount */, /* workflowFeeAmount */ ) =
            _calculateNetAndSplitFees(mintAmount, issuanceBuyFeePercentage, 0);

        // Return expected purchase return amount
        return mintAmount;
    }

    /// @dev Sets the issuance token for the FundingManager.
    /// This function updates the `issuanceToken` state variable and should be be overriden by
    /// the implementation contract if extra validation around the token characteristics is needed.
    /// @param _issuanceToken The token which will be issued by the Bonding Curve.
    function _setIssuanceToken(address _issuanceToken) internal virtual {
        address oldToken = address(issuanceToken);
        issuanceToken = IERC20Issuance_v1(_issuanceToken);
        emit IssuanceTokenUpdated(oldToken, _issuanceToken);
    }

    /// @dev Witdraw project collateral fee amount to  to receiver.
    /// Reverts when the amount is bigger than witdrawable colllateral fee amount
    /// Deducts the _amount from the project fee collected
    function _withdrawProjectCollateralFee(address _receiver, uint _amount)
        internal
        virtual
    {
        if (_amount > projectCollateralFeeCollected) {
            revert Module__BondingCurveBase__InvalidWithdrawAmount();
        }

        projectCollateralFeeCollected -= _amount;

        __Module_orchestrator.fundingManager().token().safeTransfer(
            _receiver, _amount
        );

        emit ProjectCollateralFeeWithdrawn(_receiver, _amount);
    }

    //--------------------------------------------------------------------------
    // Calls to the external ERC20 contract

    /// @dev Mints new tokens
    /// @param _to The address of the recipient.
    /// @param _amount The amount of tokens to mint.
    function _mint(address _to, uint _amount) internal virtual {
        issuanceToken.mint(_to, _amount);
    }
    /// @dev Burns tokens
    /// @param _from The address of the owner.
    /// @param _amount The amount of tokens to burn.

    function _burn(address _from, uint _amount) internal virtual {
        issuanceToken.burn(_from, _amount);
    }
}
