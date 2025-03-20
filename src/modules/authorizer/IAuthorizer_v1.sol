// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IAccessControlEnumerable} from
    "@oz/access/extensions/IAccessControlEnumerable.sol";

interface IAuthorizer_v1 is IAccessControlEnumerable {
    // ========================================================================
    // Errors
    /// @notice The provided initial admin address is invalid.
    error Module__Authorizer__InvalidInitialAdmin();

    /// @notice The provided role ID is not existing.
    error Module__Authorizer__RoleIdNotExisting();

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

    /// @notice Emits when a key is added to a function.
    /// @param  target The address of the target contract.
    /// @param  fucntionSelector The selector of the function.
    /// @param  roleIdKey The key of the role.
    event KeyAdded(address target, bytes4 fucntionSelector, bytes32 roleIdKey);

    /// @notice Emits when a key is removed from a function.
    /// @param  target The address of the target contract.
    /// @param  fucntionSelector The selector of the function.
    /// @param  roleIdKey The key of the role.
    event KeyRemoved(
        address target, bytes4 fucntionSelector, bytes32 roleIdKey
    );

    /// @notice Emits when a role is created.
    /// @param  roleId The ID of the role.
    /// @param  roleName The name of the role.
    event RoleCreated(bytes32 roleId, string roleName);

    /// @notice Emits when a role is labeled.
    /// @param  roleId The ID of the role.
    /// @param  newRoleName The new name of the role.
    event RoleLabeled(bytes32 roleId, string newRoleName);

    // ========================================================================
    // Public Getter Functions

    // ------------------------------------------------------------------------
    // Getter -  Authorization

    /// @notice Returns the keys of the given function in the target contract.
    /// @param  target_ The address of the target contract.
    /// @param  selector_ The selector of the function.
    /// @return keys_ The keys of the function.
    function getFunctionKeys(address target_, bytes4 selector_)
        external
        view
        returns (bytes32[] memory keys_);

    /// @notice Returns wether the given key is a key of the given function in the target contract.
    /// @param  target_ The address of the target contract.
    /// @param  selector_ The selector of the function.
    /// @param  roleIdKey_ The key that we want to check.
    /// @return isKey_ Returns if the key is a key of the function.
    function isFunctionKey(
        address target_,
        bytes4 selector_,
        bytes32 roleIdKey_
    ) external view returns (bool isKey_);

    /// @notice Checks whether an address holds the required role to execute the given function in the target contract.
    /// @dev    Returns true if the address holds the Default Admin role.
    ///         Returns true if the function keys contain the external key.
    // @todo Adapt name of external key??
    /// @param  caller_ The address of the caller.
    /// @param  target_ The address of the target contract.
    /// @param  selector_ The selector of the function.
    /// @return canCall_ Returns if the address can call the function.
    function canCall(address caller_, address target_, bytes4 selector_)
        external
        view
        returns (bool canCall_);

    // ------------------------------------------------------------------------
    // Getter -  Role Management

    /// @notice Returns the role ID of the admin role.
    /// @return The role ID.
    function getAdminRole() external view returns (bytes32);

    /// @notice Checks whether an address holds the required role to execute
    ///         the current transaction.
    /// @dev	The calling contract needs to generate the right role ID using its
    ///         own address and the role identifier.
    ///         In modules, this function should be used instead of `hasRole`, as
    ///         there are Authorizer-specific checks that need to be performed.
    /// @param  role The identifier of the role we want to check
    /// @param  who  The address on which to perform the check.
    /// @return bool Returns if the address holds the role
    function checkForRole(bytes32 role, address who)
        external
        view
        returns (bool);

    /// @notice Helper function to generate a bytes32 role hash for a module role.
    /// @param  module The address of the module to generate the hash for.
    /// @param  role  The ID number of the role to generate the hash for.
    /// @return bytes32 Returns the generated role hash.
    function generateRoleId(address module, bytes32 role)
        external
        pure
        returns (bytes32);

    // ========================================================================
    // Mutating Functions

    // ------------------------------------------------------------------------
    // Mutating - Authorization

    /// @notice Adds a new key to the given function in the target contract.
    /// @dev    Only callable by the Default Admin role.
    /// @dev    The key must have already been created.
    /// @dev    Does nothing if the key is already added to the function.
    /// @param  target_ The address of the target contract.
    /// @param  selector_ The selector of the function.
    /// @param  newRoleIdKey_ The new key to add.
    function addKey(address target_, bytes4 selector_, bytes32 newRoleIdKey_)
        external;

    /// @notice Removes a key from the given function in the target contract.
    /// @dev    Only callable by the Default Admin role.
    /// @dev    Does nothing if the key is not linked to the function.
    /// @param  target_ The address of the target contract.
    /// @param  selector_ The selector of the function.
    /// @param  roleIdKey_ The key to remove.
    function removeKey(address target_, bytes4 selector_, bytes32 roleIdKey_)
        external;

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
    /// @param  roleId The role on which to peform the admin transfer.
    /// @param  newAdmin The new role to which to transfer admin access to.
    function transferAdminRole(bytes32 roleId, bytes32 newAdmin) external;

    /// @notice Irreversibly burns the admin of a given role.
    /// @param  role The role to remove admin access from.
    /// @dev	The module itself can still grant and revoke it's own roles. This only burns third-party access to
    ///         the role.
    function burnAdminFromModuleRole(bytes32 role) external;

    // ------------------------------------------------------------------------
    // Mutating - Mixed Utility

    /// @notice Creates a new role, adds initial members to it and adds keys to the respective functions.
    /// @dev    Only callable by the Default Admin role.
    /// @dev    The role of the admin has to be created already.
    /// @dev    The array of targets corresponds with the two dimensional array of selectors.
    ///         The first position of targets therefor is assigned to the first position of the selector array.
    ///         The second dimension of the selector array contains all the function selectors of the target,
    ///         which get the newly created role added as a key.
    /// @dev    The target contracts array have to have the same length as the selector array.
    /// @param  roleName_ The name of the role to create.
    /// @param  respectiveAdminRole_ The role ID of the admin role.
    /// @param  initialMembers_ The addresses of the initial members.
    /// @param  targets_ The addresses of the target contracts.
    /// @param  selectors_ The selectors of the functions.
    /// @return newRoleId_ The ID of the newly created role.
    function createRoleAndAddKeys(
        string memory roleName_,
        bytes32 respectiveAdminRole_,
        address[] memory initialMembers_,
        address[] memory targets_,
        bytes4[][] memory selectors_
    ) external returns (bytes32 newRoleId_);

    // ------------------------------------------------------------------------
    // Mutating - Out of Order

    /// @notice Used by a Module to grant a role to a user.
    /// @param  role The identifier of the role to grant.
    /// @param  target  The address to which to grant the role.
    function grantRoleFromModule(bytes32 role, address target) external;

    /// @notice Used by a Module to grant a role to a set of users.
    /// @param  role The identifier of the role to grant.
    /// @param  targets  The addresses to which to grant the role.
    function grantRoleFromModuleBatched(
        bytes32 role,
        address[] calldata targets
    ) external;

    /// @notice Used by a Module to revoke a role from a user.
    /// @param  role The identifier of the role to revoke.
    /// @param  target  The address to revoke the role from.
    function revokeRoleFromModule(bytes32 role, address target) external;

    /// @notice Used by a Module to revoke a role from a set of users.
    /// @param  role The identifier of the role to revoke.
    /// @param  targets  The address to revoke the role from.
    function revokeRoleFromModuleBatched(
        bytes32 role,
        address[] calldata targets
    ) external;

    /// @notice Grants a global role to a target.
    /// @param  role The role to grant.
    /// @param  target The address to grant the role to.
    /// @dev	Only the addresses with the Admin role should be able to call this function.
    function grantGlobalRole(bytes32 role, address target) external;

    /// @notice Grants a global role to a set of targets.
    /// @param  role The role to grant.
    /// @param  targets The addresses to grant the role to.
    /// @dev	Only the addresses with the Admin role should be able to call this function.
    function grantGlobalRoleBatched(bytes32 role, address[] calldata targets)
        external;

    /// @notice Revokes a global role from a target.
    /// @param  role The role to grant.
    /// @param  target The address to grant the role to.
    /// @dev	Only the addresses with the Admin role should be able to call this function.
    function revokeGlobalRole(bytes32 role, address target) external;

    /// @notice Revokes a global role from a set of targets.
    /// @param  role The role to grant.
    /// @param  targets The addresses to grant the role to.
    /// @dev	Only the addresses with the Admin role should be able to call this function.
    function revokeGlobalRoleBatched(bytes32 role, address[] calldata targets)
        external;
}
