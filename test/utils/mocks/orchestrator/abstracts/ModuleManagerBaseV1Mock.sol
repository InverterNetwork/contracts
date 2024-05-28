// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies
import {
    ModuleManagerBase_v1,
    IModuleManagerBase_v1
} from "src/orchestrator/abstracts/ModuleManagerBase_v1.sol";

contract ModuleManagerBaseV1Mock is ModuleManagerBase_v1 {
    mapping(address => bool) private _authorized;

    bool private _allAuthorized;
    bool private _registeredProxyCheckShouldFail;

    constructor(address _trustedForwarder)
        ModuleManagerBase_v1(_trustedForwarder)
    {}

    function __ModuleManager_setIsAuthorized(address who, bool to) external {
        _authorized[who] = to;
    }

    function __ModuleManager_setAllAuthorized(bool to) external {
        _allAuthorized = to;
    }

    function __ModuleManager_setRegisteredProxyCheckShouldFail(bool to) external {
        _registeredProxyCheckShouldFail = to;
    }

    function init(address, /*moduleManager*/ address[] calldata modules)
        external
        initializer
    {
        __ModuleManager_init(address(this), modules);
    }

    // Note that the `initializer` modifier is missing.
    function initNoInitializer(
        address, /*moduleManager*/
        address[] calldata modules
    ) external {
        __ModuleManager_init(address(this), modules);
    }

    function unmockedInit(address moduleManager, address[] calldata modules)
        external
        initializer
    {
        __ModuleManager_init(moduleManager, modules);
    }

    function getOrchestratorOfProxy(address /*proxy*/)
        external
        view
        returns (address)
    {
        return _registeredProxyCheckShouldFail ? address(0) : address(this);
    }

    function call_cancelModuleUpdate(address module) external {
        _cancelModuleUpdate(module);
    }

    function call_initiateAddModuleWithTimelock(address module) external {
        _initiateAddModuleWithTimelock(module);
    }

    function call_initiateRemoveModuleWithTimelock(address module) external {
        _initiateRemoveModuleWithTimelock(module);
    }

    function call_executeAddModule(address module) external {
        _executeAddModule(module);
    }

    function call_executeRemoveModule(address module) external {
        _executeRemoveModule(module);
    }

    function __ModuleManager_isAuthorized(address who)
        internal
        view
        override(ModuleManagerBase_v1)
        returns (bool)
    {
        return _authorized[who] || _allAuthorized;
    }
}
