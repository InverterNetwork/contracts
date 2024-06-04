// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Interfaces
import {IModuleManagerBase_v1} from
    "src/orchestrator/interfaces/IModuleManagerBase_v1.sol";
import {IModule_v1} from "src/modules/base/IModule_v1.sol";

//External Dependencies
import {ERC2771Context} from "@oz/metatx/ERC2771Context.sol";
import {Initializable} from "@oz-up/proxy/utils/Initializable.sol";
import {ERC165} from "@oz/utils/introspection/ERC165.sol";

/**
 * @title   ModuleManagerBase_v1: Module Manager Base v1 for Inverter Network
 *
 * @dev     A contract to manage Inverter Network modules. It allows for adding and
 *          removing modules in a local registry for reference. Additional functionality
 *          includes the execution of calls from this contract.
 *
 *          The transaction execution and module management is copied from Gnosis
 *          Safe's [ModuleManager](https://github.com/safe-global/safe-contracts/blob/main/contracts/base/ModuleManager.sol).
 *
 * @author  Adapted from Gnosis Safe
 * @author  Inverter Network
 */
abstract contract ModuleManagerBase_v1 is
    IModuleManagerBase_v1,
    Initializable,
    ERC2771Context,
    ERC165
{
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC165)
        returns (bool)
    {
        return interfaceId == type(IModuleManagerBase_v1).interfaceId
            || super.supportsInterface(interfaceId);
    }

    //--------------------------------------------------------------------------
    // Modifiers

    modifier __ModuleManager_onlyAuthorized() {
        if (!__ModuleManager_isAuthorized(_msgSender())) {
            revert ModuleManagerBase__CallerNotAuthorized();
        }
        _;
    }

    modifier onlyModule() {
        if (!isModule(_msgSender())) {
            revert ModuleManagerBase__OnlyCallableByModule();
        }
        _;
    }

    modifier validModule(address module) {
        _ensureValidModule(module);
        _;
    }

    modifier isModule_(address module) {
        if (!isModule(module)) {
            revert ModuleManagerBase__IsNotModule();
        }
        _;
    }

    modifier isNotModule(address module) {
        _ensureNotModule(module);
        _;
    }

    modifier moduleLimitNotExceeded() {
        if (_modules.length >= MAX_MODULE_AMOUNT) {
            revert ModuleManagerBase__ModuleAmountOverLimits();
        }
        _;
    }

    modifier updatingModuleAlreadyStarted(address _module) {
        //if timelock not active
        if (!moduleAddressToTimelock[_module].timelockActive) {
            revert ModuleManagerBase__ModuleUpdateAlreadyStarted();
        }
        _;
    }

    modifier whenTimelockExpired(address _module) {
        uint timeUntil = moduleAddressToTimelock[_module].timelockUntil;
        if (block.timestamp < timeUntil) {
            revert ModuleManagerBase__ModuleUpdateTimelockStillActive(
                _module, timeUntil
            );
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Constants

    /// @dev Marks the maximum amount of Modules a Orchestrator_v1 can have to avoid out-of-gas risk.
    uint private constant MAX_MODULE_AMOUNT = 128;
    /// @dev Timelock used between initiating adding or removing a module and executing it.
    uint public constant MODULE_UPDATE_TIMELOCK = 72 hours;

    //--------------------------------------------------------------------------
    // Storage

    /// @dev List of modules.
    address[] private _modules;

    mapping(address => bool) private _isModule;

    /// @dev Mapping to keep track of active timelocks for updating modules
    mapping(address module => ModuleUpdateTimelock timelock) public
        moduleAddressToTimelock;

    // Storage gap for future upgrades
    uint[50] private __gap;

    //--------------------------------------------------------------------------
    // Initializer

    constructor(address _trustedForwarder) ERC2771Context(_trustedForwarder) {}

    function __ModuleManager_init(address[] calldata modules)
        internal
        onlyInitializing
    {
        address module;
        uint len = modules.length;

        // Check that the initial list of Modules doesn't exceed the max amount
        // The subtraction by 3 is to ensure enough space for the compulsory modules: fundingManager, authorizer and paymentProcessor
        if (len > (MAX_MODULE_AMOUNT - 3)) {
            revert ModuleManagerBase__ModuleAmountOverLimits();
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

    /// @inheritdoc IModuleManagerBase_v1
    function isModule(address module)
        public
        view
        override(IModuleManagerBase_v1)
        returns (bool)
    {
        return _isModule[module];
    }

    /// @inheritdoc IModuleManagerBase_v1
    function listModules() public view returns (address[] memory) {
        return _modules;
    }

    /// @inheritdoc IModuleManagerBase_v1
    function modulesSize() external view returns (uint8) {
        return uint8(_modules.length);
    }

    //--------------------------------------------------------------------------
    // onlyOrchestratorOwner Functions

    function _cancelModuleUpdate(address module)
        internal
        __ModuleManager_onlyAuthorized
        updatingModuleAlreadyStarted(module)
    {
        moduleAddressToTimelock[module].timelockActive = false;
        emit ModuleUpdateCanceled(module);
    }

    function _initiateAddModuleWithTimelock(address module)
        internal
        __ModuleManager_onlyAuthorized
        moduleLimitNotExceeded
        isNotModule(module)
        validModule(module)
    {
        _startModuleUpdateTimelock(module);
    }

    function _initiateRemoveModuleWithTimelock(address module)
        internal
        __ModuleManager_onlyAuthorized
        isModule_(module)
    {
        _startModuleUpdateTimelock(module);
    }

    function _executeAddModule(address module)
        internal
        __ModuleManager_onlyAuthorized
        updatingModuleAlreadyStarted(module)
        whenTimelockExpired(module)
    {
        //set timelock to inactive
        moduleAddressToTimelock[module].timelockActive = false;

        _commitAddModule(module);
    }

    function _executeRemoveModule(address module)
        internal
        __ModuleManager_onlyAuthorized
        updatingModuleAlreadyStarted(module)
        whenTimelockExpired(module)
    {
        //set timelock to inactive
        moduleAddressToTimelock[module].timelockActive = false;

        _commitRemoveModule(module);
    }

    //--------------------------------------------------------------------------
    // onlyModule Functions

    /// @inheritdoc IModuleManagerBase_v1
    function executeTxFromModule(address to, bytes memory data)
        external
        virtual
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
    function _commitAddModule(address module) internal {
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
        if (
            module.code.length == 0 || module == address(0)
                || module == address(this)
                || !ERC165(module).supportsInterface(type(IModule_v1).interfaceId)
        ) {
            revert ModuleManagerBase__InvalidModuleAddress();
        }
    }

    function _ensureNotModule(address module) private view {
        if (isModule(module)) {
            revert ModuleManagerBase__IsModule();
        }
    }

    function _startModuleUpdateTimelock(address _module) internal {
        moduleAddressToTimelock[_module] =
            ModuleUpdateTimelock(true, block.timestamp + MODULE_UPDATE_TIMELOCK);

        emit ModuleTimelockStarted(
            _module, block.timestamp + MODULE_UPDATE_TIMELOCK
        );
    }

    // IERC2771Context
    // @dev Because we want to expose the isTrustedForwarder function from the ERC2771Context Contract in the IOrchestrator_v1
    // we have to override it here as the original openzeppelin version doesnt contain a interface that we could use to expose it.

    function isTrustedForwarder(address forwarder)
        public
        view
        virtual
        override(IModuleManagerBase_v1, ERC2771Context)
        returns (bool)
    {
        return ERC2771Context.isTrustedForwarder(forwarder);
    }

    function trustedForwarder()
        public
        view
        virtual
        override(IModuleManagerBase_v1, ERC2771Context)
        returns (address)
    {
        return ERC2771Context.trustedForwarder();
    }
}
