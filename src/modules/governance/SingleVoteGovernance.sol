// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

// External Dependencies
import {ContextUpgradeable} from "@oz-up/utils/ContextUpgradeable.sol";

// Internal Dependencies
import {Types} from "src/common/Types.sol";
import {Module, IModule} from "src/modules/base/Module.sol";
import {ListAuthorizer} from "src/modules/governance/ListAuthorizer.sol";

// Interfaces
import {IProposal, IAuthorizer} from "src/proposal/IProposal.sol";

/**
 * @title Vote-based governance module
 *
 * @dev
 *  Implements a single vote governance module:
 *  -The contract keeps a list of authorized addresses. These addresses can create Votes wich other addresses can support, reject, or abstain from.
 *   -Votes are open for a set length of time. If they don't reach quorum during that period, they won't be able to be executed later, even if the quorum is lowered afterwards.
 *   -Each address can vote only once. Votes can not be modified.
 *   -the stored action can only be executed after the voting period ends, even if quorum was reached earlier.
 */

contract SingleVoteGovernance is ListAuthorizer {
    //--------------------------------------------------------------------------
    // Types

    /// @notice This struct stores the information of a governance vote
    /// @param encodedAction The tx to be executed, in ABI encoded format
    /// @param targetAddress The Module address to execute the tx on
    /// @param voteClosesAt Timestamp at which the vote will be closed
    /// @param requiredQuorum Required quorum to pass the vote
    /// @param executedAt Timestamp at which the vote was executed
    /// @param executionResult Result of that execution (success of failure)
    /// @param returnData Data returned by execution
    /// @param voters Stores all addresses who already voted
    /// @param aye "Yes" votes
    /// @param nay "No" votes
    /// @param abstain "Abstain" votes
    struct Vote {
        // Vote information
        bytes encodedAction;
        address targetAddress;
        uint voteClosesAt;
        uint requiredQuorum;
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

    error Module__SingleVoteGovernance__voteStillActive(uint voteID);
    error Module__SingleVoteGovernance__voteExpired(uint voteID);
    error Module__SingleVoteGovernance__voteAlreadyExecuted(uint _voteID);
    error Module__SingleVoteGovernance__nonexistentVoteId(uint _voteID);

    error Module__SingleVoteGovernance__quorumNotReached(uint voteID);

    error Module__SingleVoteGovernance__invalidModuleAddress(address addr);
    error Module__SingleVoteGovernance__invalidEncodedAction(bytes action);

    error Module__SingleVoteGovernance__quorumCannotBeZero();
    error Module__SingleVoteGovernance__quorumUnreachable();

    //--------------------------------------------------------------------------
    // Events

    event QuorumModified(uint oldQuorum, uint newQuorum);
    event VoteDurationModified(uint oldDuration, uint newDuration);

    event VotedInFavor(address who, uint voteID);
    event VotedAgainst(address who, uint voteID);
    event VotedAbstain(address who, uint voteID);
    event AttemptedDoubleVote(address who, uint voteID);

    event VoteCreated(uint _voteID);
    event VoteEnacted(uint voteID, bool executionResult);

    //--------------------------------------------------------------------------
    // Modifiers

    modifier voteExists(uint _voteID) {
        if (_voteID >= voteIDCounter) {
            revert Module__SingleVoteGovernance__nonexistentVoteId(_voteID);
        }
        _;
    }

    /// @notice Verifies that a given vote ID belongs to an active vote
    modifier voteIsActive(uint _voteID) {
        if (voteRegistry[_voteID].voteClosesAt < block.timestamp) {
            revert Module__SingleVoteGovernance__voteExpired(_voteID);
        }
        _;
    }

    /// @notice Verifies that a given vote is not active anymore
    modifier voteNotActive(uint _voteID) {
        if (voteRegistry[_voteID].voteClosesAt >= block.timestamp) {
            revert Module__SingleVoteGovernance__voteStillActive(_voteID);
        }
        _;
    }

    /// @notice Verifies that a given vote has not been executed
    modifier voteNotExecuted(uint _voteID) {
        if (voteRegistry[_voteID].executionResult == true) {
            revert Module__SingleVoteGovernance__voteAlreadyExecuted(_voteID);
        }
        _;
    }

    /// @notice Verifies that a given vote did reach the quorum
    modifier quorumReached(uint _voteID) {
        if (
            !(voteRegistry[_voteID].aye >= voteRegistry[_voteID].requiredQuorum)
        ) {
            revert Module__SingleVoteGovernance__quorumNotReached(_voteID);
        }
        _;
    }

    /// @notice Verifies that the suggested change wouldn't break the quorum system
    modifier validQuorum(uint _quorum) {
        if (_quorum == 0) {
            revert Module__SingleVoteGovernance__quorumCannotBeZero();
        }

        _;

        if (_quorum > getAmountAuthorized()) {
            revert Module__SingleVoteGovernance__quorumUnreachable();
        }
    }

    /// @notice Verifies that the targeted module address is indeed active in the Proposal.
    modifier validModuleAddress(address _target) {
        //this should implicitly control for address  != 0
        if (!__Module_proposal.isModule(_target)) {
            revert Module__SingleVoteGovernance__invalidModuleAddress(_target);
        }
        _;
    }

    /// @notice Verifies that the action to be executed after the vote is valid
    modifier validAction(bytes calldata _action) {
        if (_action.length == 0) {
            revert Module__SingleVoteGovernance__invalidEncodedAction(_action);
        }
        /// @todo  Should we do more in-depth checks? Like if the encoded action exists in the target module?
        _;
    }

    modifier authorizedVoter(address _voter) {
        //Using the standard isAuthorized would open the door to some pretty convoluted attack vectors since the proposal (and as such, any action confirmed through governance) is allowed by default.
        /// As such, since proposals aren't supposed to vote, we explicitly exclude them.
        if (!super.isAuthorized(_voter)) {
            revert IModule.Module__CallerNotAuthorized();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Storage

    /// @notice Registry of created votes with corresponding ID
    mapping(uint => Vote) voteRegistry;
    uint private voteIDCounter;

    /// @notice Quorum necessary to pass/deny a vote
    uint private quorum;
    /// @notice Duration of the voting period
    uint private voteDuration;

    //--------------------------------------------------------------------------
    // Constructor and/or Initialization
    function init(
        IProposal proposal_,
        Metadata memory metadata,
        bytes memory configdata
    ) external override initializer {
        address[] memory initialAuthorized;
        uint _startingQuorum;
        uint _voteDuration;
        (initialAuthorized, _startingQuorum, _voteDuration) =
            abi.decode(configdata, (address[], uint, uint));
        __SingleVoteGovernance_init(
            proposal_,
            metadata,
            initialAuthorized,
            _startingQuorum,
            _voteDuration
        );
    }

    function __SingleVoteGovernance_init(
        IProposal proposal,
        Metadata memory metadata,
        address[] memory initialAuthorized,
        uint _startingQuorum,
        uint _voteDuration
    ) internal onlyInitializing validQuorum(_startingQuorum) {
        __ListAuthorizer_init(proposal, metadata, initialAuthorized);

        quorum = _startingQuorum;
        voteDuration = _voteDuration;
    }

    //--------------------------------------------------------------------------
    // Parent Function overrides:

    /// @dev    Overrides the parent function to authorize the proposal
    ///         contract by default, so callbacks for governance execution
    ///         in other modules don't fail
    /// @notice Returns whether an address is authorized to facilitate
    ///         the current transaction.
    /// @param  _who  The address on which to perform the check.
    function isAuthorized(address _who) public view override returns (bool) {
        return (_who == address(__Module_proposal)) || super.isAuthorized(_who);
    }

    /// @dev    Overrides the parent function to make it onlyProposal, to force
    ///         changes to go through Governance
    /// @dev    Also adds the validQuorum modifier to removeFromAuthorized to
    ///         make sure that removing users doesn't end up with unreachable
    ///         quorum.
    /// @notice Removes an address from the list of authorized addresses.
    /// @param _who Address to remove authorization from
    function removeFromAuthorized(address _who)
        public
        override
        onlyProposal
        validQuorum(quorum)
    {
        super.removeFromAuthorized(_who);
    }

    /// @dev    Overrides the parent function to make it onlyProposal, to force
    ///         changes to go through Governance
    /// @notice Adds a new address to the list of authorized addresses.
    /// @param _who The address to add to the list of authorized addresses.
    function addToAuthorized(address _who) public override onlyProposal {
        super.addToAuthorized(_who);
    }

    /// @dev    Overrides the parent function to make sure that only 
    ///         authorized voters can transfer their authorization, and not the 
    ///         proposal (through a successful governance vote)       
    /// @notice Transfers authorization from the calling address to a new one.
    /// @param _to The address to transfer the authorization to
    function transferAuthorization(address _to) public override authorizedVoter(_msgSender()) {
        super.transferAuthorization(_to);
    }

    //--------------------------------------------------------------------------
    // Public Callable Funtions

    /// @notice Returns the current required quorum
    function getQuorum() external view returns (uint) {
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

    /// @notice Sets a new quorum
    /// @param _new The new quorum
    /// @dev    The onlyProposal modifier forces a quorum change to go
    ///         through governance.
    function changeQuorum(uint _new) external onlyProposal validQuorum(_new) {
        uint old = quorum;
        quorum = _new;

        emit QuorumModified(old, quorum);
    }

    /// @notice Sets a new vote duration
    /// @param _new The new vote duration
    /// @dev    The onlyProposal modifier forces a quorum change to go
    ///         through governance.
    function changeVoteDuration(uint _new) external onlyProposal {
        // @question: Should we have min and max vote duration?
        uint old = voteDuration;
        voteDuration = _new;

        emit VoteDurationModified(old, voteDuration);
    }

    /// @notice Creates a new vote
    /// @param _target The Module from which to execute the action
    /// @param _encodedAction The ABI encoded action to execute if it passes
    function createVote(address _target, bytes calldata _encodedAction)
        external
        authorizedVoter(_msgSender())
        validModuleAddress(_target)
        validAction(_encodedAction)
        returns (uint)
    {
        uint _id = voteIDCounter;

        voteRegistry[voteIDCounter].voteClosesAt =
            block.timestamp + voteDuration;
        voteRegistry[voteIDCounter].requiredQuorum = quorum;

        voteRegistry[voteIDCounter].targetAddress = _target;
        voteRegistry[voteIDCounter].encodedAction = _encodedAction;

        voteIDCounter++;

        emit VoteCreated(_id);

        return _id;
    }

    /// @notice Vote "yes"
    /// @param _voteID The ID of the vote to vote on
    function voteInFavor(uint _voteID)
        external
        voteExists(_voteID)
        voteIsActive(_voteID)
        authorizedVoter(_msgSender())
    {
        if (!hasVoted(_msgSender(), _voteID)) {
            voteRegistry[_voteID].voters.push(_msgSender());
            voteRegistry[_voteID].aye++;

            emit VotedInFavor(_msgSender(), _voteID);
        } else {
            //If the user already voted the  function doesn't fail, but at least we inform them that the vote wasn't counted
            emit AttemptedDoubleVote(_msgSender(), _voteID);
        }
    }

    /// @notice Vote "no"
    /// @param _voteID The ID of the vote to vote on
    function voteAgainst(uint _voteID)
        external
        voteExists(_voteID)
        voteIsActive(_voteID)
        authorizedVoter(_msgSender())
    {
        if (!hasVoted(_msgSender(), _voteID)) {
            voteRegistry[_voteID].voters.push(_msgSender());
            voteRegistry[_voteID].nay++;

            emit VotedAgainst(_msgSender(), _voteID);
        } else {
            //If the user already voted the  function doesn't fail, but at least we inform them that the vote wasn't counted
            emit AttemptedDoubleVote(_msgSender(), _voteID);
        }
    }

    /// @notice Vote "abstain"
    /// @param _voteID The ID of the vote to vote on
    function voteAbstain(uint _voteID)
        external
        voteExists(_voteID)
        voteIsActive(_voteID)
        authorizedVoter(_msgSender())
    {
        if (!hasVoted(_msgSender(), _voteID)) {
            voteRegistry[_voteID].voters.push(_msgSender());
            voteRegistry[_voteID].abstain++;

            emit VotedAbstain(_msgSender(), _voteID);
        } else {
            //If the user already voted the  function doesn't fail, but at least we inform them that the vote wasn't counted
            emit AttemptedDoubleVote(_msgSender(), _voteID);
        }
    }

    /// @notice Execute a vote.
    /// @param _voteID The ID of the vote to execute
    function executeVote(uint _voteID)
        external
        quorumReached(_voteID)
        voteNotActive(_voteID)
        voteNotExecuted(_voteID)
    {
        // Tell the proposal to execute the vote
        (bool executionResult, bytes memory returnData) = __Module_proposal
            .executeTxFromModule(
            voteRegistry[_voteID].targetAddress,
            voteRegistry[_voteID].encodedAction,
            Types.Operation.Call
        );

        if (!executionResult) {
            assembly {
                revert(add(returnData, 32), mload(returnData))
            }
        }

        voteRegistry[_voteID].executionResult = executionResult;
        voteRegistry[_voteID].returnData = returnData;
        voteRegistry[_voteID].executedAt = block.timestamp;

        emit VoteEnacted(_voteID, voteRegistry[_voteID].executionResult);
    }
}
