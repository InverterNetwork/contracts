// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import {LM_Oracle_Permissioned_v2} from "@lm/LM_Oracle_Permissioned_v2.sol";

contract LM_Oracle_Permissioned_v2_Exposed is LM_Oracle_Permissioned_v2 {
    function exposed_setIssuancePrice(uint price_) public {
        _setIssuancePrice(price_);
    }

    function exposed_setRedemptionPrice(uint price_) public {
        _setRedemptionPrice(price_);
    }
}
