// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

import {Module, IModule} from "src/modules/base/Module.sol";

import {IProposal} from "src/proposal/IProposal.sol";

import {
    ISingleVoteGovernor,
    IAuthorizer
} from "src/modules/authorizer/ISingleVoteGovernor.sol";

contract SingleVoteGovernor is ISingleVoteGovernor, Module {
    //--------------------------------------------------------------------------
    // Modifiers

    modifier onlySelf() {
        if (_msgSender() != address(this)) {
            revert Module__CallerNotAuthorized();
        }
        _;
    }

    modifier onlyVoter() {
        if (!isVoter[_msgSender()]) {
            revert Module__SingleVoteGovernor__CallerNotVoter();
        }
        _;
    }

    modifier isValidVoterAddress(address voter) {
        if (
            voter == address(0) || voter == address(this)
                || voter == address(proposal())
        ) {
            revert Module__SingleVoteGovernor__InvalidVoterAddress();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Constants

    /// @inheritdoc ISingleVoteGovernor
    uint public constant MAX_VOTING_DURATION = 2 weeks;

    /// @inheritdoc ISingleVoteGovernor
    uint public constant MIN_VOTING_DURATION = 1 days;

    //--------------------------------------------------------------------------
    // Storage

    /// @inheritdoc ISingleVoteGovernor
    mapping(address => bool) public isVoter;

    /// @inheritdoc ISingleVoteGovernor
    mapping(uint => Motion) public motions;

    /// @inheritdoc ISingleVoteGovernor
    uint public motionCount;

    /// @inheritdoc ISingleVoteGovernor
    uint public voterCount;

    /// @inheritdoc ISingleVoteGovernor
    uint public threshold;

    /// @inheritdoc ISingleVoteGovernor
    uint public voteDuration;

    //--------------------------------------------------------------------------
    // Initialization

    /// @inheritdoc Module
    function init(
        IProposal proposal_,
        Metadata memory metadata,
        bytes memory configdata
    ) external override initializer {
        __Module_init(proposal_, metadata);

        // Decode configdata to list of voters, the required threshold, and the
        // voting duration.
        address[] memory voters;
        uint threshold_;
        uint voteDuration_;
        (voters, threshold_, voteDuration_,,) =
            abi.decode(configdata, (address[], uint, uint, bool, string[]));

        uint votersLen = voters.length;

        // Revert if list of voters is empty.
        if (votersLen == 0) {
            revert Module__SingleVoteGovernor__EmptyVoters();
        }

        // Revert if threshold higher than number of voters, i.e. threshold being
        // unreachable.
        if (threshold_ > votersLen) {
            revert Module__SingleVoteGovernor__UnreachableThreshold();
        }

        // Revert if votingDuration outside of bounds.
        if (
            voteDuration_ < MIN_VOTING_DURATION
                || voteDuration_ > MAX_VOTING_DURATION
        ) {
            revert Module__SingleVoteGovernor__InvalidVotingDuration();
        }

        // Write voters to storage.
        address voter;
        for (uint i; i < votersLen; ++i) {
            voter = voters[i];

            if (
                voter == address(0) || voter == address(this)
                    || voter == address(proposal())
            ) {
                revert Module__SingleVoteGovernor__InvalidVoterAddress();
            }

            if (isVoter[voter]) {
                revert Module__SingleVoteGovernor__IsAlreadyVoter();
            }

            isVoter[voter] = true;
            emit VoterAdded(voter);
        }

        // Write count of voters to storage.
        voterCount = votersLen;

        // Write threshold to storage.
        threshold = threshold_;
        emit ThresholdUpdated(0, threshold_);

        // Write voteDuration to storage.
        voteDuration = voteDuration_;
        emit VoteDurationUpdated(0, voteDuration_);
    }

    //--------------------------------------------------------------------------
    // IAuthorizer Functions

    /// @inheritdoc IAuthorizer
    function isAuthorized(address who)
        public
        view
        override(IAuthorizer)
        returns (bool)
    {
        // Note that only the governance itself is authorized.
        return who == address(this);
    }

    //--------------------------------------------------------------------------
    // Data Retrieval Functions

    function getReceipt(uint _ID, address voter)
        public
        view
        returns (Receipt memory)
    {
        Receipt memory _r = motions[_ID].receipts[voter];

        return (_r);
    }

    //--------------------------------------------------------------------------
    // Configuration Functions

    function setThreshold(uint newThreshold) external onlySelf {
        // Revert if newThreshold higher than number of voters.
        if (newThreshold > voterCount) {
            revert Module__SingleVoteGovernor__UnreachableThreshold();
        }

        // Note that a threshold of zero is valid because a proposal can only be
        // created by a voter anyway.

        emit ThresholdUpdated(threshold, newThreshold);
        threshold = newThreshold;
    }

    function setVotingDuration(uint newVoteDuration) external onlySelf {
        // Revert if votingDuration outside of bounds.
        if (
            newVoteDuration < MIN_VOTING_DURATION
                || newVoteDuration > MAX_VOTING_DURATION
        ) {
            revert Module__SingleVoteGovernor__InvalidVotingDuration();
        }

        emit VoteDurationUpdated(voteDuration, newVoteDuration);
        voteDuration = newVoteDuration;
    }

    //--------------------------------------------------------------------------
    // Voter Management Functions

    function addVoter(address who) external onlySelf isValidVoterAddress(who) {
        if (!isVoter[who]) {
            isVoter[who] = true;
            unchecked {
                ++voterCount;
            }
            emit VoterAdded(who);
        }
    }

    function removeVoter(address who) external onlySelf {
        //Revert if trying to remove the last voter
        if (voterCount == 1) {
            revert Module__SingleVoteGovernor__EmptyVoters();
        }

        //Revert if removal would leave threshold unreachable
        if (voterCount <= threshold) {
            revert Module__SingleVoteGovernor__UnreachableThreshold();
        }

        if (isVoter[who]) {
            delete isVoter[who];
            unchecked {
                --voterCount;
            }
            emit VoterRemoved(who);
        }
    }

    //--------------------------------------------------------------------------
    // Governance Functions

    function createMotion(address target, bytes calldata action)
        external
        onlyVoter
        returns (uint)
    {
        // Cache motion's id.
        uint motionId = motionCount;

        // Get pointer to motion.
        // Note that the motion instance is uninitialized.
        Motion storage motion_ = motions[motionId];

        // Initialize motion.
        motion_.target = target;
        motion_.action = action;

        motion_.startTimestamp = block.timestamp;
        motion_.endTimestamp = block.timestamp + voteDuration;
        motion_.requiredThreshold = threshold;

        emit MotionCreated(motionId);

        // Increase the motion count.
        unchecked {
            ++motionCount;
        }

        return motionId;
    }

    function castVote(uint motionId, uint8 support) external onlyVoter {
        // Revert if support invalid.
        // 0 = for
        // 1 = against
        // 2 = abstain
        if (support > 2) {
            revert Module__SingleVoteGovernor__InvalidSupport();
        }

        //Revert if motionID invalid
        if (motionId >= motionCount) {
            revert Module__SingleVoteGovernor__InvalidMotionId();
        }

        // Get pointer to the motion.
        Motion storage motion_ = motions[motionId];

        // Revert if voting duration exceeded
        if (block.timestamp > motion_.endTimestamp) {
            revert Module__SingleVoteGovernor__MotionVotingPhaseClosed();
        }

        // Revert if caller attempts to double vote.
        if (motion_.receipts[_msgSender()].hasVoted) {
            revert Module__SingleVoteGovernor__AttemptedDoubleVote();
        }

        if (support == 0) {
            unchecked {
                ++motion_.forVotes;
            }
        } else if (support == 1) {
            unchecked {
                ++motion_.againstVotes;
            }
        } else if (support == 2) {
            unchecked {
                ++motion_.abstainVotes;
            }
        }

        motion_.receipts[_msgSender()] = Receipt(true, support);
    }

    function executeMotion(uint motionId) external {
        // Get pointer to the motion.
        Motion storage motion_ = motions[motionId];

        // Revert if motionId invalid.
        if (motionId >= motionCount) {
            revert Module__SingleVoteGovernor__InvalidMotionId();
        }

        // Revert if voting duration not exceeded.
        if (block.timestamp <= motion_.endTimestamp) {
            revert Module__SingleVoteGovernor__MotionInVotingPhase();
        }

        //Revert if necessary threshold was not reached
        if (motion_.forVotes < motion_.requiredThreshold) {
            revert Module__SingleVoteGovernor__ThresholdNotReached();
        }

        // Revert if motion already executed.
        if (motion_.executedAt != 0) {
            revert Module__SingleVoteGovernor__MotionAlreadyExecuted();
        }

        // Updating executedAt here to prevent reentrancy
        motion_.executedAt = block.timestamp;

        // Execute `action` on `target`.
        bool result;
        bytes memory returnData;
        (result, returnData) = motion_.target.call(motion_.action);

        // Save execution's result.
        motion_.executionResult = result;
        motion_.executionReturnData = returnData;

        emit MotionExecuted(motionId);
    }
}
