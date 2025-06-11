// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IAuthorizer_v2} from "@aut/IAuthorizer_v2.sol";

/**
 * @title   Inverter Token-Gated Role Authorizer Interface
 *
 * @notice  Extends the Inverter's role-based access control to include token
 *          gating, enabling roles to be conditionally assigned based on token
 *          ownership. This mechanism allows for dynamic permissioning tied to
 *          specific token holdings.
 *
 * @dev     Inherits functionality from:
 *          - {IAUT_TokenGated_Roles_v2}: Implementation interface.
 *          - {AUT_Roles_v2}: Inverter's role-based access control.
 *
 *          Key feeatures:
 *              - Token-based access checks before role assignment.
 *              - Supports both {ERC20} and {ERC721} tokens.
 *
 * @custom:documentation See https://github.com/InverterNetwork/contracts/tree/dev/docs/src/modules/authorizer/role/AUT_TokenGated_Roles_v2.md
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to
 *                          our Security Policy at security.inverter.network or
 *                          email us directly!
 *
 * @custom:version  v2.0.0
 *
 * @custom:inverter-standard-version    v0.1.0
 *
 * @author  Inverter Network
 */
interface IAUT_TokenGated_Roles_v2 is IAuthorizer_v2 {
    //=======================================================================
    // Errors

    /// @notice The function is only callable by an active Module.
    error Module__AUT_TokenGated_Roles__RoleNotTokenGated();

    /// @notice The function is only callable if the Module is self-managing
    ///         its roles.
    error Module__AUT_TokenGated_Roles__RoleNotEmpty();

    /// @notice The function is only callable if the Module is not the public
    ///         role.
    error Module__AUT_TokenGated_Roles__RoleIsPublic();

    /// @notice The token doesn't support balance query.
    /// @param  token_ The token address that is not supported.
    error Module__AUT_TokenGated_Roles__InvalidToken(address token_);

    /// @notice The given threshold is invalid.
    /// @param  threshold_ The threshold that is not valid.
    error Module__AUT_TokenGated_Roles__InvalidThreshold(uint threshold_);

    /// @notice The role is token-gated but no threshold is set.
    /// @param  roleId_ The role that doesnt have threshold.
    /// @param  token_ The token for which the threshold was not set.
    error Module__AUT_TokenGated_Roles__TokenRoleMustHaveThreshold(
        bytes32 roleId_, address token_
    );

    //=======================================================================
    // Events

    /// @notice Event emitted when the token-gating of a role changes.
    /// @param  roleId_ The role id of the role that was modified.
    /// @param  newValue_ The new value of the role.
    event ChangedTokenGating(bytes32 roleId_, bool newValue_);

    /// @notice Event emitted when the threshold of a token-gated role changes.
    /// @param  roleId_ The role id of the role that was modified.
    /// @param  token_ The token for which the threshold was modified.
    /// @param  newValue_ The new value of the threshold.
    event ChangedTokenThreshold(
        bytes32 roleId_, address token_, uint newValue_
    );

    // ========================================================================
    // Public Getter Functions

    /// @notice Returns if a role is token-gated or not.
    /// @param  roleId_ The ID of the role to be checked.
    /// @return isTokenGated_ True if the role is token-gated.
    function isTokenGated(bytes32 roleId_)
        external
        view
        returns (bool isTokenGated_);

    /// @notice Checks if an account qualifies for a token-gated role.
    /// @param  roleId_ The role to be checked.
    /// @param  who_ The account to be checked.
    /// @return hasTokenRole_ True if the account qualifies for the role.
    function hasTokenRole(bytes32 roleId_, address who_)
        external
        view
        returns (bool hasTokenRole_);

    /// @notice Returns the threshold balance for a given token necessary to
    ///         qualify for a specific role. If the value is 0, the supplied
    ///         token is not part of the role's token gating.
    /// @dev	In case the queried role is not token gated, all calls will
    ///         return 0.
    /// @param  roleId_ The role to be checked on.
    /// @param  token_ The token to check the threshold for.
    /// @return threshold_ The threshold amount necessary to qualify for a
    ///         given token role.
    function getThresholdValue(bytes32 roleId_, address token_)
        external
        returns (uint threshold_);

    // ========================================================================
    // Mutating Functions

    /// @notice Sets if a role is token-gated or not.
    /// @dev	Admin access for rescue purposes. If the role has active
    ///         members, they need to be reovked first.
    /// @param  roleId_ The ID of the role to be modified.
    /// @param  to_ The new value to be set.

    function setTokenGated(bytes32 roleId_, bool to_) external;

    /// @notice Sets the minimum threshold for a token-gated role.
    /// @dev	This function does not validate the threshold. It is
    ///         technically possible to set a threshold above the total supply
    ///         of the token.
    /// @param  roleId_  The ID of the role to be modified.
    /// @param  token_ The token for which to the threshold.
    /// @param  threshold_ The user will need to have at least this number to
    ///         qualify for the role.

    function setThreshold(bytes32 roleId_, address token_, uint threshold_)
        external;
}
