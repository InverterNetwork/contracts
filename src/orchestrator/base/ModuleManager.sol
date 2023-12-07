// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

// External Dependencies
import {ContextUpgradeable} from "@oz-up/utils/ContextUpgradeable.sol";
import {Initializable} from "@oz-up/proxy/utils/Initializable.sol";
import {ERC165} from "@oz/utils/introspection/ERC165.sol";

// Interfaces
import {IModuleManager} from "src/orchestrator/base/IModuleManager.sol";

/**
 * @title Module Manager
 *
 * @dev A contract to manage modules that can execute transactions via this
 *      contract and manage own role-based access control mechanisms.
 *
 *      The role-based access control mechanism is based on OpenZeppelin's
 *      AccessControl contract. Each module has it's own access control context
 *      which it is able to freely manage.
 *
 *      The transaction execution and module management is copied from Gnosis
 *      Safe's [ModuleManager](https://github.com/safe-global/safe-contracts/blob/main/contracts/base/ModuleManager.sol).
 *
 * @author Adapted from Gnosis Safe
 * @author Inverter Network
 */
abstract contract ModuleManager is
    IModuleManager,
    Initializable,
    ContextUpgradeable,
    ERC165
{

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC165)
        returns (bool)
    {
        bytes4 interfaceId_IModuleManager = type(IModuleManager).interfaceId;
        return interfaceId == interfaceId_IModuleManager
            || super.supportsInterface(interfaceId);
    }

    //--------------------------------------------------------------------------
    // Modifiers

    modifier __ModuleManager_onlyAuthorized() {
        if (!__ModuleManager_isAuthorized(_msgSender())) {
            revert Orchestrator__ModuleManager__CallerNotAuthorized();
        }
        _;
    }

    modifier onlyModule() {
        if (!isModule(_msgSender())) {
            revert Orchestrator__ModuleManager__OnlyCallableByModule();
        }
        _;
    }

    modifier validModule(address module) {
        _ensureValidModule(module);
        _;
    }

    modifier isModule_(address module) {
        if (!isModule(module)) {
            revert Orchestrator__ModuleManager__IsNotModule();
        }
        _;
    }

    modifier isNotModule(address module) {
        _ensureNotModule(module);
        _;
    }

    modifier moduleLimitNotExceeded() {
        if (_modules.length >= MAX_MODULE_AMOUNT) {
            revert Orchestrator__ModuleManager__ModuleAmountOverLimits();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Constants

    /// @dev Marks the maximum amount of Modules a Orchestrator can have to avoid out-of-gas risk.
    uint private constant MAX_MODULE_AMOUNT = 128;

    //--------------------------------------------------------------------------
    // Storage

    /// @dev List of modules.
    address[] private _modules;

    mapping(address => bool) _isModule;

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

        address module;
        uint len = modules.length;

        // Check that the initial list of Modules doesn't exceed the max amount
        // The subtraction by 3 is to ensure enough space for the compulsory modules: fundingManager, authorizer and paymentProcessor
        if (len > (MAX_MODULE_AMOUNT - 3)) {
            revert Orchestrator__ModuleManager__ModuleAmountOverLimits();
        }

        for (uint i; i < len; ++i) {
            module = modules[i];

            __ModuleManager_addModule(module);
        }
    }

    function __ModuleManager_addModule(address module)
        internal
        isNotModule(module)
        validModule(module)
    {
        _commitAddModule(module);
    }

    //--------------------------------------------------------------------------
    // Internal Functions Implemented in Downstream Contract

    /// @dev Returns whether address `who` is authorized to mutate module
    ///      manager's state.
    /// @dev MUST be overriden in downstream contract.
    function __ModuleManager_isAuthorized(address who)
        internal
        view
        virtual
        returns (bool);

    //--------------------------------------------------------------------------
    // Public View Functions

    /// @inheritdoc IModuleManager
    function isModule(address module)
        public
        view
        override(IModuleManager)
        returns (bool)
    {
        return _isModule[module];
    }

    /// @inheritdoc IModuleManager
    function listModules() public view returns (address[] memory) {
        return _modules;
    }

    /// @inheritdoc IModuleManager
    function modulesSize() external view returns (uint8) {
        return uint8(_modules.length);
    }

    //--------------------------------------------------------------------------
    // onlyOrchestratorOwner Functions

    /// @inheritdoc IModuleManager
    function addModule(address module)
        public
        __ModuleManager_onlyAuthorized
        moduleLimitNotExceeded
        isNotModule(module)
        validModule(module)
    {
        _commitAddModule(module);
    }

    /// @inheritdoc IModuleManager
    function removeModule(address module)
        public
        __ModuleManager_onlyAuthorized
        isModule_(module)
    {
        _commitRemoveModule(module);
    }

    //--------------------------------------------------------------------------
    // onlyModule Functions

    /// @inheritdoc IModuleManager
    function executeTxFromModule(address to, bytes memory data)
        external
        override(IModuleManager)
        onlyModule
        returns (bool, bytes memory)
    {
        bool ok;
        bytes memory returnData;

        (ok, returnData) = to.call(data);

        return (ok, returnData);
    }

    //--------------------------------------------------------------------------
    // Private Functions

    /// @dev Expects `module` to be valid module address.
    /// @dev Expects `module` to not be enabled module.
    function _commitAddModule(address module) private {
        // Add address to _modules list.
        _modules.push(module);
        _isModule[module] = true;
        emit ModuleAdded(module);
    }

    /// @dev Expects address arguments to be consecutive in the modules list.
    /// @dev Expects address `module` to be enabled module.
    function _commitRemoveModule(address module) private {
        // Note that we cannot delete the module's roles configuration.
        // This means that in case a module is disabled and then re-enabled,
        // its roles configuration is the same as before.
        // Note that this could potentially lead to security issues!

        //Unordered removal
        address[] memory modulesSearchArray = _modules;

        uint moduleIndex = type(uint).max;

        uint length = modulesSearchArray.length;
        for (uint i; i < length; i++) {
            if (modulesSearchArray[i] == module) {
                moduleIndex = i;
                break;
            }
        }

        // Move the last element into the place to delete
        _modules[moduleIndex] = _modules[length - 1];
        // Remove the last element
        _modules.pop();

        _isModule[module] = false;

        emit ModuleRemoved(module);
    }

    function _ensureValidModule(address module) private view {
        if (module == address(0) || module == address(this)) {
            revert Orchestrator__ModuleManager__InvalidModuleAddress();
        }
    }

    function _ensureNotModule(address module) private view {
        if (isModule(module)) {
            revert Orchestrator__ModuleManager__IsModule();
        }
    }
}
