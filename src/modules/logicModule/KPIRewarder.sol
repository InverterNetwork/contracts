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

    /*
    Tranche Example:
    trancheValues = [10000, 20000, 30000]
    trancheRewards = [100, 200, 100]
    continuous = false
     ->   if KPI is 12345, reward is 100 for the tanche [0-10000]
     ->   if KPI is 32198, reward is 400 for the tanches [0-10000, 10000-20000 and 20000-30000]

    if continuous = true
    ->    if KPI is 15000, reward is 200 for the tanches [100% 0-10000, 50% * 10000-15000]
    ->    if KPI is 25000, reward is 350 for the tanches [100% 0-10000, 100% 10000-20000, 50% 20000-30000]

    */
    struct KPI {
        uint creationTime; // timestamp the KPI was created // 
        uint numOfTranches; // number of tranches the KPI is divided into
        bool continuous; // should the tranche rewards be distributed continuously or in steps
        uint[] trancheValues; // The value at which a tranche ends
        uint[] trancheRewards; // The rewards to be dsitributed at completion of each tranche
    }

    struct Assertion {
        uint creationTime; // timestamp the assertion was created
        uint assertedValue; // the value that was asserted
        uint KpiToUse; // the KPI to be used for distribution once the assertion confirms
        // TODO: Necessary Data for UMA
    }

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