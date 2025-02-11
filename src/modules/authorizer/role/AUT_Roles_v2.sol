// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IModule_v2} from "src/modules/base/IModule_v2.sol";
import {IAuthorizer_v2} from "@aut/IAuthorizer_v2.sol";
import {IOrchestrator_v2} from
    "src/orchestrator/interfaces/IOrchestrator_v2.sol";

// Internal Dependencies
import {Module_v2} from "src/modules/base/Module_v2.sol";

// External Dependencies
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";
import {
    ERC2771ContextUpgradeable,
    ContextUpgradeable
} from "@oz-up/metatx/ERC2771ContextUpgradeable.sol";
import {
    AccessManagerUpgradeable,
    IAccessManager
} from "@oz-up/access/manager/AccessManagerUpgradeable.sol";

/**
 * @title   Inverter Roles Authorizer v2
 *
 * @notice
 *
 * @dev
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
 *
 * @author  Inverter Network
 */
contract AUT_Roles_v2 is IAuthorizer_v2, AccessManagerUpgradeable, Module_v2 {
    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId_)
        public
        view
        virtual
        override(Module_v2)
        returns (bool)
    {
        return interfaceId_ == type(IAuthorizer_v2).interfaceId
            || super.supportsInterface(interfaceId_);
    }

    //--------------------------------------------------------------------------
    // Storage

    /// @notice	The id of the next role.
    /// @dev    This is used to generate unique role ids. The id is incremented
    ///         by 1 for each new role and starts at 1 as the standard admin
    ///         role is always id 0.
    uint64 _currentRoleId;

    /// @dev	Storage gap for future upgrades.
    uint[50] private __gap;

    //--------------------------------------------------------------------------
    // Modifiers

    modifier onlyModulesOrAdmin() {
        address caller = _msgSender();
        (bool isAdmin,) = hasRole(
            0, //AdminRoleId
            caller
        );
        // caller is not a module and not an admin
        if (!orchestrator().isModule(caller) && !isAdmin) {
            revert Authorizer_v2__OnlyCallableByModuleOrAdmin();
        }
        _;
    }

    modifier existingRoleId(uint64 roleId) {
        // If given roleId is higher or equal to the current roleId
        // and is not the public roleId
        if (roleId >= _currentRoleId && roleId != type(uint64).max) {
            revert Authorizer_v2__RoleIdNotCreated();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Initialization

    /// @inheritdoc Module_v2
    function init(
        IOrchestrator_v2 orchestrator_,
        Metadata memory metadata_,
        RoleSpecification[] memory roleSpecs_,
        bytes memory configData_
    ) external override initializer {
        __Module_init(orchestrator_, metadata_, roleSpecs_);

        (address initialAdmin) = abi.decode(configData_, (address));

        __AUT_Roles_v2_init(initialAdmin);
    }

    /// @notice Initializes the role authorizer.
    /// @param  initialAdmin_ The initial admin of the AUT_Roles_v2.
    function __AUT_Roles_v2_init(address initialAdmin_)
        internal
        onlyInitializing
    {
        // Note about DEFAULT_ADMIN_ROLE: The Admin of the workflow holds the ADMIN_ROLE, and has admin
        // privileges on all Modules in the contract.
        // It is defined in the AccessManager contract and identified with uint64("0")

        __AccessManager_init(initialAdmin_);

        // Set currentRoleId to 1, as the standard admin role is always id 0.
        _currentRoleId = 1;
    }

    //--------------------------------------------------------------------------
    // Public Getter Functions

    /// @inheritdoc IAuthorizer_v2
    function getCurrentRoleId() external view returns (uint64 currentRoleId_) {
        return _currentRoleId;
    }

    //--------------------------------------------------------------------------
    // Public Mutating Functions

    /// @inheritdoc IAuthorizer_v2
    function createRoleWithSpecifications(
        address target_,
        IModule_v2.RoleSpecification memory roleSpec_
    ) public onlyModulesOrAdmin returns (uint64 roleId_) {
        // create the role and fetch the role id
        roleId_ = _createRole(roleSpec_.roleName);

        // get the amount of function selectors
        uint selectorAmount = roleSpec_.functionSelectors.length;

        // set the target function role
        for (uint i = 0; i < selectorAmount; i++) {
            _setTargetFunctionRole(
                target_, roleSpec_.functionSelectors[i], roleId_
            );
        }

        // get the amount of holders
        uint holderAmount = roleSpec_.intendedHolders.length;

        // grant role to the initial
        for (uint i = 0; i < holderAmount; i++) {
            _grantRole(roleId_, roleSpec_.intendedHolders[i], 0, 0);
        }
    }

    /// @inheritdoc IAuthorizer_v2
    function createRole(string memory roleName_)
        public
        onlyModulesOrAdmin
        returns (uint64 roleId_)
    {
        return _createRole(roleName_);
    }

    //--------------------------------------------------------------------------
    // Override Public Functions

    function grantRole(uint64 roleId, address account, uint32 executionDelay)
        public
        virtual
        override(AccessManagerUpgradeable, IAccessManager)
        existingRoleId(roleId)
    {
        super.grantRole(roleId, account, executionDelay);
    }

    function revokeRole(uint64 roleId, address account)
        public
        virtual
        override(AccessManagerUpgradeable, IAccessManager)
        existingRoleId(roleId)
    {
        super.revokeRole(roleId, account);
    }

    function renounceRole(uint64 roleId, address callerConfirmation)
        public
        virtual
        override(AccessManagerUpgradeable, IAccessManager)
        existingRoleId(roleId)
    {
        super.renounceRole(roleId, callerConfirmation);
    }

    function setRoleAdmin(uint64 roleId, uint64 admin)
        public
        virtual
        override(AccessManagerUpgradeable, IAccessManager)
        existingRoleId(roleId)
        existingRoleId(admin)
    {
        super.setRoleAdmin(roleId, admin);
    }

    function setRoleGuardian(uint64 roleId, uint64 guardian)
        public
        virtual
        override(AccessManagerUpgradeable, IAccessManager)
        existingRoleId(roleId)
        existingRoleId(guardian)
    {
        super.setRoleGuardian(roleId, guardian);
    }

    function setGrantDelay(uint64 roleId, uint32 newDelay)
        public
        virtual
        override(AccessManagerUpgradeable, IAccessManager)
        existingRoleId(roleId)
    {
        super.setGrantDelay(roleId, newDelay);
    }

    function setTargetFunctionRole(
        address target,
        bytes4[] calldata selectors,
        uint64 roleId
    )
        public
        virtual
        override(AccessManagerUpgradeable, IAccessManager)
        existingRoleId(roleId)
    {
        super.setTargetFunctionRole(target, selectors, roleId);
    }

    //--------------------------------------------------------------------------
    // Internal functions

    function _createRole(string memory roleName_)
        internal
        returns (uint64 roleId_)
    {
        roleId_ = _consumeRoleId();

        emit RoleLabel(roleId_, roleName_);
    }

    function _consumeRoleId() internal returns (uint64 createdRoleId_) {
        return _currentRoleId++;
    }

    //--------------------------------------------------------------------------
    // ERC2771 Context Upgradeable

    /// Needs to be overridden, because they are imported via the AccessControlEnumerableUpgradeable as well.
    function _msgSender()
        internal
        view
        virtual
        override(ContextUpgradeable, Module_v2)
        returns (address sender)
    {
        return Module_v2._msgSender();
    }

    /// Needs to be overridden, because they are imported via the AccessControlEnumerableUpgradeable as well.
    function _msgData()
        internal
        view
        virtual
        override(ContextUpgradeable, Module_v2)
        returns (bytes calldata)
    {
        return Module_v2._msgData();
    }

    function _contextSuffixLength()
        internal
        view
        virtual
        override(ContextUpgradeable, Module_v2)
        returns (uint)
    {
        return Module_v2._contextSuffixLength();
    }
}
