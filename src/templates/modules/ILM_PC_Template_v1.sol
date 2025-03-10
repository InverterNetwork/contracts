// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal
import {IERC20PaymentClientBase_v2} from
    "@lm/interfaces/IERC20PaymentClientBase_v2.sol";

/**
 * @title   Inverter Template Logic Module Payment Client
 *
 * @notice  A template for a logic module payment client.
 *          Users can deposit tokens up to a maximum amount, and
 *          authorized admins can process these deposits into payment orders.
 *
 * @dev     This contract implements the following key functionality:
 *          - Deposit handling with maximum amount validation
 *          - Payment order creation and processing through the Orchestrator
 *          - Role-based access control for deposit processing
 *          - ERC20 token integration with SafeERC20
 *          - Interface compliance checks via ERC165
 *
 *          Key components:
 *          - Inherits from ERC20PaymentClientBase_v2
 *          - Uses DEPOSIT_ADMIN_ROLE for authorized payment processing
 *          - Tracks user deposits in _depositedAmounts mapping
 *          - Enforces maximum deposit limit of 100 ether
 *          - Processes payments through Orchestrator's payment processor
 *
 * @custom:setup    This module requires the following MANDATORY setup steps:
 *
 *                  1. Configure DEPOSIT_ADMIN_ROLE:
 *                     - Purpose: Implements access control for processing user
 *                               deposits. Only authorized admins can process
 *                               deposits into payment orders.
 *                     - How:     The OrchestratorAdmin must:
 *                               1. Retrieve the deposit admin role identifier
 *                               2. Grant the role to designated admins
 *                     - Example: module.grantModuleRole(
 *                                 module.DEPOSIT_ADMIN_ROLE(),
 *                                 adminAddress
 *                               );
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer
 *                          to our Security Policy at security.inverter.network
 *                          or email us directly!
 *
 * @custom:version 1.0.0
 *
 * @author  Inverter Network
 */
interface ILM_PC_Template_v1 is IERC20PaymentClientBase_v2 {
    // -------------------------------------------------------------------------
    // Events

    /// @notice Emit when the token amount has been deposited.
    /// @param  sender_ The address of the depositor.
    /// @param  amount_ The amount of tokens deposited.
    event Deposited(address indexed sender_, uint amount_);

    // -------------------------------------------------------------------------
    // Errors

    /// @notice Amount must be > 0 and not exceed maximum deposit limit.
    error Module__LM_PC_Template_InvalidDepositAmount();

    // -------------------------------------------------------------------------
    // Public - Getters

    /// @notice Returns the deposited balance of a specific address.
    /// @param  user_ The address of the user.
    /// @return amount_ Deposited amount of the user.
    function getDepositedAmount(address user_)
        external
        view
        returns (uint amount_);

    /// @notice Returns the payment token address.
    /// @return token_ The address of the payment token.
    function getPaymentToken() external view returns (address token_);

    // -------------------------------------------------------------------------
    // Public - Mutating

    /// @notice Deposits tokens to the funding manager.
    /// @param  amount_ The amount of tokens to deposit.
    function deposit(uint amount_) external;

    /// @notice Processes a user's deposit.
    /// @param  user_ The address of the user whose deposit to process.
    /// @param  start_ The start timestamp for the payment schedule.
    /// @param  cliff_ The cliff timestamp for the payment schedule.
    /// @param  end_ The end timestamp for the payment schedule.
    function processDeposit(address user_, uint start_, uint cliff_, uint end_)
        external;
}
