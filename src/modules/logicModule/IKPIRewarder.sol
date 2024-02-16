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
        uint creationTime; // timestamp the KPI was created //
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

    function prepareAssertion(
        bytes32 dataId,
        bytes32 data,
        address asserter,
        uint targetValue,
        uint targetKPI
    ) external;

    function setAssertion(bytes32 dataId, bytes32 data, address asserter)
        external;

    function postAssertion() external returns (bytes32 assertionId);

    function createKPI(
        bool _continuous,
        uint[] calldata _trancheValues,
        uint[] calldata _trancheRewards
    ) external returns (uint);

    function setKPI(uint _KPINumber) external;

    function setActiveTargetValue(uint targetValue) external;

    function getKPI(uint KPInum) external view returns (KPI memory);

    function getStakingQueue() external view returns (address[] memory);
}
