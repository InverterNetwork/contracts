// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Dependencies
import {ContextUpgradeable} from "@oz-up/utils/ContextUpgradeable.sol";

// Internal Dependencies
import {Types} from "src/common/Types.sol";
import {Module} from "src/modules/base/Module.sol";
import {ListAuthorizer} from "src/modules/governance/ListAuthorizer.sol";

// Interfaces
import {IProposal, IAuthorizer} from "src/proposal/IProposal.sol";

/**
 * @title Vote-based governance module
 *
 * @dev
 *  Implements a single vote governance module:
 *  -The contract keeps a list of authorized addresses. These addresses can create Votes wich other addresses can support or reject.
 *   -Votes are open for a set length of time. If they don't reach quorum at time of voting, they won't be able to be executed later, even if the quorum is lowered.
 *   -Each address can vote only once. Votes can not be modified.
 *   -the stored action can only be executed after the voting period ends, even if quorum was reached earlier.
 */

contract SingleVoteGovernance is ListAuthorizer {
    //--------------------------------------------------------------------------
    // Types

    /// @notice This struct stores the information of a governance vote
    /// @param isActive False if canceled or executed
    /// @param encodedAction The tx to be executed, in ABI encoded format
    /// @param targetAddress The Module address to execute the tx on
    /// @param hasVoted Stores all addresses who already voted
    /// @param aye "Yes" votes
    /// @param nay "No" votes
    struct Vote {
        // Vote information
        bytes encodedAction;
        address targetAddress;
        uint createdAt;
        bool quorumReached;
        // execution information
        uint executedAt;
        bool executionResult;
        bytes returnData;
        // voting results
        mapping(address => bool) hasVoted;
        uint aye;
        uint nay;
    }

    //--------------------------------------------------------------------------
    // Errors

    error Module__SingleVoteGovernance_voteStillActive(uint voteID);
    error Module__SingleVoteGovernance_voteExpired(uint _voteID);

    error Module__SingleVoteGovernance_quorumNotReached(uint voteID);

    error Module__SingleVoteGovernance_invalidModuleAddress(address addr);
    error Module__SingleVoteGovernance_invalidEncodedAction();

    error Module__SingleVoteGovernance_quorumIsZero();
    error Module__SingleVoteGovernance_quorumUnreachable();

    //--------------------------------------------------------------------------
    // Events

    event QuorumModified(uint8 oldQuorum, uint8 newQuorum);
    event VoteDurationModified(uint oldDuration, uint newDuration);

    event VotedInFavor(address who, uint voteID);
    event VotedAgainst(address who, uint voteID);
    event AttemptedDoubleVote(address who, uint voteID);

    event VoteEnacted(uint voteID);
    event VoteCancelled(uint _voteID);

    //--------------------------------------------------------------------------
    // Modifiers

    /// @notice Verifies that a given vote is still active
    modifier voteIsActive(uint _voteID) {
        if (
            !(voteRegistry[_voteID].createdAt + voteDuration >= block.timestamp)
        ) {
            revert Module__SingleVoteGovernance_voteExpired(_voteID);
        }
        _;
    }

    /// @notice Verifies that a given vote is not active anymore
    modifier voteNotActive(uint _voteID) {
        if (!(voteRegistry[_voteID].createdAt + voteDuration < block.timestamp))
        {
            revert Module__SingleVoteGovernance_voteStillActive(_voteID);
        }
        _;
    }

    /// @notice Verifies that a given vote did reach the quorum (at the time it was voted on)
    modifier quorumReached(uint _voteID) {
        if (!voteRegistry[_voteID].quorumReached == true) {
            revert Module__SingleVoteGovernance_quorumNotReached(_voteID);
        }
        _;
    }

    /// @notice Verifies that the suggested quorum change wouldn't break the system
    modifier validQuorum(uint8 _quorum, uint _amountAuthorized) {
        if (_quorum == 0) {
            revert Module__SingleVoteGovernance_quorumIsZero();
        }
        if (_quorum > getAmountAuthorized()) {
            revert Module__SingleVoteGovernance_quorumUnreachable();
        }
        _;
    }
    /// @notice Verifies that the targeted module address is indeed active in the Proposal.

    modifier validModuleAddress(address _target) {
        //TODO I think we DO want to allow address==address(this)? F.ex. to vote on quorum change. Depends on wether the governance is allowed to cahnge itself...

        //this should implicitly control for address  != 0
        if (!__Module_proposal.isEnabledModule(_target)) {
            revert Module__SingleVoteGovernance_invalidModuleAddress(_target);
        }
        _;
    }

    /// @notice Verifies that the action to be executed after the vote is valid
    modifier validAction(bytes calldata _action) {
        if (_action.length == 0) {
            revert Module__SingleVoteGovernance_invalidEncodedAction();
        }
        /// @question  Should we do more in-depth checks? Like if the encoded action exists in the target module?
        _;
    }

    //--------------------------------------------------------------------------
    // Storage

    /// @notice Registry of created votes with corresponding ID
    mapping(uint => Vote) voteRegistry;
    uint voteIDCounter;

    /// @notice Quorum necessary to pass/deny a vote
    uint8 private quorum;
    /// @notice Duration of the voting period
    uint private voteDuration;

    //--------------------------------------------------------------------------
    // Constructor and/or Initialization

    function initialize(
        IProposal proposal,
        uint8 _startingQuorum,
        uint _voteDuration,
        Metadata memory metadata
    ) external initializer {
        __Module_init(proposal, metadata);

        // @question During initialization we don't check for valid quorum etc... Is this too risky?
        quorum = _startingQuorum;
        voteDuration = _voteDuration;
    }

    //--------------------------------------------------------------------------
    // Parent Function overrides:

    /// @dev  adds the validQuorum modifier to removeFromAuthorized to make sure
    /// that removing users doesn't end up with unreachable quorum.
    /// @notice Removes an address from the list of authorized addresses.
    /// @param _who Address to remove authorization from
    function __ListAuthorizer_removeFromAuthorized(address _who)
        public
        override
        onlyProposal
        validQuorum(quorum, (getAmountAuthorized() - 1))
    {
        super.__ListAuthorizer_removeFromAuthorized(_who);
    }

    //--------------------------------------------------------------------------
    // Public Callable Funtions

    /// @notice Returns the current required quorum
    function getRequiredQuorum() external view returns (uint8) {
        return quorum;
    }

    /// @notice Returns the current required quorum
    function getVoteDuration() external view returns (uint) {
        return voteDuration;
    }

    /// @notice Sets a new quorum
    /// @param _new The new quorum
    function __Governance_changeQuorum(uint8 _new)
        external
        onlyProposal
        validQuorum(_new, getAmountAuthorized())
    {
        uint8 old = quorum;
        quorum = _new;

        emit QuorumModified(old, quorum);
    }

    /// @notice Sets a new quorum
    /// @dev    Relay Function that routes the function call via the proposal.
    ///         The onlyProposal modifier forces a quorum change to als go
    ///         through governance.
    /// @param _new The new quorum
    function changeQuorum(uint8 _new) external onlyProposal {
        _triggerProposalCallback(
            abi.encodeWithSignature("__Governance_changeQuorum(uint8)", _new),
            Types.Operation.Call
        );
    }

    /// @notice Sets a new vote duration
    /// @param _new The new vote duration
    function __Governance_changeVoteDuration(uint _new) external onlyProposal {
        uint old = voteDuration;
        voteDuration = _new;

        emit VoteDurationModified(old, voteDuration);
    }

    /// @notice Sets a new vote duration
    /// @dev    Relay Function that routes the function call via the proposal.
    ///         The onlyProposal modifier forces a quorum change to als go
    ///         through governance.
    /// @param _new The new vote duration
    function changeVoteDuration(uint _new) external onlyProposal {
        _triggerProposalCallback(
            abi.encodeWithSignature(
                "__Governance_changeVoteDuration(uint)", _new
            ),
            Types.Operation.Call
        );
    }

    /// @notice Creates a new vote
    /// @param _target The Module from which to execute the action
    /// @param _encodedAction The ABI encoded action to execute if it passes
    function __Governance_createVote(
        address _target,
        bytes calldata _encodedAction
    )
        external
        onlyProposal
        validModuleAddress(_target)
        validAction(_encodedAction)
    {
        voteRegistry[voteIDCounter].createdAt = block.timestamp;
        voteRegistry[voteIDCounter].targetAddress = _target;
        voteRegistry[voteIDCounter].encodedAction = _encodedAction;

        voteIDCounter++;
    }

    /// @notice Creates a new vote
    /// @dev Relay Function that routes the function call via the proposal
    /// @param _target The Module from which to execute the action
    /// @param _encodedAction The ABI encoded action to execute if it passes
    function createVote(address _target, bytes calldata _encodedAction)
        external
        onlyAuthorized
    {
        _triggerProposalCallback(
            abi.encodeWithSignature(
                "__Governance_createVote(address,bytes)",
                _target,
                _encodedAction
            ),
            Types.Operation.Call
        );
    }

    /// @notice Vote "yes" and execute action if quorum is reached
    /// @param _voteID The ID of the vote to vote on
    function __Governance_confirmAction(address _voter, uint _voteID)
        external
        onlyProposal
        voteIsActive(_voteID)
    {
        if (!voteRegistry[_voteID].hasVoted[_voter]) {
            voteRegistry[_voteID].hasVoted[_voter] = true;
            voteRegistry[_voteID].aye++;

            // makes the vote executable once quorum is reached
            if (voteRegistry[_voteID].aye == quorum) {
                voteRegistry[_voteID].quorumReached = true;
            }

            emit VotedInFavor(_voter, _voteID);
        } else {
            //If the user already voted the  function doesn't fail, but at least we inform them that the vote wasn't counted
            emit AttemptedDoubleVote(_voter, _voteID);
        }
    }

    /// @notice Vote "yes" and execute action if quorum is reached
    /// @dev Relay Function that routes the function call via the proposal
    /// @param _voteID The ID of the vote to vote on
    function confirmAction(uint _voteID) external onlyAuthorized {
        _triggerProposalCallback(
            abi.encodeWithSignature(
                "__Governance_confirmAction(address,uint)",
                _msgSender(),
                _voteID
            ),
            Types.Operation.Call
        );
    }

    /// @notice Vote "no" and abort action if quorum is reached
    /// @param _voteID The ID of the vote to vote on
    function __Governance_cancelAction(address _voter, uint _voteID)
        external
        onlyProposal
        voteIsActive(_voteID)
    {
        if (!voteRegistry[_voteID].hasVoted[_voter]) {
            voteRegistry[_voteID].hasVoted[_voter] = true;
            voteRegistry[_voteID].nay++;

            emit VotedAgainst(_voter, _voteID);
        } else {
            //If the user already voted the  function doesn't fail, but at least we inform them that the vote wasn't counted
            emit AttemptedDoubleVote(_voter, _voteID);
        }
    }

    /// @notice Vote "no" and abort action if quorum is reached
    /// @dev Relay Function that routes the function call via the proposal
    /// @param _voteID The ID of the vote to vote on
    function cancelAction(uint _voteID) external onlyAuthorized {
        _triggerProposalCallback(
            abi.encodeWithSignature(
                "__Governance_cancelAction(address,uint)", _msgSender(), _voteID
            ),
            Types.Operation.Call
        );
    }

    /// @notice Execute a vote. Only called by confirmAction once quorum
    ///         is reached
    /// @param _voteID The ID of the vote to execute
    function __Governance_executeVote(uint _voteID)
        external
        onlyProposal
        quorumReached(_voteID)
        voteNotActive(_voteID)
    {
        // Tell the proposal to execute the vote
        (
            voteRegistry[_voteID].executionResult,
            voteRegistry[_voteID].returnData
        ) = __Module_proposal.executeTxFromModule(
            voteRegistry[_voteID].targetAddress,
            voteRegistry[_voteID].encodedAction,
            Types.Operation.Call
        );

        voteRegistry[_voteID].executedAt = block.timestamp;

        emit VoteEnacted(_voteID); // TODO also tell executionResult
    }

    /// @notice Execute a vote. Only called by confirmAction once quorum
    ///         is reached
    /// @dev Relay Function that routes the function call via the proposal
    /// @param _voteID The ID of the vote to execute
    function executeVote(uint _voteID)
        external
        voteIsActive(_voteID)
        quorumReached(_voteID)
    {
        _triggerProposalCallback(
            abi.encodeWithSignature("__Governance_executeVote(uint)", _voteID),
            Types.Operation.Call
        );
    }
}
