pragma solidity ^0.8.0;

interface ILM_PC_Staking_v1 {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Given stakinng token address is invalid.
    error Module__LM_PC_Staking_v1__InvalidStakingToken();

    /// @notice Given Duration is invalid.
    error Module__LM_PC_Staking_v1__InvalidDuration();

    /// @notice The calculated Reward rate is too low to be used.
    error Module__LM_PC_Staking_v1__InvalidRewardRate();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when a reward is added.
    event RewardSet(
        uint rewardAmount, uint duration, uint newRewardRate, uint newRewardsEnd
    );

    /// @notice Event emitted when a user stakes an amount.
    event Staked(address indexed user, uint amount);

    /// @notice Event emitted when a user unstakes an amount.
    event Unstaked(address indexed user, uint amount);

    /// @notice Event emitted when a user receives Rewards.
    event RewardsDistributed(address indexed user, uint amount);

    //--------------------------------------------------------------------------
    // Getter Functions

    /// @notice Returns address of the token users can stake
    function stakingToken() external view returns (address);

    /// @notice Returns the total supply of staked tokens of this contract
    function totalSupply() external view returns (uint);

    /// @notice Returns how much Tokens will be distributed per second to all users that staked in this contract
    function rewardRate() external view returns (uint);

    /// @notice Returns when the rewards will not be distributed anymore
    function rewardsEnd() external view returns (uint);

    /// @notice Returns the amount of tokens a user staked in this contract
    /// @param user The address of a user that staked
    function balanceOf(address user) external view returns (uint);

    /// @notice Returns the amount of tokens earned up until now by the current stake of a user
    /// @param user The address of a user that staked
    function earned(address user) external view returns (uint);

    /// @notice Returns a estimation of how much rewards will be earned with the current state of the staking contract
    /// @dev this calculation uses the current reward rate and the current totalSupply to calculate the rewards
    /// @dev the estimated result could be 0 if the estimated rewards are not high enough
    /// @param amount : how much token are staked
    /// @param duration : how long the tokens will be staked
    function estimateReward(uint amount, uint duration)
        external
        view
        returns (uint);

    //--------------------------------------------------------------------------
    // Mutating Functions

    /// @notice Stake a specified amount of tokens to earn rewards
    /// @dev should tokens already be staked, then the sending address will collect the rewards up until this point
    /// @dev Fee on transfer tokens are currently not supported
    /// @param amount : how much token should be staked
    function stake(uint amount) external;

    /// @notice Unstake a specified amount of tokens and collect rewards
    /// @dev Reaps the rewards collected up to this point for the msg.Sender()
    /// @dev Fee on transfer tokens are currently not supported
    /// @param amount : how much token should be unstaked
    function unstake(uint amount) external;

    /// @notice Collects the rewards that are earned up until now
    /// @dev Reaps the rewards collected up to this point for the msg.Sender()
    function claimRewards() external;

    /// @notice Sets the rewards that are to be distributed
    /// @dev Equally distributes the reward amount over the given time period
    /// @param amount : how much token should be distributed
    /// @param duration : how much time it will take to distribute the token
    function setRewards(uint amount, uint duration) external;
}
