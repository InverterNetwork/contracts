// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies
import {Types} from "src/common/Types.sol";

// Internal Interfaces
import {IModuleManager} from "src/interfaces/IModuleManager.sol";

contract ModuleManagerMock is IModuleManager {
    function executeTxFromModule(
        address to,
        bytes memory data,
        Types.Operation operation
    ) external returns (bytes memory) {
        return bytes("");
    }

    function isEnabledModule(address module) external returns (bool) {
        return false;
    }
}
