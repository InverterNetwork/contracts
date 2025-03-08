// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal
import {IERC20PaymentClientBase_v2} from
    "@lm/interfaces/IERC20PaymentClientBase_v2.sol";

interface ILM_PC_FundingPot_v1 is IERC20PaymentClientBase_v2 {
    // =========================================================================
    // Events

    // =========================================================================
    // Errors

    /// @notice Funding pot admin role is already set.
    error Module__LM_PC_FundingPot_FundingPotAdminAlreadySet();

    /// @notice Address is not funding pot admin.
    error Module__LM_PC_FundingPot_AddressIsNotFundingPotAdmin();

    // =========================================================================
    // Public - Getters

    // =========================================================================
    // Public - Mutating

    /// @notice Grants the funding pot admin role to an address.
    /// @param admin_ The address to grant the funding pot admin role to.
    function grantFundingPotAdminRole(address admin_) external;

    /// @notice Revokes the funding pot admin role from an address.
    /// @param admin_ The address to revoke the funding pot admin role from.
    function revokeFundingPotAdminRole(address admin_) external;

    /// @notice Returns the funding pot admin role id.
    /// @return roleId_ The funding pot admin role id.
    function getFundingPotAdminRoleId() external view returns (bytes32);
}
