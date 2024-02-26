// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

// Internal Dependencies
import {Module} from "src/modules/base/Module.sol";

// Internal Interfaces
import {IOrchestrator} from "src/orchestrator/IOrchestrator.sol";

import {IKPIRewarder} from "./IKPIRewarder.sol";

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

contract KPIRewarder is
    IKPIRewarder,
    StakingManager,
    OptimisticOracleIntegrator
{
    using SafeERC20 for IERC20;

    // Active KPI
    uint public activeKPI;
    uint public activeTargetValue;
    DataAssertion public activeAssertion;

    // KPI Storage
    uint public KPICounter;
    mapping(uint => KPI) public registryOfKPIs;
    mapping(bytes32 => RewardRoundConfiguration) public assertionConfig;

    // Deposit Queue
    address[] public stakingQueue;
    mapping(address => uint) public stakingQueueAmounts;
    uint public totalQueuedFunds;
    uint public constant MAX_QUEUE_LENGTH = 50;

    /*
    Tranche Example:
    trancheValues = [10000, 20000, 30000]
    trancheRewards = [100, 200, 100]
    continuous = false
     ->   if KPI is 12345, reward is 100 for the tranche [0-10000]
     ->   if KPI is 32198, reward is 400 for the tranches [0-10000, 10000-20000 and 20000-30000]

    if continuous = true
    ->    if KPI is 15000, reward is 200 for the tranches [100% 0-10000, 50% * 10000-15000]
    ->    if KPI is 25000, reward is 350 for the tranches [100% 0-10000, 100% 10000-20000, 50% 20000-30000]

    */

    modifier validBondSetup(address holder) {
        if (holder == address(this)) {
            //the module itself will be paying the bond
            if (address(defaultCurrency) == stakingToken) {
                // we need to ensure the token paid for bond is different than the one used for staking, since it could mess with the balances
                revert Module__KPIRewarder__ModuleCannotUseStakingTokenAsBond();
            }
        }

        _;
    }

    /// @inheritdoc Module
    function init(
        IOrchestrator orchestrator_,
        Metadata memory metadata,
        bytes memory configData
    )
        external
        virtual
        override(StakingManager, OptimisticOracleIntegrator)
        initializer
    {
        __Module_init(orchestrator_, metadata);

        (address stakingTokenAddr, address currencyAddr, address ooAddr) =
            abi.decode(configData, (address, address, address));

        _setStakingToken(stakingTokenAddr);

        // TODO ERC165 Interface Validation for the OO, for now it just reverts
        oo = OptimisticOracleV3Interface(ooAddr);
        defaultIdentifier = oo.defaultIdentifier();

        setDefaultCurrency(currencyAddr);
        setOptimisticOracle(ooAddr);
    }

    // ======================================================================
    // View functions

    /// @inheritdoc IKPIRewarder
    function getKPI(uint KPInum) public view returns (KPI memory) {
        return registryOfKPIs[KPInum];
    }

    /// @inheritdoc IKPIRewarder
    function getAssertionConfig(bytes32 assertionId)
        public
        view
        returns (RewardRoundConfiguration memory)
    {
        return assertionConfig[assertionId];
    }

    /// @inheritdoc IKPIRewarder
    function getStakingQueue() public view returns (address[] memory) {
        return stakingQueue;
    }

    // ========================================================================
    // Assertion Manager functions:

    /// @inheritdoc IKPIRewarder
    /// @dev about the asserter address: any address can be set as asserter, it will be expected to pay for the bond on posting.
    /// The bond tokens can also be deposited in the Module and used to pay for itself, but ONLY if the bond token is different from the one being used for staking.
    /// If the asserter is set to 0, whomever calls postAssertion will be paying the bond.
    function prepareAssertion(
        bytes32 dataId,
        bytes32 data,
        address asserter,
        uint targetValue,
        uint targetKPI
    ) external onlyOrchestratorOwner validBondSetup(asserter) {
        //we do not control the dataId and data inputs since they are external and just stored in the oracle

        setActiveTargetValue(targetValue);
        setKPI(targetKPI);
        _setAssertion(dataId, data, asserter);
    }

    function postAssertion()
        external
        onlyModuleRole(ASSERTER_ROLE)
        validBondSetup(activeAssertion.asserter)
        returns (bytes32 assertionId)
    {
        // performs staking for all users in queue
        for (uint i = 0; i < stakingQueue.length; i++) {
            address user = stakingQueue[i];
            _stake(user, stakingQueueAmounts[user]);
            totalQueuedFunds -= stakingQueueAmounts[user];
            stakingQueueAmounts[user] = 0;
        }

        // resets the queue
        delete stakingQueue;

        assertionId = assertDataFor(
            activeAssertion.dataId,
            activeAssertion.data,
            activeAssertion.asserter
        );
        assertionConfig[assertionId] = RewardRoundConfiguration(
            block.timestamp, activeTargetValue, activeKPI, false
        );
    }

    // Owner functions:

    // Top up funds to pay the optimistic oracle fee
    /// @inheritdoc IKPIRewarder
    function depositFeeFunds(uint amount)
        external
        onlyOrchestratorOwner
        nonReentrant
        validAmount(amount)
    {
        defaultCurrency.safeTransferFrom(_msgSender(), address(this), amount);

        emit FeeFundsDeposited(address(defaultCurrency), amount);
    }

    /// @inheritdoc IKPIRewarder
    function createKPI(
        bool _continuous,
        uint[] calldata _trancheValues,
        uint[] calldata _trancheRewards
    ) external onlyOrchestratorOwner returns (uint) {
        uint _numOfTranches = _trancheValues.length;

        if (_numOfTranches < 1 || _numOfTranches > 20) {
            revert Module__KPIRewarder__InvalidTrancheNumber();
        }

        if (_numOfTranches != _trancheRewards.length) {
            revert Module__KPIRewarder__InvalidKPIValueLengths();
        }

        uint _totalKPIRewards = _trancheRewards[0];
        if (_numOfTranches > 1) {
            for (uint i = 1; i < _numOfTranches; i++) {
                if (_trancheValues[i - 1] >= _trancheValues[i]) {
                    revert Module__KPIRewarder__InvalidKPITrancheValues();
                }

                _totalKPIRewards += _trancheRewards[i];
            }
        }

        uint KpiNum = KPICounter;

        registryOfKPIs[KpiNum] = KPI(
            block.timestamp,
            _numOfTranches,
            _totalKPIRewards,
            _continuous,
            _trancheValues,
            _trancheRewards
        );
        KPICounter++;

        emit KPICreated(
            KpiNum,
            _numOfTranches,
            _totalKPIRewards,
            _continuous,
            _trancheValues,
            _trancheRewards
        );

        return (KpiNum);
    }

    /// @inheritdoc IKPIRewarder
    function setKPI(uint _KPINumber) public onlyOrchestratorOwner {
        if (_KPINumber >= KPICounter) {
            revert Module__KPIRewarder__InvalidKPINumber();
        }
        activeKPI = _KPINumber;
    }

    /// @inheritdoc IKPIRewarder
    function setActiveTargetValue(uint targetValue)
        public
        onlyOrchestratorOwner
    {
        if (targetValue == 0) {
            revert Module__KPIRewarder__InvalidTargetValue();
        }
        activeTargetValue = targetValue;
    }

    /// @notice Sets the assertion to be posted to the Optimistic Oracle
    /// @param dataId The dataId to be posted
    /// @param data The data to be posted
    /// @param asserter The address of the asserter
    function _setAssertion(bytes32 dataId, bytes32 data, address asserter)
        internal
    {
        // Question: what kind of checks do we want to or can we implement? Technically the value inside "data" (and posted publicly) wouldn't need to be the same as assertedValue...
        activeAssertion = DataAssertion(dataId, data, asserter, false);
    }

    // ===========================================================
    // StakingManager Overrides:

    /// @inheritdoc IStakingManager
    function stake(uint amount)
        external
        override
        nonReentrant
        validAmount(amount)
    {
        if (stakingQueue.length >= MAX_QUEUE_LENGTH) {
            revert Module__KPIRewarder__StakingQueueIsFull();
        }

        address sender = _msgSender();

        if (stakingQueueAmounts[sender] == 0) {
            // new stake for queue
            stakingQueue.push(sender);
        }
        stakingQueueAmounts[sender] += amount;
        totalQueuedFunds += amount;

        //transfer funds to stakingManager
        IERC20(stakingToken).safeTransferFrom(sender, address(this), amount);

        emit StakeEnqueued(sender, amount);
    }

    // ============================================================
    // Optimistic Oracle Overrides:

    /// @inheritdoc IOptimisticOracleIntegrator
    function assertionResolvedCallback(
        bytes32 assertionId,
        bool assertedTruthfully
    ) public override {
        if (_msgSender() != address(oo)) {
            revert Module__OptimisticOracleIntegrator__CallerNotOO();
        }

        if (assertedTruthfully) {
            // SECURITY NOTE: this will add the value, but provides no guarantee that the fundingmanager actually holds those funds.

            // Calculate rewardamount from asserionId value
            KPI memory resolvedKPI =
                registryOfKPIs[assertionConfig[assertionId].KpiToUse];
            uint rewardAmount;

            for (uint i; i < resolvedKPI.numOfTranches; i++) {
                if (
                    resolvedKPI.trancheValues[i]
                        <= assertionConfig[assertionId].assertedValue
                ) {
                    //the asserted value is above tranche end
                    rewardAmount += resolvedKPI.trancheRewards[i];
                } else {
                    //tranche was not completed
                    if (resolvedKPI.continuous) {
                        //continuous distribution
                        uint trancheRewardValue = resolvedKPI.trancheRewards[i];
                        uint trancheStart =
                            i == 0 ? 0 : resolvedKPI.trancheValues[i - 1];

                        uint achievedReward = assertionConfig[assertionId]
                            .assertedValue - trancheStart;
                        uint trancheEnd =
                            resolvedKPI.trancheValues[i] - trancheStart;

                        rewardAmount +=
                            achievedReward * (trancheRewardValue / trancheEnd); // since the trancheRewardValue will be a very big number.
                    }
                    //else -> no reward

                    //exit the loop
                    break;
                }
            }

            _setRewards(rewardAmount, 1);
        }
        emit DataAssertionResolved(
            assertedTruthfully,
            assertionData[assertionId].dataId,
            assertionData[assertionId].data,
            assertionData[assertionId].asserter,
            assertionId
        );
    }

    /// @inheritdoc IOptimisticOracleIntegrator
    /// @dev This OptimisticOracleV3 callback function needs to be defined so the OOv3 doesn't revert when it tries to call it.
    function assertionDisputedCallback(bytes32 assertionId) public override {
        //Do nothing
    }
}
