// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IAccessControlEnumerable} from
    "@oz/access/extensions/IAccessControlEnumerable.sol";

interface IAuthorizer is IAccessControlEnumerable {
    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when a module toggles self management
    /// @param who The module.
    /// @param newValue The new value of the self management flag.
    event setRoleSelfManagement(address who, bool newValue);

    //--------------------------------------------------------------------------
    // Errors

    /// @notice The function is only callable by an active Module.
    error Module__RoleAuthorizer__NotActiveModule(address module);

    /// @notice The function is only callable if the Module is self-managing its roles.
    error Module__RoleAuthorizer__ModuleNotSelfManaged();

    /// @notice There always needs to be at least one owner.
    error Module__RoleAuthorizer__OwnerRoleCannotBeEmpty();

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Asks whether an address holds the required module role to execute
    ///         the current transaction.
    /// @param role The identifier of the role we want to check
    /// @param who  The address on which to perform the check.
    /// @dev It will use the calling address to generate the role ID. Therefore, for checking on anything other than itself, hasRole() should be used
    function hasModuleRole(bytes32 role, address who)
        external
        view
        returns (bool);

    /// @notice Helper function to generate a bytes32 role hash for a module role
    /// @param module The address of the module to generate the hash for
    /// @param role  The ID number of the role to generate the hash for
    function generateRoleId(address module, bytes32 role)
        external
        returns (bytes32);

    /// @notice Used by a Module to grant a role to a user.
    /// @param role The identifier of the role to grant
    /// @param target  The address to which to grant the role.
    function grantRoleFromModule(bytes32 role, address target) external;

    /// @notice Used by a Module to revoke a role from a user.
    /// @param role The identifier of the role to revoke
    /// @param target  The address to revoke the role from.
    function revokeRoleFromModule(bytes32 role, address target) external;

    /*     /// @notice Toggles if a Module self-manages its roles or defaults to the orchestrator's roles.
    function toggleModuleSelfManagement() external; */

    /// @notice Transfer the admin rights to a given role.
    /// @param roleId The role on which to peform the admin transfer
    /// @param newAdmin The new role to which to transfer admin access to
    function transferAdminRole(bytes32 roleId, bytes32 newAdmin) external;

    /// @notice Irreversibly burns the admin of a given role.
    /// @param role The role to remove admin access from
    /// @dev The module itself can still grant and revoke it's own roles. This only burns third-party access to the role.
    function burnAdminFromModuleRole(bytes32 role) external;

    /// @notice Grants a global role to a target
    /// @param role The role to grant
    /// @param target The address to grant the role to
    /// @dev Only the addresses with the Owner role should be able to call this function
    function grantGlobalRole(bytes32 role, address target) external;

    /// @notice Revokes a global role from a target
    /// @param role The role to grant
    /// @param target The address to grant the role to
    /// @dev Only the addresses with the Owner role should be able to call this function
    function revokeGlobalRole(bytes32 role, address target) external;

    /// @notice Returns the role ID of the owner role
    /// @return The role ID
    function getOwnerRole() external view returns (bytes32);

    /// @notice Returns the role ID of the manager role
    /// @return The role ID
    function getManagerRole() external view returns (bytes32);
}
