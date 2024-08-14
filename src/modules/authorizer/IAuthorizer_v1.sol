// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IAccessControlEnumerable} from
    "@oz/access/extensions/IAccessControlEnumerable.sol";

interface IAuthorizer_v1 is IAccessControlEnumerable {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice The function is only callable by an active Module.
    /// @param module The address of the module.
    error Module__Authorizer__NotActiveModule(address module);

    /// @notice The function is only callable if the Module is self-managing its roles.
    error Module__Authorizer__ModuleNotSelfManaged();

    /// @notice There always needs to be at least one admin.
    error Module__Authorizer__AdminRoleCannotBeEmpty();

    /// @notice The orchestrator cannot own itself.
    error Module__Authorizer__OrchestratorCannotHaveAdminRole();

    /// @notice The provided initial admin address is invalid.
    error Module__Authorizer__InvalidInitialAdmin();

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Checks whether an address holds the required role to execute
    ///         the current transaction.
    /// @dev	The calling contract needs to generate the right role ID using its
    ///         own address and the role identifier.
    ///         In modules, this function should be used instead of `hasRole`, as
    ///         there are Authorizer-specific checks that need to be performed.
    /// @param role The identifier of the role we want to check
    /// @param who  The address on which to perform the check.
    /// @return bool Returns if the address holds the role
    function checkForRole(bytes32 role, address who)
        external
        view
        returns (bool);

    /// @notice Helper function to generate a bytes32 role hash for a module role.
    /// @param module The address of the module to generate the hash for.
    /// @param role  The ID number of the role to generate the hash for.
    /// @return bytes32 Returns the generated role hash.
    function generateRoleId(address module, bytes32 role)
        external
        pure
        returns (bytes32);

    /// @notice Used by a Module to grant a role to a user.
    /// @param role The identifier of the role to grant.
    /// @param target  The address to which to grant the role.
    function grantRoleFromModule(bytes32 role, address target) external;

    /// @notice Used by a Module to grant a role to a set of users.
    /// @param role The identifier of the role to grant.
    /// @param targets  The addresses to which to grant the role.
    function grantRoleFromModuleBatched(
        bytes32 role,
        address[] calldata targets
    ) external;

    /// @notice Used by a Module to revoke a role from a user.
    /// @param role The identifier of the role to revoke.
    /// @param target  The address to revoke the role from.
    function revokeRoleFromModule(bytes32 role, address target) external;

    /// @notice Used by a Module to revoke a role from a set of users.
    /// @param role The identifier of the role to revoke.
    /// @param targets  The address to revoke the role from.
    function revokeRoleFromModuleBatched(
        bytes32 role,
        address[] calldata targets
    ) external;

    /// @notice Transfer the admin rights to a given role.
    /// @param roleId The role on which to peform the admin transfer.
    /// @param newAdmin The new role to which to transfer admin access to.
    function transferAdminRole(bytes32 roleId, bytes32 newAdmin) external;

    /// @notice Irreversibly burns the admin of a given role.
    /// @param role The role to remove admin access from.
    /// @dev	The module itself can still grant and revoke it's own roles. This only burns third-party access to
    ///         the role.
    function burnAdminFromModuleRole(bytes32 role) external;

    /// @notice Grants a global role to a target.
    /// @param role The role to grant.
    /// @param target The address to grant the role to.
    /// @dev	Only the addresses with the Admin role should be able to call this function.
    function grantGlobalRole(bytes32 role, address target) external;

    /// @notice Grants a global role to a set of targets.
    /// @param role The role to grant.
    /// @param targets The addresses to grant the role to.
    /// @dev	Only the addresses with the Admin role should be able to call this function.
    function grantGlobalRoleBatched(bytes32 role, address[] calldata targets)
        external;

    /// @notice Revokes a global role from a target.
    /// @param role The role to grant.
    /// @param target The address to grant the role to.
    /// @dev	Only the addresses with the Admin role should be able to call this function.
    function revokeGlobalRole(bytes32 role, address target) external;

    /// @notice Revokes a global role from a set of targets.
    /// @param role The role to grant.
    /// @param targets The addresses to grant the role to.
    /// @dev	Only the addresses with the Admin role should be able to call this function.
    function revokeGlobalRoleBatched(bytes32 role, address[] calldata targets)
        external;

    /// @notice Returns the role ID of the admin role.
    /// @return The role ID.
    function getAdminRole() external view returns (bytes32);
}
