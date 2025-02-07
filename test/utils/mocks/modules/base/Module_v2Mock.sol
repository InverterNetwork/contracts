// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {Module_v2} from "src/modules/base/Module_v2.sol";

contract Module_v2Mock is Module_v2 {
    uint public valueA;

    function doSmth(uint newValue) external restricted {
        valueA = newValue;
    }
}
