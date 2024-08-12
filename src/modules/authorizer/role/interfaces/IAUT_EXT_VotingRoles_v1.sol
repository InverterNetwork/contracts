// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

interface IAUT_EXT_VotingRoles_v1 {
    //--------------------------------------------------------------------------
    // Types

    /// @notice A motion is a proposal to execute an action on a target contract.
    struct Motion {
        /// @dev The address of the contract to execute the action on.
        address target;
        /// @dev The action data to execute on the target contract.
        bytes action;
        /// @dev The timestamp at which the motion starts.
        uint startTimestamp;
        /// @dev The timestamp at which the motion ends.
        uint endTimestamp;
        /// @dev The required threshold of votes to pass the motion.
        uint requiredThreshold;
        /// @dev The number of votes in favor of the motion.
        uint forVotes;
        /// @dev The number of votes against the motion.
        uint againstVotes;
        /// @dev The number of votes abstaining from the motion.
        uint abstainVotes;
        /// @dev The receipts of votes for the motion.
        /// address => Receipt
        mapping(address => Receipt) receipts;
        /// @dev The timestamp at which the motion was executed.
        uint executedAt;
        /// @dev The result of the execution.
        bool executionResult;
        /// @dev The return data of the execution.
        bytes executionReturnData;
    }

    /// @notice A receipt is a vote cast for a motion.
    struct Receipt {
        /// @dev Whether the voter has already voted.
        bool hasVoted;
        /// @dev The value that indicates how the voter supports the motion.
        uint8 support;
    }

    //--------------------------------------------------------------------------
    // Errors

    /// @notice The action would leave an empty voter list.
    error Module__VotingRoleManager__EmptyVoters();

    /// @notice The supplied voter address is invalid.
    error Module__VotingRoleManager__InvalidVoterAddress();

    /// @notice The threshold cannot exceed the amount of voters.
    ///         or be too low to be considered safe.
    error Module__VotingRoleManager__InvalidThreshold();

    /// @notice The supplied voting duration is invalid.
    error Module__VotingRoleManager__InvalidVotingDuration();

    /// @notice The function can only be called by a voter.
    error Module__VotingRoleManager__CallerNotVoter();

    /// @notice The address is already a voter.
    error Module__VotingRoleManager__IsAlreadyVoter();

    /// @notice The value given as vote is invalid.
    error Module__VotingRoleManager__InvalidSupport();

    /// @notice The supplied ID is referencing a motion that doesn't exist.
    error Module__VotingRoleManager__InvalidMotionId();

    /// @notice A user cannot vote twice.
    error Module__VotingRoleManager__AttemptedDoubleVote();

    /// @notice A motion cannot be executed if the voting duration hasn't passed.
    error Module__VotingRoleManager__MotionInVotingPhase();

    /// @notice A motion cannot be voted on if the duration has been exceeded.
    error Module__VotingRoleManager__MotionVotingPhaseClosed();

    /// @notice A motion cannot be executed twice.
    error Module__VotingRoleManager__MotionAlreadyExecuted();

    /// @notice A motion cannot be executed if it didn't reach the threshold.
    error Module__VotingRoleManager__ThresholdNotReached();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when a new voter address gets added.
    /// @param who The added address.
    event VoterAdded(address indexed who);

    /// @notice Event emitted when a voter address gets removed.
    /// @param who The removed address.
    event VoterRemoved(address indexed who);

    /// @notice Event emitted when the required threshold changes.
    /// @param oldThreshold The old threshold.
    /// @param newThreshold The new threshold.
    event ThresholdUpdated(uint oldThreshold, uint newThreshold);

    /// @notice Event emitted when the voting duration changes.
    /// @param oldVotingDuration The old voting duration.
    /// @param newVotingDuration The new voting duration.
    event VoteDurationUpdated(uint oldVotingDuration, uint newVotingDuration);

    /// @notice Event emitted when a motion is created.
    /// @param motionId The motion ID.
    event MotionCreated(bytes32 indexed motionId);

    /// @notice Event emitted when a vote is cast for a motion.
    /// @param motionId The motion ID.
    /// @param voter The address of a voter.
    /// @param motionId Value that indicates how the voter supports the motion.
    event VoteCast(
        bytes32 indexed motionId, address indexed voter, uint8 indexed support
    );

    /// @notice Event emitted when a motion is executed.
    /// @param motionId The motion ID.
    event MotionExecuted(bytes32 indexed motionId);

    //--------------------------------------------------------------------------
    // Functions

    /// @notice The maximum voting duration.
    /// @return The maximum voting duration.
    function MAX_VOTING_DURATION() external view returns (uint);

    /// @notice The minimum voting duration.
    /// @return The minimum voting duration.
    function MIN_VOTING_DURATION() external view returns (uint);

    /// @notice Checks whether an address is a voter.
    /// @param who The address to check.
    /// @return Whether the address is a voter.
    function isVoter(address who) external view returns (bool);

    /// @notice Adds a voter.
    /// @param who The address to add.
    function addVoter(address who) external;
    /// @notice Adds a voter and updates the threshold.
    /// @param who The address to add.
    /// @param newThreshold The new threshold.
    function addVoterAndUpdateThreshold(address who, uint newThreshold)
        external;

    /// @notice Removes a voter.
    /// @param who The address to remove.
    function removeVoter(address who) external;

    /// @notice Removes a voter and updates the threshold.
    /// @param who The address to remove.
    /// @param newThreshold The new threshold.
    function removeVoterAndUpdateThreshold(address who, uint newThreshold)
        external;

    /// @notice Gets the motion data.
    /// @param motionId The ID of the motion.
    /// @return target The address of the contract to execute the action on.
    /// @return action The action data to execute on the target contract.
    /// @return startTimestamp The timestamp at which the motion starts.
    /// @return endTimestamp The timestamp at which the motion ends.
    /// @return requiredThreshold The required threshold of votes to pass the motion.
    /// @return forVotes The number of votes in favor of the motion.
    /// @return againstVotes The number of votes against the motion.
    /// @return abstainVotes The number of votes abstaining from the motion.
    /// @return executedAt The timestamp at which the motion was executed.
    /// @return executionResult The result of the execution.
    /// @return executionReturnData The return data of the execution.
    function motions(bytes32 motionId)
        external
        view
        returns (
            address,
            bytes memory,
            uint,
            uint,
            uint,
            uint,
            uint,
            uint,
            uint,
            bool,
            bytes memory
        );

    /// @notice Gets the number of motions.
    /// @return The number of motions.
    function motionCount() external view returns (uint);

    /// @notice Gets the number of voters.
    /// @return The number of voters.
    function voterCount() external view returns (uint);

    /// @notice Gets the threshold.
    /// @return The threshold.
    function threshold() external view returns (uint);

    /// @notice Gets the receipt of a voter for a motion.
    /// @param _ID The ID of the motion.
    /// @param voter The address of the voter.
    /// @return The receipt of the voter.
    function getReceipt(bytes32 _ID, address voter)
        external
        view
        returns (Receipt memory);

    /// @notice Gets the voting duration.
    /// @return The voting duration.
    function voteDuration() external view returns (uint);

    /// @notice Sets the threshold.
    /// @param newThreshold The new threshold.
    function setThreshold(uint newThreshold) external;

    /// @notice Sets the voting duration.
    /// @param newVoteDuration The new voting duration.
    function setVotingDuration(uint newVoteDuration) external;

    /// @notice Creates a motion.
    /// @param target The address of the contract to execute the action on.
    /// @param action The action data to execute on the target contract.
    /// @return The ID of the created motion.
    function createMotion(address target, bytes calldata action)
        external
        returns (bytes32);

    /// @notice Casts a vote for a motion.
    /// @param motionId The ID of the motion.
    /// @param support The value that indicates how the voter supports the motion.
    function castVote(bytes32 motionId, uint8 support) external;

    /// @notice Executes a motion.
    /// @param motionId The ID of the motion.
    function executeMotion(bytes32 motionId) external;
}
