// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

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
        uint voteClosesAt;
        bool quorumReached;
        // execution information
        uint executedAt;
        bool executionResult;
        bytes returnData;
        // voting results
        address[] voters;
        uint aye;
        uint nay;
        uint abstain;
    }

    //--------------------------------------------------------------------------
    // Errors

    error Module__SingleVoteGovernance_voteStillActive(uint voteID);
    error Module__SingleVoteGovernance_voteExpired(uint voteID);

    error Module__SingleVoteGovernance_quorumNotReached(uint voteID);

    error Module__SingleVoteGovernance_invalidModuleAddress(address addr);
    error Module__SingleVoteGovernance_invalidEncodedAction(bytes action);
    error Module__SingleVoteGovernance_invalidVoterAddress(address addr);

    error Module__SingleVoteGovernance_quorumIsZero();
    error Module__SingleVoteGovernance_quorumUnreachable();

    //--------------------------------------------------------------------------
    // Events

    event QuorumModified(uint8 oldQuorum, uint8 newQuorum);
    event VoteDurationModified(uint oldDuration, uint newDuration);

    event VotedInFavor(address who, uint voteID);
    event VotedAgainst(address who, uint voteID);
    event VotedAbstain(address who, uint voteID);
    event AttemptedDoubleVote(address who, uint voteID);

    event VoteCreated(uint _voteID);
    event VoteEnacted(uint voteID, bool executionResult);
    event VoteCancelled(uint _voteID);

    //--------------------------------------------------------------------------
    // Modifiers

    /// @notice Verifies that a given vote is still active
    modifier voteIsActive(uint _voteID) {
        //TODO check for voteIDCounter too
        if (!(voteRegistry[_voteID].voteClosesAt >= block.timestamp)) {
            revert Module__SingleVoteGovernance_voteExpired(_voteID);
        }
        _;
    }

    /// @notice Verifies that a given vote is not active anymore
    modifier voteNotActive(uint _voteID) {
        if (!(voteRegistry[_voteID].voteClosesAt < block.timestamp)) {
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
        if (_quorum > _amountAuthorized) {
            revert Module__SingleVoteGovernance_quorumUnreachable();
        }
        _;
    }
    /// @notice Verifies that the targeted module address is indeed active in the Proposal.

    modifier validModuleAddress(address _target) {
        //this should implicitly control for address  != 0
        if (!__Module_proposal.isModule(_target)) {
            revert Module__SingleVoteGovernance_invalidModuleAddress(_target);
        }
        _;
    }

    /// @notice Verifies that the action to be executed after the vote is valid
    modifier validAction(bytes calldata _action) {
        if (_action.length == 0) {
            revert Module__SingleVoteGovernance_invalidEncodedAction(_action);
        }
        /// @question  Should we do more in-depth checks? Like if the encoded action exists in the target module?
        _;
    }

    modifier validVoter(address _voter) {
        /// @notice: Usually, this modifier will just repeat the check already done in the original voteInFavor/Against/etc call. I still think it's valuable to keep it for the case the call is happening out of the encoded action of a vote, and thus escaped that check. It's a slightly convoluted attack vector, since that call vote would have to have passed through governance, but still possible...
        if (!isAuthorized(_voter)) {
            revert Module__SingleVoteGovernance_invalidVoterAddress(_voter);
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Storage

    /// @notice Registry of created votes with corresponding ID
    mapping(uint => Vote) voteRegistry;
    uint private voteIDCounter;

    /// @notice Quorum necessary to pass/deny a vote
    /// question: do we want to keep this as uint8??
    uint8 private quorum;
    /// @notice Duration of the voting period
    uint private voteDuration;

    //--------------------------------------------------------------------------
    // Constructor and/or Initialization

    function initialize(
        IProposal proposal,
        address[] calldata initialAuthorized,
        uint8 _startingQuorum,
        uint _voteDuration,
        Metadata memory metadata
    ) external {
        super.initialize(proposal, initialAuthorized, metadata);

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

    /// @notice returns the current value of voteIDCounter, which is also the ID of the next vote
    function getNextVoteID() external view returns (uint) {
        return voteIDCounter;
    }

    /// @notice returns a particular vote by ID
    function getVoteByID(uint _id) external view returns (Vote memory) {
        return voteRegistry[_id];
    }

    /// @notice checks if a specific address voted in a specifc vote
    function hasVoted(address _who, uint _voteID) public view returns (bool) {
        for (uint i = 0; i < voteRegistry[_voteID].voters.length; i++) {
            if (voteRegistry[_voteID].voters[i] == _who) {
                return true;
            }
        }
        return false;
    }
    /// TODO look into how to handle the following situation
    ///         -vote gets created to lower quorum
    ///         -other vote gets created
    ///         -lower quorum gets executed
    ///         -now:
    ///             1) if aye >= newQuorum vote becomes unpassable (fix: make l.336 >=)
    ///             2) if sbd votes aye and newQuorum<=aye<oldQuorum vote becomes (wrongly?) executable
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
        /// @question: Technically, we can avoid this func altogether, since it will only be called after a vote through executeTxModule, which could directly call __Governance_changeQuorum and save gas.

        _triggerProposalCallback(
            abi.encodeWithSignature("__Governance_changeQuorum(uint8)", _new),
            Types.Operation.Call
        );
    }

    /// @notice Sets a new vote duration
    /// @param _new The new vote duration
    function __Governance_changeVoteDuration(uint _new) external onlyProposal {
        // @question: Should we have min and max vote duration?
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
        /// @question: Technically, we can avoid this func altogether, since it will only be called after a vote through executeTxModule, which could directly call __Governance_changeQuorum and save gas.

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
        voteRegistry[voteIDCounter].voteClosesAt =
            block.timestamp + voteDuration;
        voteRegistry[voteIDCounter].targetAddress = _target;
        voteRegistry[voteIDCounter].encodedAction = _encodedAction;

        voteIDCounter++;

        emit VoteCreated((voteIDCounter - 1));
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
    function __Governance_voteInFavor(address _voter, uint _voteID)
        external
        onlyProposal
        voteIsActive(_voteID)
        validVoter(_voter)
    {
        if (!hasVoted(_voter, _voteID)) {
            voteRegistry[_voteID].voters.push(_voter);
            voteRegistry[_voteID].aye++;

            // makes the vote executable once quorum is reached
            /// @dev There's an edge case where a quorum change gets approved, but before it get's executed a new vote gets created (with the old quorum still). In this case, the new quorum shuold apply once it gets executed, so this if/else structure should account for  checking everytime a new vote comes in if the current quorum has been passed.
            if (voteRegistry[_voteID].aye >= quorum) {
                voteRegistry[_voteID].quorumReached = true;
            } else {
                voteRegistry[_voteID].quorumReached = false;
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
    function voteInFavor(uint _voteID) external onlyAuthorized {
        _triggerProposalCallback(
            abi.encodeWithSignature(
                "__Governance_voteInFavor(address,uint)", _msgSender(), _voteID
            ),
            Types.Operation.Call
        );
    }

    /// @notice Vote "no"
    /// @param _voteID The ID of the vote to vote on
    function __Governance_voteAgainst(address _voter, uint _voteID)
        external
        onlyProposal
        voteIsActive(_voteID)
        validVoter(_voter)
    {
        if (!hasVoted(_voter, _voteID)) {
            voteRegistry[_voteID].voters.push(_voter);
            voteRegistry[_voteID].nay++;

            if (voteRegistry[_voteID].aye < quorum) {
                voteRegistry[_voteID].quorumReached = false;
            }

            emit VotedAgainst(_voter, _voteID);
        } else {
            //If the user already voted the  function doesn't fail, but at least we inform them that the vote wasn't counted
            emit AttemptedDoubleVote(_voter, _voteID);
        }
    }

    /// @notice Vote "no"
    /// @dev Relay Function that routes the function call via the proposal
    /// @param _voteID The ID of the vote to vote on
    function voteAgainst(uint _voteID) external onlyAuthorized {
        _triggerProposalCallback(
            abi.encodeWithSignature(
                "__Governance_voteAgainst(address,uint)", _msgSender(), _voteID
            ),
            Types.Operation.Call
        );
    }

    /// @notice Vote "abstain"
    /// @param _voteID The ID of the vote to vote on
    function __Governance_voteAbstain(address _voter, uint _voteID)
        external
        onlyProposal
        voteIsActive(_voteID)
        validVoter(_voter)
    {
        if (!hasVoted(_voter, _voteID)) {
            voteRegistry[_voteID].voters.push(_voter);
            voteRegistry[_voteID].abstain++;

            if (voteRegistry[_voteID].aye < quorum) {
                voteRegistry[_voteID].quorumReached = false;
            }

            emit VotedAbstain(_voter, _voteID);
        } else {
            //If the user already voted the  function doesn't fail, but at least we inform them that the vote wasn't counted
            emit AttemptedDoubleVote(_voter, _voteID);
        }
    }

    /// @notice Vote "no" and abort action if quorum is reached
    /// @dev Relay Function that routes the function call via the proposal
    /// @param _voteID The ID of the vote to vote on
    function voteAbstain(uint _voteID) external onlyAuthorized {
        _triggerProposalCallback(
            abi.encodeWithSignature(
                "__Governance_voteAbstain(address,uint)", _msgSender(), _voteID
            ),
            Types.Operation.Call
        );
    }

    /// @notice Execute a vote. Only called by voteInFavor once quorum
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

        emit VoteEnacted(_voteID, voteRegistry[_voteID].executionResult);
    }

    /// @notice Execute a vote. Only called by voteInFavor once quorum
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
