// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {Types} from "src/common/Types.sol";

interface IModuleManager {
    function executeTxFromModule(
        address to,
        bytes memory data,
        Types.Operation operation
    )
        external
        returns (bytes memory);

    function isActiveModule(address module) external returns (bool);
}
