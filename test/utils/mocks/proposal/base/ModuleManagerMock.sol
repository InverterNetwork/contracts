// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies
import {ModuleManager, Types} from "src/proposal/base/ModuleManager.sol";

contract ModuleManagerMock is ModuleManager {
    function init(address[] calldata modules) external initializer {
        __ModuleManager_init(modules);
    }

    // Note that the `initializer` modifier is missing.
    function reinit(address[] calldata modules) external {
        __ModuleManager_init(modules);
    }

    function disableModule(address module) external {
        __ModuleManager_disableModule(module);
    }
}
