// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import {IAuthorizer} from "src/modules/IAuthorizer.sol";

interface ISingleVoteGovernor is IAuthorizer {
    //--------------------------------------------------------------------------
    // Types

    struct Motion {
        // Execution data.
        address target;
        bytes action;
        // Governance data.
        uint startTimestamp;
        uint endTimestamp;
        uint requiredQuorum;
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

    error Module__SingleVoteGovernor__EmptyVoters();
    error Module__SingleVoteGovernor__InvalidVoterAddress();
    error Module__SingleVoteGovernor__UnreachableQuorum();
    error Module__SingleVoteGovernor__InvalidVotingDuration();
    error Module__SingleVoteGovernor__InvalidTargetModule();
    error Module__SingleVoteGovernor__CallerNotVoter();
    error Module__SingleVoteGovernor__IsAlreadyVoter();
    error Module__SingleVoteGovernor__InvalidSupport();
    error Module__SingleVoteGovernor__InvalidMotionId();
    error Module__SingleVoteGovernor__AttemptedDoubleVote();
    error Module__SingleVoteGovernor__MotionInVotingPhase();
    error Module__SingleVoteGovernor__MotionVotingPhaseClosed();
    error Module__SingleVoteGovernor__MotionAlreadyExecuted();
    error Module__SingleVoteGovernor__QuorumNotReached();

    //--------------------------------------------------------------------------
    // Events

    event VoterAdded(address indexed who);
    event VoterRemoved(address indexed who);
    event QuorumUpdated(uint oldQuorum, uint newQuorum);
    event VoteDurationUpdated(uint oldVotingDuration, uint newVotingDuration);
    event MotionCreated(uint indexed motionId);
    event MotionExecuted(uint indexed motionId);

    //--------------------------------------------------------------------------
    // Functions

    function MAX_VOTING_DURATION() external view returns (uint);
    function MIN_VOTING_DURATION() external view returns (uint);

    function isVoter(address who) external view returns (bool);

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

    function quorum() external view returns (uint);
    function voteDuration() external view returns (uint);

    function setQuorum(uint newQuorum) external;
    function setVotingDuration(uint newVoteDuration) external;

    function createMotion(address target, bytes calldata action)
        external
        returns (uint);
    function castVote(uint motionId, uint8 support) external;
    function executeMotion(uint motionId) external;
}
