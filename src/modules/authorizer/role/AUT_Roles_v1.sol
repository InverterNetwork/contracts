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

    //--------------------------------------------------------------------------
    // Storage
    /// @notice The role that is used as a placeholder for a burned admin role.
    bytes32 public constant BURN_ADMIN_ROLE =
        0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    /// @dev	Storage gap for future upgrades.
    uint[50] private __gap;

    //--------------------------------------------------------------------------
    // Modifiers

    /// @dev	Verifies that the caller is an active module.
    /// @param  module The address of the module.
    modifier onlyModule(address module) {
        if (!orchestrator().isModule(module)) {
            revert Module__Authorizer__NotActiveModule(module);
        }
        _;
    }

    /// @dev	Verifies that the admin being removed is not the last one.
    /// @param  role The id number of the role.
    modifier notLastAdmin(bytes32 role) {
        if (
            role == DEFAULT_ADMIN_ROLE
                && getRoleMemberCount(DEFAULT_ADMIN_ROLE) <= 1
        ) {
            revert Module__Authorizer__AdminRoleCannotBeEmpty();
        }
        _;
    }

    /// @dev     Verifies that the admin being added is not the {Orchestrator_v1}.
    /// @param  role The id number of the role.
    /// @param  who The user we want to check on.
    modifier noSelfAdmin(bytes32 role, address who) {
        if (role == DEFAULT_ADMIN_ROLE && who == address(orchestrator())) {
            revert Module__Authorizer__OrchestratorCannotHaveAdminRole();
        }
        _;
    }

    //--------------------------------------------------------------------------
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

        // Note about DEFAULT_ADMIN_ROLE: The Admin of the workflow holds the DEFAULT_ADMIN_ROLE, and has admin
        // privileges on all Modules in the contract.
        // It is defined in the AccessControl contract and identified with bytes32("0x00")
        // Modules can opt out of this on a per-role basis by setting the admin role to "BURN_ADMIN_ROLE".

        // make the BURN_ADMIN_ROLE immutable
        _setRoleAdmin(BURN_ADMIN_ROLE, BURN_ADMIN_ROLE);

        // set the initial admin as the DEFAULT_ADMIN_ROLE
        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
    }

    //--------------------------------------------------------------------------
    // Public functions

    /// @inheritdoc IAuthorizer_v1
    function checkForRole(bytes32 role, address who)
        external
        view
        virtual
        returns (bool)
    {
        return hasRole(role, who);
    }

    /// @inheritdoc IAuthorizer_v1
    function generateRoleId(address module, bytes32 role)
        public
        pure
        returns (bytes32)
    {
        // Generate Role ID from module and role
        return keccak256(abi.encodePacked(module, role));
    }

    /// @inheritdoc IAuthorizer_v1
    function grantRoleFromModule(bytes32 role, address target)
        external
        onlyModule(_msgSender())
    {
        bytes32 roleId = generateRoleId(_msgSender(), role);
        _grantRole(roleId, target);
    }

    /// @inheritdoc IAuthorizer_v1
    function grantRoleFromModuleBatched(
        bytes32 role,
        address[] calldata targets
    ) external onlyModule(_msgSender()) {
        bytes32 roleId = generateRoleId(_msgSender(), role);
        for (uint i = 0; i < targets.length; i++) {
            _grantRole(roleId, targets[i]);
        }
    }

    /// @inheritdoc IAuthorizer_v1
    function revokeRoleFromModule(bytes32 role, address target)
        external
        onlyModule(_msgSender())
    {
        bytes32 roleId = generateRoleId(_msgSender(), role);
        _revokeRole(roleId, target);
    }

    /// @inheritdoc IAuthorizer_v1
    function revokeRoleFromModuleBatched(
        bytes32 role,
        address[] calldata targets
    ) external onlyModule(_msgSender()) {
        bytes32 roleId = generateRoleId(_msgSender(), role);
        for (uint i = 0; i < targets.length; i++) {
            _revokeRole(roleId, targets[i]);
        }
    }

    /// @inheritdoc IAuthorizer_v1
    function transferAdminRole(bytes32 roleId, bytes32 newAdmin)
        external
        onlyRole(getRoleAdmin(roleId))
    {
        _setRoleAdmin(roleId, newAdmin);
    }

    /// @inheritdoc IAuthorizer_v1
    function burnAdminFromModuleRole(bytes32 role)
        external
        onlyModule(_msgSender())
    {
        bytes32 roleId = generateRoleId(_msgSender(), role);
        _setRoleAdmin(roleId, BURN_ADMIN_ROLE);
    }

    /// @inheritdoc IAuthorizer_v1
    function grantGlobalRole(bytes32 role, address target)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        bytes32 roleId = generateRoleId(address(orchestrator()), role);
        _grantRole(roleId, target);
    }

    /// @inheritdoc IAuthorizer_v1
    function grantGlobalRoleBatched(bytes32 role, address[] calldata targets)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        bytes32 roleId = generateRoleId(address(orchestrator()), role);
        for (uint i = 0; i < targets.length; i++) {
            _grantRole(roleId, targets[i]);
        }
    }

    /// @inheritdoc IAuthorizer_v1
    function revokeGlobalRole(bytes32 role, address target)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        bytes32 roleId = generateRoleId(address(orchestrator()), role);
        _revokeRole(roleId, target);
    }

    /// @inheritdoc IAuthorizer_v1
    function revokeGlobalRoleBatched(bytes32 role, address[] calldata targets)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        bytes32 roleId = generateRoleId(address(orchestrator()), role);
        for (uint i = 0; i < targets.length; i++) {
            _revokeRole(roleId, targets[i]);
        }
    }

    /// @inheritdoc IAuthorizer_v1
    function getAdminRole() public pure returns (bytes32) {
        return DEFAULT_ADMIN_ROLE;
    }

    //--------------------------------------------------------------------------
    // Overloaded and overridden functions

    /// @notice Overrides {_revokeRole} to prevent having an empty `ADMIN` role.
    /// @param  role The id number of the role.
    /// @param  who The user we want to check on.
    /// @return bool Returns if revoke has been succesful.
    function _revokeRole(bytes32 role, address who)
        internal
        virtual
        override
        notLastAdmin(role)
        returns (bool)
    {
        return super._revokeRole(role, who);
    }

    /// @notice Overrides {_grantRole} to prevent having the {Orchestrator_v1} having the `OWNER` role.
    /// @param  role The id of the role.
    /// @param  who The user we want to check on.
    /// @return bool Returns if grant has been succesful.
    function _grantRole(bytes32 role, address who)
        internal
        virtual
        override
        noSelfAdmin(role, who)
        returns (bool)
    {
        return super._grantRole(role, who);
    }

    //--------------------------------------------------------------------------
    // ERC2771 Context Upgradeable

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
