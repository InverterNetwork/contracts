// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal
import {IERC20PaymentClientBase_v2} from
    "@lm/interfaces/IERC20PaymentClientBase_v2.sol";

interface ILM_PC_FundingPot_v1 is IERC20PaymentClientBase_v2 {
    // -------------------------------------------------------------------------
    // Events

    // -------------------------------------------------------------------------
    // Errors

    /// @notice Amount can not be zero.
    error Module__LM_PC_FundingPot_InvalidDepositAmount();
    // -------------------------------------------------------------------------
    // Public - Getters

    /// @notice Returns the payment token.
    /// @return token_ The address of the payment token.
    function getPaymentToken() external view returns (address token_);

    /// @notice Returns the funding pot admin role.
    /// @return role_ The address of the funding pot admin role.
    function getFundingPotAdminRole() external pure returns (bytes32 role_);

    // -------------------------------------------------------------------------
    // Public - Mutating
}
