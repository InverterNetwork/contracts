// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IAccessControlEnumerable} from
    "@oz/access/extensions/IAccessControlEnumerable.sol";

/**
 * @title   Inverter Authorizer Interface
 *
 * @notice  Provides the access control mechanism for managing roles and
 *          permissions across different modules within the Inverter Network,
 *          ensuring secure and controlled access to critical functionalities.
 *
 * @dev     Inherits functionality from:
 *          - IAuthorizer_v2: Implementation interface.
 *          - Module_v1: Inverter network base module functionality.
 *          - AccessControlEnumerableUpgradeable: Access control functionality.
 *
 *          Key features:
 *
 *              - Role creation and management. This includes the ability to
 *                create roles, revoke roles, assigning and revoking role
 *                admins, which can add and remove role members.
 *
 *              - Role-based access control. This includes the ability to grant
 *                roles access to functions that implement the permissioned
 *                modifier. Functions can also be set to public access by
 *                adding the public role to the function permissions.
 *
 * @custom:documentation See https://github.com/InverterNetwork/contracts/tree/dev/docs/src/modules/authorizer/role/AUT_Roles_v1.sol
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
interface IAuthorizer_v2 is IAccessControlEnumerable {
    // ========================================================================
    // Errors

    /// @notice The provided initial admin address is invalid.
    error Module__Authorizer__InvalidInitialAdmin();

    /// @notice The provided role ID is the default admin role.
    error Module__Authorizer__CannotModifyAdminRoleAccess();

    /// @notice The provided role ID is not existing.
    error Module__Authorizer__RoleIdNotExisting();

    /// @notice The provided input length is not valid.
    error Module__Authorizer__InvalidInputLength();

    /// @notice The function is only callable by an active Module.
    /// @param  module_ The address of the module.
    error Module__Authorizer__NotActiveModule(address module_);

    /// @notice The function is only callable if the Module is self-managing
    ///         its roles.
    error Module__Authorizer__ModuleNotSelfManaged();

    /// @notice There always needs to be at least one admin.
    error Module__Authorizer__AdminRoleCannotBeEmpty();

    /// @notice The orchestrator cannot own itself.
    error Module__Authorizer__OrchestratorCannotHaveAdminRole();

    // ========================================================================
    // Events

    /// @notice Emits when a role is added to a function permission.
    /// @param  target_ The address of the target contract.
    /// @param  functionSelector_ The selector of the function.
    /// @param  roleId_ The ID of the role.
    event AccessPermissionAdded(
        address target_, bytes4 functionSelector_, bytes32 roleId_
    );

    /// @notice Emits when a role is removed from a function permission.
    /// @param  target_ The address of the target contract.
    /// @param  functionSelector_ The selector of the function.
    /// @param  roleId_ The ID of the role.
    event AccessPermissionRemoved(
        address target_, bytes4 functionSelector_, bytes32 roleId_
    );

    /// @notice Emits when a role is created.
    /// @param  roleId_ The ID of the role.
    /// @param  roleName The name of the role.
    event RoleCreated(bytes32 roleId_, string roleName);

    /// @notice Emits when a role is labeled.
    /// @param  roleId_ The ID of the role.
    /// @param  newRoleName The new name of the role.
    event RoleLabeled(bytes32 roleId_, string newRoleName);

    /// @notice Emits when a role admin is burned.
    /// @param  roleId_ The ID of the role for which the admin was burned.
    event RoleAdminBurned(bytes32 roleId_);

    // ========================================================================
    // Public Getter Functions

    // ------------------------------------------------------------------------
    // Getter -  Role Management

    /// @notice Returns the role ID of the admin role.
    /// @return defaultAdminId_ The role ID of the default admin.
    function getAdminRole() external view returns (bytes32 defaultAdminId_);

    // ------------------------------------------------------------------------
    // Getter -  Authorization

    /// @notice Returns the permissions of the given function in the target
    ///         contract.
    /// @param  target_ The address of the target contract.
    /// @param  selector_ The selector of the function.
    /// @return permissions_ The roleIds that are permissioned to call the
    ///         function.
    function getPermissions(address target_, bytes4 selector_)
        external
        view
        returns (bytes32[] memory permissions_);

    /// @notice Returns the number of created role IDs.
    /// @return lastAssignedRoleId_ The number of created role IDs.
    function getLastAssignedRoleId()
        external
        view
        returns (uint lastAssignedRoleId_);

    /// @notice Returns whether the given roleId has the permission to call the
    ///         given function in the target contract.
    /// @param  target_ The address of the target contract.
    /// @param  selector_ The selector of the function.
    /// @param  roleId_ The roleId that we want to check.
    /// @return isRolePermissioned_ Returns whether the roleId is permissioned
    ///         to call the function.
    function isRolePermissioned(
        address target_,
        bytes4 selector_,
        bytes32 roleId_
    ) external view returns (bool isRolePermissioned_);

    /// @notice Checks whether the given caller address holds the required role
    ///         to execute the given function in the target contract.
    /// @dev    Returns true if the address holds the Default Admin role.
    ///         Returns true if the function permissions contain the public
    ///         role.
    /// @param  caller_ The address of the caller.
    /// @param  target_ The address of the target contract.
    /// @param  selector_ The selector of the function.
    /// @return hasPermission_ Returns if the address can call the function.
    function hasPermission(address caller_, address target_, bytes4 selector_)
        external
        view
        returns (bool hasPermission_);

    // ========================================================================
    // Mutating Functions

    // ------------------------------------------------------------------------
    // Mutating - Role Management

    /// @notice Creates a new role and adds initial members to it.
    /// @dev    Function access controlled by authorizer.
    /// @dev    The role of the admin has to be created already.
    /// @param  roleName_ The name of the role to create.
    /// @param  respectiveAdminRole_ The role ID of the admin role.
    /// @param  initialMembers_ The addresses of the initial members.
    /// @return newRoleId_ The ID of the newly created role.
    function createRole(
        string memory roleName_,
        bytes32 respectiveAdminRole_,
        address[] memory initialMembers_
    ) external returns (bytes32 newRoleId_);

    /// @notice Changes the name of a role.
    /// @dev    Labels are emitted as events and are therefore not accessible
    ///         on-chain.
    /// @dev    Function access controlled by authorizer.
    /// @dev    The role has to be created already.
    /// @param  roleId_ The ID of the role to change the name of.
    /// @param  newRoleName_ The new name of the role.
    function labelRole(bytes32 roleId_, string memory newRoleName_) external;

    /// @notice Transfer the admin rights to a given role.
    /// @dev    Only callable by the Admin of the role.
    /// @dev    The role has to be created already.
    /// @dev    The admin of the roleId_ can not be burned.
    /// @param  roleId_ The role on which to peform the admin transfer.
    /// @param  newAdminRoleId_ The new role to which to transfer admin
    ///         access to.
    function transferAdminRole(bytes32 roleId_, bytes32 newAdminRoleId_)
        external;

    /// @notice Burns the admin of the given roleId.
    /// @dev    Only callable by the Admin of the role.
    /// @dev    The role has to be created already.
    /// @dev    Does nothing if the admin was already burned.
    /// @param  roleId_ The role for which to burn the admin.
    function burnRoleAdmin(bytes32 roleId_) external;

    // ------------------------------------------------------------------------
    // Mutating - Authorization

    /// @notice Adds a new permission to the given roleId to call the given
    ///         function in the target contract.
    /// @dev    Function access controlled by authorizer.
    /// @dev    The roleId must have already been created.
    /// @dev    Does nothing if the roleId permission is already added to the
    ///function.
    /// @param  target_ The address of the target contract.
    /// @param  selector_ The selector of the function.
    /// @param  roleId_ The roleId that will receive the permission.
    function addAccessPermission(
        address target_,
        bytes4 selector_,
        bytes32 roleId_
    ) external;

    /// @notice Removes a permission from the given roleid to call the given
    ///         function in the target contract.
    /// @dev    Function access controlled by authorizer.
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
    // Mutating - Mixed Utility

    /// @notice Creates a new role, adds initial members to it and adds
    ///         permission to call to the respective functions.
    /// @dev    Function access controlled by authorizer.
    /// @dev    The role of the admin has to be created already.
    /// @dev    The array of targets corresponds with the two dimensional array
    ///         of selectors. The first position of targets therefore is
    ///         assigned to the first position of the selector array. The
    ///         second dimension of the selector array contains all the
    ///         function selectors of the target, which get the newly created
    ///         role added as a permissioned role.
    /// @dev    The target contracts array must have the same length as the
    ///         selector array.
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
}
