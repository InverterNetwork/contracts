// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Interfaces
import {IModuleManagerBase_v1} from
    "src/orchestrator/interfaces/IModuleManagerBase_v1.sol";
import {IModuleFactory_v1} from "src/factories/OrchestratorFactory_v1.sol";
import {IModule_v1} from "src/modules/base/IModule_v1.sol";

// External Dependencies
import {ERC2771ContextUpgradeable} from
    "@oz-up/metatx/ERC2771ContextUpgradeable.sol";
import {
    Initializable,
    ERC165Upgradeable
} from "@oz-up/utils/introspection/ERC165Upgradeable.sol";

/**
 * @title   ModuleManagerBase
 *
 * @dev     A contract to manage Inverter Network modules. It allows for adding and
 *          removing modules in a local registry for reference. Additional functionality
 *          includes the execution of calls from this contract.
 *
 *          The transaction execution and module management is copied from Gnosis
 *          Safe's [ModuleManager](https://github.com/safe-global/safe-contracts/blob/main/contracts/base/ModuleManager.sol).
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
 *
 * @author  Inverter Network
 *          Adapted from Gnosis Safe
 */
abstract contract ModuleManagerBase_v1 is
    IModuleManagerBase_v1,
    Initializable,
    ERC2771ContextUpgradeable,
    ERC165Upgradeable
{
    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC165Upgradeable)
        returns (bool)
    {
        return interfaceId == type(IModuleManagerBase_v1).interfaceId
            || super.supportsInterface(interfaceId);
    }

    //--------------------------------------------------------------------------
    // Modifiers

    /// @dev    Modifier to guarantee function is only callable by authorized address.
    modifier __ModuleManager_onlyAuthorized() {
        if (!__ModuleManager_isAuthorized(_msgSender())) {
            revert ModuleManagerBase__CallerNotAuthorized();
        }
        _;
    }

    /// @dev    Modifier to guarantee that the caller is a module.
    modifier onlyModule() {
        if (!isModule(_msgSender())) {
            revert ModuleManagerBase__OnlyCallableByModule();
        }
        _;
    }

    /// @dev    Modifier to guarantee that the given module is a valid module.
    modifier validModule(address module) {
        _ensureValidModule(module);
        _;
    }

    /// @dev    Modifier to guarantee that the given module is a registered module.
    modifier isModule_(address module) {
        if (!isModule(module)) {
            revert ModuleManagerBase__IsNotModule();
        }
        _;
    }

    /// @dev    Modifier to guarantee that the given module is not a registered module.
    modifier isNotModule(address module) {
        _ensureNotModule(module);
        _;
    }

    /// @dev    Modifier to guarantee that the number of modules is not exceeded.
    modifier moduleLimitNotExceeded() {
        if (_modules.length >= MAX_MODULE_AMOUNT) {
            revert ModuleManagerBase__ModuleAmountOverLimits();
        }
        _;
    }

    /// @dev    Modifier to guarantee that the given module is not already being updated.
    modifier updatingModuleAlreadyStarted(address _module) {
        // if timelock not active
        if (!moduleAddressToTimelock[_module].timelockActive) {
            revert ModuleManagerBase__ModuleUpdateAlreadyStarted();
        }
        _;
    }

    /// @dev    Modifier to guarantee that the timelock for the given module is expired.
    modifier timelockExpired(address _module) {
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

    /// @dev	Marks the maximum amount of Modules a {Orchestrator_v1} can have to avoid out-of-gas risk.
    uint private constant MAX_MODULE_AMOUNT = 128;
    /// @dev	Timelock used between initiating adding or removing a module and executing it.
    uint public constant MODULE_UPDATE_TIMELOCK = 72 hours;

    //--------------------------------------------------------------------------
    // Storage

    /// @dev	{ModuleFactory_v1}.
    address public moduleFactory;

    /// @dev	List of modules.
    address[] private _modules;

    /// @dev	Mapping to keep track of whether a module is used in the {Orchestrator_v1}
    ///         address => isModule.
    mapping(address => bool) private _isModule;

    /// @dev	Mapping to keep track of active timelocks for updating modules
    ///         module => timelock.
    mapping(address module => ModuleUpdateTimelock timelock) public
        moduleAddressToTimelock;

    /// @dev	Storage gap for future upgrades.
    uint[50] private __gap;

    //--------------------------------------------------------------------------
    // Initializer

    constructor(address _trustedForwarder)
        ERC2771ContextUpgradeable(_trustedForwarder)
    {}

    /// @notice Initialization function.
    /// @dev	Only callable during initialization.
    /// @param _moduleFactory The address of the module factory.
    /// @param modules The addresses of the modules used in the orchestrator.
    function __ModuleManager_init(
        address _moduleFactory,
        address[] calldata modules
    ) internal onlyInitializing {
        if (_moduleFactory == address(0)) {
            revert ModuleManagerBase__ModuleFactoryInvalid();
        }
        moduleFactory = _moduleFactory;

        address module;
        uint len = modules.length;

        // Check that the initial list of Modules doesn't exceed the max amount
        // The subtraction by 3 is to ensure enough space for the compulsory modules: fundingManager,
        // authorizer and paymentProcessor
        if (len > (MAX_MODULE_AMOUNT - 3)) {
            revert ModuleManagerBase__ModuleAmountOverLimits();
        }

        for (uint i; i < len; ++i) {
            module = modules[i];

            __ModuleManager_addModule(module);
        }
    }

    /// @notice Adds address `module` as module.
    /// @param module The module address to add.
    function __ModuleManager_addModule(address module)
        internal
        isNotModule(module)
        validModule(module)
        moduleLimitNotExceeded
    {
        _commitAddModule(module);
    }

    //--------------------------------------------------------------------------
    // Internal Functions Implemented in Downstream Contract

    /// @dev	Returns whether address `who` is authorized to mutate module
    ///         manager's state.
    /// @dev	MUST be overridden in downstream contract.
    /// @param who The address to check.
    /// @return True if the address is authorized, false otherwise.
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
    // onlyOrchestratorAdmin Functions

    /// @notice Cancels an initiated update for a module.
    /// @dev	Only callable by authorized address.
    /// @dev	Fails if module update has not been initiated.
    /// @param module The module address to remove.
    function _cancelModuleUpdate(address module)
        internal
        __ModuleManager_onlyAuthorized
        updatingModuleAlreadyStarted(module)
    {
        moduleAddressToTimelock[module].timelockActive = false;
        emit ModuleUpdateCanceled(module);
    }

    /// @notice Initiates adding of a module to the {Orchestrator_v1} on a timelock.
    /// @dev	Only callable by authorized address.
    /// @dev	Fails of adding module exeeds max modules limit.
    /// @dev	Fails if address invalid or address already added as module.
    /// @param module The module address to add.
    function _initiateAddModuleWithTimelock(address module)
        internal
        __ModuleManager_onlyAuthorized
        isNotModule(module)
        validModule(module)
    {
        _startModuleUpdateTimelock(module);
    }

    /// @notice Initiates removing of a module from the {Orchestrator_v1} on a timelock.
    /// @dev	Only callable by authorized address.
    /// @dev	Fails if address not added as module.
    /// @param module The module address to remove.
    function _initiateRemoveModuleWithTimelock(address module)
        internal
        __ModuleManager_onlyAuthorized
        isModule_(module)
    {
        _startModuleUpdateTimelock(module);
    }

    /// @notice Executes adding of a module to the {Orchestrator_v1}.
    /// @dev	Only callable by authorized address.
    /// @dev	Fails if adding of module has not been initiated.
    /// @dev	Fails if timelock has not been expired yet.
    /// @param module The module address to add.
    function _executeAddModule(address module)
        internal
        __ModuleManager_onlyAuthorized
        updatingModuleAlreadyStarted(module)
        timelockExpired(module)
    {
        // set timelock to inactive
        moduleAddressToTimelock[module].timelockActive = false;

        __ModuleManager_addModule(module);
    }

    /// @notice Executes removing of a module from the {Orchestrator_v1}.
    /// @dev	Only callable by authorized address.
    /// @dev	Fails if removing of module has not been initiated.
    /// @dev	Fails if timelock has not been expired yet.
    /// @param module The module address to remove.
    function _executeRemoveModule(address module)
        internal
        __ModuleManager_onlyAuthorized
        updatingModuleAlreadyStarted(module)
        timelockExpired(module)
    {
        // set timelock to inactive
        moduleAddressToTimelock[module].timelockActive = false;

        _commitRemoveModule(module);
    }

    //--------------------------------------------------------------------------
    // Private Functions

    /// @dev	Expects `module` to be valid module address.
    /// @dev	Expects `module` to not be enabled module.
    /// @param module The module address to add.
    function _commitAddModule(address module) internal {
        // Add address to _modules list.
        _modules.push(module);
        _isModule[module] = true;
        emit ModuleAdded(module);
    }

    /// @dev	Expects address arguments to be consecutive in the modules list.
    /// @dev	Expects address `module` to be enabled module.
    /// @param module The module address to remove.
    function _commitRemoveModule(address module) private {
        // Note that we cannot delete the module's roles configuration.
        // This means that in case a module is disabled and then re-enabled,
        // its roles configuration is the same as before.
        // Note that this could potentially lead to security issues!

        // Unordered removal
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

    /// @dev	Ensures that the given module is a valid module.
    /// @dev	Reverts if the module is invalid.
    /// @param module The module address to check.
    function _ensureValidModule(address module) private view {
        if (
            module.code.length == 0 || module == address(0)
                || module == address(this)
                || !ERC165Upgradeable(module).supportsInterface(
                    type(IModule_v1).interfaceId
                )
        ) {
            revert ModuleManagerBase__InvalidModuleAddress();
        }
        if (
            IModuleFactory_v1(moduleFactory).getOrchestratorOfProxy(module)
                != address(this)
        ) {
            revert ModuleManagerBase__ModuleNotRegistered();
        }
    }

    /// @dev	Ensures that the given module is not a registered module.
    /// @dev	Reverts if the module is registered.
    /// @param module The module address to check.
    function _ensureNotModule(address module) private view {
        if (isModule(module)) {
            revert ModuleManagerBase__IsModule();
        }
    }

    /// @dev	Starts the timelock for the given module.
    /// @param _module The module address to start the timelock for.
    function _startModuleUpdateTimelock(address _module) internal {
        moduleAddressToTimelock[_module] =
            ModuleUpdateTimelock(true, block.timestamp + MODULE_UPDATE_TIMELOCK);

        emit ModuleTimelockStarted(
            _module, block.timestamp + MODULE_UPDATE_TIMELOCK
        );
    }

    // IERC2771ContextUpgradeable
    // @dev Because we want to expose the isTrustedForwarder function from the ERC2771ContextUpgradeable
    //      Contract in the IOrchestrator_v1 we have to override it here as the original openzeppelin version
    //      doesnt contain a interface that we could use to expose it.

    /// @inheritdoc IModuleManagerBase_v1
    function isTrustedForwarder(address forwarder)
        public
        view
        virtual
        override(IModuleManagerBase_v1, ERC2771ContextUpgradeable)
        returns (bool)
    {
        return ERC2771ContextUpgradeable.isTrustedForwarder(forwarder);
    }

    /// @inheritdoc IModuleManagerBase_v1
    function trustedForwarder()
        public
        view
        virtual
        override(IModuleManagerBase_v1, ERC2771ContextUpgradeable)
        returns (address)
    {
        return ERC2771ContextUpgradeable.trustedForwarder();
    }
}
