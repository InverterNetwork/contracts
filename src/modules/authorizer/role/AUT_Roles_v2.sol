// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IModule_v2} from "src/modules/base/IModule_v2.sol";
import {IAuthorizer_v2} from "@aut/IAuthorizer_v2.sol";
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";

// Internal Dependencies
import {Module_v2} from "src/modules/base/Module_v2.sol";

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
 * @notice  Provides the access control mechanism for managing roles and
 *          permissions across different modules within the Inverter Network,
 *          ensuring secure and controlled access to critical functionalities.
 *
 * @dev     Inherits functionality from:
 *          - IAuthorizer_v2: Implementation interface.
 *          - Module_v2: Inverter network base module functionality.
 *          - AccessControlEnumerableUpgradeable: Access control functionality.
 *
 *          Key features:
 *              - Role creation and management. This includes the ability to
 *                create roles, revoke roles, assigning and revoking role
 *                admins, which can add and remove role members.
 *              - Role-based access control. This includes the ability to grant
 *                roles access to functions that implement the permissioned
 *                modifier. Functions can also be set to public access by
 *                adding the public role to the function permissions. *
 *
 * @custom:documentation See https://github.com/InverterNetwork/contracts/tree/dev/docs/src/modules/authorizer/role/AUT_Roles_v2.sol
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
contract AUT_Roles_v2 is
    IAuthorizer_v2,
    Module_v2,
    AccessControlEnumerableUpgradeable
{
    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId_)
        public
        view
        virtual
        override(Module_v2, AccessControlEnumerableUpgradeable)
        returns (bool isInterfaceId_)
    {
        return interfaceId_ == type(IAuthorizer_v2).interfaceId
            || super.supportsInterface(interfaceId_);
    }

    // ========================================================================
    // Modifiers

    /// @notice Verifies that the roleId is not the default admin role.
    /// @param  roleId_ The id of the role.
    modifier idNotDefaultAdmin(bytes32 roleId_) {
        if (roleId_ == DEFAULT_ADMIN_ROLE) {
            revert Module__Authorizer__CannotModifyAdminRoleAccess();
        }
        _;
    }

    /// @notice Verifies that the roleId is already existing.
    /// @param  roleId_ The id of the role.
    modifier idExists(bytes32 roleId_) {
        // If the given roleId is greater than the last assigned roleId, then
        // it is not existing.
        if (uint(roleId_) > _lastAssignedRoleId) {
            revert Module__Authorizer__RoleIdNotExisting();
        }
        _;
    }

    // ========================================================================
    // Storage

    /// @notice The public role.
    bytes32 public constant PUBLIC_ROLE = bytes32(uint(1));

    /// @notice The burned admin role.
    bytes32 public constant BURN_ADMIN_ROLE =
        0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    /// @notice Mapping that stores the role IDs that can be used to call
    ///         functions on a target contract.
    /// @dev    target The address of the target contract.
    /// @dev    selector The function selector of the function to call.
    /// @dev    roleIds The role IDs that can be used to call the function.
    mapping(address target => mapping(bytes4 selector => bytes32[] roleIds))
        internal _permissions;

    /// @notice The counter for role IDs.
    /// @dev	This is used to generate unique role IDs for each role.
    /// @dev    Starts at 1, which symbolizes two roles: PUBLIC_ROLE and
    ///         DEFAULT_ADMIN_ROLE, but is immediately incremented when a role
    ///         is created.
    uint internal _lastAssignedRoleId;

    /// @dev	Storage gap for future upgrades.
    uint[50] private __gap;

    // ========================================================================
    // Initialization

    /// @inheritdoc Module_v2
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata_,
        bytes memory configData_
    ) external override initializer {
        __Module_init(orchestrator_, metadata_);

        (address initialAdmin) = abi.decode(configData_, (address));

        __RoleAuthorizer_init(initialAdmin);
    }

    /// @notice Initializes the role authorizer.
    /// @param  initialAdmin_ The initial admin of the role authorizer.
    function __RoleAuthorizer_init(address initialAdmin_)
        internal
        onlyInitializing
    {
        if (initialAdmin_ == address(0)) {
            revert Module__Authorizer__InvalidInitialAdmin();
        }

        // Start with 1 to account for the two native roles:
        // DEFAULT_ADMIN_ROLE at 0 and PUBLIC_ROLE at 1.
        _lastAssignedRoleId = 1;

        // Note about DEFAULT_ADMIN_ROLE:
        // The admin of the workflow holds the DEFAULT_ADMIN_ROLE, and has
        // admin privileges on all modules in the contract.
        // It is defined in the AccessControl contract and identified with
        // bytes32("0x00").
        // Modules can opt out of this on a per-role basis by setting the admin
        // role to "BURN_ADMIN_ROLE".

        // make the BURN_ADMIN_ROLE immutable.
        _setRoleAdmin(BURN_ADMIN_ROLE, BURN_ADMIN_ROLE);

        // set the initial admin as the DEFAULT_ADMIN_ROLE
        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin_);
    }

    // ========================================================================
    // Public Getter Functions

    // ------------------------------------------------------------------------
    // Getter -  Role Management

    /// @inheritdoc IAuthorizer_v2
    function getAdminRole() external pure returns (bytes32 defaultAdminId_) {
        return DEFAULT_ADMIN_ROLE;
    }

    // ------------------------------------------------------------------------
    // Getter -  Authorization

    /// @inheritdoc IAuthorizer_v2
    function getPermissions(address target_, bytes4 selector_)
        external
        view
        virtual
        returns (bytes32[] memory permissions_)
    {
        permissions_ = _permissions[target_][selector_];
    }

    /// @inheritdoc IAuthorizer_v2
    function getLastAssignedRoleId()
        external
        view
        returns (uint lastAssignedRoleId_)
    {
        lastAssignedRoleId_ = _lastAssignedRoleId;
    }

    /// @inheritdoc IAuthorizer_v2
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

    /// @inheritdoc IAuthorizer_v2
    function hasPermission(address caller_, address target_, bytes4 selector_)
        external
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

        // Go through each role and check if the caller has permission.
        for (uint i = 0; i < permissionLength; i++) {
            if (
                // Return true if the role is the public role
                // or if the caller has the role.
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

    /// @inheritdoc IAuthorizer_v2
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

    /// @inheritdoc IAuthorizer_v2
    function labelRole(bytes32 roleId_, string memory newRoleName_)
        external
        permissioned
        idExists(roleId_)
    {
        emit RoleLabeled(roleId_, newRoleName_);
    }

    /// @inheritdoc IAuthorizer_v2
    function transferAdminRole(bytes32 roleId_, bytes32 newAdminRoleId_)
        external
        onlyRole(getRoleAdmin(roleId_))
        idExists(roleId_)
        idExists(newAdminRoleId_)
    {
        _setRoleAdmin(roleId_, newAdminRoleId_);
    }

    /// @inheritdoc IAuthorizer_v2
    function burnRoleAdmin(bytes32 roleId_)
        external
        onlyRole(getRoleAdmin(roleId_))
        idExists(roleId_)
    {
        // Burn admin from the role.
        _setRoleAdmin(roleId_, BURN_ADMIN_ROLE);
        emit RoleAdminBurned(roleId_);
    }

    // ------------------------------------------------------------------------
    // Mutating - Authorization

    /// @inheritdoc IAuthorizer_v2
    function addAccessPermission(
        address target_,
        bytes4 selector_,
        bytes32 roleId_
    ) public permissioned idNotDefaultAdmin(roleId_) idExists(roleId_) {
        // if RoleId already has a permission, do nothing.
        if (isRolePermissioned(target_, selector_, roleId_)) {
            return;
        }

        _permissions[target_][selector_].push(roleId_);
        emit AccessPermissionAdded(target_, selector_, roleId_);
    }

    /// @inheritdoc IAuthorizer_v2
    function removeAccessPermission(
        address target_,
        bytes4 selector_,
        bytes32 roleId_
    ) public permissioned {
        bytes32[] memory permissions = _permissions[target_][selector_];
        uint permissionsLength = permissions.length;

        for (uint i = 0; i < permissionsLength; i++) {
            if (permissions[i] == roleId_) {
                // Replace the element to be removed with the last one.
                _permissions[target_][selector_][i] =
                    _permissions[target_][selector_][permissionsLength - 1];
                // Remove the last element.
                _permissions[target_][selector_].pop();

                // Emit Event and exit the function once the value is removed.
                emit AccessPermissionRemoved(target_, selector_, roleId_);
                return;
            }
        }
        // Do nothing if the value is not found.
    }

    // ------------------------------------------------------------------------
    // Mutating - Mixed Utility

    /// @inheritdoc IAuthorizer_v2
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

    /// @notice Overrides {_grantRole} to make sure only existing roles can be
    ///         granted.
    /// @param  role_ The id of the role.
    /// @param  who_ The user we want to check on.
    /// @return success_ Returns if grant has been successful.
    function _grantRole(bytes32 role_, address who_)
        internal
        virtual
        override
        idExists(role_)
        returns (bool success_)
    {
        return super._grantRole(role_, who_);
    }

    //--------------------------------------------------------------------------
    // Internal - ERC2771 Context Upgradeable

    /// @dev    Needs to be overridden, because they are imported via the
    ///         AccessControlEnumerableUpgradeable as well.
    function _msgSender()
        internal
        view
        virtual
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (address sender_)
    {
        return ERC2771ContextUpgradeable._msgSender();
    }

    /// @dev    Needs to be overridden, because they are imported via the
    ///         AccessControlEnumerableUpgradeable as well.
    function _msgData()
        internal
        view
        virtual
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (bytes calldata msgData_)
    {
        return ERC2771ContextUpgradeable._msgData();
    }

    /// @dev    Needs to be overridden, because they are imported via the
    ///         AccessControlEnumerableUpgradeable as well.
    function _contextSuffixLength()
        internal
        view
        virtual
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (uint contextSuffixLength_)
    {
        return ERC2771ContextUpgradeable._contextSuffixLength();
    }
}
