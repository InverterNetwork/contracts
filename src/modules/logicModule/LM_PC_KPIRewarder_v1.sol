// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {ILM_PC_KPIRewarder_v1} from "@lm/interfaces/ILM_PC_KPIRewarder_v1.sol";
import {
    ILM_PC_Staking_v1,
    LM_PC_Staking_v1,
    SafeERC20,
    IERC20,
    ERC20PaymentClientBase_v1
} from "./LM_PC_Staking_v1.sol";
import {
    IOptimisticOracleIntegrator,
    OptimisticOracleIntegrator,
    OptimisticOracleV3CallbackRecipientInterface
} from
    "src/modules/logicModule/abstracts/oracleIntegrations/UMA_OptimisticOracleV3/OptimisticOracleIntegrator.sol";

// Internal Dependencies
import {Module_v1} from "src/modules/base/Module_v1.sol";

// External Dependencies
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

/**
 * @title   Inverter KPI Rewarder Module
 *
 * @notice  Provides a mechanism for distributing rewards to stakers based
 *          on Key Performance Indicators (KPIs).
 *
 * @dev     Extends {LM_PC_Staking_v1} and integrates with {OptimisticOracleIntegrator}
 *          to enable KPI-based reward distribution within the staking manager.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
 *
 * @author  Inverter Network
 */
contract LM_PC_KPIRewarder_v1 is
    ILM_PC_KPIRewarder_v1,
    LM_PC_Staking_v1,
    OptimisticOracleIntegrator
{
    using SafeERC20 for IERC20;

    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(OptimisticOracleIntegrator, LM_PC_Staking_v1)
        returns (bool)
    {
        return interfaceId == type(ILM_PC_KPIRewarder_v1).interfaceId
            || interfaceId == type(ILM_PC_Staking_v1).interfaceId
            || super.supportsInterface(interfaceId);
    }

    //--------------------------------------------------------------------------
    // General Information about the working of this contract
    // This module enable KPI based reward distribution into the staking manager by using UMAs Optimistic Oracle.

    // It works in the following way:
    // - The admin can create KPIs, which are a set of tranches with rewards assigned. These can be continuous
    //   or not (see below).
    // - An external actor with the ASSERTER role can trigger the posting of an assertion to the UMA Oracle, specifying
    //   the value to be asserted and the KPI to use for the reward distrbution in case it resolves
    // - To ensure fairness, all new staking requests are queued until the next KPI assertion is resolved.
    //   They will be added before posting the next assertion.
    // - Once the assertion resolves, the UMA oracle triggers the assertionResolvedCallback() function.
    //   This will calculate the final reward value and distribute it to the stakers.

    //--------------------------------------------------------------------------

    // KPI and Configuration Storage
    /// @dev	The number of KPIs created.
    uint internal KPICounter;
    /// @dev	Registry of KPIsid -> KPI.
    mapping(uint => KPI) internal registryOfKPIs;
    /// @dev	Registry of Assertion Configurations assertionId -> RewardRoundConfiguration.
    mapping(bytes32 => RewardRoundConfiguration) internal assertionConfig;
    /// @dev	 For locking certain utilities when there are assertions open.
    bool internal assertionPending;

    /// @dev	Storage gap for future upgrades.
    uint[50] private __gap;

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

    /// @inheritdoc Module_v1
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata,
        bytes memory configData
    )
        external
        virtual
        override(LM_PC_Staking_v1, OptimisticOracleIntegrator)
        initializer
    {
        __Module_init(orchestrator_, metadata);

        (
            address stakingTokenAddr,
            address currencyAddr,
            uint defaultBond,
            address ooAddr,
            uint64 liveness
        ) = abi.decode(configData, (address, address, uint, address, uint64));

        __LM_PC_Staking_v1_init(stakingTokenAddr);
        __OptimisticOracleIntegrator_init(
            currencyAddr, defaultBond, ooAddr, liveness
        );
    }

    //--------------------------------------------------------------------------
    // View functions

    /// @inheritdoc ILM_PC_KPIRewarder_v1
    function getKPI(uint KPInum) external view returns (KPI memory) {
        return registryOfKPIs[KPInum];
    }

    /// @inheritdoc ILM_PC_KPIRewarder_v1
    function getAssertionConfig(bytes32 assertionId)
        external
        view
        returns (RewardRoundConfiguration memory)
    {
        return assertionConfig[assertionId];
    }

    /// @inheritdoc ILM_PC_KPIRewarder_v1
    function getKPICounter() external view returns (uint) {
        return KPICounter;
    }

    /// @inheritdoc ILM_PC_KPIRewarder_v1
    function getAssertionPending() external view returns (bool) {
        return assertionPending;
    }

    // ========================================================================
    // Assertion Manager functions:

    /// @inheritdoc ILM_PC_KPIRewarder_v1
    /// @dev    about the asserter address: any address can be set as asserter, it will be expected to pay for the
    ///         bond on posting.
    ///         The bond tokens can also be deposited in the Module and used to pay for itself,
    ///         but ONLY if the bond token is different from the one being used for staking.
    ///         If the asserter is set to 0, whomever calls postAssertion will be paying the bond.
    function postAssertion(
        bytes32 dataId,
        uint assertedValue,
        address asserter,
        uint targetKPI
    ) public onlyModuleRole(ASSERTER_ROLE) returns (bytes32 assertionId) {
        // ==================================================================
        // Pre-check

        if (assertionPending) {
            revert Module__LM_PC_KPIRewarder_v1__UnresolvedAssertionExists();
        }

        //--------------------------------------------------------------------------
        // Input Validation

        //  If the asserter is the Module itself, we need to ensure the token paid for bond is different than the one
        //  used for staking, since it could mess with the balances
        if (
            asserter == address(this)
                && address(defaultCurrency) == stakingToken
        ) {
            revert
                Module__LM_PC_KPIRewarder_v1__ModuleCannotUseStakingTokenAsBond();
        }

        // Make sure that we are targeting an existing KPI
        if (KPICounter == 0 || targetKPI >= KPICounter) {
            revert Module__LM_PC_KPIRewarder_v1__InvalidKPINumber();
        }

        // =====================================================================
        // Assertion Posting

        assertionId = assertDataFor(dataId, bytes32(assertedValue), asserter);
        assertionConfig[assertionId] = RewardRoundConfiguration(
            block.timestamp, assertedValue, targetKPI, false
        );

        emit RewardRoundConfigured(
            assertionId, block.timestamp, assertedValue, targetKPI
        );

        assertionPending = true;
    }

    //--------------------------------------------------------------------------
    // Admin Configuration Functions:

    /// @inheritdoc ILM_PC_KPIRewarder_v1
    /// @dev    Top up funds to pay the optimistic oracle fee
    function depositFeeFunds(uint amount)
        external
        onlyOrchestratorAdmin
        nonReentrant
        validAmount(amount)
    {
        defaultCurrency.safeTransferFrom(_msgSender(), address(this), amount);

        emit FeeFundsDeposited(address(defaultCurrency), amount);
    }

    /// @inheritdoc ILM_PC_KPIRewarder_v1
    function createKPI(
        bool _continuous,
        uint[] calldata _trancheValues,
        uint[] calldata _trancheRewards
    ) external onlyOrchestratorAdmin returns (uint) {
        uint _numOfTranches = _trancheValues.length;

        if (_numOfTranches < 1 || _numOfTranches > 20) {
            revert Module__LM_PC_KPIRewarder_v1__InvalidTrancheNumber();
        }

        if (_numOfTranches != _trancheRewards.length) {
            revert Module__LM_PC_KPIRewarder_v1__InvalidKPIValueLengths();
        }

        uint _totalKPIRewards = _trancheRewards[0];
        if (_numOfTranches > 1) {
            for (uint i = 1; i < _numOfTranches; i++) {
                if (_trancheValues[i - 1] >= _trancheValues[i]) {
                    revert Module__LM_PC_KPIRewarder_v1__InvalidKPITrancheValues(
                    );
                }

                _totalKPIRewards += _trancheRewards[i];
            }
        }

        uint KpiNum = KPICounter;

        registryOfKPIs[KpiNum] = KPI(
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

    //--------------------------------------------------------------------------
    // New user facing functions (stake() is a LM_PC_Staking_v1 override) :

    /// @inheritdoc ILM_PC_Staking_v1
    function stake(uint amount)
        external
        override
        nonReentrant
        validAmount(amount)
    {
        // ==================================================================
        // Pre-check

        if (assertionPending) {
            revert Module__LM_PC_KPIRewarder_v1__CannotStakeWhenAssertionPending(
            );
        }

        address sender = _msgSender();

        _stake(sender, amount);

        // transfer funds to LM_PC_Staking_v1
        IERC20(stakingToken).safeTransferFrom(sender, address(this), amount);
    }

    /// @inheritdoc ILM_PC_KPIRewarder_v1
    function deleteStuckAssertion(bytes32 assertionId)
        public
        onlyOrchestratorAdmin
    {
        // Ensure the assertionId exists in this contract (since malicious assertions could callback this contract)
        if (assertionData[assertionId].dataId == bytes32(0x0)) {
            revert Module__LM_PC_KPIRewarder_v1__NonExistentAssertionId(
                assertionId
            );
        }

        uint assertionExpirationTime =
            oo.getAssertion(assertionId).expirationTime;

        if (block.timestamp <= assertionExpirationTime) {
            revert Module__LM_PC_KPIRewarder_v1__AssertionNotStuck(assertionId);
        }

        try oo.settleAssertion(assertionId) {
            // If the assertion can be settled, it doesn't qualify as stuck and we revert
            revert Module__LM_PC_KPIRewarder_v1__AssertionNotStuck(assertionId);
        } catch {
            delete assertionConfig[assertionId];
            delete assertionData[assertionId];
            assertionPending = false;
            emit DeletedStuckAssertion(assertionId);
        }
    }

    //--------------------------------------------------------------------------
    // Optimistic Oracle Overrides:

    /// @inheritdoc OptimisticOracleV3CallbackRecipientInterface
    function assertionResolvedCallback(
        bytes32 assertionId,
        bool assertedTruthfully
    ) public override {
        // Ensure the assertionId exists in this contract (since malicious assertions could callback this contract)
        if (assertionData[assertionId].dataId == bytes32(0x0)) {
            revert Module__LM_PC_KPIRewarder_v1__NonExistentAssertionId(
                assertionId
            );
        }

        // First, we perform checks and state management on the parent function.
        super.assertionResolvedCallback(assertionId, assertedTruthfully);

        // If the assertion was true, we calculate the rewards and distribute them.
        if (assertedTruthfully) {
            // SECURITY NOTE: this will add the value, but provides no guarantee that the fundingmanager actually
            // holds those funds.

            // Calculate rewardamount from assertionId value
            KPI memory resolvedKPI =
                registryOfKPIs[assertionConfig[assertionId].KpiToUse];
            uint rewardAmount;

            for (uint i; i < resolvedKPI.numOfTranches; i++) {
                if (
                    resolvedKPI.trancheValues[i]
                        <= assertionConfig[assertionId].assertedValue
                ) {
                    // the asserted value is above tranche end
                    rewardAmount += resolvedKPI.trancheRewards[i];
                } else {
                    // tranche was not completed
                    if (resolvedKPI.continuous) {
                        // continuous distribution
                        uint trancheRewardValue = resolvedKPI.trancheRewards[i];
                        uint trancheStart =
                            i == 0 ? 0 : resolvedKPI.trancheValues[i - 1];

                        uint achievedReward = assertionConfig[assertionId]
                            .assertedValue - trancheStart;
                        uint trancheEnd =
                            resolvedKPI.trancheValues[i] - trancheStart;

                        rewardAmount +=
                            (achievedReward * trancheRewardValue) / trancheEnd;
                    }
                    // else -> no reward

                    // exit the loop
                    break;
                }
            }

            _setRewards(rewardAmount, 1);
            assertionConfig[assertionId].distributed = true;
        } else {
            // To keep in line with the upstream contract. If the assertion was false, we delete the corresponding
            // assertionConfig from storage.
            delete assertionConfig[assertionId];
        }

        // Independently of the fact that the assertion resolved true or not, new assertions can now be posted.
        assertionPending = false;
    }

    /// @inheritdoc OptimisticOracleV3CallbackRecipientInterface
    /// @dev	This OptimisticOracleV3 callback function needs to be defined so the OOv3 doesn't revert when it tries
    //          to call it.
    function assertionDisputedCallback(bytes32 assertionId) public override {
        // Do nothing
    }
}
