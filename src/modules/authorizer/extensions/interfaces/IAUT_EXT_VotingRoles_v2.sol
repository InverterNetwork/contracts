// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

interface IAUT_EXT_VotingRoles_v2 {
    // ========================================================================
    // Structs

    /// @notice A motion is a proposal to execute an action on a target
    ///         contract.
    /// @param  target The address of the contract to execute the action on.
    /// @param  action The action data to execute on the target contract.
    /// @param  startTimestamp The timestamp at which the motion starts.
    /// @param  endTimestamp The timestamp at which the motion ends.
    /// @param  requiredThreshold The required threshold of votes to pass the
    ///         motion.
    /// @param  forVotes The number of votes in favor of the motion.
    /// @param  againstVotes The number of votes against the motion.
    /// @param  abstainVotes The number of votes abstaining from the motion.
    /// @param  receipts The receipts of votes for the motion address.
    /// @param  executedAt The timestamp at which the motion was executed.
    /// @param  executionResult The result of the execution.
    /// @param  executionReturnData The return data of the execution.
    struct Motion {
        address target;
        bytes action;
        uint startTimestamp;
        uint endTimestamp;
        uint requiredThreshold;
        uint forVotes;
        uint againstVotes;
        uint abstainVotes;
        mapping(address => Receipt) receipts;
        uint executedAt;
        bool executionResult;
        bytes executionReturnData;
    }

    /// @notice A receipt is a vote cast for a motion.
    /// @param  hasVoted Whether the voter has already voted.
    /// @param  support The value that indicates wether the voter supports the
    ///         motion.
    struct Receipt {
        bool hasVoted;
        uint8 support;
    }
    // ========================================================================
    // Errors

    /// @notice This function is only callable by a motion of this contract.
    error Module__VotingRoleManager__OnlySelfCallAllowed();

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

    /// @notice A motion cannot be executed if the voting duration hasn't
    ///         passed.
    error Module__VotingRoleManager__MotionInVotingPhase();

    /// @notice A motion cannot be voted on if the duration has been exceeded.
    error Module__VotingRoleManager__MotionVotingPhaseClosed();

    /// @notice A motion cannot be executed twice.
    error Module__VotingRoleManager__MotionAlreadyExecuted();

    /// @notice A motion cannot be executed if it didn't reach the threshold.
    error Module__VotingRoleManager__ThresholdNotReached();

    // ========================================================================
    // Events

    /// @notice Event emitted when a new voter address gets added.
    /// @param  who_ The added address.
    event VoterAdded(address indexed who_);

    /// @notice Event emitted when a voter address gets removed.
    /// @param  who_ The removed address.
    event VoterRemoved(address indexed who_);

    /// @notice Event emitted when the required threshold changes.
    /// @param  oldThreshold_ The old threshold.
    /// @param  newThreshold_ The new threshold.
    event ThresholdUpdated(uint oldThreshold_, uint newThreshold_);

    /// @notice Event emitted when the voting duration changes.
    /// @param  oldVotingDuration_ The old voting duration.
    /// @param  newVotingDuration_ The new voting duration.
    event VoteDurationUpdated(uint oldVotingDuration_, uint newVotingDuration_);

    /// @notice Event emitted when a motion is created.
    /// @param  motionId_ The motion ID.
    event MotionCreated(bytes32 indexed motionId_);

    /// @notice Event emitted when a vote is cast for a motion.
    /// @param  motionId_ The motion ID.
    /// @param  voter_ The address of a voter.
    /// @param  support_ Value that indicates how the voter supports the motion.
    event VoteCast(
        bytes32 indexed motionId_,
        address indexed voter_,
        uint8 indexed support_
    );

    /// @notice Event emitted when a motion is executed.
    /// @param  motionId_ The motion ID.
    event MotionExecuted(bytes32 indexed motionId_);

    // ========================================================================
    // Public Getter Functions

    //--------------------------------------------------------------------------
    // Getter - Constants

    /// @notice The maximum voting duration.
    /// @return maxVotingDuration_ The maximum voting duration.
    function MAX_VOTING_DURATION()
        external
        view
        returns (uint maxVotingDuration_);

    /// @notice The minimum voting duration.
    /// @return minVotingDuration_ The minimum voting duration.
    function MIN_VOTING_DURATION()
        external
        view
        returns (uint minVotingDuration_);

    //--------------------------------------------------------------------------
    // Getter - State Access Functions

    /// @notice Checks whether an address is a voter.
    /// @param  who_ The address to check.
    /// @return isVoter_ Whether the address is a voter.
    function isVoter(address who_) external view returns (bool isVoter_);

    /// @notice Gets the motion data.
    /// @param  motionId_ The ID of the motion.
    /// @return target_ The address of the contract to execute the action on.
    /// @return action_ The action data to execute on the target contract.
    /// @return startTimestamp_ The timestamp at which the motion starts.
    /// @return endTimestamp_ The timestamp at which the motion ends.
    /// @return requiredThreshold_ The required threshold of votes to pass the
    ///         motion.
    /// @return forVotes_ The number of votes in favor of the motion.
    /// @return againstVotes_ The number of votes against the motion.
    /// @return abstainVotes_ The number of votes abstaining from the motion.
    /// @return executedAt_ The timestamp at which the motion was executed.
    /// @return executionResult_ The result of the execution.
    /// @return executionReturnData_ The return data of the execution.
    function getMotion(bytes32 motionId_)
        external
        view
        returns (
            address target_,
            bytes memory action_,
            uint startTimestamp_,
            uint endTimestamp_,
            uint requiredThreshold_,
            uint forVotes_,
            uint againstVotes_,
            uint abstainVotes_,
            uint executedAt_,
            bool executionResult_,
            bytes memory executionReturnData_
        );

    /// @notice Gets the number of motions.
    /// @return motionCount_ The number of motions.
    function getMotionCount() external view returns (uint motionCount_);

    /// @notice Gets the number of voters.
    /// @return voterCount_ The number of voters.
    function getVoterCount() external view returns (uint voterCount_);

    /// @notice Gets the threshold.
    /// @return threshold_ The threshold.
    function getThreshold() external view returns (uint threshold_);

    /// @notice Gets the voting duration.
    /// @return voteDuration_ The voting duration.
    function getVoteDuration() external view returns (uint voteDuration_);

    /// @notice Gets the receipt of a voter for a motion.
    /// @param  id_ The ID of the motion.
    /// @param  voter_ The address of the voter.
    /// @return receipt_ The receipt of the voter.
    function getReceipt(bytes32 id_, address voter_)
        external
        view
        returns (Receipt memory receipt_);

    //==========================================================================
    // Mutating Functions

    //--------------------------------------------------------------------------
    // Mutating - Configuration Functions

    /// @notice Sets the threshold.
    /// @param  newThreshold_ The new threshold.
    function setThreshold(uint newThreshold_) external;

    /// @notice Sets the voting duration.
    /// @param  newVoteDuration_ The new voting duration.
    function setVotingDuration(uint newVoteDuration_) external;

    //--------------------------------------------------------------------------
    // Mutating - Voter Management Functions

    /// @notice Adds a voter.
    /// @dev    Beware that adding a voter has implications for already
    ///         existing motions and might change how easy a threshold can be
    ///         reached / a motion can be executed.
    /// @param  who_ The address to add.
    function addVoter(address who_) external;

    /// @notice Adds a voter and updates the threshold.
    /// @dev    Beware that adding a voter has implications for already
    ///         existing motions and might change how easy a threshold can be
    ///         reached / a motion can be executed.
    /// @param  who_ The address to add.
    /// @param  newThreshold_ The new threshold.
    function addVoterAndUpdateThreshold(address who_, uint newThreshold_)
        external;

    /// @notice Removes a voter.
    /// @dev    Beware that removing a voter has implications for already
    ///         existing motions and might change how easy a threshold can be
    ///         reached / a motion can be executed. This can even lead to a
    ///         threshold in which a motion can't be executed anymore.
    /// @param  who_ The address to remove.
    function removeVoter(address who_) external;

    /// @notice Removes a voter and updates the threshold.
    /// @dev    Beware that removing a voter has implications for already
    ///         existing motions and might change how easy a threshold can be
    ///         reached / a motion can be executed. This can even lead to a
    ///         threshold in which a motion can't be executed anymore.
    /// @param  who_ The address to remove.
    /// @param  newThreshold_ The new threshold.
    function removeVoterAndUpdateThreshold(address who_, uint newThreshold_)
        external;

    //--------------------------------------------------------------------------
    // Mutating - Governance Functions

    /// @notice Creates a motion.
    /// @param  target_ The address of the contract to execute the action on.
    /// @param  action_ The action data to execute on the target contract.
    /// @return motionId_ The ID of the created motion.
    function createMotion(address target_, bytes calldata action_)
        external
        returns (bytes32 motionId_);

    /// @notice Casts a vote for a motion.
    /// @param  motionId_ The ID of the motion.
    /// @param  support_ The value that indicates wether the voter supports the
    ///         motion.
    function castVote(bytes32 motionId_, uint8 support_) external;

    /// @notice Executes a motion.
    /// @param  motionId_ The ID of the motion.
    function executeMotion(bytes32 motionId_) external;
}
