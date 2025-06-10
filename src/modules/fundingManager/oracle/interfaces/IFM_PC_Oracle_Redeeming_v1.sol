// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";
import {IERC20PaymentClientBase_v2} from
    "@lm/interfaces/IERC20PaymentClientBase_v2.sol";
import {IRedeemingBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IRedeemingBondingCurveBase_v1.sol";

/**
 * @title   External Price Oracle Funding Manager with Payment Client.
 *
 * @notice  A funding manager implementation that manages token issuance and
 *          redemption based on external oracle price feeds. While token
 *          issuance is processed immediately, redemption requests are added
 *          to a queue for delayed processing through an integrated payment
 *          client system.
 *
 * @dev     Inherits functionality from:
 *          - IFM_PC_Oracle_Redeeming_v1: Implementation interface.
 *          - ERC20PaymentClientBase_v2: Payment processing capabilities.
 *          - RedeemingBondingCurveBase_v1: Token issuance and redemption logic.
 *
 *          Key features:
 *              - Oracle-driven token pricing.
 *                Uses external price feeds to determine token value for all
 *                issuance and redemption operations.
 *
 *              - Token issuance and redemption.
 *                Mints new tokens during purchases and burns tokens during
 *                sell operations at oracle-determined prices.
 *
 *              - Queue-based redemption and payment processing.
 *                Creates payment orders in a queue and sends them to the payment
 *                processor for executing token redemptions.
 *
 *              - Fee management on buy/sell operations.
 *                Configurable fee structure for trading operations.
 *
 * @custom:setup    This module requires the following MANDATORY setup steps:
 *
 *                  1. Grant Minting Permission:
 *                     - Purpose: The module needs direct minting/burning
 *                                capability to handle token issuance and
 *                                redemption operations. Without this permission,
 *                                the module cannot mint or burn tokens.
 *                     - How:     The owner of the issuance token contract must
 *                                call the minter setting function to authorize
 *                                this module.
 *                     - Example: issuanceToken.setMinter(moduleAddress, true);
 *
 *                  2. Configure Oracle:
 *                     - Purpose: Since the Oracle is a separate module, it
 *                                cannot be set during initialization. The Oracle
 *                                provides price feed data needed for token
 *                                valuations during issuance and redemption.
 *                     - How:     The OrchestratorAdmin must first get the
 *                                deployed Oracle module's address, then call the
 *                                setter function.
 *                     - Example: module.setOracleAddress(oracleAddress);
 *
 *                  3. Enable Trading:
 *                     - Purpose: Makes the the buy/sell functionality of the
 *                                contract public. Trading must be explicitly
 *                                enabled.
 *                     - How:     The OrchestratorAdmin must enable both buying
 *                                and selling operations separately.
 *                     - Example: authorizer.addAccessPermission(buy.selector);
 *                                authorizer.addAccessPermission(sell.selector);
 *                                module.openBuy();
 *                                module.openSell();
 *
 *                  OPTIONAL setup steps for enhanced administration:
 *
 *                  1. Setup Whitelist:
 *                     - Purpose: Implements access control for buy/sell
 *                                functions. Only whitelisted addresses can
 *                                participate in token buy & sell operations to
 *                                provide a security layer for controlled token
 *                                distribution and compliance.
 *                     - How:     The OrchestratorAdmin must:
 *                                1. Create a whitelist role
 *                                2. Add access permission for the buy() and
 *                                   sell() functions to the whitelist role.
 *                                3. Grant the role to desired addresses.
 *                     - Example: authorizer.createRole();
 *                                authorizer.addAccessPermission();
 *                                authorizer.grantRole();
 *                     - Notice:  This assumes that the function access
 *                                permissions currently don't contain the
 *                                public role.
 *
 *                  2. Setup Queue Executors:
 *                     - Purpose: Implements access control for authorized
 *                                addresses that can process the redemption
 *                                queue.
 *                     - How:     The OrchestratorAdmin must:
 *                                1. Create a queue executor role
 *                                2. Add access permission for the executeRedemptionQueue() function.
 *                                3. Grant the role to designated executors.
 *                     - Example: authorizer.createRole();
 *                                authorizer.addAccessPermission();
 *                                authorizer.grantRole();
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
    error Module__FM_PC_ExternalPrice_Redeeming_QueueExecutionFailed(bytes data);

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
    /// @param	protocolFeeAmount_ Protocol collateral fee amount collected.
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
        uint protocolFeeAmount_,
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

    /// @notice Gets the oracle address.
    /// @return oracle_ The address of the oracle.
    function getOracle() external view returns (address oracle_);

    // -------------------------------------------------------------------------
    // External Functions

    /// @notice	Allows depositing collateral to provide reserves for redemptions.
    /// @dev    This function is always publicly callable.
    /// @param	amount_ The amount of collateral to deposit.
    function depositReserve(uint amount_) external;

    /// @notice Sets the project treasury address.
    /// @dev    Function access controlled by authorizer.
    /// @param  projectTreasury_ The address of the project treasury.
    function setProjectTreasury(address projectTreasury_) external;

    /// @notice Sets the oracle address.
    /// @dev    Function access controlled by authorizer.
    /// @param  oracle_ The address of the oracle.
    function setOracleAddress(address oracle_) external;

    /// @notice Toggles whether the contract only allows direct operations or not.
    /// @dev    Function access controlled by authorizer.
    /// @param  isDirectOperationsOnly_ The new value for the flag.
    function setIsDirectOperationsOnly(bool isDirectOperationsOnly_) external;

    /// @notice Manually executes the redemption queue in the workflows Payment
    ///         Processor.
    /// @dev    Function access controlled by authorizer.
    /// @dev    If this function is called but the Payment Processor does not
    ///         implement the option to manually execute the redemption queue
    ///         then this function will revert.
    function executeRedemptionQueue() external;
}
