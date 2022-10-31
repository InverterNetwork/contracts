// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Dependencies
import {ContextUpgradeable} from "@oz-up/utils/ContextUpgradeable.sol";
import {Initializable} from "@oz-up/proxy/utils/Initializable.sol";

// Internal Dependencies
import {Types} from "src/common/Types.sol";

// Interfaces
import {IModuleManager} from "src/proposal/base/IModuleManager.sol";

/**
 * @title Module Manager
 *
 * @dev A contract to manage modules that can execute transactions via this
 *      contract and manage own role-based access control mechanisms.
 *
 *      Note that modules can only be enabled during the initialization of the
 *      contract. It is, however, always possible to disable modules.
 *
 *      The role-based access control mechanism is based on OpenZeppelin's
 *      AccessControl contract. Each module has it's own access control context
 *      which it is able to freely manage.
 *
 *      The transaction execution and module management is copied from Gnosis
 *      Safe.
 *
 * @author byterocket
 */
abstract contract ModuleManager is
    IModuleManager,
    Initializable,
    ContextUpgradeable
{
    // @todo mp: Should be abstract?
    //--------------------------------------------------------------------------
    // Modifiers

    modifier __ModuleManager_onlyAuthorized() {
        if (!__ModuleManager_isAuthorized(msg.sender)) {
            revert("Not authorized");
        }
        _;
    }

    /// @notice Modifier to guarantee function is only callable by enabled
    ///         module.
    modifier onlyModule() {
        if (!isEnabledModule(_msgSender())) {
            revert Proposal__ModuleManager__OnlyCallableByModule();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Storage

    /// @dev Mapping of modules.
    ///
    /// @custom:invariant No modules added after initialization.
    mapping(address => bool) private _modules;

    /// @dev Mapping of modules and access control roles to accounts and
    ///      whether they holds that role.
    /// @dev module address => role => account address => bool.
    ///
    /// @custom:invariant Modules can only mutate own account roles.
    /// @custom:invariant Only modules can mutate not own account roles.
    /// @custom:invariant Account can always renounce own roles.
    /// @custom:invariant Roles only exist for enabled modules.
    mapping(address => mapping(bytes32 => mapping(address => bool))) private
        _moduleRoles;

    //--------------------------------------------------------------------------
    // Initializer

    function __ModuleManager_init(address[] calldata modules)
        internal
        onlyInitializing
    {
        __Context_init();

        // @todo mp: Change modules from address to IModules.
        //           This enables easier refactoring in future for "multi-modules".
        //           Or not???

        address module;
        for (uint i; i < modules.length; i++) {
            module = modules[i];

            if (module == address(0)) {
                revert Proposal__ModuleManager__InvalidModuleAddress();
            }

            if (_modules[module]) {
                revert Proposal__ModuleManager__ModuleAlreadyEnabled(module);
            }

            _modules[module] = true;
            emit ModuleEnabled(module);

            // @todo mp: Call into module to "register this proposal" as using
            //           that module instance?
            // This would make it possible to have "multi-modules".
            // One module contract that is an active module for infinite many
            // proposals by saving it's state on a per-proposal basis.
        }
    }

    //--------------------------------------------------------------------------
    // Internal Functions Implemented in Downstream Contract

    /// @dev Returns whether address `who` is authorized to mutate module
    ///      manager's state.
    /// @dev MUST be overriden by downstream contract.
    function __ModuleManager_isAuthorized(address who)
        internal
        view
        virtual
        returns (bool);

    //--------------------------------------------------------------------------
    // onlyAuthorized Functions

    function disableModule(address module)
        external
        __ModuleManager_onlyAuthorized
    {
        if (isEnabledModule(module)) {
            delete _modules[module];
            emit ModuleDisabled(module);
        }
    }

    //--------------------------------------------------------------------------
    // onlyModule Functions

    /// @inheritdoc IModuleManager
    function executeTxFromModule(
        address to,
        bytes memory data,
        Types.Operation operation
    )
        public
        override (IModuleManager)
        onlyModule
        returns (bool, bytes memory)
    {
        bool ok;
        bytes memory returnData;

        if (operation == Types.Operation.Call) {
            (ok, returnData) = to.call(data);
        } else {
            (ok, returnData) = to.delegatecall(data);
        }

        return (ok, returnData);
    }

    /// @inheritdoc IModuleManager
    function grantRole(bytes32 role, address account) public onlyModule {
        if (!hasRole(_msgSender(), role, account)) {
            _moduleRoles[_msgSender()][role][account] = true;
            emit ModuleRoleGranted(_msgSender(), role, account);
        }
    }

    /// @inheritdoc IModuleManager
    function revokeRole(bytes32 role, address account) public onlyModule {
        if (hasRole(_msgSender(), role, account)) {
            _moduleRoles[_msgSender()][role][account] = false;
            emit ModuleRoleRevoked(_msgSender(), role, account);
        }
    }

    //--------------------------------------------------------------------------
    // Public Mutating Functions

    /// @inheritdoc IModuleManager
    function renounceRole(address module, bytes32 role) public {
        if (hasRole(module, role, _msgSender())) {
            _moduleRoles[module][role][_msgSender()] = false;
            emit ModuleRoleRevoked(module, role, _msgSender());
        }
    }

    //--------------------------------------------------------------------------
    // Public View Functions

    /// @inheritdoc IModuleManager
    function hasRole(address module, bytes32 role, address account)
        public
        view
        returns (bool)
    {
        return isEnabledModule(module) && _moduleRoles[module][role][account];
    }

    // @todo mp: Getter for modules.

    /// @inheritdoc IModuleManager
    function isEnabledModule(address module)
        public
        view
        override (IModuleManager)
        returns (bool)
    {
        return _modules[module];
    }
}
