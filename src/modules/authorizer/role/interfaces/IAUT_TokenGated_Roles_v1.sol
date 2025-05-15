// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IAuthorizer_v1} from "@aut/IAuthorizer_v1.sol";

/**
 * @title   Inverter Token-Gated Role Authorizer Interface
 *
 * @notice  Extends the Inverter's role-based access control to include token
 *          gating, enabling roles to be conditionally assigned based on token
 *          ownership. This mechanism allows for dynamic permissioning tied to
 *          specific token holdings.
 *
 * @dev     Inherits functionality from:
 *          - {IAUT_TokenGated_Roles_v1}: Implementation interface.
 *          - {AUT_Roles_v1}: Inverter's role-based access control.
 *
 *          Key feeatures:
 *              - Token-based access checks before role assignment.
 *              - Supports both {ERC20} and {ERC721} tokens.
 *
 * @custom:guide
 *          The following guide explains in detail how to use the key features
 *          of this module:
 *
 *              - TOKEN BASED ACCESS CONTROL:
 *                  - Token Gated Role:
 *                    With this contract it is possible to extend the base
 *                    functionality of the {AUT_Roles_v1} contract to make a
 *                    role token gated. A token gated role behaves in all
 *                    respects like a regular role, but handles the membership
 *                    of that role differently. A member of a token gated role
 *                    is only allowed to access the role functionalities if
 *                    they hold a certain amount of a token.
 *                    The implementation of this contract uses a few tricks to
 *                    achieve this. Without going into too much detail, this
 *                    is the main part that is needed to understand the basic
 *                    mechanism:
 *                    In the contract the token gating is done by instead of
 *                    saving the members of the role directly in the members
 *                    property of the role, the contract saves the token
 *                    address that will gate the role in the property. That way
 *                    the token address can be looked up and the threshold
 *                    amount compared to the token balance of incoming users.
 *                    Example: We want to adapt a role so that it can only be
 *                    accessed by users that hold a certain amount of token A.
 *                    So we make the role token gated and set a threshold of
 *                    how many tokens a address needs to hold to be able to
 *                    access the role. The moment we use the grantRole function
 *                    to add the address of token A to the members property of
 *                    the role, the role will only be accessible by users that
 *                    hold the threshold amount of token A.
 *
 *                  - Making a role token gated:
 *                    Making a role token gated is done by calling the
 *                    `setTokenGated` function. This function takes the
 *                    following parameters:
 *                    - The role id of the role that we change the token gated
 *                      status of.
 *                    - The boolean that indicates if the role should be token
 *                      gated or not.
 *                    This function can only be called by a permissioned address
 *                    (See permissioned section in the {AUT_Roles_v1} contract).
 *                    Also the role can not contain any members, when it is
 *                    switched to and from token gated.
 *                    Example: Making the role "Whitelisted" token gated would
 *                    look like this:
 *                    authorizer.setTokenGated(whitelistedRoleId, true);
 *
 *                  - Setting the token threshold:
 *                    Setting the token threshold needed to pass the token gate
 *                    is done by calling the setTokenThreshold function. This
 *                    function takes the following parameters:
 *                    - The role id of the role to set the threshold for.
 *                    - The address of the token to set the threshold for.
 *                    - The threshold value to set.
 *                    This function can only be called by a permissioned address
 *                    (See permissioned section in the {AUT_Roles_v1} contract).
 *                    This function can be called anytime, even if the role is
 *                    not token gated yet.
 *                    Example: Setting the threshold for the token "USDC" to
 *                    100 would look like this:
 *                    authorizer.setTokenThreshold(
 *                      whitelistedRoleId, USDC, 100);
 *
 *                  - Adding a token to the token gate:
 *                    Adding a token to the token gate is done by calling the
 *                    grantRole function. This function takes the following
 *                    parameters:
 *                    - The role id of the role to grant.
 *                    - The address of the token to grant the role to.
 *                    The grantRole function can only be called by according
 *                    admin of the role. In addition, the given address needs
 *                    to be a contract, already have a threshold set and
 *                    contain the balanceOf function.
 *                    If the role is not token gated then grantRole will
 *                    behave like the regular grantRole function.
 *                    Example: Adding a token gate to the token gated role
 *                    "Whitelisted" would look like this:
 *                    authorizer.grantRole(whitelistedRoleId, address(USDC));
 *
 *                  - Removing a token from the token gate:
 *                    Removing a token from the token gate is done by calling
 *                    the revokeRole function. This function behaves like the
 *                    regular revokeRole function, except that it sets the
 *                    threshold for the role and token combination to 0 as
 *                    well.
 *                    Example: Removing the token from the role "Whitelisted"
 *                    would look like this:
 *                    authorizer.revokeRole(whitelistedRoleId, address(USDC));
 *
 *                  - Reversing a token gate:
 *                    In case the token gated status of a role needs to be
 *                    reverted, the setTokenGated function can be used. The
 *                    same restrictions as for the setTokenGated function apply
 *                    here as well (see above).
 *                    Example: Reversing the token gated status of the role
 *                    "Whitelisted" would look like this:
 *                    authorizer.setTokenGated(whitelistedRoleId, false);
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to
 *                          our Security Policy at security.inverter.network or
 *                          email us directly!
 *
 * @custom:version  v1.0.0
 *
 * @custom:inverter-standard-version    v0.1.0
 *
 * @author  Inverter Network
 */
interface IAUT_TokenGated_Roles_v1 is IAuthorizer_v1 {
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
