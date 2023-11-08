// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

// Internal Dependencies
import {Module} from "src/modules/base/Module.sol";

// Internal Interfaces
import {IOrchestrator} from "src/orchestrator/IOrchestrator.sol";

import {
    OptimisticOracleIntegrator,
    IOptimisticOracleIntegrator
} from "src/modules/logicModule/oracle/OptimisticOracleIntegrator.sol";

// External Dependencies
import {OptimisticOracleV3CallbackRecipientInterface} from
    "src/modules/logicModule/oracle/optimistic-oracle-v3/interfaces/OptimisticOracleV3CallbackRecipientInterface.sol";
import {OptimisticOracleV3Interface} from
    "src/modules/logicModule/oracle/optimistic-oracle-v3/interfaces/OptimisticOracleV3Interface.sol";
import {ClaimData} from
    "src/modules/logicModule/oracle/optimistic-oracle-v3/ClaimData.sol";

import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

contract OptimisticOracleIntegratorMock is OptimisticOracleIntegrator {
    // TODO: If we end up removing Module inheritance in Mixin, reintroduce it here.

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
