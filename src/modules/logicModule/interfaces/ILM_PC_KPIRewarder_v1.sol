// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

interface ILM_PC_KPIRewarder_v1 {
    //--------------------------------------------------------------------------
    // Types

    /// @notice A KPI to be used for reward distribution
    struct KPI {
        /// @dev The number of tranches the KPI is divided into
        uint numOfTranches; //
        /// @dev  The total rewards to be distributed
        uint totalRewards;
        /// @dev  If the tranche rewards should be distributed continuously or in steps
        bool continuous;
        /// @dev The value at which each tranche ends
        uint[] trancheValues; //
        /// @dev The rewards to be dsitributed at completion of each tranche
        uint[] trancheRewards;
    }

    /// @notice The configuration of the reward round tied
    struct RewardRoundConfiguration {
        /// @dev The timestamp the assertion was posted
        uint creationTime; // timestamp the assertion was created
        /// @dev The value that was asserted
        uint assertedValue;
        /// @dev The KPI to be used for distribution once the assertion confirms
        uint KpiToUse;
        /// @dev if the rewards have been distributed or not
        bool distributed;
    }

    //--------------------------------------------------------------------------
    // Errors

    /// @notice The KPI beinge created has either no tranches or too many
    error Module__LM_PC_KPIRewarder_v1__InvalidTrancheNumber();

    /// @notice The number of tranches in the KPI does not match the number of rewards
    error Module__LM_PC_KPIRewarder_v1__InvalidKPIValueLengths();

    /// @notice The values for the tranches are not in ascending order
    error Module__LM_PC_KPIRewarder_v1__InvalidKPITrancheValues();

    /// @notice The KPI number is invalid
    error Module__LM_PC_KPIRewarder_v1__InvalidKPINumber();

    /// @notice The Queue for new stakers is full
    error Module__LM_PC_KPIRewarder_v1__StakingQueueIsFull();

    /// @notice The Token used paying the bond cannot be the same that is being staked.
    error Module__LM_PC_KPIRewarder_v1__ModuleCannotUseStakingTokenAsBond();

    /// @notice The stake amount is invalid
    error Module__LM_PC_KPIRewarder_v1__InvalidStakeAmount();

    /// @notice An assertion can only by posted if the preceding one is resolved.
    error Module__LM_PC_KPIRewarder_v1__UnresolvedAssertionExists();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when a user stake is enqueued
    event StakeEnqueued(address indexed user, uint amount);

    /// @notice Event emitted when a user stake is dequeued before staking
    event StakeDequeued(address indexed user, uint amount);

    /// @notice Event emitted when a KPI is created
    event KPICreated(
        uint indexed KPI_Id,
        uint numOfTranches,
        uint totalKPIRewards,
        bool continuous,
        uint[] trancheValues,
        uint[] trancheRewards
    );

    /// @notice Event emitted when funds for paying the bonding fee are deposited into the contract
    event FeeFundsDeposited(address indexed token, uint amount);

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Posts an assertion to the Optimistic Oracle, specifying the KPI to use and the asserted value
    /// @param dataId The dataId to be posted
    /// @param assertedValue The target value that will be asserted and posted as data to the oracle
    /// @param asserter The address of the asserter
    /// @param targetKPI The KPI to be used for distribution once the assertion confirms
    /// @return assertionId The assertionId received for the posted assertion
    function postAssertion(
        bytes32 dataId,
        uint assertedValue,
        address asserter,
        uint targetKPI
    ) external returns (bytes32 assertionId);

    /// @notice Creates a KPI for the Rewarder
    /// @param _continuous Should the tranche rewards be distributed continuously or in steps
    /// @param _trancheValues The value at which the tranches end
    /// @param _trancheRewards The rewards to be distributed at completion of each tranche
    function createKPI(
        bool _continuous,
        uint[] calldata _trancheValues,
        uint[] calldata _trancheRewards
    ) external returns (uint);

    /// @notice Deposits funds into the contract so it can pay for the oracle bond and fee itself
    /// @param amount The amount to deposit
    function depositFeeFunds(uint amount) external;

    /// @notice Remove a users funds from the staking queue
    function dequeueStake() external;

    /// @notice Returns the KPI with the given number
    /// @param KPInum The number of the KPI to return
    function getKPI(uint KPInum) external view returns (KPI memory);

    /// @notice Returns the current queue to stake in the contract
    function getStakingQueue() external view returns (address[] memory);

    /// @notice Returns the Assertion Configuration for a given assertionId
    /// @param assertionId The id of the Assertion to return
    function getAssertionConfig(bytes32 assertionId)
        external
        view
        returns (RewardRoundConfiguration memory);

    /// @notice Sets the minimum amount a user must stake
    /// @param _minimumStake The minimum amount
    function setMinimumStake(uint _minimumStake) external;
}
