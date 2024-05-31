// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IAuthorizer_v1} from "@aut/IAuthorizer_v1.sol";

interface IAUT_TokenGated_Roles_v1 is IAuthorizer_v1 {
    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when the token-gating of a role changes.
    /// @param role The role that was modified.
    /// @param newValue The new value of the role.
    event ChangedTokenGating(bytes32 role, bool newValue);

    /// @notice Event emitted when the threshold of a token-gated role changes.
    /// @param role The role that was modified.
    /// @param token The token for which the threshold was modified.
    /// @param newValue The new value of the threshold.
    event ChangedTokenThreshold(bytes32 role, address token, uint newValue);

    //--------------------------------------------------------------------------
    // Errors

    /// @notice The function is only callable by an active Module.
    error Module__AUT_TokenGated_Roles__RoleNotTokenGated();

    /// @notice The function is only callable if the Module is self-managing its roles.
    error Module__AUT_TokenGated_Roles__RoleNotEmpty();

    /// @notice The token doesn't support balance query.
    error Module__AUT_TokenGated_Roles__InvalidToken(address token);

    /// @notice The given threshold is invalid
    error Module__AUT_TokenGated_Roles__InvalidThreshold(uint threshold);

    /// @notice The role is token-gated but no threshold is set.
    error Module__AUT_TokenGated_Roles__TokenRoleMustHaveThreshold(
        bytes32 role, address token
    );

    //--------------------------------------------------------------------------
    // Public functions

    /// @notice Checks if an account qualifies for a token-gated role.
    /// @param role The role to be checked.
    /// @param who The account to be checked.
    function hasTokenRole(bytes32 role, address who)
        external
        view
        returns (bool);

    /// @notice Returns the threshold amount necessary to qualify for a given token role
    /// @param roleId The role to be checked on.
    /// @param token The token to check the threshold for.
    function getThresholdValue(bytes32 roleId, address token)
        external
        returns (uint);

    /// @notice Sets up a token-gated empty role.
    /// @param role The role to be made token-gated
    /// @dev This function is only callable by an active Module for itself. Admin should use setTokenGated().
    /// @dev Calling this function does not specify WHICH token to use for gating. That has to be done with 'grantTokenFromModule()'
    function makeRoleTokenGatedFromModule(bytes32 role) external;

    /// @notice One-step setup for Modules to create a token-gated role and set its threshold.
    ///        Please be aware that using tokens that are transferable and have active markets could
    ///         make the token-gated authorization vulnerable to flash loans, potentially bypassing
    ///         the authorization mechanism.
    /// @param role The role to be made token-gated
    /// @param token The token for which the threshold will be set.
    /// @param threshold The minimum balance of the token required to qualify for the role.
    function grantTokenRoleFromModule(
        bytes32 role,
        address token,
        uint threshold
    ) external;

    /// @notice Allows a Module to set the Threshold of one of it's roles
    /// @param role The token-gated role
    /// @param token The token for which the threshold will be set.
    /// @param threshold The new minimum balance of the token required to qualify for the role.
    function setThresholdFromModule(bytes32 role, address token, uint threshold)
        external;

    /// @notice Sets if a role is token-gated or not.
    /// @param role The ID of the role to be modified
    /// @param to The new value to be set.
    /// @dev Admin access for rescue purposes. If the role has active members, they need to be reovked first.
    function setTokenGated(bytes32 role, bool to) external;

    /// @notice Sets the minimum threshold for a token-gated role.
    /// @param roleId  The ID of the role to be modified
    /// @param token The token for which to the threshold.
    /// @param threshold The user will need to have at least this number to qualify for the role.
    /// @dev This function does not validate the threshold. It is technically possible to set a threshold above the total supply of the token.
    function setThreshold(bytes32 roleId, address token, uint threshold)
        external;
}
