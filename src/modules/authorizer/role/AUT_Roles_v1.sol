// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IModule_v1} from "src/modules/base/IModule_v1.sol";
import {IAuthorizer_v1} from "@aut/IAuthorizer_v1.sol";
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";

// Internal Dependencies
import {Module_v1} from "src/modules/base/Module_v1.sol";

// External Dependencies
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";
import {
    ERC2771ContextUpgradeable,
    ContextUpgradeable
} from "@oz-up/metatx/ERC2771ContextUpgradeable.sol";
import {AccessControlEnumerableUpgradeable} from
    "@oz-up/access/extensions/AccessControlEnumerableUpgradeable.sol";

/**
 * @title   Inverter Roles Authorizer
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
 *              - Role creation and management. This includes the ability to
 *                create roles, revoke roles, assigning and revoking role
 *                admins, which can add and remove role members.
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
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
 *
 * @custom:version  v1.1.0
 *
 * @custom:inverter-standard-version    v0.1.0
 *
 * @author  Inverter Network
 */
contract AUT_Roles_v1 is
    IAuthorizer_v1,
    Module_v1,
    AccessControlEnumerableUpgradeable
{
    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(Module_v1, AccessControlEnumerableUpgradeable)
        returns (bool)
    {
        return interfaceId == type(IAuthorizer_v1).interfaceId
            || super.supportsInterface(interfaceId);
    }

    // ========================================================================
    // Modifiers

    modifier idNotDefaultAdmin(bytes32 roleId_) {
        if (roleId_ == DEFAULT_ADMIN_ROLE) {
            revert Module__Authorizer__CannotAddDefaultAdminRole();
        }
        _;
    }

    /// @dev     Verifies that the roleId is already existing.
    /// @param  roleId_ The id of the role.
    modifier idExists(bytes32 roleId_) {
        // If the given roleId is not equal or smaller than the last assigned
        // roleId, then it is not existing.
        if (uint(roleId_) > _lastAssignedRoleId) {
            revert Module__Authorizer__RoleIdNotExisting();
        }
        _;
    }

    // ========================================================================
    // Storage

    /// @notice The role that is used as a placeholder for a burned admin role.
    bytes32 public constant BURN_ADMIN_ROLE =
        0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    /// @notice The role that is used as a placeholder for a public role.
    bytes32 public constant PUBLIC_ROLE = bytes32(uint(1));

    /// @notice Mapping that stores the role IDs that can be used to call functions on a target contract.
    /// @dev    target The address of the target contract.
    /// @dev    selector The function selector of the function to call.
    /// @dev    roleIds The role IDs that can be used to call the function.
    mapping(address target => mapping(bytes4 selector => bytes32[] roleIds))
        public _permissions;

    /// @notice The counter for role IDs.
    /// @dev	This is used to generate unique role IDs for each role.
    /// @dev    Starts at 1, which symbolizes two roles: PUBLIC_ROLE and DEFAULT_ADMIN_ROLE,
    ///         but is immediately incremented when a role is created.
    uint internal _lastAssignedRoleId;

    /// @dev	Storage gap for future upgrades.
    uint[47] private __gap;

    // ========================================================================
    // Initialization

    /// @inheritdoc Module_v1
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata,
        bytes memory configData
    ) external override initializer {
        __Module_init(orchestrator_, metadata);

        (address initialAdmin) = abi.decode(configData, (address));

        __RoleAuthorizer_init(initialAdmin);
    }

    /// @notice Initializes the role authorizer.
    /// @param  initialAdmin The initial admin of the role authorizer.
    function __RoleAuthorizer_init(address initialAdmin)
        internal
        onlyInitializing
    {
        if (initialAdmin == address(0)) {
            revert Module__Authorizer__InvalidInitialAdmin();
        }

        // Start with 1 to represent the two native roles:
        // DEFAULT_ADMIN_ROLE at 0 and PUBLIC_ROLE at 1. 
        _lastAssignedRoleId = 1;

        // Note about DEFAULT_ADMIN_ROLE: The Admin of the workflow holds the DEFAULT_ADMIN_ROLE, and has admin
        // privileges on all Modules in the contract.
        // It is defined in the AccessControl contract and identified with bytes32("0x00")
        // Modules can opt out of this on a per-role basis by setting the admin role to "BURN_ADMIN_ROLE".

        // make the BURN_ADMIN_ROLE immutable
        _setRoleAdmin(BURN_ADMIN_ROLE, BURN_ADMIN_ROLE);

        // set the initial admin as the DEFAULT_ADMIN_ROLE
        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
    }

    // ========================================================================
    // Public Getter Functions

    // ------------------------------------------------------------------------
    // Getter -  Role Management

    /// @inheritdoc IAuthorizer_v1
    function getAdminRole() public pure returns (bytes32) {
        return DEFAULT_ADMIN_ROLE;
    }

    // ------------------------------------------------------------------------
    // Getter -  Authorization

    /// @inheritdoc IAuthorizer_v1
    function getPermissions(address target_, bytes4 selector_)
        public
        view
        virtual
        returns (bytes32[] memory permissions_)
    {
        permissions_ = _permissions[target_][selector_];
    }

    /// @inheritdoc IAuthorizer_v1
    function getLastAssignedRoleId()
        public
        view
        returns (uint lastAssignedRoleId_)
    {
        lastAssignedRoleId_ = _lastAssignedRoleId;
    }

    /// @inheritdoc IAuthorizer_v1
    function isRolePermissioned(
        address target_,
        bytes4 selector_,
        bytes32 roleId_
    ) public view virtual returns (bool isRolePermissioned_) {
        bytes32[] memory permissions_ = _permissions[target_][selector_];
        for (uint i = 0; i < permissions_.length; i++) {
            if (permissions_[i] == roleId_) {
                return true;
            }
        }
        return false;
    }

    /// @inheritdoc IAuthorizer_v1
    function hasPermission(address caller_, address target_, bytes4 selector_)
        public
        view
        virtual
        returns (bool hasPermission_)
    {
        // If caller is the admin, they can call any function.
        if (hasRole(DEFAULT_ADMIN_ROLE, caller_)) {
            return true;
        }

        bytes32[] memory roleIds = _permissions[target_][selector_];
        uint permissionLength = roleIds.length;

        // If there are no roles, the caller cannot call the function.
        if (permissionLength == 0) {
            return false;
        }

        // Go through each role and check if the caller has it.
        for (uint i = 0; i < permissionLength; i++) {
            if (
                // if the role the public role
                // or if the caller has the role
                roleIds[i] == PUBLIC_ROLE || hasRole(roleIds[i], caller_)
            ) {
                return true;
            }
        }
        // Caller does not have any of the roles, so they cannot call the
        // function.
        return false;
    }

    // ========================================================================
    // Mutating Functions

    // ------------------------------------------------------------------------
    // Mutating - Role Management

    /// @inheritdoc IAuthorizer_v1
    function createRole(
        string memory roleName_,
        bytes32 respectiveAdminRole_,
        address[] memory initialMembers_
    )
        public
        virtual
        permissioned
        idExists(respectiveAdminRole_)
        returns (bytes32 newRoleId_)
    {
        newRoleId_ = bytes32(++_lastAssignedRoleId);

        emit RoleCreated(newRoleId_, roleName_);

        _setRoleAdmin(newRoleId_, respectiveAdminRole_);

        uint length = initialMembers_.length;
        for (uint i = 0; i < length; i++) {
            _grantRole(newRoleId_, initialMembers_[i]);
        }
    }

    /// @inheritdoc IAuthorizer_v1
    function labelRole(bytes32 roleId_, string memory newRoleName_)
        external
        permissioned
        idExists(roleId_)
    {
        emit RoleLabeled(roleId_, newRoleName_);
    }

    /// @inheritdoc IAuthorizer_v1
    function transferAdminRole(bytes32 roleId_, bytes32 newAdminRoleId_)
        external
        onlyRole(getRoleAdmin(roleId_))
        idExists(roleId_)
        idExists(newAdminRoleId_)
    {
        _setRoleAdmin(roleId_, newAdminRoleId_);
    }

    /// @inheritdoc IAuthorizer_v1
    function burnAdminFromRole(bytes32 roleId_)
        external
        onlyRole(getRoleAdmin(roleId_))
        idExists(roleId_)
    {
        // If Role Admin is burned do nothing
        if (getRoleAdmin(roleId_) == BURN_ADMIN_ROLE) {
            return;
        }
        // Burn Role Admin
        _setRoleAdmin(roleId_, BURN_ADMIN_ROLE);
        emit RoleAdminBurned(roleId_);
    }

    // ------------------------------------------------------------------------
    // Mutating - Authorization

    /// @inheritdoc IAuthorizer_v1
    function addAccessPermission(
        address target_,
        bytes4 selector_,
        bytes32 roleId_
    ) public permissioned idNotDefaultAdmin(roleId_) idExists(roleId_) {
        // if RoleId already has a permission, do nothing
        if (isRolePermissioned(target_, selector_, roleId_)) {
            return;
        }

        _permissions[target_][selector_].push(roleId_);
        emit AccessPermissionAdded(target_, selector_, roleId_);
    }

    /// @inheritdoc IAuthorizer_v1
    function removeAccessPermission(
        address target_,
        bytes4 selector_,
        bytes32 roleId_
    ) public permissioned {
        bytes32[] memory permissions = _permissions[target_][selector_];
        uint permissionsLength = permissions.length;

        for (uint i = 0; i < permissionsLength; i++) {
            if (permissions[i] == roleId_) {
                // Replace the element to be removed with the last one
                _permissions[target_][selector_][i] =
                    _permissions[target_][selector_][permissionsLength - 1];
                // Remove the last element
                _permissions[target_][selector_].pop();

                // Emit Event and exit the function once the value is removed
                emit AccessPermissionRemoved(target_, selector_, roleId_);
                return;
            }
        }
        // Do nothing if the value is not found
    }

    // ------------------------------------------------------------------------
    // Mutating - Mixed Utility

    /// @inheritdoc IAuthorizer_v1
    function createRoleAndAddAccessPermissions(
        string memory roleName_,
        bytes32 respectiveAdminRole_,
        address[] memory initialMembers_,
        address[] memory targets_,
        bytes4[][] memory selectors_
    )
        external
        permissioned
        idExists(respectiveAdminRole_)
        returns (bytes32 newRoleId_)
    {
        uint targetsLength = targets_.length;
        if (targetsLength != selectors_.length) {
            revert Module__Authorizer__InvalidInputLength();
        }

        newRoleId_ =
            createRole(roleName_, respectiveAdminRole_, initialMembers_);

        // Run through all target and selector combinations and add permission
        // to role id.

        for (uint i = 0; i < targetsLength; i++) {
            for (uint j = 0; j < selectors_[i].length; j++) {
                addAccessPermission(targets_[i], selectors_[i][j], newRoleId_);
            }
        }
    }

    // ========================================================================
    // Internal Functions

    // ------------------------------------------------------------------------
    // Internal - Upstream Function Implementations

    /// @notice Overrides {_grantRole} to make sure only existing roles can be granted.
    /// @param  role The id of the role.
    /// @param  who The user we want to check on.
    /// @return bool Returns if grant has been successful.
    function _grantRole(bytes32 role, address who)
        internal
        virtual
        override
        idExists(role)
        returns (bool)
    {
        return super._grantRole(role, who);
    }

    //--------------------------------------------------------------------------
    // Internal - ERC2771 Context Upgradeable

    /// Needs to be overridden, because they are imported via the AccessControlEnumerableUpgradeable as well.
    function _msgSender()
        internal
        view
        virtual
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (address sender)
    {
        return ERC2771ContextUpgradeable._msgSender();
    }

    /// Needs to be overridden, because they are imported via the AccessControlEnumerableUpgradeable as well.
    function _msgData()
        internal
        view
        virtual
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (bytes calldata)
    {
        return ERC2771ContextUpgradeable._msgData();
    }

    function _contextSuffixLength()
        internal
        view
        virtual
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (uint)
    {
        return ERC2771ContextUpgradeable._contextSuffixLength();
    }
}
