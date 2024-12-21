// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";
import {IERC20PaymentClientBase_v1} from
    "@lm/interfaces/IERC20PaymentClientBase_v1.sol";
import {IRedeemingBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IRedeemingBondingCurveBase_v1.sol";

/**
 * @title   External Price Oracle Funding Manager with Payment Client
 *
 * @notice  A funding manager implementation that uses external oracle price
 *          feeds for token operations. It integrates payment client
 *          functionality and supports token redemption through a bonding curve
 *          mechanism.
 *
 * @dev     This contract inherits from:
 *              - IFM_PC_ExternalPrice_Redeeming_v1.
 *              - ERC20PaymentClientBase_v1.
 *              - RedeemingBondingCurveBase_v1.
 *          Key features:
 *              - External price integration.
 *              - Payment client functionality.
 *          The contract uses external price feeds for both issuance and
 *          redemption operations, ensuring market-aligned token pricing.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to
 *                          our Security Policy at security.inverter.network or
 *                          email us directly!
 *
 * @custom:version  v1.0.0
 *
 * @custom:standard-version v1.0.0
 *
 * @author  Zealynx Security
 */
interface IFM_PC_ExternalPrice_Redeeming_v1 is
    IFundingManager_v1,
    IERC20PaymentClientBase_v1,
    IRedeemingBondingCurveBase_v1
{
    // -------------------------------------------------------------------------
    // Type Declarations

    // Enum for redemption order states.
    enum RedemptionState {
        COMPLETED,
        CANCELLED,
        PROCESSING
    }

    // -------------------------------------------------------------------------
    // Errors

    /// @notice	Thrown when an invalid amount is provided.
    error Module__FM_PC_ExternalPrice_Redeeming_InvalidAmount();

    /// @param	fee_ The fee that was attempted to be set.
    /// @param	maxFee_ The maximum allowed fee.
    error Module__FM_PC_ExternalPrice_Redeeming_FeeExceedsMaximum(
        uint fee_, uint maxFee_
    );

    /// @notice	Thrown when the oracle contract does not implement the required
    ///         interface.
    error Module__FM_PC_ExternalPrice_Redeeming_InvalidOracleInterface();

    /// @notice	Thrown when third-party operations are disabled.
    error Module__FM_PC_ExternalPrice_Redeeming_ThirdPartyOperationsDisabled();

    /// @notice	Thrown when a redemption queue execution fails.
    error Module__FM_PC_ExternalPrice_Redeeming_QueueExecutionFailed();

    /// @notice Thrown when the project treasury address is invalid.
    error Module__FM_PC_ExternalPrice_Redeeming_InvalidProjectTreasury();

    // -------------------------------------------------------------------------
    // Events

    /// @notice	Emitted when reserve tokens are deposited.
    /// @param	depositor_ The address depositing tokens.
    /// @param	amount_ The amount deposited.
    event ReserveDeposited(address indexed depositor_, uint amount_);

    /// @notice	Emitted when a new redemption order is created.
    /// @param	orderId_ Order identifier.
    /// @param	seller_ Address selling tokens.
    /// @param	receiver_ Address who receives the redeemed tokens.
    /// @param	sellAmount_ Amount of tokens to sell.
    /// @param	exchangeRate_ Current exchange rate.
    /// @param	collateralAmount_ Amount of collateral.
    /// @param	feePercentage_ Fee percentage applied.
    /// @param	feeAmount_ Fee amount calculated.
    /// @param	redemptionAmount_ Final redemption amount.
    /// @param	collateralToken_ Address of collateral token.
    /// @param	redemptionTime_ Time of redemption.
    /// @param	state_ Initial state of the order.
    event RedemptionOrderCreated(
        uint indexed orderId_,
        address indexed seller_,
        address indexed receiver_,
        uint sellAmount_,
        uint exchangeRate_,
        uint collateralAmount_,
        uint feePercentage_,
        uint feeAmount_,
        uint redemptionAmount_,
        address collateralToken_,
        uint redemptionTime_,
        RedemptionState state_
    );

    /// @notice	Emitted when the open redemption amount is updated.
    /// @param  redemptionAmount The new open redemption amount.
    /// @param	timestamp The timestamp when the update was made.
    event RedemptionAmountUpdated(
        uint indexed redemptionAmount, uint indexed timestamp
    );

    // -------------------------------------------------------------------------
    // View Functions

    /// @notice	Gets the current open collateral redemption amount.
    /// @return	amount_ The total amount of open redemptions.
    function getOpenRedemptionAmount() external view returns (uint amount_);

    /// @notice	Gets the next available order ID.
    /// @return	orderId_ The next order ID.
    function getNextOrderId() external view returns (uint orderId_);

    /// @notice	Gets the current order ID.
    /// @return	orderId_ The current order ID.
    function getOrderId() external view returns (uint orderId_);

    /// @notice Gets the project treasury address.
    /// @return treasury_ The address of the project treasury.
    function getProjectTreasury() external view returns (address treasury_);

    /// @notice Gets the direct operations only flag.
    /// @return isDirectOnly_ Whether only direct operations are allowed.
    function getIsDirectOperationsOnly()
        external
        view
        returns (bool isDirectOnly_);

    /// @notice Gets current buy fee.
    /// @return buyFee_ The current buy fee.
    function getBuyFee() external view returns (uint buyFee_);

    /// @notice Gets the maximum fee that can be charged for buy operations.
    /// @return maxBuyFee_ The maximum buy fee.
    function getMaxBuyFee() external view returns (uint maxBuyFee_);

    /// @notice Gets the maximum project fee that can be charged for sell
    ///         operations.
    /// @return maxProjectSellFee_ The maximum project sell fee percentage.
    function getMaxProjectSellFee()
        external
        view
        returns (uint maxProjectSellFee_);

    /// @notice Gets current sell fee.
    /// @return fee_ The current sell fee.
    function getSellFee() external view returns (uint fee_);

    // -------------------------------------------------------------------------
    // External Functions

    /// @notice	Allows depositing collateral to provide reserves for redemptions.
    /// @param	amount_ The amount of collateral to deposit.
    function depositReserve(uint amount_) external;

    /// @notice Sets the project treasury address.
    /// @param projectTreasury_ The address of the project treasury.
    function setProjectTreasury(address projectTreasury_) external;

    /// @notice Sets the oracle address.
    /// @param oracle_ The address of the oracle.
    function setOracleAddress(address oracle_) external;

    /// @notice Toggles whether the contract only allows direct operations or not.
    /// @param  isDirectOperationsOnly_ The new value for the flag.
    function setIsDirectOperationsOnly(bool isDirectOperationsOnly_) external;

    /// @notice Deducts the processed redeem amount from the open redemption
    ///         amount.
    /// @param  processedRedemptionAmount_ The amount of redemption tokens that
    ///         were processed.
    function deductProcessedRedemptionAmount(uint processedRedemptionAmount_)
        external;
}
