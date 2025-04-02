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
 * @notice  Provides a robust access control mechanism for managing roles and permissions
 *          across different modules within the Inverter Network, ensuring secure and
 *          controlled access to critical functionalities.
 *
 * @dev     Extends {AccessControlEnumerableUpgradeable} and integrates with {Module_v1} to
 *          offer fine-grained access control through role-based permissions. Utilizes
 *          ERC2771 for meta-transactions to enhance module interaction experiences.
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
    AccessControlEnumerableUpgradeable,
    Module_v1
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
    modifier idExisting(bytes32 roleId_) {
        if (roleId_ != PUBLIC_ROLE && uint(roleId_) > _roleIdCounter) {
            revert Module__Authorizer__RoleIdNotExisting();
        }
        _;
    }

    // ========================================================================
    // Storage

    /// @notice The role that is used as a placeholder for a burned admin role. //@todo Question: Can we also make this the public Role? Is this confusing?
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
    uint internal _roleIdCounter;

    /// @dev	Storage gap for future upgrades.
    uint[47] private __gap; //@todo Question: Mapping Storage slot only 1 right?

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

        // Start with 1 to symbolize two roles: DEFAULT_ADMIN_ROLE at 0 and PUBLIC_ROLE at 1.
        _roleIdCounter = 1;

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
    function getRoleIdCounter() public view returns (uint roleIdCounter_) {
        roleIdCounter_ = _roleIdCounter;
    }

    /// @inheritdoc IAuthorizer_v1
    function isPermissioned(address target_, bytes4 selector_, bytes32 roleId_)
        public
        view
        virtual
        returns (bool isPermissioned_)
    {
        bytes32[] memory permissions_ = _permissions[target_][selector_];
        for (uint i = 0; i < permissions_.length; i++) {
            if (permissions_[i] == roleId_) {
                return true;
            }
        }
        return false;
    }

    /// @inheritdoc IAuthorizer_v1
    function hasPermission( //@todo with added interface function the interfaceid changes for IAuthorizer_v1 -> Implications for ERC165
    address caller_, address target_, bytes4 selector_)
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
        // Caller does not have any of the roles, so they cannot call the function.
        return false;
    }
    // ------------------------------------------------------------------------
    // Getter -  Role Management

    /// @inheritdoc IAuthorizer_v1
    function getAdminRole() public pure returns (bytes32) {
        return DEFAULT_ADMIN_ROLE;
    }

    // ------------------------------------------------------------------------
    // Getter - Out of Order

    /// @inheritdoc IAuthorizer_v1
    function checkForRole(bytes32, address)
        external
        view
        virtual
        returns (bool)
    {
        revert IModule_v1.Module__FunctionDeprecated();
    }

    /// @inheritdoc IAuthorizer_v1
    function generateRoleId(address, bytes32) public pure returns (bytes32) {
        revert IModule_v1.Module__FunctionDeprecated();
    }

    // ========================================================================
    // Mutating Functions

    // ------------------------------------------------------------------------
    // Mutating - Authorization

    /// @inheritdoc IAuthorizer_v1
    function addAccessPermission(
        address target_,
        bytes4 selector_,
        bytes32 roleId_
    )
        public
        onlyRole(DEFAULT_ADMIN_ROLE) //@todo do i just use locked here?
        idNotDefaultAdmin(roleId_)
        idExisting(roleId_)
    {
        // if RoleId already has a permission, do nothing
        if (isPermissioned(target_, selector_, roleId_)) {
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
    )
        public
        onlyRole(DEFAULT_ADMIN_ROLE) //@todo do i just use locked here?
    {
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
    // Mutating - Role Management

    /// @inheritdoc IAuthorizer_v1
    function createRole(
        string memory roleName_,
        bytes32 respectiveAdminRole_,
        address[] memory initialMembers_
    )
        public
        virtual
        onlyRole(DEFAULT_ADMIN_ROLE) //@todo do i just use locked here?
        idExisting(respectiveAdminRole_)
        returns (bytes32 newRoleId_)
    {
        newRoleId_ = bytes32(++_roleIdCounter);

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
        onlyRole(DEFAULT_ADMIN_ROLE) //@todo do i just use locked here?
        idExisting(roleId_)
    {
        emit RoleLabeled(roleId_, newRoleName_);
    }

    /// @inheritdoc IAuthorizer_v1
    function transferAdminRole(bytes32 roleId_, bytes32 newAdminRoleId_)
        external
        onlyRole(getRoleAdmin(roleId_))
        idExisting(roleId_)
        idExisting(newAdminRoleId_)
    {
        _setRoleAdmin(roleId_, newAdminRoleId_);
    }

    /// @inheritdoc IAuthorizer_v1
    function burnAdminFromRole(bytes32 roleId_)
        external
        onlyRole(getRoleAdmin(roleId_))
        idExisting(roleId_)
    {
        // If Role Admin is Burned do nothing
        if (getRoleAdmin(roleId_) == BURN_ADMIN_ROLE) {
            return;
        }
        // Burn Role Admin
        _setRoleAdmin(roleId_, BURN_ADMIN_ROLE);
        emit RoleAdminBurned(roleId_);
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
        onlyRole(DEFAULT_ADMIN_ROLE) //@todo do i just use locked here?
        idExisting(respectiveAdminRole_)
        returns (bytes32 newRoleId_)
    {
        uint targetsLength = targets_.length;
        if (targetsLength != selectors_.length) {
            revert Module__Authorizer__InvalidInputLength();
        }

        newRoleId_ =
            createRole(roleName_, respectiveAdminRole_, initialMembers_);

        // Run through all target and selector combinations and add permission to role id

        for (uint i = 0; i < targetsLength; i++) {
            for (uint j = 0; j < selectors_[i].length; j++) {
                addAccessPermission(targets_[i], selectors_[i][j], newRoleId_);
            }
        }
    }
    // ------------------------------------------------------------------------
    // Mutating - Out of Order

    /// @inheritdoc IAuthorizer_v1
    function grantRoleFromModule(bytes32, address) external pure {
        revert IModule_v1.Module__FunctionDeprecated();
    }

    /// @inheritdoc IAuthorizer_v1
    function grantRoleFromModuleBatched(bytes32, address[] calldata)
        external
        pure
    {
        revert IModule_v1.Module__FunctionDeprecated();
    }

    /// @inheritdoc IAuthorizer_v1
    function revokeRoleFromModule(bytes32, address) external pure {
        revert IModule_v1.Module__FunctionDeprecated();
    }

    /// @inheritdoc IAuthorizer_v1
    function revokeRoleFromModuleBatched(bytes32, address[] calldata)
        external
        pure
    {
        revert IModule_v1.Module__FunctionDeprecated();
    }

    /// @inheritdoc IAuthorizer_v1
    function burnAdminFromModuleRole(bytes32) external pure {
        revert IModule_v1.Module__FunctionDeprecated();
    }

    /// @inheritdoc IAuthorizer_v1
    function grantGlobalRole(bytes32, address) external pure {
        revert IModule_v1.Module__FunctionDeprecated();
    }

    /// @inheritdoc IAuthorizer_v1
    function grantGlobalRoleBatched(bytes32, address[] calldata)
        external
        pure
    {
        revert IModule_v1.Module__FunctionDeprecated();
    }

    /// @inheritdoc IAuthorizer_v1
    function revokeGlobalRole(bytes32, address) external pure {
        revert IModule_v1.Module__FunctionDeprecated();
    }

    /// @inheritdoc IAuthorizer_v1
    function revokeGlobalRoleBatched(bytes32, address[] calldata)
        external
        pure
    {
        revert IModule_v1.Module__FunctionDeprecated();
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
        idExisting(role)
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
