// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

// Internal Dependencies
import {
    ERC20PaymentClient,
    Module
} from "src/modules/logicModule/paymentClient/ERC20PaymentClient.sol";

// Internal Interfaces
import {IOrchestrator} from "src/orchestrator/IOrchestrator.sol";

import {
    IERC20PaymentClient,
    IPaymentProcessor
} from "src/modules/logicModule/paymentClient/ERC20PaymentClient.sol";

import {IStakingManager} from "src/modules/logicModule/IStakingManager.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@oz/security/ReentrancyGuard.sol";

contract StakingManager is
    IStakingManager,
    ERC20PaymentClient,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;
    //--------------------------------------------------------------------------
    // Modifiers

    modifier validDuration(uint duration) {
        if (duration == 0) {
            revert Module__StakingManager__InvalidDuration();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Storage

    address public stakingToken;

    uint public totalSupply;

    uint public rewardRate;

    uint public rewardsEnd;

    uint internal rewardValue;

    uint internal lastUpdate;

    mapping(address => uint) internal _balances;

    mapping(address => uint) internal userRewardValue;

    mapping(address => uint) internal rewards;

    //--------------------------------------------------------------------------
    // Initialization

    /// @inheritdoc Module
    function init(
        IOrchestrator orchestrator_,
        Metadata memory metadata,
        bytes memory configData
    ) external override(Module) initializer {
        __Module_init(orchestrator_, metadata);
        stakingToken = abi.decode(configData, (address)); //@note currently there is no way to change the staking token address
    }

    //--------------------------------------------------------------------------
    // Getter Functions

    /// @inheritdoc IStakingManager
    function balanceOf(address user) external view returns (uint) {
        return _balances[user];
    }

    /// @inheritdoc IStakingManager
    function earned(address user) external view returns (uint) {
        return _earned(user, _calculateRewardValue());
    }

    /// @inheritdoc IStakingManager
    function estimateReward(uint amount, uint duration)
        external
        view
        validAmount(amount)
        validDuration(duration)
        returns (uint)
    {
        if (totalSupply == 0) {
            return amount * duration * rewardRate;
        }
        return amount * duration * rewardRate / totalSupply;
    }

    //--------------------------------------------------------------------------
    // Mutating Functions

    /// @inheritdoc IStakingManager
    function stake(uint amount) external nonReentrant validAmount(amount) {
        address sender = _msgSender();
        _update(sender);

        //If the user has already earned something
        if (rewards[sender] != 0) {
            //distribute rewards for previous reward period
            _distributeRewards(sender);
        }

        //Increase balance accordingly
        _balances[sender] += amount;
        //Total supply too
        totalSupply += amount;

        //transfer funds to stakingManager
        IERC20(stakingToken).safeTransferFrom(sender, address(this), amount);

        emit Staked(sender, amount);
    }

    /// @inheritdoc IStakingManager
    function withdraw(uint amount) external nonReentrant validAmount(amount) {
        //@note should this be validWithdrawAmount? Function will break anyway if _balance is
        address sender = _msgSender();
        //Update rewardValue, updatedTimestamp and earned values
        _update(sender);

        //Reduce balances accordingly
        _balances[sender] -= amount;
        //Total supply too
        totalSupply -= amount;

        //Transfer funds back to sender
        IERC20(stakingToken).safeTransfer(sender, amount);

        //If the user has earned something
        if (rewards[sender] != 0) {
            //distribute rewards
            _distributeRewards(sender);
        }

        emit Withdrawn(sender, amount);
    }

    /// @inheritdoc IStakingManager
    function setRewards(uint amount, uint duration)
        external
        onlyOrchestratorOwnerOrManager
    {
        _setRewards(amount, duration);
    }

    //--------------------------------------------------------------------------
    // Private Functions

    /// @dev This has to trigger on every major change of the state of the contract
    function _update(address triggerAddress) internal {
        //Set a new reward value
        rewardValue = _calculateRewardValue();

        //Set timestamp correctly
        lastUpdate = _getRewardDistributionTimestamp();

        //If trigger address is 0 then its not a user
        if (triggerAddress != address(0)) {
            rewards[triggerAddress] = _earned(triggerAddress, rewardValue);
            userRewardValue[triggerAddress] = rewardValue;
        }
    }

    ///@dev This is the heart of the algorithm
    /// The reward Value is the accumulation of all the rewards a user would get for a single token if they had staked at the beginning of the lifetime of this contract
    /// A "single" reward value or with the lack of a better word "reward period" is the rewardRate (so the rewards per second for the whole contract)
    /// multiplied by the time period it was active and dividing that with the total supply
    /// This "single" value is essentially what a single token would have earned in that time period
    function _calculateRewardValue() internal view returns (uint) {
        //In case the totalSupply is 0 the rewardValue doesnt change
        if (totalSupply == 0) {
            return rewardValue;
        }

        return (_getRewardDistributionTimestamp() - lastUpdate) //Get the time difference between the last time it was updated and now (or in case the reward period ended the rewardEnd timestamp)
            * rewardRate //Multiply it with the rewardrate to get the rewards distributed for all of the stakers together
            * 1e18 // for the later division we need a value to compensate for the loss of precision. This value will be counteracted in earned()
            / totalSupply //divide it by the totalSupply to get the rewards per token
            + rewardValue; //add the old rewardValue to the new "single" rewardValue
    }

    /// @dev The function returns either the current timestamp or the last timestamp where rewards will be distributed, based on which one is earlier
    /// Is necessary to calculate the exact rewardValue at the end of the reward lifespan
    /// If not included rewards would be distributed forever
    function _getRewardDistributionTimestamp() internal view returns (uint) {
        return rewardsEnd <= block.timestamp ? rewardsEnd : block.timestamp;
    }

    /// @dev internal function to calculate how much a user earned for their stake up to this point
    /// Uses the difference between the current Reward Value and the reward value when the user staked their tokens
    /// in combination with their current balance to calculate their earnings
    function _earned(address user, uint providedRewardValue)
        internal
        view
        returns (uint)
    {
        return (providedRewardValue - userRewardValue[user]) //This difference in rewardValues basically represents the time period between now and the moment the userRewardValue was created
            * _balances[user] // multiply by users balance of tokens to get their share of the token rewards
            / 1e18 // See comment in _calculateRewardValue();
            + rewards[user];
    }

    ///@dev direct distribution of earned rewards via the payment processor
    function _distributeRewards(address recipient) internal {
        //Check what recipient has earned
        uint amount = _earned(recipient, rewardValue);
        //Set rewards to zero
        rewards[recipient] = 0;

        _addPaymentOrder(
            PaymentOrder({
                recipient: recipient,
                amount: amount,
                createdAt: block.timestamp,
                dueTo: block.timestamp
            })
        );

        __Module_orchestrator.paymentProcessor().processPayments(
            IERC20PaymentClient(address(this))
        );

        emit RewardsDistributed(recipient, amount);
    }

    /// @dev for contracts that inherit
    function _setRewards(uint amount, uint duration)
        internal
        validAmount(amount)
        validDuration(duration)
    {
        _update(address(0));
        //If rewardsEnd is already reached
        if (block.timestamp >= rewardsEnd) {
            //Dont include previous reward Rate
            rewardRate = amount / duration;
        } else {
            //Calculate remaining rewards supposed to go back into the pool
            uint remainingRewards = (rewardsEnd - block.timestamp) * rewardRate;
            //Add new Amount to previous amount and calculate rate
            rewardRate = (amount + remainingRewards) / duration;
        }

        //RewardRate cant be zero
        if (rewardRate == 0) {
            revert Module__StakingManager__InvalidRewardRate();
        }

        //Rewards end is now plus duration
        rewardsEnd = block.timestamp + duration;
        //Update lastUpdate or calculation of rewards would include timeperiod where no rewards should have been distributed
        lastUpdate = block.timestamp;

        emit RewardSet(amount, duration, rewardRate, rewardsEnd);
    }
}
