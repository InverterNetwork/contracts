// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// Internal Dependencies
import {PP_Template_v1} from "src/templates/modules/PP_Template_v1.sol";

// Mock of the PP_Template_v1 contract for testing
contract PP_Template_v1_Exposed is PP_Template_v1 {
    // Use the `exposed_` prefix for functions to expose internal contract for testing
    function exposed_setPayoutAmountMultiplier(uint newPayoutAmountMultiplier_)
        external
    {
        _setPayoutAmountMultiplier(newPayoutAmountMultiplier_);
    }
}
