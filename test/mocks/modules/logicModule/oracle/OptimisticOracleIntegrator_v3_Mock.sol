// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Dependencies
import {Module_v2} from "src/modules/base/Module_v2.sol";

// Internal Interfaces
import {IOrchestrator_v2} from
    "src/orchestrator/interfaces/IOrchestrator_v2.sol";

import {
    OptimisticOracleIntegrator_v3,
    IOptimisticOracleIntegrator_v3
} from
    "@lm/abstracts/oracleIntegrations/UMA_OptimisticOracleV3/OptimisticOracleIntegrator_v3.sol";

// External Dependencies
import {OptimisticOracleV3CallbackRecipientInterface} from
    "@lm/abstracts/oracleIntegrations/UMA_OptimisticOracleV3/optimistic-oracle-v3/interfaces/OptimisticOracleV3CallbackRecipientInterface.sol";
import {OptimisticOracleV3Interface} from
    "@lm/abstracts/oracleIntegrations/UMA_OptimisticOracleV3/optimistic-oracle-v3/interfaces/OptimisticOracleV3Interface.sol";
import {ClaimData} from
    "@lm/abstracts/oracleIntegrations/UMA_OptimisticOracleV3/optimistic-oracle-v3/ClaimData.sol";

contract OptimisticOracleIntegrator_v3_Mock is OptimisticOracleIntegrator_v3 {
    function assertionResolvedCallback(
        bytes32 assertionId,
        bool assertedTruthfully
    ) public override {
        super.assertionResolvedCallback(assertionId, assertedTruthfully);
    }

    function assertionDisputedCallback(bytes32 assertionId) public override {
        // Do nothing
    }
}
