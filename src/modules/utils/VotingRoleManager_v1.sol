// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

import {Module_v1, IModule_v1} from "src/modules/base/Module_v1.sol";

import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";

import {IVotingRoleManager_v1} from
    "src/modules/utils/interfaces/IVotingRoleManager_v1.sol";

/**
 * @title   Voting Role Manager
 *
 * @notice  Facilitates voting and motion management within the Inverter Network,
 *          allowing designated voters to participate in governance through proposals,
 *          voting, and execution of decisions.
 *
 * @dev     Supports setting thresholds for decision-making, managing voter lists,
 *          creating motions, casting votes, and executing actions based on collective
 *          decisions. This structure enhances governance transparency and efficacy.
 *
 * @author  Inverter Network
 */
contract VotingRoleManager_v1 is IVotingRoleManager_v1, Module_v1 {
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(Module_v1)
        returns (bool)
    {
        return interfaceId == type(IVotingRoleManager_v1).interfaceId
            || super.supportsInterface(interfaceId);
    }

    //--------------------------------------------------------------------------
    // Modifiers

    modifier onlySelf() {
        if (_msgSender() != address(this)) {
            revert Module__CallerNotAuthorized(
                bytes32("onlySelf"), _msgSender()
            );
        }
        _;
    }

    modifier onlyVoter() {
        if (!isVoter[_msgSender()]) {
            revert Module__VotingRoleManager__CallerNotVoter();
        }
        _;
    }

    modifier isValidVoterAddress(address voter) {
        if (
            voter == address(0) || voter == address(this)
                || voter == address(orchestrator())
        ) {
            revert Module__VotingRoleManager__InvalidVoterAddress();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Constants

    /// @inheritdoc IVotingRoleManager_v1
    uint public constant MAX_VOTING_DURATION = 2 weeks;

    /// @inheritdoc IVotingRoleManager_v1
    uint public constant MIN_VOTING_DURATION = 1 days;

    //--------------------------------------------------------------------------
    // Storage

    /// @inheritdoc IVotingRoleManager_v1
    mapping(address => bool) public isVoter;

    /// @inheritdoc IVotingRoleManager_v1
    mapping(uint => Motion) public motions;

    /// @inheritdoc IVotingRoleManager_v1
    uint public motionCount;

    /// @inheritdoc IVotingRoleManager_v1
    uint public voterCount;

    /// @inheritdoc IVotingRoleManager_v1
    uint public threshold;

    /// @inheritdoc IVotingRoleManager_v1
    uint public voteDuration;

    // Storage gap for future upgrades
    uint[50] private __gap;

    //--------------------------------------------------------------------------
    // Initialization

    /// @inheritdoc Module_v1
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata,
        bytes memory configData
    ) external override initializer {
        __Module_init(orchestrator_, metadata);

        // Decode configData to list of voters, the required threshold, and the
        // voting duration.
        address[] memory voters;
        uint threshold_;
        uint voteDuration_;
        (voters, threshold_, voteDuration_) =
            abi.decode(configData, (address[], uint, uint));

        uint votersLen = voters.length;

        // Revert if list of voters is empty.
        if (votersLen == 0) {
            revert Module__VotingRoleManager__EmptyVoters();
        }

        // Revert if threshold higher than number of voters, i.e. threshold being
        // unreachable.
        if (threshold_ > votersLen) {
            revert Module__VotingRoleManager__UnreachableThreshold();
        }

        // Revert if votingDuration outside of bounds.
        if (
            voteDuration_ < MIN_VOTING_DURATION
                || voteDuration_ > MAX_VOTING_DURATION
        ) {
            revert Module__VotingRoleManager__InvalidVotingDuration();
        }

        // Write voters to storage.
        address voter;
        for (uint i; i < votersLen; ++i) {
            voter = voters[i];

            if (
                voter == address(0) || voter == address(this)
                    || voter == address(orchestrator())
            ) {
                revert Module__VotingRoleManager__InvalidVoterAddress();
            }

            if (isVoter[voter]) {
                revert Module__VotingRoleManager__IsAlreadyVoter();
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
            revert Module__VotingRoleManager__UnreachableThreshold();
        }

        // Note that a threshold of zero is valid because a orchestrator can only be
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
            revert Module__VotingRoleManager__InvalidVotingDuration();
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
            revert Module__VotingRoleManager__EmptyVoters();
        }

        //Revert if removal would leave threshold unreachable
        if (voterCount <= threshold) {
            revert Module__VotingRoleManager__UnreachableThreshold();
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
            revert Module__VotingRoleManager__InvalidSupport();
        }

        //Revert if motionID invalid
        if (motionId >= motionCount) {
            revert Module__VotingRoleManager__InvalidMotionId();
        }

        // Get pointer to the motion.
        Motion storage motion_ = motions[motionId];

        // Revert if voting duration exceeded
        if (block.timestamp > motion_.endTimestamp) {
            revert Module__VotingRoleManager__MotionVotingPhaseClosed();
        }

        // Revert if caller attempts to double vote.
        if (motion_.receipts[_msgSender()].hasVoted) {
            revert Module__VotingRoleManager__AttemptedDoubleVote();
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
            revert Module__VotingRoleManager__InvalidMotionId();
        }

        // Revert if voting duration not exceeded.
        if (block.timestamp <= motion_.endTimestamp) {
            revert Module__VotingRoleManager__MotionInVotingPhase();
        }

        //Revert if necessary threshold was not reached
        if (motion_.forVotes < motion_.requiredThreshold) {
            revert Module__VotingRoleManager__ThresholdNotReached();
        }

        // Revert if motion already executed.
        if (motion_.executedAt != 0) {
            revert Module__VotingRoleManager__MotionAlreadyExecuted();
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
