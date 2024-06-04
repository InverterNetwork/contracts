// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Dependencies
import {
    ERC20PaymentClientBase_v1,
    Module_v1
} from "@lm/abstracts/ERC20PaymentClientBase_v1.sol";

// Internal Interfaces
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";

import {
    IERC20PaymentClientBase_v1,
    IPaymentProcessor_v1
} from "@lm/interfaces/IERC20PaymentClientBase_v1.sol";

import {ILM_PC_Staking_v1} from "@lm/interfaces/ILM_PC_Staking_v1.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@oz/utils/ReentrancyGuard.sol";

contract LM_PC_Staking_v1 is
    ILM_PC_Staking_v1,
    ERC20PaymentClientBase_v1,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;
    //--------------------------------------------------------------------------
    // Modifiers

    modifier validDuration(uint duration) {
        if (duration == 0) {
            revert Module__LM_PC_Staking_v1__InvalidDuration();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Storage
    /// @dev address of the token that can be staked here
    address public stakingToken;
    /// @dev total supply of the token that is staked here
    uint public totalSupply;
    /// @dev rate of how many reward tokens are distributed from the fundingmanager to the whole staking pool in seconds
    uint public rewardRate;
    /// @dev timestamp of when the reward period will end
    uint public rewardsEnd;
    /// @dev internal value that is needed to calculate the reard each user will receive
    uint internal rewardValue;
    /// @dev timestamp of when the rewardValue was last updated
    uint internal lastUpdate;

    /// @dev mapping of balances of each user in the staking token
    mapping(address => uint) internal _balances;
    /// @dev mapping of reward Values that are needed to calculate the rewards that a user should receive
    /// @dev should change everytime the user stakes or unstakes funds
    mapping(address => uint) internal userRewardValue;
    /// @dev mapping of how many reward tokens the user accumulated
    mapping(address => uint) internal rewards;

    // Storage gap for future upgrades
    uint[50] private __gap;

    //--------------------------------------------------------------------------
    // Initialization

    /// @inheritdoc Module_v1
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata,
        bytes memory configData
    ) external virtual override(Module_v1) initializer {
        __Module_init(orchestrator_, metadata);

        address _stakingToken = abi.decode(configData, (address));
        __LM_PC_Staking_v1_init(_stakingToken);
    }

    function __LM_PC_Staking_v1_init(address _stakingToken)
        internal
        onlyInitializing
    {
        _setStakingToken(_stakingToken);
    }

    //--------------------------------------------------------------------------
    // Getter Functions

    /// @inheritdoc ILM_PC_Staking_v1
    function balanceOf(address user) external view returns (uint) {
        return _balances[user];
    }

    /// @inheritdoc ILM_PC_Staking_v1
    function earned(address user) external view returns (uint) {
        return _earned(user, _calculateRewardValue());
    }

    /// @inheritdoc ILM_PC_Staking_v1
    function estimateReward(uint amount, uint duration)
        external
        view
        validAmount(amount)
        validDuration(duration)
        returns (uint)
    {
        //if rewardsend is reached you dont get any rewards
        if (block.timestamp > rewardsEnd) {
            return 0;
        }
        //If duration went over rewardsend
        if (block.timestamp + duration > rewardsEnd) {
            //change duration so that it goes until rewardsend
            duration = rewardsEnd - block.timestamp;
        }
        //If no one else staked
        if (totalSupply == 0) {
            //Get full amount back
            return amount * duration * rewardRate;
        }
        return amount * duration * rewardRate / totalSupply;
    }

    //--------------------------------------------------------------------------
    // Mutating Functions

    /// @inheritdoc ILM_PC_Staking_v1
    function stake(uint amount)
        external
        virtual
        nonReentrant
        validAmount(amount)
    {
        address sender = _msgSender();

        _stake(sender, amount);

        //transfer funds to LM_PC_Staking_v1
        IERC20(stakingToken).safeTransferFrom(sender, address(this), amount);
    }

    /// @inheritdoc ILM_PC_Staking_v1
    /// @dev this function will revert with a Over/Underflow error in case amount is higher than balance
    function unstake(uint amount)
        external
        virtual
        nonReentrant
        validAmount(amount)
    {
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

        emit Unstaked(sender, amount);
    }

    /// @inheritdoc ILM_PC_Staking_v1
    function claimRewards() external virtual nonReentrant {
        address recipient = _msgSender();

        _update(recipient);
        _distributeRewards(recipient);
    }

    /// @inheritdoc ILM_PC_Staking_v1
    function setRewards(uint amount, uint duration)
        external
        onlyOrchestratorOwnerOrManager
    {
        _setRewards(amount, duration);
    }

    //--------------------------------------------------------------------------
    // Private Functions

    function _stake(address depositFor, uint amount) internal virtual {
        _update(depositFor);

        //If the user has already earned something
        if (rewards[depositFor] != 0) {
            //distribute rewards for previous reward period
            _distributeRewards(depositFor);
        }

        //Increase balance accordingly
        _balances[depositFor] += amount;
        //Total supply too
        totalSupply += amount;

        emit Staked(depositFor, amount);
    }

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
            * 1e36 // for the later division we need a value to compensate for the loss of precision. This value will be counteracted in earned()
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
            / 1e36 // See comment in _calculateRewardValue();
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
            IERC20PaymentClientBase_v1(address(this))
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
            revert Module__LM_PC_Staking_v1__InvalidRewardRate();
        }

        //Rewards end is now plus duration
        rewardsEnd = block.timestamp + duration;
        //Update lastUpdate or calculation of rewards would include timeperiod where no rewards should have been distributed
        lastUpdate = block.timestamp;

        emit RewardSet(amount, duration, rewardRate, rewardsEnd);
    }

    function _setStakingToken(address _token) internal {
        if (_token == address(0)) {
            revert Module__LM_PC_Staking_v1__InvalidStakingToken();
        }
        stakingToken = _token;
    }
}
