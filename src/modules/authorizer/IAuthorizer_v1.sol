// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IAccessControlEnumerable} from
    "@oz/access/extensions/IAccessControlEnumerable.sol";

/**
 * @title   Inverter Authorizer Interface
 *
 * @notice  Provides the access control mechanism for managing roles and permissions
 *          across different modules within the Inverter Network, ensuring secure and
 *          controlled access to critical functionalities.
 *
 * @dev     Inherits functionality from:
 *          - IAuthorizer_v1: Implementation interface.
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
 * @custom:guide
 *          The following guide explains in detail how to use the key features
 *          of this module:
 *
 *              - ROLE MANAGEMENT:
 *                  - Roles:
 *                    A role has the following properties:
 *                    - A unique identifier (ID)
 *                    - A label
 *                    - A list of members
 *                    - A associated admin role
 *                    The id is a value assigned by the authorizer module and
 *                    is used to reference the role in the different functions
 *                    of the authorizer module.
 *                    The label is a string that is emitted as an event when
 *                    the role is created. It is used to make the role human
 *                    readable in the frontend and has no practical use in the
 *                    onchain live setup.
 *                    The members are the addresses that inhabit the role.
 *                    The admin role is the role that can add and remove new
 *                    members to the role.
 *
 *                  - Native Roles:
 *                    There are three native roles that are created with the
 *                    authorizer module:
 *                    - The default admin role
 *                    - The public role
 *                    - The burn admin role
 *                    The default admin role is the role that is
 *
 *                  - Role Creation:
 *                    A role can be created by calling the createRole function.
 *                    The function takes the following parameters:
 *                    - The role name
 *                    - The role id of the role that will become the admin of
 *                      the new role.
 *                    - The addresses of the initial members of the new role.
 *                    The rolename in this context refers to the label of the
 *                    role and is therefor not referenceable onchain.
 *                    The function can only be called by a permissioned address
 *                    (See permissioned section below).
 *
 *                  - Role Labeling:
 *                    The label of a role can be overwritten by calling the
 *                    labelRole function. With this a new event is emitted,
 *                    that signals the frontend that the label has been
 *                    updated.
 *                    The function can only be called by a permissioned address
 *                    (See permissioned section below).
 *
 *                  - Role granting and revoking:
 *                    A role can be granted to a address by calling the
 *                    grantRole function. The function takes the following
 *                    parameters:
 *                    - The role id of the role to grant
 *                    - The address to grant the role to
 *                    The grantRole function can only be called by according
 *                    admin of the role.
 *                    A role can be revoked from an address by calling the
 *                    revokeRole function. The function takes the following
 *                    parameters:
 *                    - The role id of the role to revoke
 *                    - The address to revoke the role from
 *                    The revokeRole function can only be called by according
 *                    admin of the role.
 *
 *                  - Transferal and Burning of Admin Roles:
 *                    The admin role of a role can be transferred by calling
 *                    the transferAdminRole function. The function takes the
 *                    following parameters:
 *                    - The role id of the role to transfer the admin from
 *                    - The role id of the role to transfer the admin to
 *                    The transferAdminRole function can only be called by
 *                    according admin of the role.
 *                    The admin role can be burned by calling the
 *                    burnAdminFromRole function.
 *                    The function takes the following parameters:
 *                    - The role id of the role to burn the admin from
 *                    If the admin role is burned, then no members can be added
 *                    or removed from a role anymore.
 *                    Remmeber: This step is irreversible.
 *
 *              - ROLE BASED ACCESS CONTROL:
 *                  - Permissioned
 *                    Most of the state altering functions in a workflow are
 *                    permissioned functions. This means that only roles that
 *                    have been granted the according function permission can
 *                    call the function. The permissioned status is enforced
 *                    by the `permissioned` modifier.
 *                    Some of the native roles have special rights in this
 *                    system. The default admin role can access every
 *                    permissioned function regardless of wether the default
 *                    admin role was granted the permission or not. If the
 *                    public role is granted the permission to a function, then
 *                    every caller can access the function, regardless of
 *                    wether they inhabit a already added role or not.
 *                    Note: As a workflow is intialized without any native
 *                    permissions, some functions that could be perceived as
 *                    "this should be publicly accessible" are not. Examples
 *                    for this could be the "buy" and "sell" functions of some
 *                    funding manager modules or the stake and unstake
 *                    functions of the staking logic module. For these
 *                    functions, the public role has to be added to the access
 *                    of the respective function.
 *
 *                  - Adding access permissions
 *                    Adding access permissions is done by calling the
 *                    `addAccessPermission` function. This function takes the
 *                    following parameters:
 *                    - The contract for which the permission is added
 *                    - The function selector of the target function
 *                    - The role ID of the role that will receive the
 *                      permission
 *                    Example: Adding the role "BOUNTY_MANAGER" to the
 *                    "createBounty" function of the "bountyManager" contract
 *                    would look like this:
 *                    authorizer.addAccessPermission(
 *                        address(bountyManager),
 *                        bountyManager.createBounty.selector,
 *                        bountyManagerId);
 *
 *                  - Removing access permissions
 *                    Removing access permissions is done by calling the
 *                    `removeAccessPermission` function. This function takes
 *                    the following parameters:
 *                    - The contract for which the permission is removed
 *                    - The function selector of the target function
 *                    - The role ID of the role that will lose the permission
 *                    Example: Removing the role "BOUNTY_MANAGER" from the
 *                    "createBounty" function of the "bountyManager" contract
 *                    would look like this:
 *                    authorizer.removeAccessPermission(
 *                        address(bountyManager),
 *                        bountyManager.createBounty.selector,
 *                        bountyManagerId);
 *
 *                  - Making a function public
 *                    A function can be made public by calling the
 *                    `addAccessPermission` function with the public role as
 *                    target role.
 *                    Example: Making the "buy" function of the funding manager
 *                    contract public would look like this:
 *                    authorizer.addAccessPermission(
 *                        address(fundingManager),
 *                        fundingManager.buy.selector,
 *                        authorizer.PUBLIC_ROLE());
 *                    The public role can be removed in the same way as any
 *                    other role.
 *
 *              - MIXED UTILITY:
 *                  - The createRoleAndAddAccessPermissions function
 *                    This function is a convenience function that combines
 *                    the creation of a new role and the adding of access
 *                    permissions. It takes the following parameters:
 *                    - The name of the role
 *                    - The role id of the role that will become the admin of
 *                      the new role.
 *                    - The addresses of the initial members of the new role.
 *                    - The addresses of the targets contracts.
 *                    - The selectors of the functions.
 *                    Note: The selectors of the functions are linked to the
 *                    respective target contracts. As the selectors are passed
 *                    as a 2 Dimensional array, the first dimension is coupled
 *                    to target contract and the second one contains the
 *                    actual selectors for that target contract.
 *                    Example: The target contracts are the fundingManager at
 *                    position 0 in the array and the logic module at position
 *                    1. The selectors therefor contain two arrays, one for
 *                    position 0 and one for position 1.
 *                    Example: authorizer.createRoleAndAddAccessPermissions(
 *                      "newRole",
 *                      authorizer.DEFAULT_ADMIN_ROLE(),
 *                      [initialMember1, initialMember2],
 *                      [fundingManager.address, logicModule.address],
 *                      [
 *                          [
 *                              fundingManager.buy.selector,
 *                              fundingManager.sell.selector
 *                          ],
 *                          [logicModule.execute.selector]
 *                      ]
 *                    )
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
    error Module__Authorizer__CannotModifyAdminRoleAccess();

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

    /// @notice Emits when a role is added to a function permission.
    /// @param  target The address of the target contract.
    /// @param  functionSelector The selector of the function.
    /// @param  roleId The ID of the role.
    event AccessPermissionAdded(
        address target, bytes4 functionSelector, bytes32 roleId
    );

    /// @notice Emits when a role is removed from a function permission.
    /// @param  target The address of the target contract.
    /// @param  functionSelector The selector of the function.
    /// @param  roleId The ID of the role.
    event AccessPermissionRemoved(
        address target, bytes4 functionSelector, bytes32 roleId
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
    // Getter -  Role Management

    /// @notice Returns the role ID of the admin role.
    /// @return The role ID.
    function getAdminRole() external view returns (bytes32);

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
    /// @return lastAssignedRoleId_ The number of created role IDs.
    function getLastAssignedRoleId()
        external
        view
        returns (uint lastAssignedRoleId_);

    /// @notice Returns whether the given roleId has the permission to call the given function in the target contract.
    /// @param  target_ The address of the target contract.
    /// @param  selector_ The selector of the function.
    /// @param  roleId_ The roleId that we want to check.
    /// @return isRolePermissioned_ Returns whether the roleId is permissioned to call the function.
    function isRolePermissioned(
        address target_,
        bytes4 selector_,
        bytes32 roleId_
    ) external view returns (bool isRolePermissioned_);

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
    // Mutating - Authorization

    /// @notice Adds a new permission to the given roleId to call the given function in the target contract.
    /// @dev    Function access controlled by authorizer.
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

    /// @notice Creates a new role, adds initial members to it and adds permission to call to the respective functions.
    /// @dev    Function access controlled by authorizer.
    /// @dev    The role of the admin has to be created already.
    /// @dev    The array of targets corresponds with the two dimensional array of selectors.
    ///         The first position of targets therefore is assigned to the first position of the selector array.
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
}
