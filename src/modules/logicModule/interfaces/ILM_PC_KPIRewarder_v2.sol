// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

interface ILM_PC_KPIRewarder_v2 {
    //--------------------------------------------------------------------------
    // Structs

    /// @notice A KPI to be used for reward distribution.
    /// @param  numOfTranches The number of tranches the KPI is divided into.
    /// @param  totalRewards The total rewards to be distributed.
    /// @param  continuous If the tranche rewards should be distributed continuously or in steps.
    /// @param  trancheValues The value at which each tranche ends.
    /// @param  trancheRewards The rewards to be distributed at completion of each tranche.
    struct KPI {
        uint numOfTranches; //
        uint totalRewards;
        bool continuous;
        uint[] trancheValues; //
        uint[] trancheRewards;
    }

    /// @notice The configuration of the reward round tied.
    /// @param  creationTime The timestamp the assertion was posted.
    /// @param  assertedValue The value that was asserted.
    /// @param  KpiToUse The KPI to be used for distribution once the assertion confirms.
    /// @param  distributed If the rewards have been distributed or not.
    struct RewardRoundConfiguration {
        uint creationTime; // timestamp the assertion was created
        uint assertedValue;
        uint KpiToUse;
        bool distributed;
    }

    //--------------------------------------------------------------------------
    // Errors

    /// @notice The KPI beinge created has either no tranches or too many.
    error Module__LM_PC_KPIRewarder_v2__InvalidTrancheNumber();

    /// @notice The number of tranches in the KPI does not match the number of rewards.
    error Module__LM_PC_KPIRewarder_v2__InvalidKPIValueLengths();

    /// @notice The values for the tranches are not in ascending order.
    error Module__LM_PC_KPIRewarder_v2__InvalidKPITrancheValues();

    /// @notice The KPI number is invalid.
    error Module__LM_PC_KPIRewarder_v2__InvalidKPINumber();

    /// @notice The Token used paying the bond cannot be the same that is being staked.
    error Module__LM_PC_KPIRewarder_v2__ModuleCannotUseStakingTokenAsBond();

    /// @notice An assertion can only by posted if the preceding one is resolved.
    error Module__LM_PC_KPIRewarder_v2__UnresolvedAssertionExists();

    /// @notice The user cannot stake while an assertion is unresolved.
    error Module__LM_PC_KPIRewarder_v2__CannotStakeWhenAssertionPending();

    /// @notice Callback received references non existent assertionId.
    error Module__LM_PC_KPIRewarder_v2__NonExistentAssertionId(
        bytes32 assertionId
    );

    /// @notice The assertion that is being removed was not stuck.
    error Module__LM_PC_KPIRewarder_v2__AssertionNotStuck(bytes32 assertionId);

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when a KPI is created.
    /// @param  KPI_Id The id of the KPI.
    /// @param  numOfTranches The number of tranches in the KPI.
    /// @param  totalKPIRewards The total rewards for the KPI.
    /// @param  continuous Whether the KPI is continuous or not.
    /// @param  trancheValues The values at which each tranche ends.
    /// @param  trancheRewards The rewards to be distributed at completion of each tranche.
    event KPICreated(
        uint indexed KPI_Id,
        uint numOfTranches,
        uint totalKPIRewards,
        bool continuous,
        uint[] trancheValues,
        uint[] trancheRewards
    );

    /// @notice Event emitted when a reward round is configured.
    /// @param  assertionId The id of the assertion.
    /// @param  creationTime The timestamp the assertion was created.
    /// @param  assertedValue The value that was asserted.
    /// @param  KpiToUse The KPI to be used for distribution once the assertion confirms.
    event RewardRoundConfigured(
        bytes32 indexed assertionId,
        uint creationTime,
        uint assertedValue,
        uint indexed KpiToUse
    );

    /// @notice Event emitted when funds for paying the bonding fee are deposited into the contract.
    /// @param  token The token used for the deposit.
    /// @param  amount The amount deposited.
    event FeeFundsDeposited(address indexed token, uint amount);

    /// @notice Event emitted when a stuck assertion gets deleted.
    event DeletedStuckAssertion(bytes32 indexed assertionId);

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Posts an assertion to the Optimistic Oracle, specifying the KPI to use and the asserted value.
    /// @param  dataId The dataId to be posted.
    /// @param  assertedValue The target value that will be asserted and posted as data to the oracle.
    /// @param  asserter The address of the asserter.
    /// @param  targetKPI The KPI to be used for distribution once the assertion confirms.
    /// @return assertionId The assertionId received for the posted assertion.
    function postAssertion(
        bytes32 dataId,
        uint assertedValue,
        address asserter,
        uint targetKPI
    ) external returns (bytes32 assertionId);

    /// @notice Creates a KPI for the Rewarder.
    /// @param  _continuous Should the tranche rewards be distributed continuously or in steps.
    /// @param  _trancheValues The value at which the tranches end.
    /// @param  _trancheRewards The rewards to be distributed at completion of each tranche.
    /// @return The KPI id.
    function createKPI(
        bool _continuous,
        uint[] calldata _trancheValues,
        uint[] calldata _trancheRewards
    ) external returns (uint);

    /// @notice Deposits funds into the contract so it can pay for the oracle bond and fee itself.
    /// @param  amount The amount to deposit.
    function depositFeeFunds(uint amount) external;

    /// @notice Returns the KPI with the given number.
    /// @param  KPInum The number of the KPI to return.
    /// @return The KPI.
    function getKPI(uint KPInum) external view returns (KPI memory);

    /// @notice Returns the Assertion Configuration for a given assertionId.
    /// @param  assertionId The id of the Assertion to return.
    /// @return The Assertion Configuration.
    function getAssertionConfig(bytes32 assertionId)
        external
        view
        returns (RewardRoundConfiguration memory);

    /// @notice Deletes a stuck assertion.
    /// @dev    This function is only callable by the Orchestrator Admin.
    /// @param  assertionId The id of the assertion to delete.
    function deleteStuckAssertion(bytes32 assertionId) external;

    /// @notice Returns the current KPI counter.
    /// @return The KPI counter.
    function getKPICounter() external view returns (uint);

    /// @notice Returns the assertion pending flag.
    /// @return The assertion pending flag.
    function getAssertionPending() external view returns (bool);
}
