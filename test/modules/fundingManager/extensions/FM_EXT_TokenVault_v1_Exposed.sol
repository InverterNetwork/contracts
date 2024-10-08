// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {FM_EXT_TokenVault_v1} from "@fm/extensions/FM_EXT_TokenVault_v1.sol";

contract FM_EXT_TokenVault_v1_Exposed is FM_EXT_TokenVault_v1 {
    function exposed_onlyValidAmount(uint amt_) external pure {
        _onlyValidAmount(amt_);
    }
}
