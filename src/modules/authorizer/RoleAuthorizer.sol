// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;
// External Libraries

import {AccessControlEnumerableUpgradeable} from
    "@oz-up/access/AccessControlEnumerableUpgradeable.sol";
import {Module, IModule} from "src/modules/base/Module.sol";
import {IProposal} from "src/proposal/IProposal.sol";
import {IRoleAuthorizer} from "./IRoleAuthorizer.sol";

import "forge-std/console.sol";

contract RoleAuthorizer is
    IRoleAuthorizer,
    AccessControlEnumerableUpgradeable,
    Module
{
    //--------------------------------------------------------------------------
    // Storage

    // Core roles for a proposal. They correspond to uint8(0) and uint(1)
    // NOTE that proposal owner can register more global roles using numbers from 2 onward. They'l need to go through the DEFAULT_ADMIN_ROLE for this.
    // TODO Maybe it would be worth it to create an extra function that bypasses DEFAULT_ADMIN_ROLE, but only for global roles and by the PROPOSAL_OWNER_ROLE? This would streamline the process of creating roles for all modules
    enum CoreRoles {
        OWNER, // Partial Access to Protected Functions
        MANAGER // Full Access to Protected Functions
    }

    // Stores the if a module wants to use it's own roles
    // If false it uses the proposal's  core roles.
    mapping(address => bool) public selfManagedModules;

    // Stored for easy public reference. Other Modules can assume the following roles to exist
    bytes32 public PROPOSAL_OWNER_ROLE;
    bytes32 public PROPOSAL_MANAGER_ROLE;

    bytes32 public constant BURN_ADMIN_ROLE =
        0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    //--------------------------------------------------------------------------
    // Modifiers

    /// @notice Verifies that the caller is an active module
    modifier onlyModule() {
        if (!proposal().isModule(_msgSender())) {
            revert Module__RoleAuthorizer__OnlyCallableByModule();
        }
        _;
    }

    /// @notice Verifies that the calling module has turned on self-management
    modifier onlySelfManaged() {
        if (!selfManagedModules[_msgSender()]) {
            revert Module__RoleAuthorizer__ModuleNotSelfManaged();
        }
        _;
    }

    /// @notice Verifies that the owner being removed is not the last one
    modifier notLastOwner(bytes32 role) {
        if (
            role == PROPOSAL_OWNER_ROLE
                && getRoleMemberCount(PROPOSAL_OWNER_ROLE) <= 1
        ) {
            revert Module__RoleAuthorizer__OwnerRoleCannotBeEmpty();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Constructor and initialization

    constructor() {
        // make the BURN_ADMIN_ROLE immutable
        _setRoleAdmin(BURN_ADMIN_ROLE, BURN_ADMIN_ROLE);
    }

    /// @inheritdoc Module
    function init(
        IProposal proposal_,
        Metadata memory metadata,
        bytes memory configdata
    ) external override initializer {
        __Module_init(proposal_, metadata);

        (address[] memory initialOwners, address initialManager) =
            abi.decode(configdata, (address[], address));

        __RoleAuthorizer_init(initialOwners, initialManager);
    }

    function __RoleAuthorizer_init(
        address[] memory initialOwners,
        address initialManager
    ) internal onlyInitializing {
        // Note about DEFAULT_ADMIN_ROLE: The DEFAULT_ADMIN_ROLE has admin privileges on all roles in the contract. It starts out empty, but we set the proposal owners as "admins of the admin role",
        // so they can whitelist an address which then will have full write access to the roles in the system. This is mainly intended for safety/recovery situations,
        // Modules can opt out of this on a per-role basis by setting the admin role to "BURN_ADMIN_ROLE".

        // Store RoleIDs for the Proposal roles:
        PROPOSAL_OWNER_ROLE =
            generateRoleId(address(proposal()), uint8(CoreRoles.OWNER));
        PROPOSAL_MANAGER_ROLE =
            generateRoleId(address(proposal()), uint8(CoreRoles.MANAGER));

        // Set up OWNER role structure:

        // -> set OWNER as admin of itself
        _setRoleAdmin(PROPOSAL_OWNER_ROLE, PROPOSAL_OWNER_ROLE);
        // -> set OWNER as admin of DEFAULT_ADMIN_ROLE
        _setRoleAdmin(DEFAULT_ADMIN_ROLE, PROPOSAL_OWNER_ROLE);

        // grant OWNER role to users from configData.
        // Note: If an initial ownerlist has been supplied, the deployer will not be an owner.
        uint ownerLength = initialOwners.length;
        if (ownerLength == 0) {
            _grantRole(PROPOSAL_OWNER_ROLE, _msgSender());
        } else {
            for (uint i; i < ownerLength; ++i) {
                address current = initialOwners[i];
                _grantRole(PROPOSAL_OWNER_ROLE, current);
            }
        }

        // Set up MANAGER role structure:
        // -> set OWNER as admin of DEFAULT_ADMIN_ROLE
        _setRoleAdmin(PROPOSAL_MANAGER_ROLE, PROPOSAL_OWNER_ROLE);
        // grant MANAGER Role to specified address
        _grantRole(PROPOSAL_MANAGER_ROLE, initialManager);
    }

    //--------------------------------------------------------------------------
    // Overloaded and overriden functions

    /// @notice Overloads {hasRole} to check if an address has a specific role from a module
    /// @param module The module on which we want to check the role
    /// @param role The id number of the role
    /// @param who The user we want to check on
    /// @dev If the Module isn't self-managing, the fact that an address has the role DOES NOT mean it will be able to execute actions acting as it.
    function hasRole(address module, uint8 role, address who)
        public
        view
        returns (bool)
    {
        bytes32 roleId = generateRoleId(module, role);

        return hasRole(roleId, who);
    }

    /// @notice Overrides {_revokeRole} to prevent having an empty OWNER role
    /// @param role The id number of the role
    /// @param who The user we want to check on
    function _revokeRole(bytes32 role, address who)
        internal
        virtual
        override
        notLastOwner(role)
    {
        super._revokeRole(role, who);
    }

    //--------------------------------------------------------------------------
    // Public functions

    // View functions

    /// @notice Returns whether an address is authorized to facilitate
    ///         the current transaction.
    /// @param who  The address on which to perform the check.
    /// @dev Implements the function of the IAuthorizer interface by defauling to check if the caller holds the OWNER role.
    function isAuthorized(address who) external view returns (bool) {
        // In case no role is specfied, we ask if the caller is an owner
        return hasRole(PROPOSAL_OWNER_ROLE, who);
    }

    /// @notice Overloads {isAuthorized} for a Module to ask whether an address holds the required role to execute
    ///         the current transaction.
    /// @param role The identifier of the role we want to check
    /// @param who  The address on which to perform the check.
    /// @dev If the role is not self-managed, it will default to the proposal roles
    /// @dev If not, it will use the calling address to generate the role ID. Therefore, for checking on anything other than itself, hasRole() should be used
    function isAuthorized(uint8 role, address who)
        external
        view
        returns (bool)
    {
        //Note: since it uses msgSenderto generate ID, this should only be used by modules. Users should call hasRole()
        bytes32 roleId;
        // If the module uses its own roles, check if account has the role.
        // else check if account has role in proposal
        if (selfManagedModules[_msgSender()]) {
            roleId = generateRoleId(_msgSender(), role);
        } else {
            roleId = generateRoleId(address(proposal()), role);
        }
        return hasRole(roleId, who);
    }

    /// @notice Helper function to generate a bytes32 role hash for a module role
    /// @param module The address of the module to generate the hash for
    /// @param role  The ID number of the role to generate the hash for
    function generateRoleId(address module, uint8 role)
        public
        pure
        returns (bytes32)
    {
        // Generate Role ID from module and role
        return keccak256(abi.encodePacked(module, role));
    }

    // State-altering functions

    /// @notice Toggles if a Module self-manages or defaults to the proposal's roles.
    function toggleSelfManagement() external onlyModule {
        if (selfManagedModules[_msgSender()]) {
            selfManagedModules[_msgSender()] = false;
            emit setRoleSelfManagement(_msgSender(), false);
        } else {
            selfManagedModules[_msgSender()] = true;
            emit setRoleSelfManagement(_msgSender(), true);
        }
    }

    /// @notice Used by a Module to grant a role to a user.
    /// @param role The identifier of the role to grant
    /// @param target  The address to which to grant the role.
    function grantRoleFromModule(uint8 role, address target)
        external
        onlyModule
        onlySelfManaged
    {
        bytes32 roleId = generateRoleId(_msgSender(), role);
        _grantRole(roleId, target);
    }

    /// @notice Used by a Module to revoke a role from a user.
    /// @param role The identifier of the role to revoke
    /// @param target  The address to revoke the role from.
    function revokeRoleFromModule(uint8 role, address target)
        external
        onlyModule
        onlySelfManaged
    {
        bytes32 roleId = generateRoleId(_msgSender(), role);
        _revokeRole(roleId, target);
    }

    /// @notice Burns the admin of a given role.
    /// @param role The role to remove admin access from
    /// @dev The module itself can still grant and revoke it's own roles. This only burns third-party access to the role.
    function burnAdminRole(uint8 role) external onlyModule onlySelfManaged {
        bytes32 roleId = generateRoleId(_msgSender(), role);
        _setRoleAdmin(roleId, BURN_ADMIN_ROLE);
    }

    /// @notice Transfer the admin rights to a given role.
    /// @param roleId The role on which to peform the admin transfer
    /// @param newAdmin The new role to which to transfer admin access to
    function transferAdminRole(bytes32 roleId, bytes32 newAdmin)
        external
        onlyRole(getRoleAdmin(roleId))
    {
        _setRoleAdmin(roleId, newAdmin);
    }
}
