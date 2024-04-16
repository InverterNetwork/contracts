// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies
import {
    ModuleManager,
    IModuleManager
} from "src/orchestrator/base/ModuleManager.sol";

import {IModuleFactory} from "src/factories/IModuleFactory.sol";

contract ModuleManagerMock is ModuleManager {
    mapping(address => bool) private _authorized;

    bool private _allAuthorized;

    IModuleFactory private _moduleFactory;

    constructor(address _trustedForwarder) ModuleManager(_trustedForwarder) {}

    function __ModuleManager_setIsAuthorized(address who, bool to) external {
        _authorized[who] = to;
    }

    function __ModuleManager_setAllAuthorized(bool to) external {
        _allAuthorized = to;
    }

    function init(address moduleFactory, address[] calldata modules)
        external
        initializer
    {
        if (moduleFactory == address(0)) {
            __ModuleManager_init(address(this), modules);
        } else {
            __ModuleManager_init(moduleFactory, modules);
        }
    }

    // Note that the `initializer` modifier is missing.
    function initNoInitializer(
        address moduleFactory,
        address[] calldata modules
    ) external {
        if (moduleFactory == address(0)) {
            __ModuleManager_init(address(this), modules);
        } else {
            __ModuleManager_init(moduleFactory, modules);
        }
    }

    function __ModuleManager_isAuthorized(address who)
        internal
        view
        override(ModuleManager)
        returns (bool)
    {
        return _authorized[who] || _allAuthorized;
    }

    // This is a function from the ModuleFactory.
    // It has been added here, as we don't always deploy
    // the factory during testing with the mocks, depending on
    // the circumstance. In that case (factory is address zero)
    // we just answer the call with the correct address.
    function getOrchestratorOfProxy(address module)
        external
        view
        returns (address)
    {
        if (address(_moduleFactory) == address(0)) {
            return msg.sender;
        }
        return _moduleFactory.getOrchestratorOfProxy(module);
    }
}
