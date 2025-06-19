// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {FM_EXT_TokenVault_v2} from "@fm/extensions/FM_EXT_TokenVault_v2.sol";

contract FM_EXT_TokenVault_v2_Exposed is FM_EXT_TokenVault_v2 {
    function exposed_amountIsValid(uint amt_) external pure {
        _ensureAmountIsValid(amt_);
    }
}
