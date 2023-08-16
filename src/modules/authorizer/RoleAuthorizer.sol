// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;
// External Libraries

import {AccessControlEnumerableUpgradeable} from
    "@oz-up/access/AccessControlEnumerableUpgradeable.sol";
import {Module, IModule} from "src/modules/base/Module.sol";
import {IAuthorizer} from "./IAuthorizer.sol";
import {IOrchestrator} from "src/orchestrator/IOrchestrator.sol";

contract RoleAuthorizer is
    IAuthorizer,
    AccessControlEnumerableUpgradeable,
    Module
{
    //--------------------------------------------------------------------------
    // Storage

    /*   // Core roles for a orchestrator. They correspond to uint8(0) and uint(1)
    // NOTE that orchestrator owner can register more global roles using numbers from 2 onward. They'l need to go through the DEFAULT_ADMIN_ROLE for this.
    enum CoreRoles {
        OWNER, // Full Access to Protected Functions
        MANAGER // Partial Access to Protected Functions
    }
    */
    // Stores the if a module wants to use it's own roles
    // If false it uses the orchestrator's  core roles.
    mapping(address => bool) public selfManagedModules;

    // Stored for easy public reference. Other Modules can assume the following roles to exist
    bytes32 public constant ORCHESTRATOR_OWNER_ROLE = "0x01";
    bytes32 public constant ORCHESTRATOR_MANAGER_ROLE = "0x02";

    bytes32 public constant BURN_ADMIN_ROLE =
        0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    //--------------------------------------------------------------------------
    // Modifiers

    /// @notice Verifies that the caller is an active module
    modifier onlyModule(address module) {
        if (!orchestrator().isModule(module)) {
            revert Module__RoleAuthorizer__NotActiveModule(module);
        }
        _;
    }

    /*     /// @notice Verifies that the calling module has turned on self-management
    modifier onlySelfManaged() {
        if (!selfManagedModules[_msgSender()]) {
            revert Module__RoleAuthorizer__ModuleNotSelfManaged();
        }
        _;
    } */

    /// @notice Verifies that the owner being removed is not the last one
    modifier notLastOwner(bytes32 role) {
        if (
            role == ORCHESTRATOR_OWNER_ROLE
                && getRoleMemberCount(ORCHESTRATOR_OWNER_ROLE) <= 1
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
        IOrchestrator orchestrator_,
        Metadata memory metadata,
        bytes memory configData
    ) external override initializer {
        __Module_init(orchestrator_, metadata);

        (address initialOwner, address initialManager) =
            abi.decode(configData, (address, address));

        __RoleAuthorizer_init(initialOwner, initialManager);
    }

    function __RoleAuthorizer_init(address initialOwner, address initialManager)
        internal
        onlyInitializing
    {
        // Note about DEFAULT_ADMIN_ROLE: The DEFAULT_ADMIN_ROLE has admin privileges on all roles in the contract. It starts out empty, but we set the orchestrator owners as "admins of the admin role",
        // so they can whitelist an address which then will have full write access to the roles in the system. This is mainly intended for safety/recovery situations,
        // Modules can opt out of this on a per-role basis by setting the admin role to "BURN_ADMIN_ROLE".

        // Store RoleIDs for the Orchestrator roles:
        /*  ORCHESTRATOR_OWNER_ROLE =
            generateRoleId(address(orchestrator()), uint8(CoreRoles.OWNER));
        ORCHESTRATOR_MANAGER_ROLE =
            generateRoleId(address(orchestrator()), uint8(CoreRoles.MANAGER)); */

        //We preliminarily grant admin role to the caller
        _grantRole(ORCHESTRATOR_OWNER_ROLE, _msgSender());

        // Set up OWNER role structure:

        // -> set OWNER as admin of itself
        _setRoleAdmin(ORCHESTRATOR_OWNER_ROLE, ORCHESTRATOR_OWNER_ROLE);
        // -> set OWNER as admin of DEFAULT_ADMIN_ROLE
        _setRoleAdmin(DEFAULT_ADMIN_ROLE, ORCHESTRATOR_OWNER_ROLE);

        // Set up MANAGER role structure:
        // -> set OWNER as admin of DEFAULT_ADMIN_ROLE
        _setRoleAdmin(ORCHESTRATOR_MANAGER_ROLE, ORCHESTRATOR_OWNER_ROLE);
        // grant MANAGER Role to specified address
        _grantRole(ORCHESTRATOR_MANAGER_ROLE, initialManager);

        // If there is an initial owner specified, we set it as owner and remove the deployer
        // Note: If the initial owner is 0x0, it stays as msgSender()
        if (initialOwner != address(0)) {
            _grantRole(ORCHESTRATOR_OWNER_ROLE, initialOwner);
            renounceRole(ORCHESTRATOR_OWNER_ROLE, _msgSender());
        }
    }

    //--------------------------------------------------------------------------
    // Overloaded and overriden functions

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
    /* 
    /// @inheritdoc IAuthorizer
    /// @dev Implements the function of the IAuthorizer interface by defauling to check if the caller holds the OWNER role.
    function isAuthorized(address who) external view returns (bool) {
        // In case no role is specfied, we ask if the caller is an owner
        return hasRole(ORCHESTRATOR_OWNER_ROLE, who);
    }

    /// @inheritdoc IAuthorizer
    function isAuthorized(bytes32 role, address who)
        external
        view
        virtual
        returns (bool)
    {
        //Note: since it uses msgSenderto generate ID, this should only be used by modules. Users should call hasRole()
        bytes32 roleId;
        // If the module uses its own roles, check if account has the role.
        // else check if account has role in orchestrator
        if (selfManagedModules[_msgSender()]) {
            roleId = generateRoleId(_msgSender(), role);
        } else {
            roleId = generateRoleId(address(orchestrator()), role);
        }
        return hasRole(roleId, who);
    }
    */
    /// @inheritdoc IAuthorizer
    function hasModuleRole(bytes32 role, address who)
        external
        view
        virtual
        returns (bool)
    {
        //Note: since it uses msgSenderto generate ID, this should only be used by modules. Users should call hasRole()
        bytes32 roleId = generateRoleId(_msgSender(), role);
        return hasRole(roleId, who);
    }

    /// @inheritdoc IAuthorizer
    function generateRoleId(address module, bytes32 role)
        public
        pure
        returns (bytes32)
    {
        // Generate Role ID from module and role
        return keccak256(abi.encodePacked(module, role));
    }

    // State-altering functions

    /*     /// @inheritdoc IAuthorizer
    function toggleModuleSelfManagement() external onlyModule(_msgSender()) {
        if (selfManagedModules[_msgSender()]) {
            selfManagedModules[_msgSender()] = false;
            emit setRoleSelfManagement(_msgSender(), false);
        } else {
            selfManagedModules[_msgSender()] = true;
            emit setRoleSelfManagement(_msgSender(), true);
        }
    } */

    /// @inheritdoc IAuthorizer
    function grantRoleFromModule(bytes32 role, address target)
        external
        onlyModule(_msgSender())
    {
        selfManagedModules[_msgSender()] = true; // placeholder for in between removing uint8 role system
        bytes32 roleId = generateRoleId(_msgSender(), role);
        _grantRole(roleId, target);
    }

    /// @inheritdoc IAuthorizer
    function revokeRoleFromModule(bytes32 role, address target)
        external
        onlyModule(_msgSender())
    {
        bytes32 roleId = generateRoleId(_msgSender(), role);
        _revokeRole(roleId, target);
    }

    /// @inheritdoc IAuthorizer
    function transferAdminRole(bytes32 roleId, bytes32 newAdmin)
        external
        onlyRole(getRoleAdmin(roleId))
    {
        _setRoleAdmin(roleId, newAdmin);
    }

    /// @inheritdoc IAuthorizer
    function burnAdminFromModuleRole(bytes32 role)
        external
        onlyModule(_msgSender())
    {
        bytes32 roleId = generateRoleId(_msgSender(), role);
        _setRoleAdmin(roleId, BURN_ADMIN_ROLE);
    }

    /// @inheritdoc IAuthorizer
    function grantGlobalRole(bytes32 role, address target)
        external
        onlyRole(ORCHESTRATOR_OWNER_ROLE)
    {
        bytes32 roleId = generateRoleId(address(orchestrator()), role);
        _grantRole(roleId, target);
    }

    /// @inheritdoc IAuthorizer
    function revokeGlobalRole(bytes32 role, address target)
        external
        onlyRole(ORCHESTRATOR_OWNER_ROLE)
    {
        bytes32 roleId = generateRoleId(address(orchestrator()), role);
        _revokeRole(roleId, target);
    }

    /// @inheritdoc IAuthorizer
    function getOwnerRole() public view returns (bytes32) {
        return ORCHESTRATOR_OWNER_ROLE;
    }

    /// @inheritdoc IAuthorizer
    function getManagerRole() public view returns (bytes32) {
        return ORCHESTRATOR_MANAGER_ROLE;
    }
}
