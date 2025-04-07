pragma solidity ^0.8.0;

interface ILM_PC_Staking_v2 {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Given staking token address is invalid.
    error Module__LM_PC_Staking_v2__InvalidStakingToken();

    /// @notice Given Duration is invalid.
    error Module__LM_PC_Staking_v2__InvalidDuration();

    /// @notice The calculated Reward rate is too low to be used.
    error Module__LM_PC_Staking_v2__InvalidRewardRate();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when a reward is added.
    /// @param  rewardAmount The amount of tokens to distribute.
    /// @param  duration The duration of the reward period.
    /// @param  newRewardRate The new reward rate.
    /// @param  newRewardsEnd The new timestamp of when the rewards will end.
    event RewardSet(
        uint rewardAmount, uint duration, uint newRewardRate, uint newRewardsEnd
    );

    /// @notice Event emitted when a user stakes an amount.
    /// @param  user The address of the user.
    /// @param  amount The amount of tokens staked.
    event Staked(address indexed user, uint amount);

    /// @notice Event emitted when a user unstakes an amount.
    /// @param  user The address of the user.
    /// @param  amount The amount of tokens unstaked.
    event Unstaked(address indexed user, uint amount);

    /// @notice Event emitted when a user receives Rewards.
    /// @param  user The address of the user.
    /// @param  amount The amount of tokens earned.
    event RewardsDistributed(address indexed user, uint amount);

    /// @notice Event emitted for each major change of state.
    /// @param  triggerAddress Address of user if state change was triggered by a staking action. Else can be zero.
    /// @param  rewardValue Variable necessary to calculate how much rewards a staker is eligible for.
    /// @param  lastUpdate Timestamp of last state change.
    /// @param  earnedRewards How much a user earned up to point of state change.
    event Updated(
        address indexed triggerAddress,
        uint rewardValue,
        uint lastUpdate,
        uint earnedRewards
    );

    /// @notice Event emitted when staking token is set.
    /// @param  token Address of token that can be staked.
    event StakingTokenSet(address indexed token);

    //--------------------------------------------------------------------------
    // Getter Functions

    /// @notice Returns address of the token users can stake.
    /// @return The address of the token.
    function getStakingToken() external view returns (address);

    /// @notice Returns the total supply of staked tokens of this contract.
    /// @return The total supply of staked tokens.
    function getTotalSupply() external view returns (uint);

    /// @notice Returns how much Tokens will be distributed per second to all users that staked in this contract.
    /// @return The reward rate.
    function getRewardRate() external view returns (uint);

    /// @notice Returns when the rewards will not be distributed anymore.
    /// @return The timestamp of when the rewards will end.
    function getRewardsEnd() external view returns (uint);

    /// @notice Returns the amount of tokens a user staked in this contract.
    /// @param  user The address of a user that staked.
    function getBalance(address user) external view returns (uint);

    /// @notice Returns the amount of tokens earned up until now by the current stake of a user.
    /// @param  user The address of a user that staked.
    /// @return The amount of tokens earned.
    function getEarned(address user) external view returns (uint);

    /// @notice Returns a estimation of how much rewards will be earned with the current state of the staking contract.
    /// @dev	This calculation uses the current reward rate and the current totalSupply to calculate the rewards.
    /// @dev	the estimated result could be 0 if the estimated rewards are not high enough.
    /// @param  amount How much token are staked.
    /// @param  duration How long the tokens will be staked.
    /// @return The estimated amount of tokens earned.
    function getEstimatedReward(uint amount, uint duration)
        external
        view
        returns (uint);

    /// @notice Returns the reward value.
    /// @return The reward value.
    function getRewardValue() external view returns (uint);

    /// @notice Returns the timestamp of last state change.
    /// @return The timestamp of last state change.
    function getLastUpdate() external view returns (uint);

    //--------------------------------------------------------------------------
    // Mutating Functions

    /// @notice Stake a specified amount of tokens to earn rewards.
    /// @dev	Should tokens already be staked, then the sending address will collect the rewards up until this point.
    /// @dev	Fee on transfer tokens are currently not supported.
    /// @param  amount How much token should be staked.
    function stake(uint amount) external;

    /// @notice Unstake a specified amount of tokens and collect rewards.
    /// @dev	Reaps the rewards collected up to this point for the msg.Sender().
    /// @dev	Fee on transfer tokens are currently not supported.
    /// @param  amount How much token should be unstaked.
    function unstake(uint amount) external;

    /// @notice Collects the rewards that are earned up until now.
    /// @dev	Reaps the rewards collected up to this point for the msg.Sender().
    function claimRewards() external;

    /// @notice Sets the rewards that are to be distributed.
    /// @dev	Equally distributes the reward amount over the given time period.
    /// @param  amount How much token should be distributed.
    /// @param  duration How much time it will take to distribute the token.
    function setRewards(uint amount, uint duration) external;
}
