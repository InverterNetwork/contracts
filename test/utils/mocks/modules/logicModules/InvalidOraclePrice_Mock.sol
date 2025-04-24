// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

import "src/modules/base/Module_v1.sol";

contract InvalidOraclePrice_Mock is Module_v1 {
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata,
        bytes memory /* configData */
    ) public override(Module_v1) initializer {
        __Module_init(orchestrator_, metadata);
    }
}
