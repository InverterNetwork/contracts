// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import {Module, IModule} from "src/modules/base/Module.sol";

import {IProposal} from "src/proposal/IProposal.sol";

import {
    ISingleVoteGovernor,
    IAuthorizer
} from "src/modules/governance/ISingleVoteGovernor.sol";

contract SingleVoteGovernor is ISingleVoteGovernor, Module {
    //--------------------------------------------------------------------------
    // Modifiers

    modifier onlySelf() {
        if (msg.sender != address(this)) {
            revert Module__CallerNotAuthorized();
        }
        _;
    }

    modifier onlyVoter() {
        if (!isVoter[msg.sender]) {
            revert Module__SingleVoteGovernor__CallerNotVoter();
        }
        _;
    }

    /// @notice Verifies that the targeted module address is indeed active in the Proposal.
    modifier validTargetModule(address _target) {
        //this should implicitly control for address  != 0
        if (!__Module_proposal.isModule(_target)) {
            revert Module__SingleVoteGovernor__InvalidTargetModule();
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
    mapping(uint => Proposal) public proposals;

    /// @inheritdoc ISingleVoteGovernor
    uint public proposalCount;

    /// @inheritdoc ISingleVoteGovernor
    uint public voterCount;

    /// @inheritdoc ISingleVoteGovernor
    uint public quorum;

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

        // Decode configdata to list of voters, the required quorum, and the
        // voting duration.
        address[] memory voters;
        uint quorum_;
        uint voteDuration_;
        (voters, quorum_, voteDuration_) =
            abi.decode(configdata, (address[], uint, uint));

        uint votersLen = voters.length;

        // Revert if list of voters is empty.
        if (votersLen == 0) {
            revert Module__SingleVoteGovernor__EmptyVoters();
        }

        // Revert if quorum higher than number of voters, i.e. quorum being
        // unreachable.
        if (quorum_ > votersLen) {
            revert Module__SingleVoteGovernor__UnreachableQuorum();
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
        for (uint i; i < votersLen; i++) {
            voter = voters[i];

            if (isVoter[voter]) {
                revert Module__SingleVoteGovernor__IsAlreadyVoter();
            }

            isVoter[voter] = true;
            emit VoterAdded(voter);
        }

        // Write count of voters to storage.
        voterCount = votersLen;

        // Write quorum to storage.
        quorum = quorum_;
        emit QuorumUpdated(0, quorum_);

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
        override (IAuthorizer)
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
        Receipt memory _r = proposals[_ID].receipts[voter];

        return (_r);
    }

    //--------------------------------------------------------------------------
    // Configuration Functions

    function setQuorum(uint newQuorum) external onlySelf {
        // Revert is newQuorum higher than number of voters.
        if (newQuorum > voterCount) {
            revert Module__SingleVoteGovernor__UnreachableQuorum();
        }

        // Note that a quorum of zero is valid because a proposal can only be
        // created by a voter anyway.

        emit QuorumUpdated(quorum, newQuorum);
        quorum = newQuorum;
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

    function addVoter(address who) external onlySelf {
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

        //Revert if removal would leave quorum unreachable
        if (voterCount == quorum) {
            revert Module__SingleVoteGovernor__UnreachableQuorum();
        }

        if (isVoter[who]) {
            delete isVoter[who];
            unchecked {
                --voterCount;
            }
            emit VoterRemoved(who);
        }
    }

    function transferVotingRights(address to) external onlyVoter {
        // Revert if `to` is already voter.
        if (isVoter[to]) {
            revert Module__SingleVoteGovernor__IsAlreadyVoter();
        }

        delete isVoter[msg.sender];
        emit VoterRemoved(msg.sender);

        isVoter[to] = true;
        emit VoterAdded(to);
    }

    //--------------------------------------------------------------------------
    // Governance Functions

    function createProposal(address target, bytes calldata action)
        external
        onlyVoter
        validTargetModule(target)
        returns (uint)
    {
        // Cache proposal's id.
        uint proposalId = proposalCount;

        // Get pointer to proposal.
        // Note that the proposal instance is uninitialized.
        Proposal storage proposal_ = proposals[proposalId];

        // Initialize proposal.
        proposal_.target = target;
        proposal_.action = action;

        proposal_.startTimestamp = block.timestamp;
        proposal_.endTimestamp = block.timestamp + voteDuration;
        proposal_.requiredQuorum = quorum;

        emit ProposalCreated(proposalId);

        // Increase the proposal count.
        unchecked {
            ++proposalCount;
        }

        return proposalId;
    }

    function castVote(uint proposalId, uint8 support) external onlyVoter {
        // Revert if support invalid.
        // 0 = for
        // 1 = against
        // 2 = abstain
        if (support > 2) {
            revert Module__SingleVoteGovernor__InvalidSupport();
        }

        //Revert if proposalID invalid
        if (proposalId >= proposalCount) {
            revert Module__SingleVoteGovernor__InvalidProposalId();
        }

        // Get pointer to the proposal.
        Proposal storage proposal_ = proposals[proposalId];

        // Revert if proposalId invalid.
        if (proposal_.startTimestamp == 0) {
            revert Module__SingleVoteGovernor__InvalidProposalId();
        }

        // Revert if voting duration exceeded
        if (block.timestamp > proposal_.endTimestamp) {
            revert Module__SingleVoteGovernor__ProposalVotingPhaseClosed();
        }

        // Revert if caller attempts to double vote.
        if (proposal_.receipts[msg.sender].hasVoted) {
            revert Module__SingleVoteGovernor__AttemptedDoubleVote();
        }

        if (support == 0) {
            unchecked {
                ++proposal_.forVotes;
            }
        } else if (support == 1) {
            unchecked {
                ++proposal_.againstVotes;
            }
        } else if (support == 2) {
            unchecked {
                ++proposal_.abstainVotes;
            }
        }

        proposal_.receipts[msg.sender] = Receipt(true, support);
    }

    function executeProposal(uint proposalId) external {
        // Get pointer to the proposal.
        Proposal storage proposal_ = proposals[proposalId];

        // Revert if proposalId invalid.
        if (proposalId >= proposalCount) {
            revert Module__SingleVoteGovernor__InvalidProposalId();
        }

        // Revert if voting duration not exceeded.
        if (block.timestamp < proposal_.endTimestamp) {
            revert Module__SingleVoteGovernor__ProposalInVotingPhase();
        }

        //Revert if necessary quorum was not reached
        if (proposal_.forVotes < proposal_.requiredQuorum) {
            revert Module__SingleVoteGovernor__QuorumNotReached();
        }

        // Revert if proposal already executed.
        if (proposal_.executedAt != 0) {
            revert Module__SingleVoteGovernor__ProposalAlreadyExecuted();
        }

        // Execute `action` on `target`.
        bool result;
        bytes memory returnData;
        (result, returnData) = proposal_.target.call(proposal_.action);

        // Save execution's result.
        proposal_.executedAt = block.timestamp;
        proposal_.executionResult = result;
        proposal_.executionReturnData = returnData;

        emit ProposalExecuted(proposalId);
    }
}
