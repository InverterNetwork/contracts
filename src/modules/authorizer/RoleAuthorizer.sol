// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;
// External Libraries

import {AccessControlEnumerableUpgradeable} from
    "@oz-up/access/AccessControlEnumerableUpgradeable.sol";
import {Module, IModule} from "src/modules/base/Module.sol";
import {IProposal} from "src/proposal/IProposal.sol";
import {IRoleAuthorizer} from "./IRoleAuthorizer.sol";

contract RoleAuthorizer is
    IRoleAuthorizer,
    AccessControlEnumerableUpgradeable,
    Module
{
    // Probably not necessary here, but in proposal
    enum Roles {
        OWNER, // Partial Access to Protected Functions
        MANAGER // Full Access to Protected Functions
    }

    /// @notice Event emitted when a module toggles self management
    /// @param who The module.
    /// @param newValue The new value of the self management flag.
    event setRoleSelfManagement(address who, bool newValue);

    error Module__RoleAuthorizer__OnlyCallableByModule();
    error Module__RoleAuthorizer__ModuleNotSelfManaged();
    error Module__RoleAuthorizer__OwnerRoleCannotBeEmpty();

    //--------------------------------------------------------------------------
    // Modifiers
    /// @notice checks that the caller is an active module

    modifier onlyModule() {
        if (!proposal().isModule(_msgSender())) {
            revert Module__RoleAuthorizer__OnlyCallableByModule();
        }
        _;
    }

    modifier onlySelfManaged() {
        if (!selfManagedModules[_msgSender()]) {
            revert Module__RoleAuthorizer__ModuleNotSelfManaged();
        }
        _;
    }

    modifier notLastOwner(bytes32 role) {
        if (
            role == PROPOSAL_OWNER_ROLE
                && getRoleMemberCount(PROPOSAL_OWNER_ROLE) == 1
        ) {
            revert Module__RoleAuthorizer__OwnerRoleCannotBeEmpty();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Storage

    // Stores the if a module wants to use it's own roles
    // If false it uses the proposal's roles.
    mapping(address => bool) public selfManagedModules;

    // For quick reference, since we'll be comparing against role this on revocation
    bytes32 public PROPOSAL_OWNER_ROLE;

    bytes32 public constant BURN_ADMIN_ROLE =
        0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    constructor() {
        // set up the BURN_ADMIN_ROLE
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
        // Modules can opt out of this in individual roles by  setting the admin role to "BURN_ADMIN_ROLE" which is an immutable empty set of roles.

        // Generate RoleIDs for the Proposal roles:
        PROPOSAL_OWNER_ROLE = generateRoleId(address(proposal()), 0);
        bytes32 managerRoleId = generateRoleId(address(proposal()), 1);

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
        _setRoleAdmin(managerRoleId, PROPOSAL_OWNER_ROLE);
        // grant MANAGER Role to specified address
        _grantRole(managerRoleId, initialManager);
    }

    //--------------------------------------------------------------------------
    // Override functions

    function hasRole(address module, uint8 role, address who)
        public
        view
        returns (bool)
    {
        bytes32 roleId;
        // If module uses own roles, check if account has role in module
        // else check if account has role in proposal
        if (selfManagedModules[_msgSender()]) {
            roleId = generateRoleId(module, role);
        } else {
            roleId = generateRoleId(address(proposal()), role);
        }
        return hasRole(roleId, who);
    }

    /**
     * @dev Overload {_revokeRole} to block empty owner role
     */
    function _revokeRole(bytes32 role, address account)
        internal
        virtual
        override
        notLastOwner(role)
    {
        super._revokeRole(role, account);
    }

    function isAuthorized(uint8 role, address who)
        external
        view
        returns (bool)
    {
        return hasRole(_msgSender(), role, who);
    }

    function isAuthorized(address who) external view returns (bool) {
        // In case no role is specfied, we ask if the caller is an owner
        return hasRole(PROPOSAL_OWNER_ROLE, who);
    }

    function toggleSelfManagement() external onlyModule {
        if (selfManagedModules[_msgSender()]) {
            selfManagedModules[_msgSender()] = false;
            emit setRoleSelfManagement(_msgSender(), false);
        } else {
            selfManagedModules[_msgSender()] = true;
            emit setRoleSelfManagement(_msgSender(), true);
        }
    }

    function burnAdminRole(uint8 role) external onlyModule onlySelfManaged {
        bytes32 roleId = generateRoleId(_msgSender(), role);
        _setRoleAdmin(roleId, BURN_ADMIN_ROLE);
    }

    function grantRoleFromModule(uint8 role, address target)
        external
        onlyModule
        onlySelfManaged
    {
        bytes32 roleId = generateRoleId(_msgSender(), role);
        _grantRole(roleId, target);
    }

    function revokeRoleFromModule(uint8 role, address target)
        external
        onlyModule
        onlySelfManaged
    {
        bytes32 roleId = generateRoleId(_msgSender(), role);
        _revokeRole(roleId, target);
    }

    function generateRoleId(address module, uint8 role)
        public
        pure
        returns (bytes32)
    {
        // Generate Role ID from module and role
        return keccak256(abi.encodePacked(module, role));
    }
}
