// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal
import {IERC20PaymentClientBase_v2} from
    "@lm/interfaces/IERC20PaymentClientBase_v2.sol";

/**
 * @title   Inverter Template Logic Module Payment Client
 *
 * @notice  A template logic module payment client that handles deposits and payment processing.
 *          Users can deposit tokens up to a maximum amount, and authorized admins can process
 *          these deposits into payment orders.
 *
 * @dev     This contract implements the following key functionality:
 *          - Deposit handling with maximum amount validation
 *          - Payment order creation and processing through the Orchestrator
 *          - Role-based access control for deposit processing
 *          - ERC20 token integration with SafeERC20
 *          - Interface compliance checks via ERC165
 *
 *          Key components:
 *          - Inherits ERC20PaymentClientBase_v2 for payment client functionality
 *          - Uses DEPOSIT_ADMIN_ROLE for authorized payment processing
 *          - Tracks user deposits in _depositedAmounts mapping
 *          - Enforces maximum deposit limit of 100 ether
 *          - Processes payments through Orchestrator's payment processor
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
interface ILM_PC_FundingPot_v1 is IERC20PaymentClientBase_v2 {
    // =========================================================================
    // Events

    /// @notice Emit when the token amount has been deposited.
    /// @param  sender_ The address of the depositor.
    /// @param  amount_ The amount of tokens deposited.
    event Deposited(address indexed sender_, uint amount_);

    // =========================================================================
    // Errors

    /// @notice Amount can not be zero.
    error Module__LM_PC_FundingPot_InvalidDepositAmount();
    error Module__LM_PC_FundingPot_FundingPotAdminAlreadySet();
    error Module__LM_PC_FundingPot_AddressIsNotFundingPotAdmin();

    // =========================================================================
    // Public - Getters

    /// @notice Returns the deposited balance of a specific address.
    /// @param  user_ The address of the user.
    /// @return amount_ Deposited amount of the user.
    function getDepositedAmount(address user_)
        external
        view
        returns (uint amount_);

    // =========================================================================
    // Public - Mutating

    /// @notice Deposits tokens to the funding manager.
    /// @param  amount_ The amount of tokens to deposit.
    function deposit(uint amount_) external;

    /// @notice Process a specific deposit by calling processPayments on the payment processor
    /// @param user_ The address of the user whose deposit to process
    function processDeposit(address user_) external;

    /// @notice Grants the funding pot admin role to an address.
    /// @param admin_ The address to grant the funding pot admin role to.
    function grantFundingPotAdminRole(address admin_) external;

    /// @notice Revokes the funding pot admin role from an address.
    /// @param admin_ The address to revoke the funding pot admin role from.
    function revokeFundingPotAdminRole(address admin_) external;
}
