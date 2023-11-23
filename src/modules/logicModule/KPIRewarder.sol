// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

// Internal Dependencies
import {Module} from "src/modules/base/Module.sol";

// Internal Interfaces
import {IOrchestrator} from "src/orchestrator/IOrchestrator.sol";


import {IStakingManager, StakingManager} from "./StakingManager.sol";
import {IOptimisticOracleIntegrator, OptimisticOracleIntegrator} from "./oracle/OptimisticOracleIntegrator.sol";

contract KPIRewarder is StakingManager, OptimisticOracleIntegrator {


    bytes32 public constant ASSERTION_MANAGER = "ASSERTION_MANAGER";

    /// @inheritdoc Module
    function init(
        IOrchestrator orchestrator_,
        Metadata memory metadata,
        bytes memory configData
    ) external virtual override(StakingManager, OptimisticOracleIntegrator) initializer {
        __Module_init(orchestrator_, metadata);

    }

    // Assertion Manager functions:
    function setAssertion() external onlyModuleRole(ASSERTION_MANAGER) {
        // TODO stores the assertion that will be posted to the Optimistic Oracle
        // needs to store locally the numeric value to be asserted. the amount to distribute and the distribution time
    }

    function postAssertion() external onlyModuleRole(ASSERTION_MANAGER) {
        // TODO posts the assertion to the Optimistic Oracle
        // Takes the payout from the FundingManager
    }

    // Owner functions:

    function setKPI() external onlyOrchestratorOwner() {
        // TODO sets the KPI that will be used to calculate the reward
        // Should it be only the owner, or do we create a separate role for this?
        // Also should we set more than one KPI in one step?
    }

    // StakingManager Overrides:

        /// @inheritdoc IStakingManager
    function stake(uint amount) external nonReentrant validAmount(amount) override {
       // TODO implement the delayed stake
    }


    // Optimistic Oracle Overrides:

    /// @inheritdoc IOptimisticOracleIntegrator
    /// @dev This updates status on local storage (or deletes the assertion if it was deemed false). Any additional functionalities can be appended by the inheriting contract.
    function assertionResolvedCallback(
        bytes32 assertionId,
        bool assertedTruthfully
    ) public override {
        // TODO
        // If resolves to true, add rewards to staking contract
        // If resolves to false, return payout funds to funding manager
    }

    /// @inheritdoc IOptimisticOracleIntegrator
    /// @dev This OptimisticOracleV3 callback function needs to be defined so the OOv3 doesn't revert when it tries to call it.
    function assertionDisputedCallback(bytes32 assertionId) public override{
        //TODO
 
    }

}