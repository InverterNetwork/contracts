// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

//Internal Dependencies
import {ModuleTest, IModule, IOrchestrator} from "test/modules/ModuleTest.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

// SuT
import {KPIRewarder, IOptimisticOracleIntegrator, IStakingManager} from "src/modules/logicModule/KPIRewarder.sol";

import {OptimisticOracleV3Mock} from
    "test/modules/logicModule/oracle/utils/OptimisiticOracleV3Mock.sol";

import {StakingManagerAccessMock} from
    "test/utils/mocks/modules/logicModules/StakingManagerAccessMock.sol";

// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

contract KPIRewarderTest is ModuleTest {
    // SuT
    KPIRewarder kpiManager;

    OptimisticOracleV3Mock ooV3;

    uint64 immutable DEFAULT_LIVENESS = 5000;

    // Mock data for assertions
    bytes32 constant MOCK_ASSERTION_DATA_ID = "0x1234";
    bytes32 constant MOCK_ASSERTION_DATA = "This is test data";
    address constant MOCK_ASSERTER_ADDRESS = address(0x0);

    ERC20Mock stakingToken = new ERC20Mock("Staking Mock Token", "STAKE MOCK");
    ERC20Mock rewardToken =
        new ERC20Mock("KPI Reward Mock Token", "REWARD MOCK");

    function setUp() public {
        ooV3 = new OptimisticOracleV3Mock(_token, DEFAULT_LIVENESS);
        // we whitelist the default currency
        ooV3.whitelistCurrency(address(_token), 5e17);

        //Add Module to Mock Orchestrator
        address impl = address(new KPIRewarder());
        kpiManager = KPIRewarder(Clones.clone(impl));

        _setUpOrchestrator(kpiManager);

        _authorizer.setIsAuthorized(address(this), true);

        bytes memory configData =
            abi.encode(address(stakingToken), address(rewardToken), ooV3);

        kpiManager.init(_orchestrator, _METADATA, configData);
    
    }

    //--------------------------------------------------------------------------
    // Test: Initialization

    function testInit() public override(ModuleTest) {
        address impl = address(new KPIRewarder());
        kpiManager = KPIRewarder(Clones.clone(impl));

        _setUpOrchestrator(kpiManager);

        bytes memory configData =
            abi.encode(address(stakingToken), address(rewardToken), ooV3);

        //Init Module wrongly
        vm.expectRevert(IModule.Module__InvalidOrchestratorAddress.selector);
        kpiManager.init(IOrchestrator(address(0)), _METADATA, configData);

        // Test invalid staking token
        vm.expectRevert(
            IStakingManager
                .Module__StakingManager__InvalidStakingToken
                .selector
        );
        kpiManager.init(
            _orchestrator,
            _METADATA,
            abi.encode(address(0), address(rewardToken), address(ooV3))
        );

        // Test invalid reward token
        vm.expectRevert(
            IOptimisticOracleIntegrator
                .Module__OptimisticOracleIntegrator__InvalidDefaultCurrency
                .selector
        );
        kpiManager.init(
            _orchestrator,
            _METADATA,
            abi.encode(address(stakingToken), address(0), address(ooV3))
        );

        // Test invalid OOAddress. See comment in OOIntegrator contract
        vm.expectRevert();
        kpiManager.init(
            _orchestrator, _METADATA, abi.encode(address(_token), address(0))
        );
    }

    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__AlreadyInitialized);
        kpiManager.init(_orchestrator, _METADATA, bytes(""));
    }
}

/*
postAssertionTest
├── when stakingQueue length is bigger than 0
│   └── it should stake all orders in the stakingQueue
├── it shoul delete the stakingQueue
├── it should set the queued funds to zero
├── when there aren't enough funds to pay the assertion fee
│   └── it should revert
└── when there are enough funds to pay the assertion fee
    ├── it should post a valid assertion in the UMA oracle
    ├── it should store the RewardRound configuration
    └── it should return a correct assertionId
*/
contract KPIRewarder_postAssertionTest is KPIRewarderTest {
    function test_WhenStakingQueueLengthIsBiggerThan0() external {
        // it should stake all orders in the stakingQueue
    }

    function test_ShoulDeleteTheStakingQueue() external {
        // it shoul delete the stakingQueue
    }

    function test_ShouldSetTheQueuedFundsToZero() external {
        // it should set the queued funds to zero
    }

    function test_RevertWhen_ThereArentEnoughFundsToPayTheAssertionFee() external {
        // it should revert
    }

    function test_WhenThereAreEnoughFundsToPayTheAssertionFee() external {
        // it should post a valid assertion in the UMA oracle
        // it should store the RewardRound configuration
        // it should return a correct assertionId
    }
}
/*
createKPITest
├── when the number of tranches is 0
│   └── it should revert
├── when the number of tranches is bigger than 20
│   └── it should revert
├── when the length of the trancheValue array and the trancheReward array don't match
│   └── it should revert
├── when the values in the trancheValue array aren't incremental
│   └── it should revert
└── when the input is valid
    └── it should create a KPI struct with the currentKPI counter as ID and increase the counter


*/

contract KPIRewarder_createKPITest is KPIRewarderTest {
    function test_RevertWhen_TheNumberOfTranchesIs0() external {
        // it should revert
    }

    function test_RevertWhen_TheNumberOfTranchesIsBiggerThan20() external {
        // it should revert
    }

    function test_RevertWhen_TheLengthOfTheTrancheValueArrayAndTheTrancheRewardArrayDontMatch() external {
        // it should revert
    }

    function test_RevertWhen_TheValuesInTheTrancheValueArrayArentIncremental() external {
        // it should revert
    }

    function test_WhenTheInputIsValid() external {
        // it should create a KPI struct with the currentKPI counter as ID and increase the counter
    }
}

/*
setKPITest
├── when the KPI number is above the current KPI
│   └── it should revert
└── when the KPI number is among the existing KPIs
    └── it should change the activeKPI to the given KPI
*/

contract KPIRewarder_setKPITest is KPIRewarderTest {
    function test_RevertWhen_TheKPINumberIsAboveTheCurrentKPI() external {
        // it should revert
    }

    function test_WhenTheKPINumberIsAmongTheExistingKPIs() external {
        // it should change the activeKPI to the given KPI
    }
}

/*
stakeTest
├── when the staked amount is 0
│   └── it should revert
├── when the length of the staking Queue is already at MAX_QUEUE_LENGTH
│   └── it should revert
├── when the caller does not have sufficient funds
│   └── it should revert
└── when the caller has sufficient funds
    └── it should store the amount + caller in the staking Queue and increase the value of totalQueuedFunds by the staked amount
*/
contract KPIRewarder_stakeTest is KPIRewarderTest {
    function test_RevertWhen_TheStakedAmountIs0() external {
        // it should revert
    }

    function test_RevertWhen_TheLengthOfTheStakingQueueIsAlreadyAtMAX_QUEUE_LENGTH() external {
        // it should revert
    }

    function test_RevertWhen_TheCallerDoesNotHaveSufficientFunds() external {
        // it should revert
    }

    function test_WhenTheCallerHasSufficientFunds() external {
        // it should store the amount + caller in the staking Queue and increase the value of totalQueuedFunds by the staked amount
    }
}

/*
assertionresolvedCallbackTest
├── when the assertion resolved to false
│   └── it should emit an event
└── when the assertion resolved to true
    ├── it will go through all tranches until reaching the asserted amount
    ├── when the rewardType is continuous
    │   └── it should pay out an amount from the last tranche proportional to its level of completion
    ├── when the rewardType is not continuous
    │   └── it should not pay out any amount from the uncompleted tranche at all
    ├── it should set the staking rewards to the calculated value with a duration of 1
    └── it should emit an event

*/


contract KPIRewarder_assertionresolvedCallbackTest is KPIRewarderTest {
    function test_WhenTheAssertionResolvedToFalse() external {
        // it should emit an event
    }

    modifier whenTheAssertionResolvedToTrue() {
        _;
    }

    function test_WhenTheAssertionResolvedToTrue() external whenTheAssertionResolvedToTrue {
        // it will go through all tranches until reaching the asserted amount
        // it should set the staking rewards to the calculated value with a duration of 1
        // it should emit an event
    }

    function test_WhenTheRewardTypeIsContinuous() external whenTheAssertionResolvedToTrue {
        // it should pay out an amount from the last tranche proportional to its level of completion
    }

    function test_WhenTheRewardTypeIsNotContinuous() external whenTheAssertionResolvedToTrue {
        // it should not pay out any amount from the uncompleted tranche at all
    }
}

/*
setAssertionTest
├── when the dataID is not valid
│   └── it should revert
├── when the data is not valid
│   └── it should revert
└── when the asserter address is not valid
    └── it should revert
*/

contract KPIRewarder_setAssertionTest is KPIRewarderTest {
    function test_RevertWhen_TheDataIDIsNotValid() external {
        // it should revert
    }

    function test_RevertWhen_TheDataIsNotValid() external {
        // it should revert
    }

    function test_RevertWhen_TheAsserterAddressIsNotValid() external {
        // it should revert
    }
}




