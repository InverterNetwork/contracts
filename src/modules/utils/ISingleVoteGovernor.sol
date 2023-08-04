// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IAuthorizer} from "src/modules/authorizer/IAuthorizer.sol";

interface ISingleVoteGovernor {
    //--------------------------------------------------------------------------
    // Types

    struct Motion {
        // Execution data.
        address target;
        bytes action;
        // Governance data.
        uint startTimestamp;
        uint endTimestamp;
        uint requiredThreshold;
        // Voting result.
        uint forVotes;
        uint againstVotes;
        uint abstainVotes;
        mapping(address => Receipt) receipts;
        // Execution result.
        uint executedAt;
        bool executionResult;
        bytes executionReturnData;
    }

    struct Receipt {
        bool hasVoted;
        uint8 support;
    }

    //--------------------------------------------------------------------------
    // Errors

    /// @notice The action would leave an empty voter list.
    error Module__SingleVoteGovernor__EmptyVoters();

    /// @notice The supplied voter address is invalid.
    error Module__SingleVoteGovernor__InvalidVoterAddress();

    /// @notice The threshold cannot exceed the amount of voters
    error Module__SingleVoteGovernor__UnreachableThreshold();

    /// @notice The supplied voting duration is invalid.
    error Module__SingleVoteGovernor__InvalidVotingDuration();

    /// @notice The function can only be called by a voter.
    error Module__SingleVoteGovernor__CallerNotVoter();

    /// @notice The address is already a voter.
    error Module__SingleVoteGovernor__IsAlreadyVoter();

    /// @notice The value given as vote is invalid.
    error Module__SingleVoteGovernor__InvalidSupport();

    /// @notice The supplied ID is referencing a motion that doesn't exist.
    error Module__SingleVoteGovernor__InvalidMotionId();

    /// @notice A user cannot vote twice.
    error Module__SingleVoteGovernor__AttemptedDoubleVote();

    /// @notice A motion cannot be executed if the voting duration hasn't passed.
    error Module__SingleVoteGovernor__MotionInVotingPhase();

    /// @notice A motion cannot be voted on if the duration has been exceeded.
    error Module__SingleVoteGovernor__MotionVotingPhaseClosed();

    /// @notice A motion cannot be executed twice.
    error Module__SingleVoteGovernor__MotionAlreadyExecuted();

    /// @notice A motion cannot be executed if it didn't reach the threshold.
    error Module__SingleVoteGovernor__ThresholdNotReached();

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

    /// @notice Event emitted when a motion is created
    /// @param motionId The motion ID.
    event MotionCreated(uint indexed motionId);

    /// @notice Event emitted when a motion is executed.
    /// @param motionId The motion ID.
    event MotionExecuted(uint indexed motionId);

    //--------------------------------------------------------------------------
    // Functions

    function MAX_VOTING_DURATION() external view returns (uint);
    function MIN_VOTING_DURATION() external view returns (uint);

    function isVoter(address who) external view returns (bool);


    function addVoter(address who) external;
    function removeVoter(address who) external;

    function motions(uint motionId)
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

    function motionCount() external view returns (uint);
    function voterCount() external view returns (uint);

    function threshold() external view returns (uint);
    function voteDuration() external view returns (uint);

    function setThreshold(uint newThreshold) external;
    function setVotingDuration(uint newVoteDuration) external;

    function createMotion(address target, bytes calldata action)
        external
        returns (uint);
    function castVote(uint motionId, uint8 support) external;
    function executeMotion(uint motionId) external;
}
