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

    constructor(address _trustedForwarder)
        ModuleManagerBase_v1(_trustedForwarder)
    {}

    function __ModuleManager_setIsAuthorized(address who, bool to) external {
        _authorized[who] = to;
    }

    function __ModuleManager_setAllAuthorized(bool to) external {
        _allAuthorized = to;
    }

    function init(address[] calldata modules) external initializer {
        __ModuleManager_init(modules);
    }

    // Note that the `initializer` modifier is missing.
    function initNoInitializer(address[] calldata modules) external {
        __ModuleManager_init(modules);
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
