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

    struct KPI {
        uint creationTime; // timestamp the KPI was created
        uint numOfTranches; // number of tranches the KPI is divided into
        uint totalRewards; // total rewards to be distributed
        bool continuous; // should the tranche rewards be distributed continuously or in steps
        uint[] trancheValues; // The value at which a tranche ends
        uint[] trancheRewards; // The rewards to be dsitributed at completion of each tranche
    }

    struct RewardRoundConfiguration {
        uint creationTime; // timestamp the assertion was created
        uint assertedValue; // the value that was asserted
        uint KpiToUse; // the KPI to be used for distribution once the assertion confirms
        bool distributed;
    }

    //--------------------------------------------------------------------------
    // Errors

    error Module__KPIRewarder__InvalidTrancheNumber();
    error Module__KPIRewarder__InvalidKPIValueLengths();
    error Module__KPIRewarder__InvalidKPITrancheValues();
    error Module__KPIRewarder__InvalidKPINumber();
    error Module__KPIRewarder__InvalidTargetValue();
    error Module__KPIRewarder__StakingQueueIsFull();
    error Module__KPIRewarder__ModuleCannotUseStakingTokenAsBond();

    //--------------------------------------------------------------------------
    // Events

    event StakeEnqueued(address sender, uint amount);

    event KPICreated(
        uint KPI_Id,
        uint numOfTranches,
        uint totalKPIRewards,
        bool continuous,
        uint[] trancheValues,
        uint[] trancheRewards
    );

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
    /// @param _trancheRewards The rewards to be diitributed at completion of each tranche
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
