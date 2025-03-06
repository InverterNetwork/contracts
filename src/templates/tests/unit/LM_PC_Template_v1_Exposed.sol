// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal
import {LM_PC_Template_v1} from "src/templates/modules/LM_PC_Template_v1.sol";

// Access Mock of the PP_Template_v1 contract for Testing.
contract LM_PC_Template_v1_Exposed is LM_PC_Template_v1 {
    // Use the `exposed_` prefix for functions to expose internal functions for
    // testing.
    function exposed_ensureValidDepositAmount(uint amount_) external pure {
        _ensureValidDepositAmount(amount_);
    }
}
