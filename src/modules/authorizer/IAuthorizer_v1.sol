// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IAccessControlEnumerable} from
    "@oz/access/extensions/IAccessControlEnumerable.sol";

/**
 * @title   Inverter Authorizer Interface
 *
 * @notice  This interface enables Role-based Access Control for the
 *          a Inverter Network Workflow.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to
 *                          our Security Policy at security.inverter.network or
 *                          email us directly!
 *
 * @custom:version  v1.1.0
 *
 * @custom:inverter-standard-version    v0.1.0
 *
 * @author  Inverter Network
 */
interface IAuthorizer_v1 is IAccessControlEnumerable {
    // ========================================================================
    // Errors

    /// @notice The provided initial admin address is invalid.
    error Module__Authorizer__InvalidInitialAdmin();

    /// @notice The provided role ID is the default admin role.
    error Module__Authorizer__CannotAddDefaultAdminRole();

    /// @notice The provided role ID is not existing.
    error Module__Authorizer__RoleIdNotExisting();

    /// @notice The admin of the provided role ID is already burned.
    error Module__Authorizer__RoleAdminBurned();

    /// @notice The provided input length is not valid.
    error Module__Authorizer__InvalidInputLength();

    /// @notice The function is only callable by an active Module.
    /// @param  module The address of the module.
    error Module__Authorizer__NotActiveModule(address module);

    /// @notice The function is only callable if the Module is self-managing its roles.
    error Module__Authorizer__ModuleNotSelfManaged();

    /// @notice There always needs to be at least one admin.
    error Module__Authorizer__AdminRoleCannotBeEmpty();

    /// @notice The orchestrator cannot own itself.
    error Module__Authorizer__OrchestratorCannotHaveAdminRole();

    // ========================================================================
    // Events

    /// @notice Emits when a function permission is added to a role.
    /// @param  target The address of the target contract.
    /// @param  fucntionSelector The selector of the function.
    /// @param  roleId The ID of the role.
    event AccessPermissionAdded(
        address target, bytes4 fucntionSelector, bytes32 roleId
    );

    /// @notice Emits when a function permission is removed from a role.
    /// @param  target The address of the target contract.
    /// @param  fucntionSelector The selector of the function.
    /// @param  roleId The ID of the role.
    event AccessPermissionRemoved(
        address target, bytes4 fucntionSelector, bytes32 roleId
    );

    /// @notice Emits when a role is created.
    /// @param  roleId The ID of the role.
    /// @param  roleName The name of the role.
    event RoleCreated(bytes32 roleId, string roleName);

    /// @notice Emits when a role is labeled.
    /// @param  roleId The ID of the role.
    /// @param  newRoleName The new name of the role.
    event RoleLabeled(bytes32 roleId, string newRoleName);

    /// @notice Emits when a role admin is burned.
    /// @param  roleId The ID of the role for which the admin was burned.
    event RoleAdminBurned(bytes32 roleId);

    // ========================================================================
    // Public Getter Functions

    // ------------------------------------------------------------------------
    // Getter -  Authorization

    /// @notice Returns the permissions of the given function in the target contract.
    /// @param  target_ The address of the target contract.
    /// @param  selector_ The selector of the function.
    /// @return permissions_ The roleIds that are permissioned to call the function.
    function getPermissions(address target_, bytes4 selector_)
        external
        view
        returns (bytes32[] memory permissions_);

    /// @notice Returns the number of created role IDs.
    /// @return roleIdCounter_ The number of created role IDs.
    function getRoleIdCounter() external view returns (uint roleIdCounter_);

    /// @notice Returns wether the given roleId has the permission to callthe given function in the target contract.
    /// @param  target_ The address of the target contract.
    /// @param  selector_ The selector of the function.
    /// @param  roleId_ The roleId that we want to check.
    /// @return isPermissioned_ Returns if the roleId is permissioned to call the function.
    function isPermissioned(address target_, bytes4 selector_, bytes32 roleId_)
        external
        view
        returns (bool isPermissioned_);

    /// @notice Checks whether the given caller address holds the required role to execute the given function in the target contract.
    /// @dev    Returns true if the address holds the Default Admin role.
    ///         Returns true if the function permissions contain the public role.
    /// @param  caller_ The address of the caller.
    /// @param  target_ The address of the target contract.
    /// @param  selector_ The selector of the function.
    /// @return hasPermission_ Returns if the address can call the function.
    function hasPermission(address caller_, address target_, bytes4 selector_)
        external
        view
        returns (bool hasPermission_);

    // ------------------------------------------------------------------------
    // Getter -  Role Management

    /// @notice Returns the role ID of the admin role.
    /// @return The role ID.
    function getAdminRole() external view returns (bytes32);

    // ------------------------------------------------------------------------
    // Getter - Out of Order

    /// @notice This function is deprecated and will revert when called.
    function checkForRole(bytes32, address) external view returns (bool);

    /// @notice This function is deprecated and will revert when called.
    function generateRoleId(address, bytes32) external pure returns (bytes32);

    // ========================================================================
    // Mutating Functions

    // ------------------------------------------------------------------------
    // Mutating - Authorization

    /// @notice Adds a new permission to the given roleId to call the given function in the target contract.
    /// @dev    Only callable by the Default Admin role.
    /// @dev    The roleId must have already been created.
    /// @dev    Does nothing if the roleId permission is already added to the function.
    /// @param  target_ The address of the target contract.
    /// @param  selector_ The selector of the function.
    /// @param  roleId_ The roleId that will receive the permission.
    function addAccessPermission(
        address target_,
        bytes4 selector_,
        bytes32 roleId_
    ) external;

    /// @notice Removes a permission from the given roleid to call the given function in the target contract.
    /// @dev    Only callable by the Default Admin role.
    /// @dev    Does nothing if the roleId is not linked to the function.
    /// @param  target_ The address of the target contract.
    /// @param  selector_ The selector of the function.
    /// @param  roleId_ The roleId to remove.
    function removeAccessPermission(
        address target_,
        bytes4 selector_,
        bytes32 roleId_
    ) external;

    // ------------------------------------------------------------------------
    // Mutating - Role Management

    /// @notice Creates a new role and adds initial members to it.
    /// @dev    Only callable by the Default Admin role.
    /// @dev    The role if of the admin has to be created already.
    /// @param  roleName_ The name of the role to create.
    /// @param  respectiveAdminRole_ The role ID of the admin role.
    /// @param  initialMembers_ The addresses of the initial members.
    /// @return _newRoleId The ID of the newly created role.
    function createRole(
        string memory roleName_,
        bytes32 respectiveAdminRole_,
        address[] memory initialMembers_
    ) external returns (bytes32 _newRoleId);

    /// @notice Changes the name of a role.
    /// @dev    Only callable by the Default Admin role.
    /// @dev    The role has to be created already.
    /// @param  roleId_ The ID of the role to change the name of.
    /// @param  newRoleName_ The new name of the role.
    function labelRole(bytes32 roleId_, string memory newRoleName_) external;

    /// @notice Transfer the admin rights to a given role.
    /// @dev    Only callable by the Admin of the role.
    /// @dev    The role has to be created already.
    /// @dev    The admin of the roleId_ can not be burned.
    /// @param  roleId_ The role on which to peform the admin transfer.
    /// @param  newAdminRoleId_ The new role to which to transfer admin access to.
    function transferAdminRole(bytes32 roleId_, bytes32 newAdminRoleId_)
        external;

    /// @notice    Burns the admin of the given roleId.
    /// @dev    Only callable by the Admin of the role.
    /// @dev    The role has to be created already.
    /// @dev    Does nothing if the admin was already burned.
    /// @param  roleId_ The role for which to burn the admin.
    function burnAdminFromRole(bytes32 roleId_) external;

    // ------------------------------------------------------------------------
    // Mutating - Mixed Utility

    /// @notice Creates a new role, adds initial members to it and adds permission to call to the respective functions.
    /// @dev    Only callable by the Default Admin role.
    /// @dev    The role of the admin has to be created already.
    /// @dev    The array of targets corresponds with the two dimensional array of selectors.
    ///         The first position of targets therefor is assigned to the first position of the selector array.
    ///         The second dimension of the selector array contains all the function selectors of the target,
    ///         which get the newly created role added as a permissioned role.
    /// @dev    The target contracts array have to have the same length as the selector array.
    /// @param  roleName_ The name of the role to create.
    /// @param  respectiveAdminRole_ The role ID of the admin role.
    /// @param  initialMembers_ The addresses of the initial members.
    /// @param  targets_ The addresses of the target contracts.
    /// @param  selectors_ The selectors of the functions.
    /// @return newRoleId_ The ID of the newly created role.
    function createRoleAndAddAccessPermissions(
        string memory roleName_,
        bytes32 respectiveAdminRole_,
        address[] memory initialMembers_,
        address[] memory targets_,
        bytes4[][] memory selectors_
    ) external returns (bytes32 newRoleId_);

    // ------------------------------------------------------------------------
    // Mutating - Out of Order

    /// @notice This function is deprecated and will revert when called.
    function grantRoleFromModule(bytes32, address) external pure;

    /// @notice This function is deprecated and will revert when called.
    function grantRoleFromModuleBatched(bytes32, address[] calldata)
        external
        pure;

    /// @notice This function is deprecated and will revert when called.
    function revokeRoleFromModule(bytes32, address) external pure;

    /// @notice This function is deprecated and will revert when called.
    function revokeRoleFromModuleBatched(bytes32, address[] calldata)
        external
        pure;

    /// @notice This function is deprecated and will revert when called.
    function burnAdminFromModuleRole(bytes32) external pure;

    /// @notice This function is deprecated and will revert when called.
    function grantGlobalRole(bytes32, address) external pure;

    /// @notice This function is deprecated and will revert when called.
    function grantGlobalRoleBatched(bytes32, address[] calldata)
        external
        pure;

    /// @notice This function is deprecated and will revert when called.
    function revokeGlobalRole(bytes32, address) external pure;

    /// @notice This function is deprecated and will revert when called.
    function revokeGlobalRoleBatched(bytes32, address[] calldata)
        external
        pure;
}
