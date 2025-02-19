// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";
import {IERC20PaymentClientBase_v2} from
    "@lm/interfaces/IERC20PaymentClientBase_v2.sol";
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
 *              - IFM_PC_Oracle_Redeeming_v1.
 *              - ERC20PaymentClientBase_v2.
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
interface IFM_PC_Oracle_Redeeming_v1 is
    IFundingManager_v1,
    IERC20PaymentClientBase_v2,
    IRedeemingBondingCurveBase_v1
{
    // -------------------------------------------------------------------------
    // Type Declarations

    // Enum for redemption order states.
    enum RedemptionState {
        PROCESSED,
        CANCELLED,
        PENDING,
        FAILED
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

    /// @notice Thrown when the maximum buy/sell fee is invalid.
    error Module__FM_PC_ExternalPrice_Redeeming_InvalidMaxFee();

    // -------------------------------------------------------------------------
    // Events

    /// @notice	Emitted when reserve tokens are deposited.
    /// @param	depositor_ The address depositing tokens.
    /// @param	amount_ The amount deposited.
    event ReserveDeposited(address indexed depositor_, uint amount_);

    /// @notice Emitted when the project treasury address is updated.
    /// @param  currentProjectTreasury_ The current project treasury to be replaced.
    /// @param  newProjectTreasury_ The new project treasury replacing the current.
    event ProjectTreasuryUpdated(
        address indexed currentProjectTreasury_,
        address indexed newProjectTreasury_
    );

    /// @notice Emitted when the oracle address is updated.
    /// @param  currentOracle_ The current oracle to be replaced.
    /// @param  newOracle_ The new oracle replacing the current.
    event OracleUpdated(
        address indexed currentOracle_, address indexed newOracle_
    );

    /// @notice Emitted when direct operation permission is updated.
    /// @param  currentIsDirectOperationFlag_ The current state of
    ///         direct operation permission.
    /// @param  newIsDirectOperationFlag_ The new state of direct
    ///         operations permission.
    event DirectOperationsOnlyUpdated(
        bool indexed currentIsDirectOperationFlag_,
        bool indexed newIsDirectOperationFlag_
    );

    /// @notice	Emitted when a new redemption order is created.
    /// @param  paymentClient_ The address of payment client that created
    ///         the payment order.
    /// @param	orderId_ Order identifier.
    /// @param	seller_ Address selling tokens.
    /// @param	receiver_ Address who receives the redeemed collateral tokens.
    /// @param	sellAmount_ Amount of issuance tokens sold.
    /// @param	exchangeRate_ Current redemption exchange rate, denominated
    ///         in collateral token decimals.
    /// @param	feePercentage_ Project collateral fee percentage applied.
    /// @param	feeAmount_ Project collateral fee amount collected.
    /// @param	finalRedemptionAmount_ Final redemption amount to be received.
    /// @param	collateralToken_ Address of collateral token.
    /// @param	state_ Initial state of the order.
    event RedemptionOrderCreated(
        address indexed paymentClient_,
        uint indexed orderId_,
        address seller_,
        address indexed receiver_,
        uint sellAmount_,
        uint exchangeRate_,
        uint feePercentage_,
        uint feeAmount_,
        uint finalRedemptionAmount_,
        address collateralToken_,
        RedemptionState state_
    );

    /// @notice	Emitted when the open redemption amount is updated.
    /// @param	_openRedemptionAmount The new open redemption amount.
    event RedemptionAmountUpdated(uint _openRedemptionAmount);

    /// @notice Emitted when the maximum buy fee is set.
    /// @param  maxProjectBuyFee_ The maximum project buy fee.
    event MaxProjectBuyFeeSet(uint maxProjectBuyFee_);

    /// @notice Emitted when the maximum sell fee is set.
    /// @param  maxProjectSellFee_ The maximum project sell fee.
    event MaxProjectSellFeeSet(uint maxProjectSellFee_);

    // -------------------------------------------------------------------------
    // View Functions

    /// @notice	Gets the current open collateral redemption amount.
    /// @return	amount_ The total amount of open redemptions.
    function getOpenRedemptionAmount() external view returns (uint amount_);

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
    /// @return maxProjectBuyFee_ The maximum buy fee.
    function getMaxProjectBuyFee()
        external
        view
        returns (uint maxProjectBuyFee_);

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

    /// @notice Gets the whitelist role identifier
    /// @return role_ The whitelist role identifier
    function getWhitelistRole() external pure returns (bytes32 role_);

    /// @notice Gets the whitelist role admin identifier
    /// @return role_ The whitelist role admin identifier
    function getWhitelistRoleAdmin() external pure returns (bytes32 role_);

    /// @notice Gets the queue executor role identifier
    /// @return role_ The queue executor role identifier
    function getQueueExecutorRole() external pure returns (bytes32 role_);

    /// @notice Gets the queue executor role admin identifier
    /// @return role_ The queue executor role admin identifier
    function getQueueExecutorRoleAdmin()
        external
        pure
        returns (bytes32 role_);

    /// @notice Gets the oracle address.
    /// @return oracle_ The address of the oracle.
    function getOracle() external view returns (address oracle_);

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

    /// @notice Manually executes the redemption queue in the workflows Payment
    ///         Processor.
    /// @dev    If this function is called but the Payment Processor does not
    ///         implement the option to manually execute the redemption queue
    ///         then this function will revert.
    function executeRedemptionQueue() external;
}
