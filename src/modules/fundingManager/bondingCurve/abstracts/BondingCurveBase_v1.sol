// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Dependencies
import {Module_v1, IModule_v1} from "src/modules/base/Module_v1.sol";
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";

// External Interfaces
import {IERC20Issuance_v1} from "@ex/token/IERC20Issuance_v1.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@oz/token/ERC20/extensions/IERC20Metadata.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

// External Dependencies
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

/**
 * @title   Inverter Bonding Curve Funding Manager Base
 *
 * @notice  Manages the issuance of token for collateral along a bonding curve in the
 *          Inverter Network, including fee handling and sell functionality control.
 *
 * @dev     Provides core functionalities for issuance operations, fee adjustments,
 *          and issuance calculations.
 *          Fee calculations utilize BPS for precision. Issuance-specific calculations should be
 *          implemented in derived contracts.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer
 *                          to our Security Policy at security.inverter.network
 *                          or email us directly!
 *
 * @custom:version 1.1.2
 *
 * @author  Inverter Network
 */
abstract contract BondingCurveBase_v1 is IBondingCurveBase_v1, Module_v1 {
    /// @inheritdoc ERC165Upgradeable
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

    // -------------------------------------------------------------------------
    // Storage

    /// @dev	Base Points used for percentage calculation. This value represents 100%.
    uint internal constant BPS = 10_000;

    /// @dev	The token the curve will mint and burn from.
    IERC20Issuance_v1 internal issuanceToken;

    /// @dev	Indicates whether the buy functionality is open or not.
    ///         Enabled = true || disabled = false.
    bool public buyIsOpen;
    /// @dev	Buy fee expressed in base points, i.e. 0% = 0; 1% = 100; 10% = 1000.
    uint public buyFee;

    /// @notice Accumulated project trading fees collected from deposits made by users
    ///         when engaging with the bonding curve-based funding manager. Collected in collateral.
    uint public projectCollateralFeeCollected;

    /// @dev	Storage gap for future upgrades.
    uint[50] private __gap;

    // -------------------------------------------------------------------------
    // Modifiers

    /// @dev	Modifier to guarantee the buying functionality is enabled.
    modifier buyingIsEnabled() {
        _checkBuyIsEnabled();
        _;
    }

    /// @dev	Modifier to guarantee token recipient is valid.
    modifier validReceiver(address _receiver) {
        _validateRecipient(_receiver);
        _;
    }

    // -------------------------------------------------------------------------
    // Public Functions

    /// @inheritdoc IBondingCurveBase_v1
    function buyFor(address _receiver, uint _depositAmount, uint _minAmountOut)
        public
        virtual
        buyingIsEnabled
        validReceiver(_receiver)
    {
        _buyOrder(_receiver, _depositAmount, _minAmountOut);
    }

    /// @inheritdoc IBondingCurveBase_v1
    function buy(uint _depositAmount, uint _minAmountOut) public virtual {
        buyFor(_msgSender(), _depositAmount, _minAmountOut);
    }

    // -------------------------------------------------------------------------
    // OnlyOrchestrator Functions

    /// @inheritdoc IBondingCurveBase_v1
    function openBuy() external virtual onlyOrchestratorAdmin {
        buyIsOpen = true;
        emit BuyingEnabled();
    }

    /// @inheritdoc IBondingCurveBase_v1
    function closeBuy() external virtual onlyOrchestratorAdmin {
        buyIsOpen = false;
        emit BuyingDisabled();
    }

    /// @inheritdoc IBondingCurveBase_v1
    function setBuyFee(uint _fee) external virtual onlyOrchestratorAdmin {
        _setBuyFee(_fee);
    }

    /// @inheritdoc IBondingCurveBase_v1
    function calculatePurchaseReturn(uint _depositAmount)
        public
        view
        virtual
        returns (uint mintAmount)
    {
        // Set min amount out to 1 for price calculation
        _ensureNonZeroTradeParameters(_depositAmount, 1);
        // Get protocol fee percentages
        (
            ,
            ,
            /* collateralreasury */
            /* issuanceTreasury */
            uint collateralBuyFeePercentage,
            uint issuanceBuyFeePercentage
        ) = _getFunctionFeesAndTreasuryAddresses(
            bytes4(keccak256(bytes("_buyOrder(address,uint,uint)")))
        );

        // Deduct protocol and project buy fee from collateral, if applicable
        (_depositAmount, /* protocolFeeAmount */ /* projectFeeAmount */,) =
        _calculateNetAndSplitFees(
            _depositAmount, collateralBuyFeePercentage, buyFee
        );

        // Get issuance token return from formula and deduct protocol buy fee, if applicable
        (mintAmount, /* protocolFeeAmount */ /* projectFeeAmount */,) =
        _calculateNetAndSplitFees(
            _issueTokensFormulaWrapper(_depositAmount),
            issuanceBuyFeePercentage,
            0
        );
    }

    /// @inheritdoc IBondingCurveBase_v1
    function withdrawProjectCollateralFee(address _receiver, uint _amount)
        public
        virtual
        validReceiver(_receiver)
        onlyOrchestratorAdmin
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

    // -------------------------------------------------------------------------
    // Public Functions

    /// @inheritdoc IBondingCurveBase_v1
    function getIssuanceToken() external view virtual returns (address) {
        return address(issuanceToken);
    }

    // -------------------------------------------------------------------------
    // Public Functions Implemented in Downstream Contract

    /// @inheritdoc IBondingCurveBase_v1
    function getStaticPriceForBuying() external view virtual returns (uint);

    // -------------------------------------------------------------------------
    // Internal Functions Implemented in Downstream Contract

    /// @dev    Function used for wrapping the call to the external contract responsible for
    ///         calculating the issuing amount. This function is an abstract function and must be
    ///         implemented in the downstream contract.
    /// @param  _depositAmount The amount of collateral token that is deposited.
    /// @return uint Return the amount of tokens to be issued.
    function _issueTokensFormulaWrapper(uint _depositAmount)
        internal
        view
        virtual
        returns (uint);

    // -------------------------------------------------------------------------
    // Internal Functions

    /// @dev    Internal function to handle the buying of tokens.
    ///         This function performs the core logic for buying tokens. It transfers the collateral,
    ///         deducts any applicable fees, and mints new tokens for the buyer.
    /// @param  _receiver The address that will receive the bought tokens.
    /// @param  _depositAmount The amount of collateral to deposit for buying tokens.
    /// @param  _minAmountOut The minimum acceptable amount the user expects to receive from the transaction.
    /// @return totalIssuanceTokenMinted The total amount of issuance token minted during this function call.
    /// @return collateralFeeAmount The amount of collateral token subtracted as fee.
    function _buyOrder(
        address _receiver,
        uint _depositAmount,
        uint _minAmountOut
    )
        internal
        returns (uint totalIssuanceTokenMinted, uint collateralFeeAmount)
    {
        _ensureNonZeroTradeParameters(_depositAmount, _minAmountOut);

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
        ) = _getFunctionFeesAndTreasuryAddresses(
            bytes4(keccak256(bytes("_buyOrder(address,uint,uint)")))
        );

        // Get net amount, protocol and project fee amounts
        (uint netDeposit, uint protocolFeeAmount, uint projectFeeAmount) =
        _calculateNetAndSplitFees(
            _depositAmount, collateralBuyFeePercentage, buyFee
        );

        // collateral Fee Amount is the combination of protocolFeeAmount plus the projectFeeAmount
        collateralFeeAmount = protocolFeeAmount + projectFeeAmount;

        // Process the protocol fee
        _processProtocolFeeViaTransfer(
            collateralTreasury, collateralToken, protocolFeeAmount
        );

        // Add project fee if applicable
        if (projectFeeAmount > 0) {
            _projectFeeCollected(projectFeeAmount);
        }

        // Calculate token amount based on upstream formula
        uint issuanceTokenAmount = _issueTokensFormulaWrapper(netDeposit);
        totalIssuanceTokenMinted = issuanceTokenAmount;

        // Get net amount, protocol and project fee amounts. Currently there is no issuance project
        // fee enabled
        (issuanceTokenAmount, protocolFeeAmount, /* projectFeeAmount */ ) =
        _calculateNetAndSplitFees(
            issuanceTokenAmount, issuanceBuyFeePercentage, 0
        );
        // collect protocol fee on outgoing issuance token
        _processProtocolFeeViaMinting(issuanceTreasury, protocolFeeAmount);

        // Revert if the token amount is lower than the minimum amount the user expects
        if (issuanceTokenAmount < _minAmountOut) {
            revert Module__BondingCurveBase__InsufficientOutputAmount();
        }

        // Use virtual function to handle issuance tokens
        _handleIssuanceTokensAfterBuy(_receiver, issuanceTokenAmount);

        emit TokensBought(
            _receiver, _depositAmount, issuanceTokenAmount, _msgSender()
        );
    }

    /// @notice Virtual function to handle issuance tokens after a successful buy.
    /// @param  _receiver The address for which the issuance tokens will be handled.
    /// @param  _issuanceTokenAmount The amount of issuance tokens to handle.
    function _handleIssuanceTokensAfterBuy(
        address _receiver,
        uint _issuanceTokenAmount
    ) internal virtual;

    /// @dev	Sets the buy transaction fee, expressed in BPS.
    /// @param  _fee The fee percentage to set for buy transactions.
    function _setBuyFee(uint _fee) internal virtual {
        _validateProjectFee(_fee);
        emit BuyFeeUpdated(_fee, buyFee);
        buyFee = _fee;
    }

    /// @dev    Returns the collateral and issuance fee percentage retrieved from the fee manager for
    ///         a specific operation.
    /// @return collateralTreasury The address the protocol fee in collateral should be sent to.
    /// @return issuanceTreasury The address the protocol fee in issuance should be sent to.
    /// @return collateralFeePercentage The percentage fee to be collected from the collateral
    ///                                  token being deposited or redeemed, expressed in BPS.
    /// @return issuanceFeePercentage The percentage fee to be collected from the issuance token
    ///         being deposited or minted, expressed in BPS.
    function _getFunctionFeesAndTreasuryAddresses(bytes4 _selector)
        internal
        view
        virtual
        returns (
            address collateralTreasury,
            address issuanceTreasury,
            uint collateralFeePercentage,
            uint issuanceFeePercentage
        )
    {
        (collateralFeePercentage, collateralTreasury) =
            _getFeeManagerCollateralFeeData(_selector);
        (issuanceFeePercentage, issuanceTreasury) =
            _getFeeManagerIssuanceFeeData(_selector);
    }

    /// @dev    Calculates the proportion of the fees for the given amount and returns them plus the amount
    ///         minus the fees.
    ///         Reverts under the following two conditions:
    ///         - if (project fee + protocol fee) > BPS
    ///         - if protocol fee amount or project fee amounts == 0 given the fee percentage is not zero. This
    ///         would indicate a rouding down to zero due to integer division.
    /// @param  _totalAmount The amount from which the fees will be taken.
    /// @param  _protocolFee The protocol fee percentage in relation to the BPS that will be applied to the `totalAmount`.
    /// @param  _projectFee The project fee percentage in relation to the BPS that will be applied to the `totalAmount`.
    /// @return netAmount   The total amount minus the combined fee amount.
    /// @return protocolFeeAmount   The fee amount of the protocol fee.
    /// @return projectFeeAmount   The fee amount of the project fee.
    function _calculateNetAndSplitFees(
        uint _totalAmount,
        uint _protocolFee,
        uint _projectFee
    )
        internal
        pure
        returns (uint netAmount, uint protocolFeeAmount, uint projectFeeAmount)
    {
        if ((_protocolFee + _projectFee) >= BPS) {
            revert Module__BondingCurveBase__FeeAmountToHigh();
        }
        // Calculate protocol fee amount if applicable
        if (_protocolFee > 0) {
            protocolFeeAmount = _totalAmount * _protocolFee / BPS;
            // Revert if calculated protocol fee amount rounded down to zero
            if (protocolFeeAmount == 0) {
                revert Module__BondingCurveBase__TradeAmountTooLow();
            }
        }
        // Calculate project fee amount if applicable
        if (_projectFee > 0) {
            projectFeeAmount = _totalAmount * _projectFee / BPS;
            // Revert if calculated project fee amount rounded down to zero
            if (projectFeeAmount == 0) {
                revert Module__BondingCurveBase__TradeAmountTooLow();
            }
        }

        netAmount = _totalAmount - protocolFeeAmount - projectFeeAmount;
    }

    /// @dev	Internal function to transfer protocol fees to the treasury.
    /// @param  _treasury The address of the protocol treasury.
    /// @param  _token The token to transfer the fees from.
    /// @param  _feeAmount The amount of fees to transfer.
    function _processProtocolFeeViaTransfer(
        address _treasury,
        IERC20 _token,
        uint _feeAmount
    ) internal {
        // skip protocol fee collection if fee percentage set to zero
        if (_feeAmount > 0) {
            _validateRecipient(_treasury);

            // transfer fee amount
            _token.safeTransfer(_treasury, _feeAmount);
            emit IModule_v1.ProtocolFeeTransferred(
                address(_token), _treasury, _feeAmount
            );
        }
    }

    function _processProtocolFeeViaMinting(address _treasury, uint _feeAmount)
        internal
    {
        // skip protocol fee collection if fee percentage set to zero
        if (_feeAmount > 0) {
            _validateRecipient(_treasury);

            // mint fee amount
            _mint(_treasury, _feeAmount);
            emit ProtocolFeeMinted(address(this), _treasury, _feeAmount);
        }
    }

    /// @dev    Sets the issuance token for the FundingManager.
    ///         This function updates the `issuanceToken` state variable and should be be overridden by
    ///         the implementation contract if extra validation around the token characteristics is needed.
    /// @param  _issuanceToken The token which will be issued by the Bonding Curve.
    function _setIssuanceToken(address _issuanceToken) internal virtual {
        emit IssuanceTokenSet(
            _issuanceToken, IERC20Metadata(_issuanceToken).decimals()
        );
        issuanceToken = IERC20Issuance_v1(_issuanceToken);
    }

    /// @dev    Checks if the buy functionality is enabled.
    function _checkBuyIsEnabled() internal view {
        if (!buyIsOpen) {
            revert Module__BondingCurveBase__BuyingFunctionaltiesClosed();
        }
    }

    /// @dev    Validates the recipient address.
    function _validateRecipient(address _receiver) internal view {
        if (_receiver == address(0) || _receiver == address(this)) {
            revert Module__BondingCurveBase__InvalidRecipient();
        }
    }

    /// @dev    Validates the project fee.
    function _validateProjectFee(uint _projectFee) internal pure virtual {
        if (_projectFee > BPS) {
            revert Module__BondingCurveBase__InvalidFeePercentage();
        }
    }

    /// @dev    Internal function to add project fee collected to the state variable
    /// @param  _projectFeeAmount The amount of fee collected
    function _projectFeeCollected(uint _projectFeeAmount) internal virtual {
        projectCollateralFeeCollected += _projectFeeAmount;
        emit ProjectCollateralFeeAdded(_projectFeeAmount);
    }

    /// @dev    Ensures that the deposit amount and min amount out are not zero.
    /// @param  _depositAmount Deposit amount.
    /// @param  _minAmountOut Minimum amount out.`
    function _ensureNonZeroTradeParameters(
        uint _depositAmount,
        uint _minAmountOut
    ) internal pure {
        if (_depositAmount == 0) {
            revert Module__BondingCurveBase__InvalidDepositAmount();
        }
        if (_minAmountOut == 0) {
            revert Module__BondingCurveBase__InvalidMinAmountOut();
        }
    }

    // -------------------------------------------------------------------------
    // Calls to the external ERC20 contract

    /// @dev	Mints new tokens.
    /// @param  _to The address of the recipient.
    /// @param  _amount The amount of tokens to mint.
    function _mint(address _to, uint _amount) internal virtual {
        issuanceToken.mint(_to, _amount);
    }

    /// @dev	Burns tokens.
    /// @param  _from The address of the owner.
    /// @param  _amount The amount of tokens to burn.
    function _burn(address _from, uint _amount) internal virtual {
        issuanceToken.burn(_from, _amount);
    }
}
