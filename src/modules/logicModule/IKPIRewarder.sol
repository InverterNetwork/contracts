// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {
    IStakingManager,
    StakingManager,
    SafeERC20,
    IERC20,
    IERC20PaymentClient,
    ReentrancyGuard
} from "./StakingManager.sol";

import {
    IOptimisticOracleIntegrator,
    OptimisticOracleIntegrator,
    OptimisticOracleV3CallbackRecipientInterface,
    OptimisticOracleV3Interface,
    ClaimData
} from "./oracle/OptimisticOracleIntegrator.sol";

interface IKPIRewarder {
    // TODO Natspec

    //--------------------------------------------------------------------------
    // Types

    /// @notice A KPI to be used for reward distribution
    struct KPI {
        /// @dev Timestamp the KPI was created at
        uint creationTime;
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
    error Module__KPIRewarder__InvalidTrancheNumber();

    /// @notice The number of tranches in the KPI does not match the number of rewards
    error Module__KPIRewarder__InvalidKPIValueLengths();

    /// @notice The values for the tranches are not in ascending order
    error Module__KPIRewarder__InvalidKPITrancheValues();

    /// @notice The KPI number is invalid
    error Module__KPIRewarder__InvalidKPINumber();

    /// @notice The target value for the assertion cannot be zero
    error Module__KPIRewarder__InvalidTargetValue();

    /// @notice The Queue for new stakers is full
    error Module__KPIRewarder__StakingQueueIsFull();

    /// @notice The Token used paying the bond cannot be the same that is being staked.
    error Module__KPIRewarder__ModuleCannotUseStakingTokenAsBond();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when a user stake is enqueued
    event StakeEnqueued(address sender, uint amount);

    /// @notice Event emitted when a KPI is created
    event KPICreated(
        uint KPI_Id,
        uint numOfTranches,
        uint totalKPIRewards,
        bool continuous,
        uint[] trancheValues,
        uint[] trancheRewards
    );

    /// @notice Event emitted when funds for paying the bonding fee are deposited into the contract
    event FeeFundsDeposited(address token, uint amount);

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Prepares a full Assertion to be posted, including asserted value and KPI
    /// @param dataId The dataId to be posted
    /// @param data The data to be posted
    /// @param asserter The address of the asserter
    /// @param targetValue The target value that will be asserted
    /// @param targetKPI The KPI to be used for distribution once the assertion confirms
    function prepareAssertion(
        bytes32 dataId,
        bytes32 data,
        address asserter,
        uint targetValue,
        uint targetKPI
    ) external;

    /// @notice Posts an assertion to the Optimistic Oracle
    /// @return assertionId The assertionId received for the posted assertion
    function postAssertion() external returns (bytes32 assertionId);

    /// @notice Creates a KPI for the Rewarder
    /// @param _continuous Should the tranche rewards be distributed continuously or in steps
    /// @param _trancheValues The value at which the tranches end
    /// @param _trancheRewards The rewards to be distributed at completion of each tranche
    function createKPI(
        bool _continuous,
        uint[] calldata _trancheValues,
        uint[] calldata _trancheRewards
    ) external returns (uint);

    /// @notice Sets the KPI to be used for the assertion
    function setKPI(uint _KPINumber) external;

    /// @notice Sets the target value used if the asserion confirms
    function setActiveTargetValue(uint targetValue) external;

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

    /// @notice Deposits funds into the contract to pay for the oracle bond and fee
    function depositFeeFunds(uint amount) external;
}
