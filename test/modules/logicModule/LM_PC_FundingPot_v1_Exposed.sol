// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal
import {LM_PC_FundingPot_v1} from
    "src/modules/logicModule/LM_PC_FundingPot_v1.sol";

// Access Mock of the PP_FundingPot_v1 contract for Testing.
contract LM_PC_FundingPot_v1_Exposed is LM_PC_FundingPot_v1 {
    // Use the `exposed_` prefix for functions to expose internal contract for
    // testing.

    function exposed_checkForFundingPotAdminRole(address admin_)
        external
        view
        returns (bool)
    {
        return _checkForFundingPotAdminRole(admin_);
    }
}
