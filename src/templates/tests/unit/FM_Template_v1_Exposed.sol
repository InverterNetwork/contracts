// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {FM_Template_v1} from "src/templates/modules/FM_Template_v1.sol";

// Access Mock of the FM_Template_v1 contract for Testing.
contract FM_Template_v1_Exposed is FM_Template_v1 {
    // Use the `exposed_` prefix for functions to expose internal functions for testing purposes only.

    function exposed_validateOrchestratorTokenTransfer(
        address to_,
        uint amount_
    ) external view {
        return _validateOrchestratorTokenTransfer(to_, amount_);
    }
}
