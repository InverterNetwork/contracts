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

contract SimpleGovernance is ListAuthorizer{

    /*
        requiredQuorum() - Returns the number of confirmations that a certain action requires before it may be executed
        changeQuorum() - Updates the number of confirmations that a certain action requires before it may be executed
        confirmAction(action) - Confirms a queued action that has been initiated by another authorized address. It automatically executes the action if the quorum has been reached.
        cancelAction(action)
    */

    /// @notice This is the part that maybe could be "delegated" to the calling
    ///         addresses, i.e Gnosis Safe, Aragon DAO, etc.
    

    event QuorumModified(uint8 oldQuorum, uint8 newQuorum);

    event VoteEnacted(uint voteID);
    event VotedInFavor(address who, uint voteID);
    event VotedAgainst(address who, uint voteID);
    event VoteCancelled(uint _voteID);

    


    error Module__addressAlreadyVoted(address who);
    error Module__voteNotActive(uint voteID);
    event Module__ExecuteVoteFailed();

    error Module__invalidAddress();
    error Module__invalidEncodedAction();

    error Module__quorumIsZero();
    error Module_quorumUnreachable();

    modifier voteIsActive(uint _voteID){

        // Ensure that the vote is active (and exists)
        if(! voteRegistry[_voteID].isActive ){
            revert Module__voteNotActive(_voteID);
        }
        _;
    }

    modifier validQuorum(uint8 _quorum){
        
        if(_quorum == 0){
            revert Module__quorumIsZero();
        }
        if(_quorum > amountAuthorized){
            revert Module_quorumUnreachable();
        }
        _;

    }

    modifier validModuleAddress(address _target){
        if(_target == address(0)){
            revert Module__invalidAddress();
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
        bool isActive;
        bytes encodedAction;
        address targetAddress;
        mapping(address => bool) hasVoted;
        uint aye;
        uint nay;

    }
    
    /// @notice Registry of created votes with corresponding ID
    mapping(uint => Vote ) voteRegistry;
    uint voteIDCounter;

    /// @notice Quorum necessary to pass/deny a vote
    uint8 quorum;

    /// @notice Returns the current required quorum
    function requiredQuorum() external view returns(uint8){
        return quorum;
    }


    /// @notice Sets a new quorum
    /// @param _new The new quorum
    function __Governance_changeQuorum(uint8 _new) external onlyProposal validQuorum(_new){


        uint8 old= quorum;
        quorum = _new;

        emit QuorumModified(old, quorum);

    }

    /// @notice Sets a new quorum
    /// @dev Relay Function that routes the function call via the proposal
    /// @param _new The new quorum
    function changeQuorum(uint8 _new) external onlyAuthorized {


        _triggerProposalCallback(
            abi.encodeWithSignature(
                "__Governance_changeQuorum(uint8)",
                _new
            ),
            Types.Operation.Call
        );       


    }


    /// @notice Creates a new vote
    /// @param _target The Module from which to execute the action
    /// @param _encodedAction The ABI encoded action to execute if it passes
    function __Governance_createVote(address _target, bytes calldata _encodedAction) external onlyProposal validModuleAddress(_target) validAction(_encodedAction){


        voteRegistry[voteIDCounter].isActive = true;
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
    function __Governance_confirmAction(uint _voteID) external onlyProposal voteIsActive(_voteID){


        // Ensure voter hasn't voted yet
        if(!voteRegistry[_voteID].hasVoted[_msgSender()]){

            voteRegistry[_voteID].hasVoted[_msgSender()] = true;
            voteRegistry[_voteID].aye++;

            emit VotedInFavor(_msgSender(), _voteID);
            
        }


        // If enough confirmations happened, execute vote
        if(voteRegistry[_voteID].aye >= quorum){
            executeVote(_voteID);
        }


    }

    /// @notice Vote "yes" and execute action if quorum is reached
    /// @dev Relay Function that routes the function call via the proposal
    /// @param _voteID The ID of the vote to vote on
    function confirmAction(uint _voteID) external onlyAuthorized{

        _triggerProposalCallback(
            abi.encodeWithSignature(
                "__Governance_confirmAction(uint)",
                _voteID
            ),
            Types.Operation.Call
        );       


    }

    /// @notice Vote "no" and abort action if quorum is reached
    /// @param _voteID The ID of the vote to vote on
    function __Governance_cancelAction(uint _voteID) external onlyProposal voteIsActive(_voteID){



        // If the voter hasn't voted yet register vote
        if(!voteRegistry[_voteID].hasVoted[_msgSender()]){

            voteRegistry[_voteID].hasVoted[_msgSender()] = true;
            voteRegistry[_voteID].nay++;

            emit VotedAgainst(_msgSender(), _voteID);
                    
        } 

        
        // If enough denials happened, cancel vote
        if(voteRegistry[_voteID].nay >= quorum){
            voteRegistry[_voteID].isActive= false;
            emit VoteCancelled(_voteID);
        }

    }

    /// @notice Vote "no" and abort action if quorum is reached
    /// @dev Relay Function that routes the function call via the proposal
    /// @param _voteID The ID of the vote to vote on
    function cancelAction(uint _voteID) external onlyAuthorized{

        _triggerProposalCallback(
            abi.encodeWithSignature(
                "__Governance_cancelAction(uint)",
                _voteID
            ),
            Types.Operation.Call
        );       


    }


    /// @notice Execute a vote. Only called by confirmAction once quorum 
    ///         is reached
    /// @param _voteID The ID of the vote to execute
    function executeVote(uint _voteID) internal voteIsActive(_voteID){

        // Deactivate the vote
        voteRegistry[_voteID].isActive= false;

        // Tell the proposal to execute the vote
        __Module_proposal.executeTxFromModule(
            voteRegistry[_voteID].targetAddress, 
            voteRegistry[_voteID].encodedAction, 
            Types.Operation.Call
            );

        emit VoteEnacted(_voteID);

    }

}
