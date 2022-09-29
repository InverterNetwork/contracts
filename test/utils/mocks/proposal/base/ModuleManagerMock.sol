// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Dependencies
import {Initializable} from "@oz-up/proxy/utils/Initializable.sol";

// Internal Dependencies
import {ModuleManager, Types} from "src/proposal/base/ModuleManager.sol";

contract ModuleManagerMock is ModuleManager, Initializable {
    function init(address[] calldata modules) external initializer {
        __ModuleManager_init(modules);
    }
}
