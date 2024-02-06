// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;
// External Libraries

import {ERC165} from "@oz/utils/introspection/ERC165.sol";
import {AccessControlEnumerableUpgradeable} from
    "@oz-up/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {Module, IModule} from "src/modules/base/Module.sol";
import {IAuthorizer} from "./IAuthorizer.sol";
import {IOrchestrator} from "src/orchestrator/IOrchestrator.sol";

contract RoleAuthorizer is
    IAuthorizer,
    AccessControlEnumerableUpgradeable,
    Module
{
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(Module, AccessControlEnumerableUpgradeable)
        returns (bool)
    {
        return interfaceId == type(IAuthorizer).interfaceId
            || super.supportsInterface(interfaceId);
    }

    //--------------------------------------------------------------------------
    // Storage

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

        // If there is no initial owner specfied or the initial owner is the same as the deployer, the initial setup is finished at this point
        // If intialOwner corresponds to a different address, we need to set it up at this point and renounce the deployer
        if (initialOwner != address(0) && initialOwner != _msgSender()) {
            _grantRole(ORCHESTRATOR_OWNER_ROLE, initialOwner);
            renounceRole(ORCHESTRATOR_OWNER_ROLE, _msgSender());
        }
    }

    //--------------------------------------------------------------------------
    // Overloaded and overriden functions

    /// @notice Overrides {_revokeRole} to prevent having an empty OWNER role
    /// @param role The id number of the role
    /// @param who The user we want to check on
    /// @return bool Returns if revoke has been succesful
    function _revokeRole(bytes32 role, address who)
        internal
        virtual
        override
        notLastOwner(role)
        returns (bool)
    {
        return super._revokeRole(role, who);
    }

    //--------------------------------------------------------------------------
    // Public functions

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

    /// @inheritdoc IAuthorizer
    function grantRoleFromModule(bytes32 role, address target)
        external
        onlyModule(_msgSender())
    {
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
    function getOwnerRole() public pure returns (bytes32) {
        return ORCHESTRATOR_OWNER_ROLE;
    }

    /// @inheritdoc IAuthorizer
    function getManagerRole() public pure returns (bytes32) {
        return ORCHESTRATOR_MANAGER_ROLE;
    }
}
