// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies
import {Types} from "src/common/Types.sol";
import {ContextUpgradeable} from "@oz-up/utils/ContextUpgradeable.sol";
import {Module} from "src/modules/base/Module.sol";
import {ListAuthorizer} from "src/modules/governance/ListAuthorizer.sol";

// Interfaces
import {IProposal} from "src/interfaces/IProposal.sol";
import {IAuthorizer} from "src/interfaces/IAuthorizer.sol";

/**
* @title Vote-based governance module
*
* @dev
* This Module handles the authorization of several of the smart contract
* functions
* 
* It keeps a list authorized addresses and implements the IAuthorizers
* abstract function "isAuthorized", necessary for the "onlyAuthorized" modifier
* in the base module contract. 
*
* The authorized addresses can be anything, ranging from an EOA to a Gnosis 
* multisignature, keeping the module agnostic to the specific governance 
* structure employed.   
*
* Authorized Addresses can vote on proposed tx exectutions. Once quorum is 
* passed, those transactions are canceled or executed.
*/

contract SingleVoteGovernance is ListAuthorizer{

    /*
        requiredQuorum() - Returns the number of confirmations that a certain action requires before it may be executed
        changeQuorum() - Updates the number of confirmations that a certain action requires before it may be executed
        confirmAction(action) - Confirms a queued action that has been initiated by another authorized address. It automatically executes the action if the quorum has been reached.
        cancelAction(action)
    */

    /// @notice This is the part that maybe could be "delegated" to the calling
    ///         addresses, i.e Gnosis Safe, Aragon DAO, etc.


    /// Function overrides:


    function __ListAuthorizer_removeFromAuthorized(address _who) override public onlyProposal validQuorum(quorum, (amountAuthorized-1)){
        super.__ListAuthorizer_removeFromAuthorized(_who);
    }


    

    event QuorumModified(uint8 oldQuorum, uint8 newQuorum);
    event VoteDurationModified(uint oldDuration, uint newDuration);

    event VoteEnacted(uint voteID);
    event VotedInFavor(address who, uint voteID);
    event VotedAgainst(address who, uint voteID);
    event VoteCancelled(uint _voteID);

    


    error Module__SingleVoteGovernance_addressAlreadyVoted(address who);
    error Module__SingleVoteGovernance_voteNotActive(uint voteID);
    error Module__SingleVoteGovernance_voteStillActive(uint voteID);
    error Module__SingleVoteGovernance_ExecuteVoteFailed();
    error Module__SingleVoteGovernance_quorumNotReached(uint voteID);
    error Module__SingleVoteGovernance_voteExpired(uint _voteID);

    error Module__SingleVoteGovernance_invalidAddress();
    error Module__SingleVoteGovernance_invalidEncodedAction();

    error Module__SingleVoteGovernance_quorumIsZero();
    error Module__SingleVoteGovernance_quorumUnreachable();

    modifier voteIsActive(uint _voteID){

        if(! (voteRegistry[_voteID].createdAt + VOTE_DURATION >= block.timestamp) ){
            revert Module__SingleVoteGovernance_voteExpired(_voteID);
        }
        _;
    }

    modifier voteNotActive(uint _voteID){

        if(! (voteRegistry[_voteID].createdAt + VOTE_DURATION < block.timestamp) ){
            revert Module__SingleVoteGovernance_voteStillActive(_voteID);
        }
        _;
    }


    modifier quorumReached(uint _voteID){
        if(! (voteRegistry[_voteID].aye >= quorum)){
            revert Module__SingleVoteGovernance_quorumNotReached(_voteID);
        }
        _;
    }

    modifier validQuorum(uint8 _quorum, uint _amountAuthorized){
        
        if(_quorum == 0){
            revert Module__SingleVoteGovernance_quorumIsZero();
        }
        if(_quorum > amountAuthorized){
            revert Module__SingleVoteGovernance_quorumUnreachable();
        }
        _;

    }

    modifier validModuleAddress(address _target){
        if(_target == address(0)){
            revert Module__SingleVoteGovernance_invalidAddress();
        }
        //I think we DO want to explicitly allow address==address(this)? F.ex. to vote on quorum change

        //TODO maybe check if address is in proposal module list?
        _;
    }

    modifier validAction(bytes calldata _action){


        /// TODO Check if _encoded action correct? Or only if not zero?
        _;
    }




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
        // execution information
        uint executedAt;
        bool executionResult;
        bytes returnata;
        // voting results
        mapping(address => bool) hasVoted;
        uint aye;
        uint nay;

    }
    
    /// @notice Registry of created votes with corresponding ID
    mapping(uint => Vote ) voteRegistry;
    uint voteIDCounter;

    /// @notice Quorum necessary to pass/deny a vote
    uint8 private quorum;
    uint private VOTE_DURATION;

    /// @notice Returns the current required quorum
    function requiredQuorum() external view returns(uint8){
        return quorum;
    }


    function initialize(IProposal proposal, uint8 _startingQuorum, uint _voteDuration, Metadata memory metadata) external initializer{
        __Module_init(proposal, metadata);

        //During initialization we don't check for valid quorum etc... Is this too risky?
        quorum = _startingQuorum;
        VOTE_DURATION = _voteDuration;
        
    }

    /// @notice Sets a new quorum
    /// @param _new The new quorum
    function __Governance_changeQuorum(uint8 _new) external onlyProposal validQuorum(_new, amountAuthorized){


        uint8 old= quorum;
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
            abi.encodeWithSignature(
                "__Governance_changeQuorum(uint8)",
                _new
            ),
            Types.Operation.Call
        );       


    }

        /// @notice Returns the current required quorum
    function voteDuration() external view returns(uint){
        return VOTE_DURATION;
    }


    /// @notice Sets a new quorum
    /// @param _new The new quorum
    function __Governance_changeVoteDuration(uint _new) external onlyProposal {


        uint old= VOTE_DURATION;
        VOTE_DURATION = _new;

        emit VoteDurationModified(old, VOTE_DURATION);

    }

    /// @notice Sets a new quorum
    /// @dev    Relay Function that routes the function call via the proposal. 
    ///         The onlyProposal modifier forces a quorum change to als go
    ///         through governance.
    /// @param _new The new quorum
    function changeVoteDuration(uint _new) external onlyProposal {


        _triggerProposalCallback(
            abi.encodeWithSignature(
                "__Governance_changeVoteDuration(uint)",
                _new
            ),
            Types.Operation.Call
        );       


    }


    /// @notice Creates a new vote
    /// @param _target The Module from which to execute the action
    /// @param _encodedAction The ABI encoded action to execute if it passes
    function __Governance_createVote(address _target, bytes calldata _encodedAction) external onlyProposal validModuleAddress(_target) validAction(_encodedAction){


        voteRegistry[voteIDCounter].createdAt = block.timestamp;
        voteRegistry[voteIDCounter].targetAddress = _target;
        voteRegistry[voteIDCounter].encodedAction = _encodedAction;

        voteIDCounter++;

    }


    /// @notice Creates a new vote
    /// @dev Relay Function that routes the function call via the proposal
    /// @param _target The Module from which to execute the action
    /// @param _encodedAction The ABI encoded action to execute if it passes
    function createVote(address _target, bytes calldata _encodedAction) external onlyAuthorized{

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
    function __Governance_confirmAction(address _voter, uint _voteID) external onlyProposal voteIsActive(_voteID){


        // Ensure voter hasn't voted yet
        if(!voteRegistry[_voteID].hasVoted[_voter]){

            voteRegistry[_voteID].hasVoted[_voter] = true;
            voteRegistry[_voteID].aye++;

            emit VotedInFavor(_voter, _voteID);
            
        }

    }

    /// @notice Vote "yes" and execute action if quorum is reached
    /// @dev Relay Function that routes the function call via the proposal
    /// @param _voteID The ID of the vote to vote on
    function confirmAction(uint _voteID) external onlyAuthorized{

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
    function __Governance_cancelAction(address _voter, uint _voteID) external onlyProposal voteIsActive(_voteID){



        // If the voter hasn't voted yet register vote
        if(!voteRegistry[_voteID].hasVoted[_voter]){

            voteRegistry[_voteID].hasVoted[_voter] = true;
            voteRegistry[_voteID].nay++;

            emit VotedAgainst(_voter, _voteID);
                    
        } 

    }

    /// @notice Vote "no" and abort action if quorum is reached
    /// @dev Relay Function that routes the function call via the proposal
    /// @param _voteID The ID of the vote to vote on
    function cancelAction(uint _voteID) external onlyAuthorized{

        _triggerProposalCallback(
            abi.encodeWithSignature(
                "__Governance_cancelAction(address,uint)",
                _msgSender(),
                _voteID
            ),
            Types.Operation.Call
        );       


    }


    /// @notice Execute a vote. Only called by confirmAction once quorum 
    ///         is reached
    /// @param _voteID The ID of the vote to execute
    function executeVote(uint _voteID) external voteIsActive(_voteID) quorumReached(_voteID){
        _triggerProposalCallback(
            abi.encodeWithSignature(
                "__Governance_executeVote(uint)",
                _voteID
            ),
            Types.Operation.Call
        );       


    }

    function __Governance_executeVote(uint _voteID) external onlyProposal quorumReached(_voteID) voteNotActive(_voteID){


        // Tell the proposal to execute the vote
        (voteRegistry[_voteID].executionResult, voteRegistry[_voteID].returnData) = __Module_proposal.executeTxFromModule(
            voteRegistry[_voteID].targetAddress, 
            voteRegistry[_voteID].encodedAction, 
            Types.Operation.Call
            );
        
        voteRegistry[_voteID].executedAt = block.timestamp;

        emit VoteEnacted(_voteID);

    }

}
